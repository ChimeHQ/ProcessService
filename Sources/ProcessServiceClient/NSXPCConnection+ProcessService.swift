import Foundation

import ProcessServiceShared

extension NSXPCConnection {
    public static func processServiceConnection(named name: String) -> NSXPCConnection {
        let connection = NSXPCConnection(serviceName: name)

        connection.remoteObjectInterface = NSXPCInterface(with: ProcessServiceXPCProtocol.self)

        connection.exportedInterface = NSXPCInterface(with: ProcessServiceClientXPCProtocol.self)
        connection.exportedObject = ExportedProcessServiceClient()

		#if compiler(>=5.7.1)
		// this API is available in 11.0, but only exposed in the headers for 13.0
		connection.activate()
		#else
		connection.resume()
		#endif

        return connection
    }
}
