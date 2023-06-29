import XCTest

import ProcessServiceShared
@testable import ProcessServiceServer

#if compiler(>=5.9)
final class MockClient: ProcessServiceClientXPCProtocol {
	typealias EventSequence = AsyncStream<(UUID, Process.Event)>

	let eventSequence: EventSequence
	private let continuation: EventSequence.Continuation

	public init() {
		(self.eventSequence, self.continuation) = EventSequence.makeStream()
	}

	public func launchedProcess(with identifier: UUID, stdoutData: Data) {
		continuation.yield((identifier, .stdout(stdoutData)))
	}

	public func launchedProcess(with identifier: UUID, stderrData: Data) {
		continuation.yield((identifier, .stderr(stderrData)))
	}

	public func launchedProcess(with identifier: UUID, terminated: Int) {
		let event = Process.Event.terminated(Process.TerminationReason(rawValue: terminated)!)

		continuation.yield((identifier, event))
	}
}

final class ExportedProcessServiceTests: XCTestCase {
	typealias EventStream = AsyncStream<(UUID, Process.Event)>

	func testCaptureEnviroment() async throws {
		let client = MockClient()
		let service = ExportedProcessService(client: client)

		let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: String], Error>) in
			service.captureUserEnvironment(reply: { env, error in
				if let error = error {
					continuation.resume(throwing: error)
					return
				}

				continuation.resume(returning: env!)
			})
		}

		// just a simple check to ensure we got something from the environment
		XCTAssertNotNil(value["USER"])
	}

	func testLaunchProcess() async throws {
		let client = MockClient()
		let service = ExportedProcessService(client: client)

		self.continueAfterFailure = false

		var events = client.eventSequence.map({ $0.1 }).makeAsyncIterator()

		_ = try await service.launchProcess(with: .init(path: "/bin/echo", arguments: ["-n", "hello"]))

		let stdoutEvent = await events.next()

		XCTAssertEqual(stdoutEvent, Process.Event.stdout("hello".data(using: .utf8)!))

		let terminateEvent = await events.next()

		XCTAssertEqual(terminateEvent, Process.Event.terminated(.exit))
	}

	func testTerminationReadingRace() async throws {
		let client = MockClient()
		let service = ExportedProcessService(client: client)
		let params = Process.ExecutionParameters(path: "/bin/echo", arguments: ["-n", "hello"])

		self.continueAfterFailure = false

		var events = client.eventSequence.map({ $0.1 }).makeAsyncIterator()

		for _ in 0..<30000 {
//			print("iteration start \(i)")

			_ = try await service.launchProcess(with: params)

			let stdoutEvent = await events.next()

			XCTAssertEqual(stdoutEvent, Process.Event.stdout("hello".data(using: .utf8)!))

			let terminateEvent = await events.next()

			XCTAssertEqual(terminateEvent, Process.Event.terminated(.exit))

//			print("iteration end")
		}
	}
}
#endif
