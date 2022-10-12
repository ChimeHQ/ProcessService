import Foundation
import Combine

import ConcurrencyPlus
import ProcessEnv
import ProcessServiceShared

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

/// An interface to a remote ExportedProcessService instance
///
/// You can use this class to start and control a remote `ExportedProcessService`.
public actor HostedProcess {
    private let connection: NSXPCConnection
    let parameters: Process.ExecutionParameters
    private var uuid: UUID? = nil

	public init(named name: String, parameters: Process.ExecutionParameters) {
        self.connection = NSXPCConnection.processServiceConnection(named: name)
        self.parameters = parameters
    }

    deinit {
        connection.invalidate()
    }

    public func launch() async throws {
        if let uuid = self.uuid {
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

#if swift(>=5.7)
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
#else
    public var processEventPublisher: ExportedProcessServiceClient.ProcessEventPublisher {
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
#endif

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

            await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
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

extension HostedProcess {
	/// Capture the interactive-login shell environment
	///
	/// This function makes use of the `userEnvironment` function
	/// in `ProcessEnv`.
    public static func userEnvironment(with serviceName: String) async throws -> [String : String] {
        let connection = NSXPCConnection.processServiceConnection(named: serviceName)

        return try await connection.withContinuation { (service: ProcessServiceXPCProtocol, continuation) in
            service.captureUserEnvironment(reply: continuation.resumingHandler)
        }
    }
}
