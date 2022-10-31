import XCTest

import ConcurrencyPlus
import ProcessServiceShared
@testable import ProcessServiceServer

final class MockClient: ProcessServiceClientXPCProtocol {
	var eventHandler: (UUID, Process.Event) -> Void = { _, _ in }

	public init() {
	}

	public func launchedProcess(with identifier: UUID, stdoutData: Data) {
		eventHandler(identifier, .stdout(stdoutData))
	}

	public func launchedProcess(with identifier: UUID, stderrData: Data) {
		eventHandler(identifier, .stderr(stderrData))
	}

	public func launchedProcess(with identifier: UUID, terminated: Int) {
		eventHandler(identifier, .terminated(Process.TerminationReason(rawValue: terminated)!))
	}
}

class ExportedProcessServiceTests: XCTestCase {
	func testCaptureEnviroment() async throws {
		let client = MockClient()
		let service = ExportedProcessService(client: client)

		let value = try await withCheckedThrowingContinuation({ continuation in
			service.captureUserEnvironment(reply: continuation.resumingHandler)
		})

		// just a simple check to ensure we got something from the environment
		XCTAssertNotNil(value["USER"])
	}

	func testLaunchProcess() async throws {
		let subject = AsyncSubject<(UUID, Process.Event)>()
		let client = MockClient()

		client.eventHandler = { subject.send(($0, $1)) }

		let service = ExportedProcessService(client: client)

		self.continueAfterFailure = false

		var events = subject.map({ $0.1 }).makeAsyncIterator()

		_ = try await service.launchProcess(with: .init(path: "/bin/echo", arguments: ["-n", "hello"]))

		let stdoutEvent = await events.next()

		XCTAssertEqual(stdoutEvent, Process.Event.stdout("hello".data(using: .utf8)!))

		let terminateEvent = await events.next()

		XCTAssertEqual(terminateEvent, Process.Event.terminated(.exit))
	}

	func testTerminationReadingRace() async throws {
		let subject = AsyncSubject<(UUID, Process.Event)>()
		let client = MockClient()
		let service = ExportedProcessService(client: client)
		let params = Process.ExecutionParameters(path: "/bin/echo", arguments: ["-n", "hello"])

		client.eventHandler = { subject.send(($0, $1)) }

		self.continueAfterFailure = false

		var events = subject.map({ $0.1 }).makeAsyncIterator()

		for _ in 0..<10000 {
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
