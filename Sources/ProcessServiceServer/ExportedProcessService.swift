import Foundation

import ConcurrencyPlus
import ProcessEnv
import ProcessServiceShared

enum ProcessServiceError: Error {
    case unknownIdentifier(UUID)
}

actor ExportedProcessService {
    private var processes: [UUID: Process] = [:]
    private let client: ProcessServiceClientXPCProtocol

    public init(client: ProcessServiceClientXPCProtocol) {
        self.client = client
    }

    private nonisolated func handleProcessTermination(with uuid: UUID, process: Process) {
        (process.standardOutput as? Pipe)?.fileHandleForReading.closeFile()
        (process.standardError as? Pipe)?.fileHandleForReading.closeFile()
        (process.standardInput as? Pipe)?.fileHandleForWriting.closeFile()

        let reason = process.terminationReason

        Task {
            await self.removeProcessAndInformClient(uuid: uuid, reason: reason)
        }
    }

    private func removeProcessAndInformClient(uuid: UUID, reason: Process.TerminationReason) {
        self.processes[uuid] = nil

        self.client.launchedProcess(with: uuid, terminated: reason.rawValue)
    }

    private func terminateProcess(with identifier: UUID) async throws {
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

    private func launchProcess(at url: URL, arguments: [String], environment: [String : String]?, currentDirectoryURL: URL?) async throws -> UUID {
        let uuid = UUID()
        let process = Process()

        process.executableURL = url
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectoryURL

        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardInput = stdinPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] in self?.handleProcessTermination(with: uuid, process: $0) }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] (handle) in
            let data = handle.availableData

            guard data.count > 0 else {
                // if we get here, add some delay to avoid spinning the CPU while
                // we wait for the termination processing to complete
                usleep(1000)
                return
            }

            self?.client.launchedProcess(with: uuid, stdoutData: data)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] (handle) in
            let data = handle.availableData

            guard data.count > 0 else {
                return
            }

            self?.client.launchedProcess(with: uuid, stderrData: data)
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
        Task.relayResult(to: reply) {
            return try await self.launchProcess(at: url, arguments: arguments, environment: environment, currentDirectoryURL: currentDirectoryURL)
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
