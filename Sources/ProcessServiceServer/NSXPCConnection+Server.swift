import Foundation

import ProcessServiceShared

extension NSXPCConnection {
    public func configureProcessServiceServer() throws {
        self.remoteObjectInterface = NSXPCInterface(with: ProcessServiceClientXPCProtocol.self)

        guard let client = remoteObjectProxy as? ProcessServiceClientXPCProtocol else {
            return
        }

        self.exportedInterface = NSXPCInterface(with: ProcessServiceXPCProtocol.self)

        let exportedObject = ExportedProcessService(client: client) // retained by the connection
        self.exportedObject = exportedObject
    }
}
