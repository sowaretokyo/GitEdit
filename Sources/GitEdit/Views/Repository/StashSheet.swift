import SwiftUI

/// Management sheet for `git stash`: create a new stash from the working
/// tree, and browse/apply/pop/drop existing ones. The drop confirmation
/// dialog itself lives on `RepositoryView` (see `StashActionDialogs`) so it
/// presents consistently with the rest of the app's destructive dialogs.
struct StashSheet: View {
    @ObservedObject var repoVM: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var message: String = ""
    @State private var includeUntracked: Bool = true
    @State private var isCreating: Bool = false
    @State private var busySelector: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            composer
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 480, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        Text(L("退避した変更"))
            .font(.title2.weight(.semibold))
            .padding(DT.Space.lg)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            TextField(L("退避メッセージ（任意）"), text: $message)
                .textFieldStyle(.roundedBorder)
                .disabled(isCreating)

            HStack {
                Toggle(isOn: $includeUntracked) {
                    Text(L("未追跡ファイルも含める"))
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
                .disabled(isCreating)

                Spacer()

                if isCreating {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await createStash() }
                } label: {
                    Text(L("退避する"))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!repoVM.hasUncommittedChanges || isCreating)
            }
        }
        .padding(DT.Space.lg)
    }

    private func createStash() async {
        isCreating = true
        defer { isCreating = false }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        await repoVM.createStash(message: trimmed, includeUntracked: includeUntracked)
        message = ""
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if repoVM.stashes.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: DT.Space.xs) {
                    ForEach(repoVM.stashes) { entry in
                        StashRow(
                            entry: entry,
                            isBusy: busySelector == entry.selector,
                            onApply: { runExclusive(entry) { await repoVM.applyStash($0) } },
                            onPop: { runExclusive(entry) { await repoVM.popStash($0) } },
                            onDrop: { repoVM.requestDropStash(entry) }
                        )
                    }
                }
                .padding(DT.Space.md)
            }
        }
    }

    /// Runs an apply/pop against `entry`, marking its row busy for the
    /// duration so the same stash can't be double-triggered mid-flight.
    private func runExclusive(_ entry: StashEntry, _ operation: @escaping (StashEntry) async -> Void) {
        guard busySelector == nil else { return }
        busySelector = entry.selector
        Task {
            await operation(entry)
            busySelector = nil
        }
    }

    private var emptyState: some View {
        VStack(spacing: DT.Space.sm) {
            Spacer()
            Image(systemName: "archivebox")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("退避された変更はありません"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button(L("閉じる")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(DT.Space.md)
    }
}

// MARK: - Row

private struct StashRow: View {
    let entry: StashEntry
    let isBusy: Bool
    let onApply: () -> Void
    let onPop: () -> Void
    let onDrop: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DT.Space.sm) {
            Image(systemName: "archivebox")
                .foregroundStyle(.secondary)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.callout)
                    .lineLimit(2)
                Text(entry.relativeDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: DT.Space.sm)

            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                HStack(spacing: DT.Space.xs) {
                    Button(action: onApply) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .help(L("復元"))

                    Button(action: onPop) {
                        Image(systemName: "tray.and.arrow.up")
                    }
                    .help(L("復元して退避を削除"))

                    Button(role: .destructive, action: onDrop) {
                        Image(systemName: "trash")
                    }
                    .help(L("退避を削除"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(DT.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
    }
}
