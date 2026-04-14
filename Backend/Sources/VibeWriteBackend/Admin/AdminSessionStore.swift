import Foundation

actor AdminSessionStore: VibeWriteAdminSessionStore {
    private var activeSessionTokens: Set<String> = []

    func issueSession() -> String {
        let sessionToken = UUID().uuidString.lowercased()
        activeSessionTokens.insert(sessionToken)
        return sessionToken
    }

    func isAuthenticated(sessionToken: String?) -> Bool {
        guard let sessionToken else {
            return false
        }

        return activeSessionTokens.contains(sessionToken)
    }

    func logout(sessionToken: String?) {
        guard let sessionToken else {
            return
        }

        activeSessionTokens.remove(sessionToken)
    }
}
