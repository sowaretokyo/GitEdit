import SwiftUI

/// Standard cancel/default-action pair used by form sheets.
struct SheetActionButtons: View {
    let actionTitle: String
    let isActionEnabled: Bool
    let isWorking: Bool
    var actionMinWidth: CGFloat? = 80
    let onCancel: () -> Void
    let onAction: () -> Void

    var body: some View {
        Group {
            Button(L("キャンセル"), action: onCancel)
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)

            Button(action: onAction) {
                Text(actionTitle)
                    .frame(minWidth: actionMinWidth)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!isActionEnabled)
        }
    }
}
