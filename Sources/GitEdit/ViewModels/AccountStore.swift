import Foundation
import SwiftUI

/// Shared store for the signed-in GitHub account.
/// Token lives in the Keychain; account profile is mirrored to UserDefaults
/// so the UI can render immediately on launch.
@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    private static let keychainAccount = "github.com:default"
    private static let defaultsKey = "githubAccount"

    @Published private(set) var currentAccount: GitHubAccount?
    @Published var isAuthenticating: Bool = false
    @Published var lastError: String?

    var isSignedIn: Bool { currentAccount != nil && currentToken != nil }

    var currentToken: String? {
        KeychainStore.readString(account: Self.keychainAccount)
    }

    private init() {
        loadStoredAccount()
    }

    // MARK: - Sign in / out

    func signIn(token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isAuthenticating = true
        defer { isAuthenticating = false }
        lastError = nil

        do {
            let api = GitHubAPI(token: trimmed)
            let user = try await api.currentUser()
            try KeychainStore.save(string: trimmed, account: Self.keychainAccount)
            if let encoded = try? JSONEncoder().encode(user) {
                UserDefaults.standard.set(encoded, forKey: Self.defaultsKey)
            }
            currentAccount = user
        } catch {
            lastError = L("認証に失敗: %@", error.localizedDescription)
        }
    }

    func signOut() {
        _ = try? KeychainStore.delete(account: Self.keychainAccount)
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        currentAccount = nil
        lastError = nil
    }

    func dismissError() {
        lastError = nil
    }

    // MARK: - Restore

    private func loadStoredAccount() {
        guard KeychainStore.readString(account: Self.keychainAccount) != nil else {
            return
        }
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let account = try? JSONDecoder().decode(GitHubAccount.self, from: data) else {
            return
        }
        currentAccount = account
    }
}
