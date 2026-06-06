import SwiftUI
import AppKit

/// SwiftUI wrapper around an editable `NSTextView`, with monospaced font,
/// undo, line-number gutter and per-line background highlights.
///
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    let highlightedLines: Set<Int>
    let isEditable: Bool
    let onSave: () -> Void

    private static let editorFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        configureTextView(textView)
        // Delegate + editability must be wired here (configureTextView has no
        // access to the context). Without the delegate, `textDidChange` never
        // fires and edits never propagate back to the binding.
        textView.delegate = context.coordinator
        textView.isEditable = isEditable

        // Set up the ruler BEFORE the initial text — adding the ruler later
        // shrinks the textView's clip area and the previously-laid-out glyphs
        // never get re-drawn, leaving the body invisible.
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler

        // Initial content with explicit color in storage.
        applyText(text, to: textView)

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
            applyText(text, to: textView)
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

    // MARK: - Setup helpers

    private func configureTextView(_ textView: NSTextView) {
        textView.font = Self.editorFont
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
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
        textView.textContainerInset = NSSize(width: 6, height: 8)
        // Standard wrap-to-width layout — the textContainer width tracks the
        // text view and the text view's width tracks the scroll view's clip.
        // This is what `scrollableTextView()` gives us by default; we just
        // make sure nothing later overrides it.
        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.lineFragmentPadding = 4
        }
    }

    private func applyText(_ string: String, to textView: NSTextView) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.editorFont,
            .foregroundColor: NSColor.textColor
        ]
        guard let storage = textView.textStorage else {
            textView.string = string
            return
        }
        let attributed = NSAttributedString(string: string, attributes: attrs)
        storage.beginEditing()
        storage.setAttributedString(attributed)
        storage.endEditing()
        textView.typingAttributes = attrs
        // Force the layout manager to re-lay out and the view to redraw,
        // otherwise glyphs from an earlier (possibly empty) state can be
        // cached invisibly.
        if let layout = textView.layoutManager, let container = textView.textContainer {
            layout.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: attributed.length))
            layout.ensureLayout(for: container)
        }
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
