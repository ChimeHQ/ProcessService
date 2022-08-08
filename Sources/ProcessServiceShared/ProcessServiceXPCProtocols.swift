import Foundation
import Combine

@objc public protocol ProcessServiceXPCProtocol {
    func launchProcess(at url: URL, arguments: [String], environment: [String : String]?, currentDirectoryURL: URL?, reply: @escaping (UUID?, Error?) -> Void)
    func terminateProcess(with identifier: UUID, reply: @escaping (Error?) -> Void)

    func writeDataToStdin(_ data: Data, for identifier: UUID, reply: @escaping (Error?) -> Void)

    func captureUserEnvironment(reply: @escaping ([String: String]?, Error?) -> Void)
}

@objc public protocol ProcessServiceClientXPCProtocol {
    func launchedProcess(with identifier: UUID, stdoutData: Data)
    func launchedProcess(with identifier: UUID, stderrData: Data)
    func launchedProcess(with identifier: UUID, terminated: Int)
}