import SwiftUI
import AppKit

/// A SwiftUI wrapper around an editable `NSTextView` with monospaced font,
/// undo support, line-number gutter, and per-line background highlights.
///
/// Built on top of Apple's `NSTextView.scrollableTextView()` factory so the
/// scroll view, clip view, text container, layout manager, and text storage
/// are all wired up by AppKit itself (avoiding subtle bugs from manual setup).
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    let highlightedLines: Set<Int>
    let isEditable: Bool
    let onSave: () -> Void

    private static let editorFont: NSFont = .monospacedSystemFont(ofSize: 12.5, weight: .regular)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // Canonical factory — guarantees the layout pipeline is correct.
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // Code-editor-friendly text container: no soft wrap, scroll horizontally.
        textView.isHorizontallyResizable = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        if let container = textView.textContainer {
            container.widthTracksTextView = false
            container.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            container.lineFragmentPadding = 6
        }

        // Make sure the text view always has a defined font + color.
        textView.font = Self.editorFont
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.insertionPointColor = .controlAccentColor
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
        textView.isEditable = isEditable

        // Initial content with explicit attributes.
        setText(text, on: textView)

        // Line-number ruler.
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.installSaveMonitor()
        applyHighlights(to: textView, lines: highlightedLines)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let oldRange = textView.selectedRange()
            setText(text, on: textView)
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

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.removeSaveMonitor()
    }

    /// Replace the text storage with an attributed string that carries
    /// explicit font + color attributes so the rendered text is always visible.
    private func setText(_ string: String, on textView: NSTextView) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.editorFont,
            .foregroundColor: NSColor.textColor
        ]
        if let storage = textView.textStorage {
            let attributed = NSAttributedString(string: string, attributes: attrs)
            storage.beginEditing()
            storage.setAttributedString(attributed)
            storage.endEditing()
        } else {
            textView.string = string
        }
        textView.typingAttributes = attrs
        textView.layoutManager?.ensureLayout(for: textView.textContainer ?? NSTextContainer())
        textView.needsDisplay = true
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
        private var saveMonitor: Any?

        init(_ parent: CodeEditor) {
            self.parent = parent
        }

        deinit {
            removeSaveMonitor()
        }

        func installSaveMonitor() {
            removeSaveMonitor()
            saveMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      event.modifierFlags.contains(.command),
                      !event.modifierFlags.contains(.shift),
                      event.charactersIgnoringModifiers == "s",
                      let textView = self.textView,
                      event.window === textView.window,
                      textView.window?.firstResponder === textView
                else {
                    return event
                }
                self.parent.onSave()
                return nil
            }
        }

        func removeSaveMonitor() {
            if let monitor = saveMonitor {
                NSEvent.removeMonitor(monitor)
                saveMonitor = nil
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            ruler?.needsDisplay = true
        }
    }
}
