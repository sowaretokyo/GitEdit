import SwiftUI

/// File-menu command that opens the currently selected repository in its
/// own standalone window. Mirrors the sidebar's per-row "Open in New
/// Window" context menu action.
struct OpenInNewWindowButton: View {
    let selectedID: Repository.ID?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L("リポジトリを新しいウィンドウで開く")) {
            guard let selectedID else { return }
            openWindow(id: "repository", value: selectedID)
        }
        .keyboardShortcut("n", modifiers: .command)
        .disabled(selectedID == nil)
    }
}
