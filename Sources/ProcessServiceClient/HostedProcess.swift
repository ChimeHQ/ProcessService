import Foundation
import Combine

import ConcurrencyPlus
import ProcessEnv
import Shared

enum UnrestrictedProcessError: Error {
    case alreadyLaunched(UUID)
    case notRunning
    case connectionInvalid
}

extension Process {
    public enum Event {
        case stdout(Data)
        case stderr(Data)
        case terminated(Process.TerminationReason)
    }
}

public actor HostedProcess {
    private let connection: NSXPCConnection
    let parameters: Process.ExecutionParameters
    private var uuid: UUID? = nil

    public init(path: String, arguments: [String] = [], environment: [String : String]? = nil, currentDirectoryURL: URL? = nil) {
        self.connection = NSXPCConnection.processService
        self.parameters = Process.ExecutionParameters(path: path,
                                                      arguments: arguments,
                                                      environment: environment,
                                                      currentDirectoryURL: currentDirectoryURL)
    }

    public func launch() async throws {
        if let uuid {
            throw UnrestrictedProcessError.alreadyLaunched(uuid)
        }

        self.uuid = try await connection.withContinuation({ (service: ProcessServiceXPCProtocol, continuation) in
            return service.launchProcess(at: URL(fileURLWithPath: parameters.path),
                                         arguments: parameters.arguments,
                                         environment: parameters.environment,
                                         currentDirectoryURL: parameters.currentDirectoryURL,
                                         reply: continuation.resumingHandler)
        })
    }

    public func terminate() async throws {
        guard let uuid = self.uuid else {
            throw UnrestrictedProcessError.notRunning
        }

        self.uuid = nil

        try await connection.withContinuation({ (service: ProcessServiceXPCProtocol, continuation) in
            service.terminateProcess(with: uuid, reply: continuation.resumingHandler)
        })
    }

    public var processEventPublisher: some Publisher<Process.Event, Error> {
        get async throws {
            guard let uuid = self.uuid else {
                throw UnrestrictedProcessError.notRunning
            }

            guard let client = connection.exportedObject as? ExportedProcessServiceClient else {
                throw UnrestrictedProcessError.connectionInvalid
            }

            return await client.processEventPublisher(for: uuid)
        }
    }

    public func write(_ data: Data) async throws {
        guard let uuid = self.uuid else {
            throw UnrestrictedProcessError.notRunning
        }

        try await connection.withContinuation({ (service: ProcessServiceXPCProtocol, continuation) in
            service.writeDataToStdin(data, for: uuid, reply: continuation.resumingHandler)
        })
    }

    public func runAndReadStdout() async throws -> Data {
        try await launch()

        let eventPublisher = try await processEventPublisher

        return await Task {
            var data = Data()
            var subscription: AnyCancellable? = nil

            await withCheckedContinuation { continuation in
                subscription = eventPublisher.sink { _ in
                    continuation.resume()

                    if let _ = subscription {
                    }
                } receiveValue: { event in
                    switch event {
                    case .stdout(let stdout):
                        data.append(stdout)
                    default:
                        break
                    }
                }
            }

            return data
        }.value
    }
}
