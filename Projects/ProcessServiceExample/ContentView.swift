import SwiftUI

import ProcessServiceClient

struct ContentView: View {
	func doTest() async {
		let params = Process.ExecutionParameters(path: "/bin/ls")

		do {
			let remoteProcess = HostedProcess(named: "com.yourcompany.ProcessService", parameters: params)

			let data = try await remoteProcess.runAndReadStdout()
			let value = String(data: data, encoding: .utf8) ?? "nothing"

			print("value: \(value)")
		} catch {
			print("error: \(error)")
		}
	}

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundColor(.accentColor)
            Text("Hello, world!")
        }
        .padding()
		.task {
			await doTest()
		}
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
