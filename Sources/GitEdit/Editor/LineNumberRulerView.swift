import AppKit

/// NSRulerView subclass that renders 1-based line numbers next to an NSTextView.
final class LineNumberRulerView: NSRulerView {
    weak var managedTextView: NSTextView?
    private var observers: [NSObjectProtocol] = []

    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.managedTextView = textView
        self.clientView = textView
        self.ruleThickness = 44

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSText.didChangeNotification, object: textView, queue: .main
        ) { [weak self] _ in self?.needsDisplay = true })

        if let clip = textView.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            observers.append(center.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in self?.needsDisplay = true })
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.controlBackgroundColor.withAlphaComponent(0.4).setFill()
        dirtyRect.fill()

        NSColor.separatorColor.withAlphaComponent(0.6).setFill()
        NSRect(x: bounds.maxX - 0.5, y: 0, width: 0.5, height: bounds.height).fill()
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = managedTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let nsText = textView.string as NSString
        guard nsText.length > 0 else {
            // Draw "1" for empty file
            drawNumber("1", at: NSPoint(x: 0, y: 0), in: textView)
            return
        }

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.length > 0 else { return }
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Compute line number of the first visible line
        var lineNumber = 1
        var pos = 0
        while pos < charRange.location && pos < nsText.length {
            let r = nsText.lineRange(for: NSRange(location: pos, length: 0))
            pos = NSMaxRange(r)
            if pos <= charRange.location { lineNumber += 1 }
        }

        // Move to start of the line containing the first visible char
        let firstLineRange = nsText.lineRange(for: NSRange(location: charRange.location, length: 0))
        var current = firstLineRange.location

        let endChar = NSMaxRange(charRange)

        let textInset = textView.textContainerInset.height
        let baseFontSize = textView.font?.pointSize ?? NSFont.systemFontSize
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: baseFontSize - 1, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        while current < nsText.length && current <= endChar {
            let lineCharRange = nsText.lineRange(for: NSRange(location: current, length: 0))
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineCharRange, actualCharacterRange: nil)
            let usedRect = layoutManager.boundingRect(forGlyphRange: lineGlyphRange, in: textContainer)

            let textViewY = usedRect.minY + textInset
            let rulerY = textViewY - visibleRect.minY

            let str = "\(lineNumber)" as NSString
            let size = str.size(withAttributes: attrs)
            let x = ruleThickness - size.width - 8
            str.draw(at: NSPoint(x: x, y: rulerY + 1), withAttributes: attrs)

            current = NSMaxRange(lineCharRange)
            lineNumber += 1
        }

        // Trailing empty line (file ends with newline)
        if nsText.length > 0,
           nsText.character(at: nsText.length - 1) == 10 /* \n */,
           current >= nsText.length {
            let lineGlyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: nsText.length, length: 0),
                actualCharacterRange: nil
            )
            let usedRect = layoutManager.boundingRect(forGlyphRange: lineGlyphRange, in: textContainer)
            let textViewY = usedRect.minY + textInset
            let rulerY = textViewY - visibleRect.minY
            let str = "\(lineNumber)" as NSString
            let size = str.size(withAttributes: attrs)
            let x = ruleThickness - size.width - 8
            str.draw(at: NSPoint(x: x, y: rulerY + 1), withAttributes: attrs)
        }
    }

    private func drawNumber(_ str: String, at pt: NSPoint, in textView: NSTextView) {
        let baseFontSize = textView.font?.pointSize ?? NSFont.systemFontSize
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: baseFontSize - 1, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let nsstr = str as NSString
        let size = nsstr.size(withAttributes: attrs)
        let x = ruleThickness - size.width - 8
        nsstr.draw(at: NSPoint(x: x, y: pt.y + textView.textContainerInset.height + 1), withAttributes: attrs)
    }
}
