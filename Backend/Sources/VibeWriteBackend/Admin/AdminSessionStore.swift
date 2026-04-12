import Foundation

actor AdminSessionStore {
    private let username: String
    private let password: String
    private var activeSessionTokens: Set<String> = []

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func login(username: String, password: String) -> String? {
        guard username == self.username, password == self.password else {
            return nil
        }

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
