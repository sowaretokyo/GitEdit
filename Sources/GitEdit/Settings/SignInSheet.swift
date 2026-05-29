import SwiftUI
import AppKit

struct SignInSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var store: AccountStore
    @State private var token: String = ""

    private let tokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo,user:email&description=GitEdit")!

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.lg) {
            header
            instructions
            tokenField
            errorBanner
            Spacer(minLength: 0)
            footer
        }
        .padding(DT.Space.xl)
        .frame(width: 560)
        .onAppear { store.dismissError() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DT.Space.xs) {
            HStack(spacing: DT.Space.sm) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title)
                    .foregroundStyle(.tint)
                Text(L("GitHub にサインイン"))
                    .font(.title2.weight(.semibold))
            }
            Text(L("Personal Access Token (Classic) を貼り付けてください。"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            Text(L("トークンの作成"))
                .font(.callout.weight(.medium))
            Text(L("GitHub のトークン発行画面で `repo` と `user:email` の権限を付与したトークンを発行してください。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NSWorkspace.shared.open(tokenURL)
            } label: {
                Label(L("GitHub でトークンを発行…"), systemImage: "safari")
            }
            .buttonStyle(.bordered)
        }
        .padding(DT.Space.md)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.5)
        )
    }

    private var tokenField: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            Text(L("トークン"))
                .font(.callout.weight(.medium))
            SecureField("ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", text: $token)
                .textFieldStyle(.roundedBorder)
                .disabled(store.isAuthenticating)
                .onSubmit { Task { await performSignIn() } }
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = store.lastError {
            HStack(alignment: .top, spacing: DT.Space.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(nsColor: .systemRed))
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(DT.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .systemRed).opacity(0.1))
            )
        }
    }

    private var footer: some View {
        HStack {
            if store.isAuthenticating {
                ProgressView().controlSize(.small)
                Text(L("認証中…"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("キャンセル")) { isPresented = false }
                .keyboardShortcut(.cancelAction)
                .disabled(store.isAuthenticating)
            Button {
                Task { await performSignIn() }
            } label: {
                Text(L("サインイン"))
                    .frame(minWidth: 80)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isAuthenticating)
        }
    }

    private func performSignIn() async {
        await store.signIn(token: token)
        if store.currentAccount != nil {
            isPresented = false
        }
    }
}
