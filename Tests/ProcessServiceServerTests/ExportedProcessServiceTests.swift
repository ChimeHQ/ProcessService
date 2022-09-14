import XCTest

import ConcurrencyPlus
import ProcessServiceShared
@testable import ProcessServiceServer

final class MockClient: ProcessServiceClientXPCProtocol {
	func launchedProcess(with identifier: UUID, stdoutData: Data) {
	}

	func launchedProcess(with identifier: UUID, stderrData: Data) {
	}

	func launchedProcess(with identifier: UUID, terminated: Int) {
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
}
