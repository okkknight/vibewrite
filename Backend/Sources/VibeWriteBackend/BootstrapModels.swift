import Vapor

struct HealthResponse: Content {
    let status: String
}

struct BootstrapRequest: Content {
    let installationId: String
    let appVersion: String
    let platform: String
    let deviceName: String
}

struct BootstrapResponse: Content {
    let deviceToken: String
    let deviceStatus: DeviceStatus
    let quotaSummary: QuotaSummary
}

enum DeviceStatus: String, Content {
    case active
    case blocked
}

struct QuotaSummary: Content {
    let dailyLimit: Int
    let weeklyLimit: Int

    static let `default` = QuotaSummary(dailyLimit: 50, weeklyLimit: 200)
}
