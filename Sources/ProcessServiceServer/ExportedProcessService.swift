import Foundation

import ProcessEnv
import ProcessServiceShared

enum ProcessServiceError: Error {
    case unknownIdentifier(UUID)
}

final class ExportedProcessService: NSObject {
    private var processes: [UUID: Process] = [:]
    private let client: ProcessServiceClientXPCProtocol

    public init(client: ProcessServiceClientXPCProtocol) {
        self.client = client
    }
}

extension ExportedProcessService: ProcessServiceXPCProtocol {
    func launchProcess(at url: URL, arguments: [String], environment: [String : String]?, currentDirectoryURL: URL?, reply: @escaping (UUID?, Error?) -> Void) {
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

        process.terminationHandler = { [unowned self] in
            self.client.launchedProcess(with: uuid, terminated: $0.terminationReason.rawValue)
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [unowned self] (handle) in
            let data = handle.availableData

            guard data.count > 0 else {
                return
            }

            self.client.launchedProcess(with: uuid, stdoutData: data)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [unowned self] (handle) in
            let data = handle.availableData

            guard data.count > 0 else {
                return
            }

            self.client.launchedProcess(with: uuid, stderrData: data)
        }

        self.processes[uuid] = process

        do {
            try process.run()

            reply(uuid, nil)
        } catch {
            self.processes[uuid] = nil

            reply(nil, error)
        }
    }

    func terminateProcess(with identifier: UUID, reply: @escaping (Error?) -> Void) {
        guard let process = processes[identifier] else {
            reply(ProcessServiceError.unknownIdentifier(identifier))
            return
        }

        process.terminate()

        reply(nil)
    }

    func writeDataToStdin(_ data: Data, for identifier: UUID, reply: @escaping (Error?) -> Void) {
        let process = processes[identifier]

        do {
            guard let pipe = process?.standardInput as? Pipe else {
                throw ProcessServiceError.unknownIdentifier(identifier)
            }

            try pipe.fileHandleForWriting.write(contentsOf: data)

            reply(nil)
        } catch {
            reply(error)
        }
    }

    func captureUserEnvironment(reply: @escaping ([String : String]?, Error?) -> Void) {
        let env = ProcessInfo.processInfo.userEnvironment

        reply(env, nil)
    }
}
