import SwiftUI
import AppKit

/// Single-line `NSTextField` wrapper with ↑↓ commit-message history navigation.
/// Use this instead of `HistoryAwareTextEditor` when the field should behave
/// like a one-line input (e.g. the Summary line of a commit message), so the
/// placeholder is vertically centered naturally by AppKit.
struct HistoryAwareTextField: NSViewRepresentable {
    @Binding var text: String
    let history: [String]
    let placeholder: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.backgroundColor = .clear
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.textColor = .textColor
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: HistoryAwareTextField
        private var historyIndex: Int = -1
        private var draft: String = ""

        init(_ parent: HistoryAwareTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
            historyIndex = -1
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                return navigate(.older, control: control)
            case #selector(NSResponder.moveDown(_:)):
                return navigate(.newer, control: control)
            default:
                return false
            }
        }

        private enum Direction { case older, newer }

        private func navigate(_ direction: Direction, control: NSControl) -> Bool {
            guard !parent.history.isEmpty,
                  let field = control as? NSTextField else { return false }

            switch direction {
            case .older:
                if historyIndex == -1 { draft = field.stringValue }
                let next = historyIndex + 1
                guard next < parent.history.count else { return true }
                historyIndex = next
                let msg = parent.history[next]
                field.stringValue = msg
                parent.text = msg
                return true

            case .newer:
                guard historyIndex >= 0 else { return false }
                let next = historyIndex - 1
                historyIndex = next
                let msg = next == -1 ? draft : parent.history[next]
                field.stringValue = msg
                parent.text = msg
                return true
            }
        }
    }
}
