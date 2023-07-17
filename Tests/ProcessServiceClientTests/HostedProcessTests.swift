import XCTest

@testable import ProcessServiceClient
import ProcessServiceContainer

final class HostedProcessTests: XCTestCase {
	override func setUp() {
		ServiceContainer.bootstrap()
	}

	func testLaunchAndReadStdout() async throws {
		let params = Process.ExecutionParameters(path: "/bin/echo", arguments: ["hello"])
		let process = HostedProcess(named: ServiceContainer.name, parameters: params)

		let data = try await process.runAndReadStdout()
		let value = try XCTUnwrap(String(data: data, encoding: .utf8))

		XCTAssertEqual(value, "hello\n")
	}

	/// stress the io/termination synchronization
	///
	/// There have been races here, but they are hard to trigger. have to run a lot of iterations to have some confidence in the system.
	func testRunStress() async throws {
		let params = Process.ExecutionParameters(path: "/bin/echo", arguments: ["hello"])

		for _ in 0..<1000 {
			let process = HostedProcess(named: ServiceContainer.name, parameters: params)
			
			let data = try await process.runAndReadStdout()
			let value = try XCTUnwrap(String(data: data, encoding: .utf8))
			
			XCTAssertEqual(value, "hello\n")
		}
	}

	func testWriting() async throws {
		let params = Process.ExecutionParameters(path: "/usr/bin/tee", arguments: ["/dev/null"])
		let process = HostedProcess(named: ServiceContainer.name, parameters: params)

		try await process.launch()

		var iterator = await process.eventSequence.makeAsyncIterator()

		try await process.write(Data("hello\n".utf8))

		let first = await iterator.next()

		XCTAssertEqual(first, .stdout(Data("hello\n".utf8)))

		try await process.write(Data("goodbye\n".utf8))

		let second = await iterator.next()

		XCTAssertEqual(second, .stdout(Data("goodbye\n".utf8)))
	}
}
