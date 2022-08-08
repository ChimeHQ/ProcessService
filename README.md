# ProcessService
Unsandboxed XPC service building blocks

```swift
// main.swift

import Foundation

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        do {
            try newConnection.configureProcessServiceServer()
        } catch {
            newConnection.invalidate()
            return false
        }
        
        newConnection.activate()

        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()

listener.delegate = delegate
listener.resume()
```

