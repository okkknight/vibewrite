import Foundation
import XCTVapor
@testable import VibeWriteBackend
import VibeWriteShared

final class AdminSystemPromptTests: XCTestCase {
    func testAdminSystemPromptRequiresSessionCookie() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(
            app,
            adminUsername: "admin",
            adminPassword: "password"
        )

        try app.test(.GET, "v3/admin/system-prompt", afterResponse: { response in
            XCTAssertEqual(response.status, .unauthorized)
        })
    }

    func testLoggedInAdminCanReadAndUpdateSystemPromptSnapshot() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(
            app,
            adminUsername: "admin",
            adminPassword: "password"
        )

        let cookieHeader = try adminSessionCookieHeader(in: app, username: "admin", password: "password")

        try app.test(.GET, "v3/admin/system-prompt", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminSystemPromptResponse.self, response) { body in
                XCTAssertEqual(body.templateBody, "")
                XCTAssertFalse(body.actionRulesJson.isEmpty)
                XCTAssertFalse(body.modelContextRulesJson.isEmpty)
                XCTAssertNotNil(AdminDateCodec.parse(body.updatedAt))

                guard let actionRules = try? jsonObject(from: body.actionRulesJson),
                      let modelContextRules = try? jsonObject(from: body.modelContextRulesJson) else {
                    XCTFail("Expected valid JSON strings.")
                    return
                }

                XCTAssertNotNil(actionRules["prose"])
                XCTAssertNotNil(actionRules["metadata"])
                XCTAssertNotNil(modelContextRules["providerModel"])
                XCTAssertNotNil(modelContextRules["metadataRoute"])
            }
        })

        try app.test(.PUT, "v3/admin/system-prompt", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
            try request.content.encode(AdminSystemPromptUpdateRequest(
                templateBody: "Updated shared template body",
                actionRulesJson: nil,
                modelContextRulesJson: nil
            ))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminSystemPromptResponse.self, response) { body in
                XCTAssertEqual(body.templateBody, "Updated shared template body")
                XCTAssertNotNil(AdminDateCodec.parse(body.updatedAt))
            }
        })

        let updatedActionRulesJson = """
        {
          "metadata": {
            "continueWriting": ["C1"],
            "edit": ["E1"],
            "startDraft": ["S1"]
          },
          "prose": {
            "continueWriting": ["P2"],
            "edit": ["P3"],
            "startDraft": ["P1"]
          }
        }
        """

        try app.test(.PUT, "v3/admin/system-prompt", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
            try request.content.encode(AdminSystemPromptUpdateRequest(
                templateBody: nil,
                actionRulesJson: updatedActionRulesJson,
                modelContextRulesJson: nil
            ))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminSystemPromptResponse.self, response) { body in
                XCTAssertNotNil((try? jsonObject(from: body.actionRulesJson))?["prose"])
                XCTAssertEqual(body.templateBody, "Updated shared template body")
            }
        })

        let updatedModelContextRulesJson = """
        {
          "metadataRoute": {
            "current": ["current-route"],
            "text01JsonSchema": ["schema-route"]
          },
          "providerModel": ["Provider X", "Model Y"]
        }
        """

        try app.test(.PUT, "v3/admin/system-prompt", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
            try request.content.encode(AdminSystemPromptUpdateRequest(
                templateBody: nil,
                actionRulesJson: nil,
                modelContextRulesJson: updatedModelContextRulesJson
            ))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminSystemPromptResponse.self, response) { body in
                XCTAssertEqual(body.templateBody, "Updated shared template body")
                XCTAssertNotNil((try? jsonObject(from: body.actionRulesJson))?["metadata"])
                XCTAssertNotNil((try? jsonObject(from: body.modelContextRulesJson))?["metadataRoute"])
            }
        })

        try app.test(.GET, "v3/admin/system-prompt", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminSystemPromptResponse.self, response) { body in
                XCTAssertEqual(body.templateBody, "Updated shared template body")
                XCTAssertNotNil((try? jsonObject(from: body.actionRulesJson))?["prose"])
                XCTAssertNotNil((try? jsonObject(from: body.modelContextRulesJson))?["providerModel"])
            }
        })
    }

    func testAdminSystemPromptRejectsInvalidJson() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(
            app,
            adminUsername: "admin",
            adminPassword: "password"
        )

        let cookieHeader = try adminSessionCookieHeader(in: app, username: "admin", password: "password")

        try app.test(.PUT, "v3/admin/system-prompt", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
            try request.content.encode(AdminSystemPromptUpdateRequest(
                templateBody: nil,
                actionRulesJson: "{not json}",
                modelContextRulesJson: nil
            ))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .badRequest)
        })

        try app.test(.PUT, "v3/admin/system-prompt", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
            try request.content.encode(AdminSystemPromptUpdateRequest(
                templateBody: nil,
                actionRulesJson: nil,
                modelContextRulesJson: "{not json}"
            ))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .badRequest)
        })
    }

    private func adminSessionCookieHeader(in app: Application, username: String, password: String) throws -> String {
        var setCookieHeader: String?
        try app.test(.POST, "v3/admin/login", beforeRequest: { request in
            try request.content.encode(AdminLoginRequest(username: username, password: password))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            setCookieHeader = response.headers.first(name: .setCookie)
        })

        guard let sessionToken = AdminSessionCookie.sessionToken(fromSetCookieHeader: setCookieHeader) else {
            XCTFail("Expected admin session cookie to be set.")
            return ""
        }

        return "\(AdminSessionCookie.name)=\(sessionToken)"
    }

    private func jsonObject(from json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw NSError(domain: "AdminSystemPromptTests", code: 1)
        }
        return dictionary
    }
}
