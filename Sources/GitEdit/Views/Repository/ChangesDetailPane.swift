import SwiftUI

/// Right-hand detail pane for the Changes tab.
/// Delegates to DiffEditView when a file is selected; otherwise shows an
/// empty state similar to GitHub Desktop's "No local changes" view.
struct ChangesDetailPane: View {
    @ObservedObject var viewModel: ChangesViewModel
    @ObservedObject var repoVM: RepositoryViewModel

    var body: some View {
        if viewModel.selectedChange != nil {
            DiffEditView(viewModel: viewModel)
        } else if viewModel.changes.isEmpty {
            cleanState
        } else {
            pickFilePrompt
        }
    }

    private var cleanState: some View {
        VStack(spacing: DT.Space.xl) {
            VStack(spacing: DT.Space.md) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .green.opacity(0.2), radius: 16, y: 4)

                Text(L("ローカル変更はありません"))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))

                Text(L("このリポジトリにはまだコミット待ちの変更はありません。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            if repoVM.ahead > 0 {
                pushHint
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pushHint: some View {
        HStack(alignment: .top, spacing: DT.Space.md) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "arrow.up.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L("origin に %d 件のコミットをプッシュできます", repoVM.ahead))
                    .font(.body.weight(.semibold))
                Text(L("ツールバーの「プッシュ」ボタンを押してください。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                Task { await repoVM.push() }
            } label: {
                Text(L("プッシュ"))
                    .frame(minWidth: 80)
            }
            .buttonStyle(.borderedProminent)
            .disabled(repoVM.isBusy)
        }
        .padding(DT.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5)
        )
        .frame(maxWidth: 520)
    }

    private var pickFilePrompt: some View {
        VStack(spacing: DT.Space.sm) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("左のリストからファイルを選択"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(L("差分がここに表示されます"))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
