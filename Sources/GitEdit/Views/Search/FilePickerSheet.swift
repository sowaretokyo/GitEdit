import SwiftUI

/// ⌘P style center-floating file picker.
struct FilePickerSheet: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel: FilePickerViewModel
    let onSelect: (String) -> Void

    @FocusState private var queryFocused: Bool

    init(
        repository: URL,
        isPresented: Binding<Bool>,
        onSelect: @escaping (String) -> Void
    ) {
        self._isPresented = isPresented
        self.onSelect = onSelect
        self._viewModel = StateObject(wrappedValue: FilePickerViewModel(repository: repository))
    }

    var body: some View {
        VStack(spacing: 0) {
            queryField
            Divider()
            results
        }
        .frame(width: 640, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await viewModel.load()
            queryFocused = true
        }
        .onChange(of: viewModel.query) { _, _ in
            viewModel.recompute()
        }
    }

    private var queryField: some View {
        FilterField(
            text: $viewModel.query,
            prompt: L("ファイルパスで絞り込み"),
            font: .title3,
            imageScale: .large,
            horizontalPadding: DT.Space.lg,
            verticalPadding: DT.Space.md,
            showsClearButton: false,
            isLoading: viewModel.isLoading,
            focus: $queryFocused,
            onSubmit: { confirmSelection() }
        )
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    @ViewBuilder
    private var results: some View {
        if viewModel.results.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { idx, match in
                            FilePickerRow(
                                match: match,
                                isSelected: idx == viewModel.selectedIndex
                            )
                            .id(idx)
                            .onTapGesture {
                                viewModel.selectedIndex = idx
                                confirmSelection()
                            }
                        }
                    }
                    .padding(.vertical, DT.Space.xs)
                }
                .onChange(of: viewModel.selectedIndex) { _, newIdx in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(newIdx, anchor: .center)
                    }
                }
                .background(KeyEventCatcher(
                    onUp: { viewModel.moveSelection(by: -1) },
                    onDown: { viewModel.moveSelection(by: +1) },
                    onEscape: { isPresented = false },
                    onReturn: { confirmSelection() }
                ))
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: viewModel.query.isEmpty
                ? L("ファイル名を入力")
                : L("ファイルが見つかりません"),
            iconSize: 36,
            background: .clear
        )
    }

    private func confirmSelection() {
        guard let match = viewModel.selectedMatch() else { return }
        onSelect(match.path)
        isPresented = false
    }
}

private struct FilePickerRow: View {
    let match: FilePickerViewModel.Match
    let isSelected: Bool

    var body: some View {
        let fileName = (match.path as NSString).lastPathComponent
        let directory = (match.path as NSString).deletingLastPathComponent

        HStack(spacing: DT.Space.sm) {
            Image(systemName: "doc.text")
                .foregroundStyle(.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                highlightedText(text: fileName, ranges: rangesIn(fileName))
                    .font(.callout)
                    .lineLimit(1)
                if !directory.isEmpty {
                    highlightedText(text: directory, ranges: rangesIn(directory))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm - 1)
        .background(
            Rectangle()
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func highlightedText(text: String, ranges: [Range<String.Index>]) -> Text {
        if ranges.isEmpty {
            return Text(text)
        }
        var attr = AttributedString(text)
        for range in ranges {
            if let attrRange = Range(range, in: attr) {
                attr[attrRange].foregroundColor = Color(nsColor: .systemYellow)
                attr[attrRange].font = .body.weight(.semibold)
            }
        }
        return Text(attr)
    }

    /// Restrict the global match-ranges to the substring `text`.
    /// `text` is a substring of `match.path`.
    private func rangesIn(_ text: String) -> [Range<String.Index>] {
        guard let textStart = match.path.range(of: text)?.lowerBound else { return [] }
        let textStartOffset = match.path.distance(from: match.path.startIndex, to: textStart)
        let textLen = text.count
        return match.matchedRanges.compactMap { fullRange -> Range<String.Index>? in
            let loOff = match.path.distance(from: match.path.startIndex, to: fullRange.lowerBound)
            let hiOff = match.path.distance(from: match.path.startIndex, to: fullRange.upperBound)
            let relLo = loOff - textStartOffset
            let relHi = hiOff - textStartOffset
            guard relHi > 0, relLo < textLen else { return nil }
            let clampedLo = max(0, relLo)
            let clampedHi = min(textLen, relHi)
            let lo = text.index(text.startIndex, offsetBy: clampedLo)
            let hi = text.index(text.startIndex, offsetBy: clampedHi)
            return lo..<hi
        }
    }
}

/// Bridges arrow / escape / return keys from AppKit into SwiftUI closures.
private struct KeyEventCatcher: NSViewRepresentable {
    let onUp: () -> Void
    let onDown: () -> Void
    let onEscape: () -> Void
    let onReturn: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyHandlingView()
        view.onUp = onUp
        view.onDown = onDown
        view.onEscape = onEscape
        view.onReturn = onReturn
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? KeyHandlingView else { return }
        view.onUp = onUp
        view.onDown = onDown
        view.onEscape = onEscape
        view.onReturn = onReturn
    }

    private final class KeyHandlingView: NSView {
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?
        var onEscape: (() -> Void)?
        var onReturn: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            switch event.specialKey {
            case .upArrow:    onUp?()
            case .downArrow:  onDown?()
            default:
                if event.keyCode == 53 { // Esc
                    onEscape?()
                } else if event.keyCode == 36 || event.keyCode == 76 { // Return / numpad Enter
                    onReturn?()
                } else {
                    super.keyDown(with: event)
                }
            }
        }
    }
}
