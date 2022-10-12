public struct ServiceContainer {
	/// The name of the bundled XPC service.
	public static let name = "com.chimehq.ProcessService"

	/// Initializes the service so look ups can work from anywhere in the current process.
	///
	/// This function **must** be run once before trying to interact with the any of the `ProcessServiceClient` APIs. This only needs to happen once per system boot, which makes errors here very hard to detect.
	public static func bootstrap() {
		_ = NSXPCConnection(serviceName: name)
	}
}
