import SwiftUI
import AppKit

/// A SwiftUI wrapper around an editable `NSTextView` with monospaced font,
/// undo support, line-number gutter, and per-line background highlights.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    let highlightedLines: Set<Int>
    let isEditable: Bool
    let onSave: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let contentSize = scrollView.contentSize
        let textView = EditorTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        if let container = textView.textContainer {
            container.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            container.widthTracksTextView = true
            container.lineFragmentPadding = 6
        }

        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.string = text
        textView.isEditable = isEditable
        textView.saveAction = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onSave()
        }

        scrollView.documentView = textView

        // Line number ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        applyHighlights(to: textView, lines: highlightedLines)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let oldRange = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            let clamped = NSRange(
                location: min(oldRange.location, length),
                length: 0
            )
            textView.setSelectedRange(clamped)
        }
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        applyHighlights(to: textView, lines: highlightedLines)
        context.coordinator.ruler?.needsDisplay = true
    }

    private func applyHighlights(to textView: NSTextView, lines: Set<Int>) {
        guard let storage = textView.textStorage else { return }
        let nsString = storage.string as NSString
        let length = nsString.length
        let fullRange = NSRange(location: 0, length: length)

        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: fullRange)

        guard !lines.isEmpty, length > 0 else {
            storage.endEditing()
            return
        }

        let highlight = NSColor.systemGreen.withAlphaComponent(0.18)

        var lineNumber = 1
        var idx = 0
        while idx < length {
            let lineRange = nsString.lineRange(for: NSRange(location: idx, length: 0))
            if lines.contains(lineNumber) {
                storage.addAttribute(.backgroundColor, value: highlight, range: lineRange)
            }
            idx = NSMaxRange(lineRange)
            lineNumber += 1
        }
        storage.endEditing()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?

        init(_ parent: CodeEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            ruler?.needsDisplay = true
        }
    }
}

/// `NSTextView` subclass that calls `saveAction` on Cmd+S.
final class EditorTextView: NSTextView {
    var saveAction: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "s" {
            saveAction?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
