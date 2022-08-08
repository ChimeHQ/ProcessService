import Foundation

import ProcessServiceShared

extension NSXPCConnection {
    public static func processServiceConnection(named name: String) -> NSXPCConnection {
        let connection = NSXPCConnection(serviceName: name)

        connection.remoteObjectInterface = NSXPCInterface(with: ProcessServiceXPCProtocol.self)

        connection.exportedInterface = NSXPCInterface(with: ProcessServiceClientXPCProtocol.self)
        connection.exportedObject = ExportedProcessServiceClient()

        connection.activate()

        return connection
    }
}
