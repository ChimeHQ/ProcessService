[![Build Status][build status badge]][build status]
[![License][license badge]][license]
[![Platforms][platforms badge]][platforms]
[![Documentation][documentation badge]][documentation]

# ProcessService
System to host an executable within an XPC service.

## Integration

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/ChimeHQ/ProcessService", branch: "main")
]
```

### XPC Service

To be useful, you also need an actual XPC service that hosts the process server. Distributing an XPC service using SPM requires a workaround: bundling a pre-built binary in an xcframework. This comes with two disadvantages. It requires that you both link and embed the framework, which incurs size and potential launch-time impact. And, second, it requires a bootstrapping step to ensure the service can be found at runtime anywhere within the running process.

This is all **optional** and provided for convenience. You can just build your own service if you want.

```swift
import ProcessServiceContainer

ServiceContainer.bootstrap()

let userEnv = try await HostedProcess.userEnvironment(with: ServiceContainer.name)
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

We'd love to hear from you! Get in touch via an issue or pull request.

Please note that this project is released with a [Contributor Code of Conduct](CODE_OF_CONDUCT.md). By participating in this project you agree to abide by its terms.

[build status]: https://github.com/ChimeHQ/ProcessService/actions
[build status badge]: https://github.com/ChimeHQ/ProcessService/workflows/CI/badge.svg
[license]: https://opensource.org/licenses/BSD-3-Clause
[license badge]: https://img.shields.io/github/license/ChimeHQ/ProcessService
[platforms]: https://swiftpackageindex.com/ChimeHQ/ProcessService
[platforms badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FChimeHQ%2FProcessService%2Fbadge%3Ftype%3Dplatforms
[documentation]: https://swiftpackageindex.com/ChimeHQ/ProcessService/main/documentation
[documentation badge]: https://img.shields.io/badge/Documentation-DocC-blue

