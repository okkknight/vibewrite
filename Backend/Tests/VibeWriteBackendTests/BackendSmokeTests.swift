import XCTVapor
@testable import VibeWriteBackend

final class BackendSmokeTests: XCTestCase {
    func testHealthEndpointReturnsOk() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app)

        try app.test(.GET, "v3/health", afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(HealthResponse.self, response) { health in
                XCTAssertEqual(health.status, "ok")
            }
        })
    }

    func testBootstrapReusesDeviceTokenForSameInstallationId() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app)

        let bootstrapRequest = BootstrapRequest(
            installationId: "installation-001",
            appVersion: "3.0.0",
            platform: "macOS",
            deviceName: "QA Mac"
        )

        var firstToken = ""
        try app.test(.POST, "v3/client/bootstrap", beforeRequest: { request in
            try request.content.encode(bootstrapRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)

            XCTAssertContent(BootstrapResponse.self, response) { decoded in
                XCTAssertEqual(decoded.deviceStatus, .active)
                XCTAssertEqual(decoded.quotaSummary.dailyLimit, 50)
                XCTAssertEqual(decoded.quotaSummary.weeklyLimit, 200)
                firstToken = decoded.deviceToken
            }
            XCTAssertFalse(firstToken.isEmpty)
        })

        try app.test(.POST, "v3/client/bootstrap", beforeRequest: { request in
            try request.content.encode(bootstrapRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)

            XCTAssertContent(BootstrapResponse.self, response) { decoded in
                XCTAssertEqual(decoded.deviceToken, firstToken)
                XCTAssertEqual(decoded.deviceStatus, .active)
                XCTAssertEqual(decoded.quotaSummary.dailyLimit, 50)
                XCTAssertEqual(decoded.quotaSummary.weeklyLimit, 200)
            }
        })
    }
}
