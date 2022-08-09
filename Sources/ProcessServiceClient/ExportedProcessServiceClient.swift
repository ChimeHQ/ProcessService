import Foundation
import Combine

import ConcurrencyPlus
import ProcessServiceShared

public actor ExportedProcessServiceClient {
    public typealias ProcessEventSubject = PassthroughSubject<Process.Event, Error>
#if swift(>=5.7)
    public typealias ProcessEventPublisher = Publisher<Process.Event, Error>
#else
    public typealias ProcessEventPublisher = AnyPublisher<Process.Event, Error>
#endif

    private var processEventSubjects = [UUID: ProcessEventSubject]()
    private let taskQueue = TaskQueue()

    public init() {
    }

    private func processEventSubject(for identifier: UUID) -> ProcessEventSubject {
        if let subject = processEventSubjects[identifier] {
            return subject
        }

        let subject = ProcessEventSubject()

        processEventSubjects[identifier] = subject

        return subject
    }

    private func removeSubject(for identifier: UUID) {
        precondition(processEventSubjects[identifier] != nil)

        self.processEventSubjects[identifier] = nil
    }

#if swift(>=5.7)
    public func processEventPublisher(for identifier: UUID) -> some ProcessEventPublisher {
        return processEventSubject(for: identifier)
    }
#else
    public func processEventPublisher(for identifier: UUID) -> ProcessEventPublisher {
        return processEventSubject(for: identifier).eraseToAnyPublisher()
    }
#endif
}

extension ExportedProcessServiceClient: ProcessServiceClientXPCProtocol {
    public nonisolated func launchedProcess(with identifier: UUID, stdoutData: Data) {
        taskQueue.addOperation {
            await self.processEventSubject(for: identifier).send(.stdout(stdoutData))
        }
    }

    public nonisolated func launchedProcess(with identifier: UUID, stderrData: Data) {
        taskQueue.addOperation {
            await self.processEventSubject(for: identifier).send(.stderr(stderrData))
        }
    }

    public nonisolated func launchedProcess(with identifier: UUID, terminated: Int) {
        let reason = Process.TerminationReason(rawValue: terminated) ?? .exit

        taskQueue.addOperation {
            let subject = await self.processEventSubject(for: identifier)

            await self.removeSubject(for: identifier)

            subject.send(.terminated(reason))
            subject.send(completion: .finished)
        }
    }
}
