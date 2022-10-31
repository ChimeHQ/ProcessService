import Foundation

import ConcurrencyPlus
import ProcessEnv
import ProcessServiceShared

enum ProcessServiceError: Error {
    case unknownIdentifier(UUID)
}

extension Process {
	struct StdioPipeSet: Hashable, Sendable {
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

final class ExportedProcessService: @unchecked Sendable {
    private var processes: [UUID: Process] = [:]
    private let client: ProcessServiceClientXPCProtocol
	private let queue = DispatchQueue(label: "com.chimehq.ProcessService.ExportedProcessService")

    public init(client: ProcessServiceClientXPCProtocol) {
        self.client = client
    }

    private func handleProcessTermination(with uuid: UUID, process: Process) {
		let pipeSet = process.stdioPipeSet
		let reason = process.terminationReason

		queue.async {
			self.finish(with: uuid, pipeSet: pipeSet, reason: reason)
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
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(), Error>) in
			queue.async {
				guard let process = self.processes[identifier] else {
					continuation.resume(throwing: ProcessServiceError.unknownIdentifier(identifier))

					return
				}

				process.terminate()

				continuation.resume()
			}
		}
    }

    private func writeDataToStdin(_ data: Data, for identifier: UUID) async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(), Error>) in
			queue.async {
				let process = self.processes[identifier]

				guard let pipe = process?.standardInput as? Pipe else {
					continuation.resume(with: .failure(ProcessServiceError.unknownIdentifier(identifier)))
					return
				}

				do {
					try pipe.fileHandleForWriting.write(contentsOf: data)

					continuation.resume()
				} catch {
					continuation.resume(with: .failure(error))
				}

			}
		}
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

	private func prepareProcess(with params: Process.ExecutionParameters, uuid: UUID) -> Process {
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

			self.queue.sync {
				let data = handle.availableData
				if data.isEmpty {
					handle.readabilityHandler = nil
					return
				}

				self.handleProcessEvent(.stdout(data), for: uuid)
			}
		}

		return process
	}

	func launchProcess(with params: Process.ExecutionParameters) async throws -> UUID {
		return try await withCheckedThrowingContinuation({ continuation in
			self.queue.async {
				let uuid = UUID()
				let process = self.prepareProcess(with: params, uuid: uuid)

				// this must be set before we launch, so
				// we can deal with any data immediately
				self.processes[uuid] = process

				do {
					try process.run()

					self.processes[uuid] = process

					continuation.resume(returning: uuid)
				} catch {
					continuation.resume(throwing: error)
				}
			}
		})
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
