import SwiftUI

struct AccountsSettingsView: View {
    @StateObject private var store = AccountStore.shared
    @State private var isShowingSignIn = false

    var body: some View {
        Form {
            Section {
                if let account = store.currentAccount {
                    signedInRow(account: account)
                } else {
                    signInRow
                }
            } header: {
                Text(L("GitHub アカウント"))
            } footer: {
                Text(L("プルリクエストやコミットの作者解決などに利用します。トークンは macOS の Keychain に安全に保存されます。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $isShowingSignIn) {
            SignInSheet(isPresented: $isShowingSignIn, store: store)
        }
    }

    private func signedInRow(account: GitHubAccount) -> some View {
        HStack(alignment: .center, spacing: DT.Space.md) {
            AvatarImageView(
                url: account.avatarURL.flatMap { URL(string: $0) },
                initials: String(account.login.prefix(1)).uppercased(),
                tintColor: .accentColor,
                size: 48
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name ?? account.login)
                    .font(.body.weight(.medium))
                Text("@\(account.login)")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                if let email = account.email, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            Button(L("サインアウト")) {
                store.signOut()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private var signInRow: some View {
        Button {
            isShowingSignIn = true
        } label: {
            HStack(spacing: DT.Space.sm) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("GitHub にサインイン…"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(L("Personal Access Token を使って認証します"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
