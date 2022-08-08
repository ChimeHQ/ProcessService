import Foundation

import Shared

extension NSXPCConnection {
    public static var processService: NSXPCConnection {
        get {
            let connection = NSXPCConnection(serviceName: "com.chimehq.ProcessService")

            connection.remoteObjectInterface = NSXPCInterface(with: ProcessServiceXPCProtocol.self)

            connection.exportedInterface = NSXPCInterface(with: ProcessServiceClientXPCProtocol.self)
            connection.exportedObject = ExportedProcessServiceClient()

            connection.activate()

            return connection
        }
    }
}
