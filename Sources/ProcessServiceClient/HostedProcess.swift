import Foundation
import Combine

import AsyncXPCConnection
import ProcessEnv
import ProcessServiceShared

enum UnrestrictedProcessError: Error {
    case alreadyLaunched(UUID)
    case notRunning
    case connectionInvalid
}

/// An interface to a remote ExportedProcessService instance
///
/// You can use this class to start and control a remote `ExportedProcessService`.
public actor HostedProcess {
	public typealias EventSequence = AsyncStream<Process.Event>

    private let connection: NSXPCConnection
    let parameters: Process.ExecutionParameters
	private var state: (UUID, Task<Void, Never>)? = nil

	public let eventSequence: EventSequence
	private let eventContinuation: EventSequence.Continuation

	public init(named name: String, parameters: Process.ExecutionParameters) {
		self.connection = NSXPCConnection.processServiceConnection(named: name)
        self.parameters = parameters

		(self.eventSequence, self.eventContinuation) = EventSequence.makeStream()
    }

    deinit {
        connection.invalidate()
		eventContinuation.finish()
		
		if let (_, task) = state {
			task.cancel()
		}
    }

    public func launch() async throws {
		if let uuid = self.state?.0 {
            throw UnrestrictedProcessError.alreadyLaunched(uuid)
        }

		let uuid = try await connection.withValueErrorCompletion { (service: ProcessServiceXPCProtocol, handler) in
            return service.launchProcess(at: URL(fileURLWithPath: parameters.path),
                                         arguments: parameters.arguments,
                                         environment: parameters.environment,
                                         currentDirectoryURL: parameters.currentDirectoryURL,
                                         reply: handler)
        }

		guard let client = connection.exportedObject as? ExportedProcessServiceClient else {
			throw UnrestrictedProcessError.connectionInvalid
		}

		let sequence = await client.processEventSequence(for: uuid)

		let task = Task { [eventContinuation] in
			for await event in sequence {
				eventContinuation.yield(event)

				if case .terminated = event {
					eventContinuation.finish()
					break
				}
			}
		}

		self.state = (uuid, task)
    }

    public func terminate() async throws {
		guard let state = self.state else {
            throw UnrestrictedProcessError.notRunning
        }

		state.1.cancel()

        try await connection.withErrorCompletion { (service: ProcessServiceXPCProtocol, handler) in
			service.terminateProcess(with: state.0, reply: handler)
        }
    }

    public func write(_ data: Data) async throws {
		guard let uuid = self.state?.0 else {
            throw UnrestrictedProcessError.notRunning
        }

        try await connection.withErrorCompletion { (service: ProcessServiceXPCProtocol, handler) in
            service.writeDataToStdin(data, for: uuid, reply: handler)
        }
    }

    public nonisolated func runAndReadStdout() async throws -> Data {
        try await launch()

		let sequence = eventSequence

		return await sequence.reduce(Data(), { partialData, event in
			switch event {
			case .stdout(let newData):
				return partialData + newData
			case .stderr, .terminated:
				return partialData
			}
		})
    }
    
    /// The process ID (PID) of the XPC service itself (not its hosted executable)
    public var serviceProcessID: Int {
        Int(connection.processIdentifier)
    }
}

extension HostedProcess {
	/// Capture the interactive-login shell environment.
	///
	/// This function makes use of the `userEnvironment` function
	/// in `ProcessEnv`.
    public static func userEnvironment(with serviceName: String) async throws -> [String : String] {
        let connection = NSXPCConnection.processServiceConnection(named: serviceName)

        return try await connection.withValueErrorCompletion { (service: ProcessServiceXPCProtocol, handler) in
            service.captureUserEnvironment(reply: handler)
        }
    }

	/// Returns parameters that emulate an invocation in the user's shell.
	///
	/// See `ProcessEnv` documentation for details.
	public static func userShellInvocation(of params: Process.ExecutionParameters,
										   with serviceName: String) async throws -> Process.ExecutionParameters {
		let paramsData = try JSONEncoder().encode(params)
		let connection = NSXPCConnection.processServiceConnection(named: serviceName)

		return try await connection.withDecodingCompletion { (service: ProcessServiceXPCProtocol, handler) in
			service.userShellInvocation(of: paramsData, reply: handler)
		}
	}
}
