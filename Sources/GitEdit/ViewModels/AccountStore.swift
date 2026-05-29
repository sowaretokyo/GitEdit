import Foundation
import SwiftUI
import AppKit

/// Shared store for the signed-in GitHub account.
/// Token lives in the Keychain; account profile is mirrored to UserDefaults
/// so the UI can render immediately on launch.
@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    /// Default OAuth client_id — `gh` CLI's well-known public client_id, which
    /// supports Device Flow with the scopes we need. Override via
    /// `UserDefaults.standard.set(_, forKey: "githubClientID")` if you'd like
    /// to use your own OAuth App.
    static let defaultClientID = "178c6fc778ccc68e1d6a"

    private static let keychainAccount = "github.com:default"
    private static let defaultsKey = "githubAccount"
    private static let clientIDKey = "githubClientID"

    @Published private(set) var currentAccount: GitHubAccount?
    @Published var isAuthenticating: Bool = false
    @Published var deviceCode: GitHubAuth.DeviceCode?
    @Published var isPollingForToken: Bool = false
    @Published var lastError: String?

    private var pollingTask: Task<Void, Never>?

    var isSignedIn: Bool { currentAccount != nil && currentToken != nil }

    var currentToken: String? {
        KeychainStore.readString(account: Self.keychainAccount)
    }

    var clientID: String {
        UserDefaults.standard.string(forKey: Self.clientIDKey) ?? Self.defaultClientID
    }

    private init() {
        loadStoredAccount()
    }

    // MARK: - Sign in (Device Flow — primary path)

    func startDeviceFlow() {
        pollingTask?.cancel()
        lastError = nil
        deviceCode = nil
        isPollingForToken = false
        isAuthenticating = true

        pollingTask = Task { [weak self] in
            await self?.performDeviceFlow()
        }
    }

    func cancelDeviceFlow() {
        pollingTask?.cancel()
        pollingTask = nil
        deviceCode = nil
        isPollingForToken = false
        isAuthenticating = false
    }

    private func performDeviceFlow() async {
        defer { isAuthenticating = false }

        let auth = GitHubAuth(clientID: clientID)

        do {
            let code = try await auth.requestDeviceCode()
            try Task.checkCancellation()

            deviceCode = code
            copyToPasteboard(code.userCode)
            openVerificationURL(code.verificationURI)

            isPollingForToken = true
            defer { isPollingForToken = false }

            let token = try await auth.pollForToken(
                deviceCode: code.deviceCode,
                initialInterval: code.interval
            )
            try Task.checkCancellation()

            let api = GitHubAPI(token: token)
            let user = try await api.currentUser()
            try Task.checkCancellation()

            try KeychainStore.save(string: token, account: Self.keychainAccount)
            if let encoded = try? JSONEncoder().encode(user) {
                UserDefaults.standard.set(encoded, forKey: Self.defaultsKey)
            }
            currentAccount = user
            deviceCode = nil
        } catch is CancellationError {
            // Cancelled by the user — no error to surface.
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func openVerificationURL(_ uri: String) {
        guard let url = URL(string: uri) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Sign out

    func signOut() {
        pollingTask?.cancel()
        _ = try? KeychainStore.delete(account: Self.keychainAccount)
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        currentAccount = nil
        lastError = nil
        deviceCode = nil
        isPollingForToken = false
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
