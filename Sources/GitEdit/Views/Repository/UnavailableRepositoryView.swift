import SwiftUI

/// Shown inside a standalone repository window when the referenced
/// repository can no longer be resolved in the store — e.g. it was removed
/// from the list or its folder moved after the window was opened.
struct UnavailableRepositoryView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: DT.Space.sm) {
            Spacer()
            Image(systemName: "questionmark.folder")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("リポジトリが見つかりません"))
                .font(.callout.weight(.semibold))
            Text(L("このリポジトリはリストから削除されたか、移動された可能性があります。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(L("ウィンドウを閉じる")) {
                dismissWindow()
            }
            .padding(.top, DT.Space.sm)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
