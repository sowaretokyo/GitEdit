import SwiftUI
import AppKit

/// A multi-line text editor that maps ↑↓ (when the caret is on the first/last line
/// and the field isn't being navigated otherwise) to navigate `history`.
/// -1 represents the user's current draft; 0..<history.count walks older commits.
struct HistoryAwareTextEditor: NSViewRepresentable {
    @Binding var text: String
    let history: [String]
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 2, height: 2)
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = false
        textView.string = text

        context.coordinator.textView = textView
        context.coordinator.installPlaceholder(text: placeholder)
        context.coordinator.updatePlaceholderVisibility()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.resetHistoryIfEdited()
        }
        context.coordinator.updatePlaceholderVisibility()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HistoryAwareTextEditor
        weak var textView: NSTextView?
        private var historyIndex: Int = -1
        private var draft: String = ""
        private let placeholderLabel = NSTextField(labelWithString: "")

        init(_ parent: HistoryAwareTextEditor) {
            self.parent = parent
        }

        func installPlaceholder(text: String) {
            placeholderLabel.stringValue = text
            placeholderLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
            placeholderLabel.textColor = .tertiaryLabelColor
            placeholderLabel.isEditable = false
            placeholderLabel.isBordered = false
            placeholderLabel.backgroundColor = .clear
            placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

            guard let tv = textView else { return }
            tv.addSubview(placeholderLabel)
            NSLayoutConstraint.activate([
                placeholderLabel.leadingAnchor.constraint(equalTo: tv.leadingAnchor, constant: 5),
                placeholderLabel.topAnchor.constraint(equalTo: tv.topAnchor, constant: 2)
            ])
        }

        func updatePlaceholderVisibility() {
            placeholderLabel.isHidden = !(textView?.string.isEmpty ?? false)
        }

        func resetHistoryIfEdited() {
            historyIndex = -1
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            historyIndex = -1
            updatePlaceholderVisibility()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                return navigate(.older, in: textView)
            case #selector(NSResponder.moveDown(_:)):
                return navigate(.newer, in: textView)
            default:
                return false
            }
        }

        private enum Direction { case older, newer }

        private func navigate(_ direction: Direction, in textView: NSTextView) -> Bool {
            guard !parent.history.isEmpty else { return false }

            let nsString = textView.string as NSString
            let selection = textView.selectedRange()
            let lineRange = nsString.lineRange(for: NSRange(location: min(selection.location, nsString.length), length: 0))
            let isFirstLine = lineRange.location == 0
            let isLastLine = NSMaxRange(lineRange) >= nsString.length

            switch direction {
            case .older:
                guard isFirstLine else { return false }
                if historyIndex == -1 { draft = textView.string }
                let next = historyIndex + 1
                guard next < parent.history.count else { return true }
                historyIndex = next
                setText(parent.history[next], in: textView)
                return true

            case .newer:
                guard isLastLine, historyIndex >= 0 else { return false }
                let next = historyIndex - 1
                historyIndex = next
                let msg = (next == -1) ? draft : parent.history[next]
                setText(msg, in: textView)
                return true
            }
        }

        private func setText(_ string: String, in textView: NSTextView) {
            textView.string = string
            parent.text = string
            let end = (string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            updatePlaceholderVisibility()
        }
    }
}
