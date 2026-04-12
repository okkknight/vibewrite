import Foundation
import Vapor
import VibeWriteShared

struct AdminLoginRequest: Content {
    let username: String
    let password: String
}

struct AdminStatusResponse: Content {
    let status: String
}

struct AdminSecretsUpdateRequest: Content {
    let providerApiKey: String?
    let adminUsername: String?
    let adminPassword: String?
}

struct AdminSecretsResponse: Content {
    let providerApiKeyConfigured: Bool
    let adminUsername: String
    let adminPasswordConfigured: Bool
    let updatedAt: String
}

struct AdminRequestQuery: Content {
    let installationId: String?
    let action: WritingAIAction?
    let status: RequestLogStatus?
    let errorCode: String?
    let createdAtStart: String?
    let createdAtEnd: String?
}

enum AdminDateCodec {
    private static func makeFractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func makePlainFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    static func parse(_ value: String) -> Date? {
        makeFractionalFormatter().date(from: value) ?? makePlainFormatter().date(from: value)
    }

    static func string(from date: Date) -> String {
        makeFractionalFormatter().string(from: date)
    }
}

actor AdminSecretStore {
    struct Snapshot: Sendable, Equatable {
        let providerApiKey: String?
        let adminUsername: String
        let adminPassword: String
        let updatedAt: Date

        var providerApiKeyConfigured: Bool {
            guard let providerApiKey else {
                return false
            }

            return !providerApiKey.isEmpty
        }

        var adminPasswordConfigured: Bool {
            !adminPassword.isEmpty
        }
    }

    private let clock: any VibeWriteClock
    private var snapshot: Snapshot

    init(
        providerApiKey: String?,
        adminUsername: String,
        adminPassword: String,
        clock: any VibeWriteClock = SystemVibeWriteClock()
    ) {
        self.clock = clock
        self.snapshot = Snapshot(
            providerApiKey: providerApiKey,
            adminUsername: adminUsername,
            adminPassword: adminPassword,
            updatedAt: clock.now()
        )
    }

    func authenticate(username: String, password: String) -> Bool {
        snapshot.adminUsername == username && snapshot.adminPassword == password
    }

    func providerApiKey() -> String? {
        snapshot.providerApiKey
    }

    func currentSnapshot() -> Snapshot {
        snapshot
    }

    func snapshotResponse() -> AdminSecretsResponse {
        AdminSecretsResponse(
            providerApiKeyConfigured: snapshot.providerApiKeyConfigured,
            adminUsername: snapshot.adminUsername,
            adminPasswordConfigured: snapshot.adminPasswordConfigured,
            updatedAt: AdminDateCodec.string(from: snapshot.updatedAt)
        )
    }

    func update(
        providerApiKey: String? = nil,
        adminUsername: String? = nil,
        adminPassword: String? = nil
    ) {
        guard providerApiKey != nil || adminUsername != nil || adminPassword != nil else {
            return
        }

        snapshot = Snapshot(
            providerApiKey: providerApiKey ?? snapshot.providerApiKey,
            adminUsername: adminUsername ?? snapshot.adminUsername,
            adminPassword: adminPassword ?? snapshot.adminPassword,
            updatedAt: clock.now()
        )
    }
}

enum AdminSessionCookie {
    static let name = "vibewrite_admin_session"

    static func sessionToken(from request: Request) -> String? {
        sessionToken(fromCookieHeader: request.headers.first(name: .cookie))
    }

    static func loginHeader(for sessionToken: String) -> String {
        makeCookieHeader(value: sessionToken)
    }

    static func logoutHeader() -> String {
        makeCookieHeader(value: "", maxAge: 0)
    }

    static func sessionToken(fromSetCookieHeader header: String?) -> String? {
        sessionToken(fromCookieHeader: header)
    }

    private static func sessionToken(fromCookieHeader header: String?) -> String? {
        guard let header else {
            return nil
        }

        for component in header.split(separator: ";") {
            let pair = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else {
                continue
            }

            let key = pair[0].trimmingCharacters(in: .whitespaces)
            guard key == name else {
                continue
            }

            return pair[1].trimmingCharacters(in: .whitespaces).isEmpty ? nil : String(pair[1].trimmingCharacters(in: .whitespaces))
        }

        return nil
    }

    private static func makeCookieHeader(value: String, maxAge: Int? = nil) -> String {
        var parts = [
            "\(name)=\(value)",
            "Path=/",
            "HttpOnly",
            "SameSite=Lax"
        ]

        if let maxAge {
            parts.append("Max-Age=\(maxAge)")
            if maxAge == 0 {
                parts.append("Expires=Thu, 01 Jan 1970 00:00:00 GMT")
            }
        }

        return parts.joined(separator: "; ")
    }
}
