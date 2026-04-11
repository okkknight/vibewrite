import Foundation

actor InMemoryDeviceRegistry {
    private var deviceTokensByInstallationId: [String: String] = [:]

    func deviceToken(for installationId: String) -> String {
        if let existingToken = deviceTokensByInstallationId[installationId] {
            return existingToken
        }

        let newToken = Self.makeDeviceToken()
        deviceTokensByInstallationId[installationId] = newToken
        return newToken
    }

    private static func makeDeviceToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
