import SwiftUI
import AppKit

/// Browser-based GitHub OAuth sign-in (Device Authorization Grant).
/// Modeled after GitHub Desktop's "Sign in Using Your Browser" sheet — the only
/// UX difference is the user pasting an 8-char code in the browser (a Device Flow
/// requirement, since the SwiftPM environment can't easily host a custom URL scheme).
struct DeviceFlowSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var store: AccountStore

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.lg) {
            header
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(DT.Space.xl)
        .frame(width: 540)
        .onAppear { store.dismissError() }
        .onDisappear {
            if store.isPollingForToken || store.isAuthenticating {
                store.cancelDeviceFlow()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DT.Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L("ブラウザでサインイン"))
                    .font(.title3.weight(.semibold))
                Text(L("ブラウザで GitHub のサインインを完了します。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Content (state machine)

    @ViewBuilder
    private var content: some View {
        if let code = store.deviceCode {
            codeStateView(code: code)
        } else if store.isAuthenticating {
            preparingView
        } else if let error = store.lastError {
            errorStateView(message: error)
        } else {
            initialStateView
        }
    }

    private var initialStateView: some View {
        VStack(alignment: .leading, spacing: DT.Space.md) {
            HStack(alignment: .top, spacing: DT.Space.sm) {
                Image(systemName: "1.circle.fill")
                    .foregroundStyle(.tint)
                Text(L("「ブラウザで続ける」を押すと、新しいタブが開きます。"))
            }
            HStack(alignment: .top, spacing: DT.Space.sm) {
                Image(systemName: "2.circle.fill")
                    .foregroundStyle(.tint)
                Text(L("表示される 8 文字のコードを GitHub の画面に貼り付け、Authorize を押してください。"))
            }
            HStack(alignment: .top, spacing: DT.Space.sm) {
                Image(systemName: "3.circle.fill")
                    .foregroundStyle(.tint)
                Text(L("承認するとブラウザを閉じて、ここに戻ってきてください。自動でサインインが完了します。"))
            }
        }
        .font(.callout)
        .padding(DT.Space.md)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                .fill(Color.accentColor.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var preparingView: some View {
        HStack(spacing: DT.Space.sm) {
            ProgressView().controlSize(.small)
            Text(L("認証コードを取得しています…"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DT.Space.md)
    }

    private func codeStateView(code: GitHubAuth.DeviceCode) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.md) {
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text(L("認証コード"))
                    .font(.callout.weight(.medium))
                Text(L("クリップボードにコピー済みです。ブラウザの欄に貼り付けてください。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: DT.Space.sm) {
                Text(code.userCode)
                    .font(.system(.title, design: .monospaced).weight(.bold))
                    .tracking(2)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, DT.Space.lg)
                    .padding(.vertical, DT.Space.md)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                            .fill(Color.accentColor.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5)
                    )
                    .textSelection(.enabled)

                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(code.userCode, forType: .string)
                } label: {
                    Label(L("コピー"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }

            Button {
                if let url = URL(string: code.verificationURI) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(L("もう一度ブラウザを開く"), systemImage: "safari")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if store.isPollingForToken {
                HStack(spacing: DT.Space.sm) {
                    ProgressView().controlSize(.small)
                    Text(L("ブラウザでの承認を待っています…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, DT.Space.xs)
            }
        }
    }

    private func errorStateView(message: String) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            HStack(alignment: .top, spacing: DT.Space.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(nsColor: .systemRed))
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DT.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .systemRed).opacity(0.1))
            )
            Button(L("もう一度試す")) {
                store.startDeviceFlow()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button(L("キャンセル")) {
                store.cancelDeviceFlow()
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)

            if store.deviceCode == nil && !store.isAuthenticating {
                Button {
                    store.startDeviceFlow()
                } label: {
                    Label(L("ブラウザで続ける"), systemImage: "safari")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onChange(of: store.currentAccount?.login) { _, newLogin in
            // Sign-in succeeded — close the sheet.
            if newLogin != nil {
                isPresented = false
            }
        }
    }
}
