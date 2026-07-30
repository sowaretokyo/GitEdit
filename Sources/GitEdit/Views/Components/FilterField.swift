import SwiftUI

/// Search/filter input with a leading symbol and optional clear/loading affordances.
struct FilterField: View {
    @Binding var text: String

    let prompt: String
    var systemImage: String = "magnifyingglass"
    var font: Font = .callout
    var imageScale: Image.Scale = .medium
    var horizontalPadding: CGFloat = DT.Space.md
    var verticalPadding: CGFloat = DT.Space.sm
    var showsClearButton: Bool = true
    var isLoading: Bool = false
    var focus: FocusState<Bool>.Binding? = nil
    var onClear: (() -> Void)? = nil
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: systemImage)
                .imageScale(imageScale)
                .foregroundStyle(.secondary)

            input

            if showsClearButton && !text.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            if isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }

    @ViewBuilder
    private var input: some View {
        if let focus {
            textField.focused(focus)
        } else {
            textField
        }
    }

    private var textField: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .onSubmit { onSubmit?() }
    }

    private func clear() {
        if let onClear {
            onClear()
        } else {
            text = ""
        }
    }
}
