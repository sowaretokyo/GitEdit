import SwiftUI

/// Name-input sheet shared by "create group" and "rename group" — the two
/// flows differ only in title, confirm-button label, and initial text.
struct GroupNameSheet: View {
    let title: String
    let confirmTitle: String
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(title: String, confirmTitle: String, name: String, onSubmit: @escaping (String) -> Void) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.onSubmit = onSubmit
        _name = State(initialValue: name)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.lg) {
            Text(title)
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: DT.Space.sm) {
                Text(L("グループ名"))
                    .font(.callout.weight(.medium))
                TextField(L("例: 仕事"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
            }

            HStack {
                Spacer()
                Button(L("キャンセル")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    submit()
                } label: {
                    Text(confirmTitle)
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(DT.Space.xl)
        .frame(width: 360)
    }

    private func submit() {
        guard canSubmit else { return }
        onSubmit(trimmedName)
        dismiss()
    }
}
