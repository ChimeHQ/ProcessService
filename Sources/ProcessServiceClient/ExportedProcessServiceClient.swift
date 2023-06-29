import Foundation
import Combine

import ProcessServiceShared
import Queue

public actor ExportedProcessServiceClient {
	public typealias EventSequence = AsyncStream<Process.Event>
	private typealias SequencePair = (stream: EventSequence, continuation: EventSequence.Continuation)

	private var processEventPairs = [UUID: SequencePair]()
	private let queue = AsyncQueue()

    public init() {
    }

    private func processEventPair(for identifier: UUID) -> SequencePair {
        if let pair = processEventPairs[identifier] {
            return pair
        }

		let pair = EventSequence.makeStream()

		processEventPairs[identifier] = pair

        return pair
    }

    private func removePair(for identifier: UUID) {
        precondition(processEventPairs[identifier] != nil)

		processEventPairs[identifier]?.continuation.finish()
        self.processEventPairs[identifier] = nil
    }

	public func processEventSequence(for identifier: UUID) -> EventSequence {
		return processEventPair(for: identifier).stream
    }
}

extension ExportedProcessServiceClient: ProcessServiceClientXPCProtocol {
    public nonisolated func launchedProcess(with identifier: UUID, stdoutData: Data) {
		queue.addOperation {
			let pair = await self.processEventPair(for: identifier)
			
			pair.continuation.yield(.stdout(stdoutData))
		}
    }

    public nonisolated func launchedProcess(with identifier: UUID, stderrData: Data) {
		queue.addOperation {
			let pair = await self.processEventPair(for: identifier)

			pair.continuation.yield(.stderr(stderrData))
		}
    }

    public nonisolated func launchedProcess(with identifier: UUID, terminated: Int) {
        let reason = Process.TerminationReason(rawValue: terminated) ?? .exit

		queue.addOperation {
            let pair = await self.processEventPair(for: identifier)

			pair.continuation.yield(.terminated(reason))

			await self.removePair(for: identifier)
        }
    }
}
