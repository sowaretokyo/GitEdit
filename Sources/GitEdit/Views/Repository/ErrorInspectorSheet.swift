import SwiftUI
import AppKit

/// Modal sheet that explains a classified `GitOperationError` in detail.
///
/// Structure (top → bottom):
///   1. Header: status icon + operation label + classified title
///   2. Summary paragraph: friendly explanation of the cause
///   3. Suggestions: actionable buttons (Pull / Fetch / Retry / etc.)
///   4. Collapsible details: `git` command + raw stderr, with a Copy button
struct ErrorInspectorSheet: View {
    let error: GitOperationError
    @ObservedObject var repoVM: RepositoryViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var detailsExpanded: Bool = false
    @State private var didCopy: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DT.Space.lg) {
                    summarySection
                    if !error.suggestions.isEmpty {
                        suggestionsSection
                    }
                    detailsSection
                }
                .padding(DT.Space.lg)
            }

            Divider()
            footer
        }
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 720, minHeight: 420, idealHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: DT.Space.md) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .systemRed).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.large)
                    .foregroundStyle(Color(nsColor: .systemRed))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(error.operation.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(error.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DT.Space.lg)
    }

    // MARK: - Summary

    private var summarySection: some View {
        Text(error.summary)
            .font(.callout)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            Text(L("提案された対処"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: DT.Space.sm) {
                ForEach(error.suggestions) { suggestion in
                    SuggestionRow(
                        suggestion: suggestion,
                        onTap: { handle(suggestion) }
                    )
                }
            }
        }
    }

    // MARK: - Details (collapsible)

    private var detailsSection: some View {
        DisclosureGroup(isExpanded: $detailsExpanded) {
            VStack(alignment: .leading, spacing: DT.Space.sm) {
                if !error.command.isEmpty {
                    detailBlock(label: L("実行コマンド"), text: error.command)
                }
                detailBlock(label: L("git からのメッセージ"), text: stderrDisplay)

                HStack {
                    Spacer()
                    Button {
                        copyDetails()
                    } label: {
                        Label(
                            didCopy ? L("コピーしました") : L("詳細をコピー"),
                            systemImage: didCopy ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.top, DT.Space.sm)
        } label: {
            Label(L("技術的な詳細"), systemImage: "terminal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var stderrDisplay: String {
        let trimmed = error.rawStderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L("（メッセージなし）") : trimmed
    }

    private func detailBlock(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(DT.Space.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button(L("閉じる")) {
                repoVM.dismissErrorDetails()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(DT.Space.md)
    }

    // MARK: - Suggestion handler

    private func handle(_ suggestion: GitOperationError.Suggestion) {
        guard let action = suggestion.action else { return }
        switch action {
        case .openHelp(let url):
            openURL(url)
        case .copyDetails:
            copyDetails()
        case .pull, .fetch, .push, .retry:
            // Dismiss the sheet immediately so the toolbar's progress UI is
            // visible while the new operation runs.
            repoVM.dismissErrorDetails()
            dismiss()
            Task { await repoVM.perform(action) }
        case .openCommitTab, .openIdentitySettings, .openAccountSettings:
            // Currently leaves the sheet open; the host view can listen via
            // perform() if it wants to navigate elsewhere.
            Task { await repoVM.perform(action) }
        }
    }

    private func copyDetails() {
        let lines = [
            "[\(error.operation.label)] \(error.title)",
            "",
            error.summary,
            "",
            "$ \(error.command)",
            error.rawStderr
        ]
        let payload = lines.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)

        didCopy = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            didCopy = false
        }
    }
}

// MARK: - Suggestion row

private struct SuggestionRow: View {
    let suggestion: GitOperationError.Suggestion
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: DT.Space.md) {
                Image(systemName: icon)
                    .imageScale(.medium)
                    .foregroundStyle(suggestion.isPrimary ? Color.white : Color.accentColor)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(suggestion.isPrimary ? Color.accentColor : Color.accentColor.opacity(0.15))
                    )
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.label)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let detail = suggestion.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
            }
            .padding(DT.Space.md)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                    .fill(
                        suggestion.isPrimary
                        ? Color.accentColor.opacity(0.08)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.6)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                    .strokeBorder(
                        suggestion.isPrimary
                        ? Color.accentColor.opacity(0.4)
                        : Color(nsColor: .separatorColor),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        guard let action = suggestion.action else { return "lightbulb" }
        switch action {
        case .pull: return "arrow.down.circle.fill"
        case .fetch: return "arrow.triangle.2.circlepath"
        case .push: return "arrow.up.circle.fill"
        case .retry: return "arrow.clockwise"
        case .openCommitTab: return "pencil.circle.fill"
        case .openIdentitySettings: return "person.crop.circle.badge.questionmark"
        case .openAccountSettings: return "person.crop.circle.fill"
        case .openHelp: return "book.fill"
        case .copyDetails: return "doc.on.doc"
        }
    }
}
