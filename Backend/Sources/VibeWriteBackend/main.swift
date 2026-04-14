import Dispatch
import Logging
import Vapor

final class StartupErrorBox: @unchecked Sendable {
    var error: Error?
}

var environment = try Environment.detect()
try LoggingSystem.bootstrap(from: &environment)

let app = Application(environment)
defer { app.shutdown() }

if let bootstrapper = try configure(app) {
    let startupSemaphore = DispatchSemaphore(value: 0)
    let startupErrorBox = StartupErrorBox()
    Task {
        do {
            try await bootstrapper.prepare()
        } catch {
            startupErrorBox.error = error
        }
        startupSemaphore.signal()
    }

    startupSemaphore.wait()
    if let startupError = startupErrorBox.error {
        throw startupError
    }
}

try app.run()
