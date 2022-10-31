import Foundation

import ConcurrencyPlus
import ProcessEnv
import ProcessServiceShared

enum ProcessServiceError: Error {
    case unknownIdentifier(UUID)
}

extension Process {
	struct StdioPipeSet {
		let stdin: Pipe
		let stdout: Pipe
		let stderr: Pipe

		init(stdin: Pipe, stdout: Pipe, stderr: Pipe) {
			self.stdin = stdin
			self.stdout = stdout
			self.stderr = stderr
		}

		init() {
			self.init(stdin: Pipe(), stdout: Pipe(), stderr: Pipe())
		}
	}

	var stdioPipeSet: StdioPipeSet? {
		get {
			guard
				let inPipe = standardInput as? Pipe,
				let outPipe = standardOutput as? Pipe,
				let errPipe = standardError as? Pipe
			else {
				return nil
			}

			return StdioPipeSet(stdin: inPipe, stdout: outPipe, stderr: errPipe)
		}
		set {
			standardInput = newValue?.stdin
			standardOutput = newValue?.stdout
			standardError = newValue?.stderr
		}
	}
}

actor ExportedProcessService {
    private var processes: [UUID: Process] = [:]
    private let client: ProcessServiceClientXPCProtocol

    public init(client: ProcessServiceClientXPCProtocol) {
        self.client = client
    }

    private nonisolated func handleProcessTermination(with uuid: UUID, process: Process) {
		let pipeSet = process.stdioPipeSet
		let reason = process.terminationReason

		Task {
			await self.finish(with: uuid, pipeSet: pipeSet, reason: reason)
		}
    }

	private func finish(with uuid: UUID, pipeSet: Process.StdioPipeSet?, reason: Process.TerminationReason) {
		pipeSet?.stdin.fileHandleForWriting.writeabilityHandler = nil
		pipeSet?.stderr.fileHandleForReading.readabilityHandler = nil
		pipeSet?.stdout.fileHandleForReading.readabilityHandler = nil

		try? pipeSet?.stdin.fileHandleForWriting.close()

		if let data = try? pipeSet?.stdout.fileHandleForReading.readToEnd(), data.isEmpty == false {
			handleProcessEvent(.stdout(data), for: uuid)
		}

		try? pipeSet?.stdout.fileHandleForReading.close()

		if let data = try? pipeSet?.stderr.fileHandleForReading.readToEnd(), data.isEmpty == false {
			handleProcessEvent(.stderr(data), for: uuid)
		}

		try? pipeSet?.stderr.fileHandleForReading.close()

		self.processes[uuid] = nil

		handleProcessEvent(.terminated(reason), for: uuid)
	}

    func terminateProcess(with identifier: UUID) async throws {
        guard let process = processes[identifier] else {
            throw ProcessServiceError.unknownIdentifier(identifier)
        }

        process.terminate()
    }

    private func writeDataToStdin(_ data: Data, for identifier: UUID) async throws {
        let process = processes[identifier]

        guard let pipe = process?.standardInput as? Pipe else {
            throw ProcessServiceError.unknownIdentifier(identifier)
        }

        try pipe.fileHandleForWriting.write(contentsOf: data)
    }

	private func handleProcessEvent(_ event: Process.Event, for uuid: UUID) {
		switch event {
		case .stdout(let data):
			client.launchedProcess(with: uuid, stdoutData: data)
		case .stderr(let data):
			client.launchedProcess(with: uuid, stderrData: data)
		case .terminated(let reason):
			client.launchedProcess(with: uuid, terminated: reason.rawValue)
		}
	}

	private func readFromStdoutHandle(_ handle: FileHandle, for uuid: UUID) {
		if handle.readabilityHandler == nil {
			return
		}
		
		let data = handle.availableData

		if data.isEmpty {
			handle.readabilityHandler = nil

			return
		}

		self.handleProcessEvent(.stdout(data), for: uuid)
	}

	func launchProcess(with params: Process.ExecutionParameters) async throws -> UUID {
        let uuid = UUID()
        let process = Process()

        process.parameters = params

		let pipeSet = Process.StdioPipeSet()

        process.stdioPipeSet = pipeSet

        process.terminationHandler = { [weak self] in
			self?.handleProcessTermination(with: uuid, process: $0)
		}

		pipeSet.stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
			guard let self = self else {
				handle.readabilityHandler = nil
				return
			}

			Task {
				await self.readFromStdoutHandle(handle, for: uuid)
			}
		}

        // this must be set before we launch, so
        // we can deal with any data immediately
        self.processes[uuid] = process

        do {
            try process.run()
        } catch {
            self.processes[uuid] = nil

            throw error
        }

        return uuid
    }
}

extension ExportedProcessService: ProcessServiceXPCProtocol {
    nonisolated func launchProcess(at url: URL, arguments: [String], environment: [String : String]?, currentDirectoryURL: URL?, reply: @escaping (UUID?, Error?) -> Void) {
		let params = Process.ExecutionParameters(path: url.path,
												 arguments: arguments,
												 environment: environment,
												 currentDirectoryURL: currentDirectoryURL)
        Task.relayResult(to: reply) {
			return try await self.launchProcess(with: params)
        }
    }

    nonisolated func terminateProcess(with identifier: UUID, reply: @escaping (Error?) -> Void) {
        Task.relayResult(to: reply) {
            try await self.terminateProcess(with: identifier)
        }
    }

    nonisolated func writeDataToStdin(_ data: Data, for identifier: UUID, reply: @escaping (Error?) -> Void) {
        Task.relayResult(to: reply) {
            try await self.writeDataToStdin(data, for: identifier)
        }
    }

    nonisolated func captureUserEnvironment(reply: @escaping ([String : String]?, Error?) -> Void) {
        let env = ProcessInfo.processInfo.userEnvironment

        reply(env, nil)
    }

	nonisolated func userShellInvocation(of executionParametersData: Data, reply: @escaping (Data?, Error?) -> Void) {
		do {
			let params = try JSONDecoder().decode(Process.ExecutionParameters.self, from: executionParametersData)

			let userParams = params.userShellInvocation()

			let paramsData = try JSONEncoder().encode(userParams)

			reply(paramsData, nil)
		} catch {
			reply(nil, error)
		}
	}
}
