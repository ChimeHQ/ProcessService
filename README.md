[![Build Status][build status badge]][build status]
[![License][license badge]][license]
[![Platforms][platforms badge]][platforms]

# ProcessService
System to host an executable within an XPC service.

## Integration

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/ChimeHQ/ProcessService")
]
```

## Usage

To interact with the service:

```swift
import ProcessServiceClient

let userEnv = try await HostedProcess.userEnvironment(with: "com.myxpcservice")

let process = HostedProcess(named: "com.myxpcservice", parameters: params)
let data = try await process.runAndReadStdout()
```

Here's now to make an XPC service. Make sure to match up the service bundle id with the name you use.

```swift
// main.swift

import Foundation

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        do {
            try newConnection.configureProcessServiceServer()
        } catch {
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

## Suggestions or Feedback

We'd love to hear from you! Get in touch via [twitter](https://twitter.com/chimehq), an issue, or a pull request.

Please note that this project is released with a [Contributor Code of Conduct](CODE_OF_CONDUCT.md). By participating in this project you agree to abide by its terms.

[build status]: https://github.com/ChimeHQ/ProcessService/actions
[build status badge]: https://github.com/ChimeHQ/ProcessService/workflows/CI/badge.svg
[license]: https://opensource.org/licenses/BSD-3-Clause
[license badge]: https://img.shields.io/github/license/ChimeHQ/ProcessService
[platforms]: https://swiftpackageindex.com/ChimeHQ/ProcessService
[platforms badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FChimeHQ%2FProcessService%2Fbadge%3Ftype%3Dplatforms

