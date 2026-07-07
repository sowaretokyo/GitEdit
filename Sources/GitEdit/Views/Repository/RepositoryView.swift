import SwiftUI
import AppKit

/// The main view shown when a repository is selected.
/// Mirrors GitHub Desktop's layout:

struct RepositoryView: View {
    let repository: Repository

    @StateObject private var repoVM: RepositoryViewModel
    @StateObject private var changesVM: ChangesViewModel
    @StateObject private var historyVM: HistoryViewModel
    @StateObject private var searchVM: SearchViewModel
    @StateObject private var explorerVM: ExplorerViewModel

    @State private var selectedTab: Tab = .changes
    @State private var watcher: RepositoryWatcher?
    @State private var isShowingFilePicker: Bool = false
    @State private var viewedGrepResult: GrepResult?
    @State private var viewedExplorerNode: FileNode?

    enum Tab: String, CaseIterable, Identifiable {
        case changes
        case history
        case search
        case explorer
        var id: String { rawValue }
        var title: String {
            switch self {
            case .changes: return L("変更")
            case .history: return L("履歴")
            case .search: return L("検索")
            case .explorer: return L("エクスプローラ")
            }
        }
        var iconSystemName: String {
            switch self {
            case .changes: return "pencil"
            case .history: return "clock"
            case .search: return "magnifyingglass"
            case .explorer: return "folder"
            }
        }
    }

    init(repository: Repository) {
        self.repository = repository
        _repoVM = StateObject(wrappedValue: RepositoryViewModel(repository: repository))
        _changesVM = StateObject(wrappedValue: ChangesViewModel(repository: repository))
        _historyVM = StateObject(wrappedValue: HistoryViewModel(repository: repository))
        _searchVM = StateObject(wrappedValue: SearchViewModel(repository: repository.url))
        _explorerVM = StateObject(wrappedValue: ExplorerViewModel(repository: repository.url))
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)

            detail
                .frame(minWidth: 380)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await repoVM.bootstrap()
            await changesVM.refreshAll()
            startWatching()
        }
        .onDisappear { watcher?.stop(); watcher = nil }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .history && historyVM.commits.isEmpty {
                Task { await historyVM.load() }
            }
        }
        .onChange(of: repoVM.dataVersion) { _, _ in
            Task { await reload() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await reload() }
        }
        // After a commit, refresh the repo-level branch info (ahead / behind /
        // upstream) so the Push toolbar button lights up immediately, GHD-style.
        .onChange(of: changesVM.commitVersion) { _, _ in
            Task {
                await repoVM.refreshBranchInfo()
                await repoVM.refreshUndoState()
                if selectedTab == .history {
                    await historyVM.load()
                }
            }
        }
        // ChangesViewModel owns commit / stage / save errors but has no banner of
        // its own — forward them into the shared repository banner so the UI is
        // consistent regardless of where the failure originated.
        .onChange(of: changesVM.lastError) { _, newValue in
            if let err = newValue {
                repoVM.operationError = err
                changesVM.clearLastError()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                CurrentRepositoryPicker()
            }
            ToolbarItem(placement: .navigation) {
                BranchPicker(repoVM: repoVM)
            }
            ToolbarItem(placement: .navigation) {
                BranchIssueLink(repoVM: repoVM)
            }
            ToolbarItem(placement: .navigation) {
                UndoToolbarButton(repoVM: repoVM)
            }
            ToolbarItem(placement: .primaryAction) {
                StashToolbarButton(repoVM: repoVM)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                NetworkOpsToolbarItems(repoVM: repoVM)
            }
        }
        .sheet(isPresented: $repoVM.isShowingCreateBranchSheet) {
            CreateBranchSheet(repoVM: repoVM)
        }
        .sheet(isPresented: $repoVM.isShowingStashSheet) {
            StashSheet(repoVM: repoVM)
        }
        .sheet(isPresented: $repoVM.isShowingPartialStashSheet) {
            PartialStashSheet(repoVM: repoVM)
        }
        .confirmationDialog(
            L("未コミットの変更があります"),
            isPresented: Binding(
                get: { repoVM.pendingSwitchBranch != nil },
                set: { if !$0 { repoVM.cancelSwitchAfterDirtyWarning() } }
            ),
            presenting: repoVM.pendingSwitchBranch
        ) { _ in
            Button(L("このまま切り替え"), role: .destructive) {
                Task { await repoVM.confirmSwitchAfterDirtyWarning() }
            }
            Button(L("変更を退避して切り替え")) {
                Task { await repoVM.stashThenSwitchAfterDirtyWarning() }
            }
            Button(L("キャンセル"), role: .cancel) {
                repoVM.cancelSwitchAfterDirtyWarning()
            }
        } message: { _ in
            Text(L("先に変更をコミットするか退避してから切り替えてください。"))
        }
        .confirmationDialog(
            L("リモートと分岐しています"),
            isPresented: Binding(
                get: { repoVM.pendingMergePull },
                set: { if !$0 { repoVM.cancelMergePull() } }
            )
        ) {
            Button(L("マージして取り込む")) {
                Task { await repoVM.confirmMergePull() }
            }
            Button(L("キャンセル"), role: .cancel) {
                repoVM.cancelMergePull()
            }
        } message: {
            Text(L("リモートにローカルとは別のコミットがあります。マージして取り込みますか？"))
        }
        .modifier(BranchActionDialogs(repoVM: repoVM))
        .modifier(StashActionDialogs(repoVM: repoVM))
        .modifier(UndoActionDialogs(repoVM: repoVM))
        .overlay(alignment: .bottomTrailing) {
            OperationFeedbackBanner(repoVM: repoVM)
        }
        .sheet(item: $repoVM.inspectingError) { err in
            ErrorInspectorSheet(error: err, repoVM: repoVM)
        }
        .sheet(isPresented: $isShowingFilePicker) {
            FilePickerSheet(
                repository: repository.url,
                isPresented: $isShowingFilePicker
            ) { path in
                openFileByPath(path)
            }
        }
        // Hidden ⌘P shortcut to summon the file picker.
        .background(
            Button(action: { isShowingFilePicker = true }) {
                EmptyView()
            }
            .keyboardShortcut("p", modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
        )
        // Hidden ⇧⌘F shortcut to jump to the search tab.
        .background(
            Button(action: { selectedTab = .search }) {
                EmptyView()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .opacity(0)
            .accessibilityHidden(true)
        )
    }

    // MARK: - File-picker selection routing

    /// `⌘P` selection: always display the file in the read-only
    /// `FileViewerPane`, matching the Search / Explorer flow.
    /// Routes through the Explorer tab so the right pane already has the
    /// viewer wired up.
    private func openFileByPath(_ path: String) {
        let fileName = (path as NSString).lastPathComponent
        let absoluteURL = repository.url.appendingPathComponent(path)
        let node = FileNode(
            path: path,
            name: fileName,
            url: absoluteURL,
            isDirectory: false,
            children: nil
        )
        viewedExplorerNode = node
        selectedTab = .explorer
    }

    private func openGrepResult(_ match: GrepResult) {
        // Stay on the search tab and show the file in the right pane,
        // scrolled / highlighted to the matched line.
        viewedGrepResult = match
    }

    // MARK: - Auto refresh

    /// Re-read everything from disk: branch/ahead-behind, working tree changes,
    /// and (when relevant) the commit history. Cheap enough to run on every
    /// detected change because the underlying git calls are debounced upstream.
    private func reload() async {
        await repoVM.refresh()
        await changesVM.refreshAll()
        if selectedTab == .history || !historyVM.commits.isEmpty {
            await historyVM.load()
        }
    }

    private func startWatching() {
        guard watcher == nil else { return }
        let w = RepositoryWatcher(url: repository.url) {
            Task { await reload() }
        }
        w.start()
        watcher = w
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            SidebarTabBar(selection: $selectedTab)
            Divider()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .changes:
            ChangesSidebar(viewModel: changesVM)
        case .history:
            HistorySidebar(viewModel: historyVM)
        case .search:
            SearchSidebar(
                viewModel: searchVM,
                currentResultId: viewedGrepResult?.id
            ) { match in
                openGrepResult(match)
            }
        case .explorer:
            ExplorerSidebar(viewModel: explorerVM) { node in
                viewedExplorerNode = node
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedTab {
        case .changes:
            ChangesDetailPane(viewModel: changesVM, repoVM: repoVM)
        case .history:
            if let commit = historyVM.selectedCommit {
                CommitDetailView(commit: commit, viewModel: historyVM, issueRepository: repoVM.githubRepository)
            } else {
                pickCommitPrompt
            }
        case .search:
            if let result = viewedGrepResult {
                FileViewerPane(
                    repositoryURL: repository.url,
                    path: result.path,
                    highlightLine: result.lineNumber
                )
            } else {
                searchPrompt
            }
        case .explorer:
            if let node = viewedExplorerNode, !node.isDirectory {
                FileViewerPane(
                    repositoryURL: repository.url,
                    path: node.path,
                    highlightLine: nil
                )
            } else {
                explorerPrompt
            }
        }
    }

    private var explorerPrompt: some View {
        VStack(spacing: DT.Space.sm) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("左でファイルをクリックすると内容が表示されます"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var searchPrompt: some View {
        VStack(spacing: DT.Space.sm) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("左で検索結果をクリックすると詳細が表示されます"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pickCommitPrompt: some View {
        VStack(spacing: DT.Space.sm) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("左のリストからコミットを選択"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Branch action confirmation dialogs (merge / delete / force-delete)

/// Extracted into its own `ViewModifier` so the type checker evaluates these
/// three `confirmationDialog`s independently of `RepositoryView.body`'s
/// already-long modifier chain.
private struct BranchActionDialogs: ViewModifier {
    @ObservedObject var repoVM: RepositoryViewModel

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                L("「%@」を「%@」にマージしますか？", repoVM.pendingMergeBranch?.name ?? "", repoVM.currentBranchName ?? ""),
                isPresented: Binding(
                    get: { repoVM.pendingMergeBranch != nil },
                    set: { if !$0 { repoVM.cancelMerge() } }
                ),
                presenting: repoVM.pendingMergeBranch
            ) { _ in
                Button(L("マージ")) {
                    Task { await repoVM.confirmMerge() }
                }
                Button(L("キャンセル"), role: .cancel) {
                    repoVM.cancelMerge()
                }
            } message: { branch in
                Text(L("「%@」の変更が現在のブランチに取り込まれます。", branch.name))
            }
            .confirmationDialog(
                L("「%@」を削除しますか？", repoVM.pendingDeleteBranch?.name ?? ""),
                isPresented: Binding(
                    get: { repoVM.pendingDeleteBranch != nil },
                    set: { if !$0 { repoVM.cancelDelete() } }
                ),
                presenting: repoVM.pendingDeleteBranch
            ) { _ in
                Button(L("削除"), role: .destructive) {
                    Task { await repoVM.confirmDeleteBranch() }
                }
                Button(L("キャンセル"), role: .cancel) {
                    repoVM.cancelDelete()
                }
            } message: { _ in
                Text(L("このブランチをローカルから削除します。"))
            }
            .confirmationDialog(
                L("未マージのブランチです"),
                isPresented: Binding(
                    get: { repoVM.pendingForceDeleteBranch != nil },
                    set: { if !$0 { repoVM.cancelForceDelete() } }
                ),
                presenting: repoVM.pendingForceDeleteBranch
            ) { _ in
                Button(L("強制削除"), role: .destructive) {
                    Task { await repoVM.confirmForceDeleteBranch() }
                }
                Button(L("キャンセル"), role: .cancel) {
                    repoVM.cancelForceDelete()
                }
            } message: { branch in
                Text(L("「%@」にはまだマージされていない変更があります。強制削除するとこれらのコミットは失われる可能性があります。", branch.name))
            }
    }
}

// MARK: - Stash action confirmation dialog (drop)

/// Extracted for the same reason as `BranchActionDialogs`: keeps `body`'s
/// modifier chain from growing further.
private struct StashActionDialogs: ViewModifier {
    @ObservedObject var repoVM: RepositoryViewModel

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                L("退避を削除しますか？"),
                isPresented: Binding(
                    get: { repoVM.pendingStashDrop != nil },
                    set: { if !$0 { repoVM.cancelDropStash() } }
                ),
                presenting: repoVM.pendingStashDrop
            ) { _ in
                Button(L("退避を削除"), role: .destructive) {
                    Task { await repoVM.confirmDropStash() }
                }
                Button(L("キャンセル"), role: .cancel) {
                    repoVM.cancelDropStash()
                }
            } message: { _ in
                Text(L("この退避を削除すると元に戻せません。"))
            }
    }
}

// MARK: - Undo action dialogs (confirm / blocked notice)

/// Extracted for the same reason as `BranchActionDialogs` / `StashActionDialogs`.
private struct UndoActionDialogs: ViewModifier {
    @ObservedObject var repoVM: RepositoryViewModel

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                undoTitle(repoVM.pendingUndo),
                isPresented: Binding(
                    get: { repoVM.pendingUndo != nil },
                    set: { if !$0 { repoVM.cancelUndo() } }
                ),
                presenting: repoVM.pendingUndo
            ) { op in
                Button(L("取り消す"), role: destructiveRole(op)) {
                    Task { await repoVM.confirmUndo() }
                }
                Button(L("キャンセル"), role: .cancel) {
                    repoVM.cancelUndo()
                }
            } message: { op in
                Text(undoMessage(op))
            }
            .confirmationDialog(
                L("この操作は取り消せません"),
                isPresented: Binding(
                    get: { repoVM.undoBlockedMessage != nil },
                    set: { if !$0 { repoVM.dismissUndoBlocked() } }
                )
            ) {
                Button(L("閉じる"), role: .cancel) {
                    repoVM.dismissUndoBlocked()
                }
            } message: {
                Text(repoVM.undoBlockedMessage ?? "")
            }
    }

    private func destructiveRole(_ op: UndoableOperation) -> ButtonRole? {
        op.requiresHardReset && repoVM.hasUncommittedChanges ? .destructive : nil
    }

    private func undoTitle(_ op: UndoableOperation?) -> String {
        guard let op else { return "" }
        switch op {
        case .commit(let summary, _):
            return L("コミット『%@』を取り消しますか？", summary)
        case .amendCommit:
            return L("直前の修正（amend）を取り消しますか？")
        case .mergeCommit(let summary, _):
            return L("マージ『%@』を取り消しますか？", summary)
        case .branchSwitch:
            return L("ブランチ切替を取り消しますか？")
        }
    }

    private func undoMessage(_ op: UndoableOperation) -> String {
        var message: String
        switch op {
        case .commit:
            message = L("このコミットを取り消し、変更はステージされた状態に戻します。")
        case .amendCommit:
            message = L("amend を取り消し、修正前のコミットに戻します。")
        case .mergeCommit:
            message = L("このマージを取り消し、マージ前の状態に戻します。")
        case .branchSwitch(let from, _):
            message = L("「%@」に戻ります。", from)
        }
        if op.requiresHardReset, repoVM.hasUncommittedChanges {
            message += L("未コミットの変更は失われます。")
        }
        return message
    }
}

// MARK: - Operation Feedback Banner (extracted from old RepositoryDetailView)

struct OperationFeedbackBanner: View {
    @ObservedObject var repoVM: RepositoryViewModel

    var body: some View {
        Group {
            if let error = repoVM.operationError {
                ErrorBanner(error: error, repoVM: repoVM)
            } else if let success = repoVM.operationSuccess {
                SuccessBanner(message: success) {
                    repoVM.dismissFeedback()
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: repoVM.operationError)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: repoVM.operationSuccess)
    }
}

/// Compact error banner: title + one-line summary + "詳細" entry point.
/// Stays on screen until dismissed — error messages are too important to
/// auto-dismiss like success toasts do.
private struct ErrorBanner: View {
    let error: GitOperationError
    @ObservedObject var repoVM: RepositoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            HStack(alignment: .top, spacing: DT.Space.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .imageScale(.medium)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(error.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(error.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DT.Space.sm)
                Button {
                    repoVM.dismissFeedback()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: DT.Space.sm) {
                if let primary = error.suggestions.first(where: { $0.isPrimary }),
                   let action = primary.action,
                   isQuickAction(action) {
                    Button {
                        Task { await repoVM.perform(action) }
                    } label: {
                        Text(primary.label)
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button {
                    repoVM.presentErrorDetails()
                } label: {
                    Text(L("詳細を表示"))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)
            }
        }
        .padding(DT.Space.md)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                        .strokeBorder(Color(nsColor: .systemRed).opacity(0.4), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        )
        .frame(maxWidth: 440)
        .padding(.trailing, DT.Space.md)
        .padding(.bottom, DT.Space.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// In-banner quick action: must be safe to run immediately without
    /// additional input. Other suggestions (open settings, copy details) are
    /// reached through "詳細を表示".
    private func isQuickAction(_ action: GitOperationError.Suggestion.Action) -> Bool {
        switch action {
        case .pull, .fetch, .push, .retry: return true
        default: return false
        }
    }
}

/// Standard success toast — auto-dismisses after a few seconds.
private struct SuccessBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(nsColor: .systemGreen))
            Text(message)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: DT.Space.md)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                        .strokeBorder(Color(nsColor: .systemGreen).opacity(0.4), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
        )
        .frame(maxWidth: 420)
        .padding(.trailing, DT.Space.md)
        .padding(.bottom, DT.Space.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run { onDismiss() }
        }
    }
}

// MARK: - Stash Toolbar Button

struct StashToolbarButton: View {
    @ObservedObject var repoVM: RepositoryViewModel

    var body: some View {
        Button {
            repoVM.isShowingStashSheet = true
        } label: {
            Label(L("退避"), systemImage: "archivebox")
        }
        .help(L("退避した変更"))
        .overlay(alignment: .topTrailing) {
            if !repoVM.stashes.isEmpty {
                Text("\(repoVM.stashes.count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color(nsColor: .systemGray), in: Capsule())
                    .offset(x: 6, y: -4)
            }
        }
    }
}

// MARK: - Undo Toolbar Button

struct UndoToolbarButton: View {
    @ObservedObject var repoVM: RepositoryViewModel

    var body: some View {
        Button {
            repoVM.requestUndo()
        } label: {
            Label(L("直前の操作を取り消す"), systemImage: "arrow.uturn.backward")
        }
        .help(
            repoVM.undoState == .none
                ? L("取り消せる操作はありません（作業ツリーの変更・退避・プッシュ済みの操作は取り消し対象外）")
                : L("直前の操作を取り消す")
        )
        .disabled(repoVM.undoState == .none)
    }
}

// MARK: - Network Ops Toolbar Items (extracted from old RepositoryDetailView)

struct NetworkOpsToolbarItems: View {
    @ObservedObject var repoVM: RepositoryViewModel

    private var pushTitle: String {
        repoVM.hasUpstream ? L("プッシュ") : L("プッシュ（初回）")
    }

    private var pushIcon: String {
        repoVM.hasUpstream ? "arrow.up.circle" : "paperplane.circle"
    }

    var body: some View {
        Group {
            Button {
                Task { await repoVM.fetch() }
            } label: {
                Label(L("フェッチ"), systemImage: "arrow.triangle.2.circlepath")
                    .rotationEffect(.degrees(repoVM.isFetching ? 360 : 0))
                    .animation(
                        repoVM.isFetching
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: repoVM.isFetching
                    )
            }
            .help(L("フェッチ"))
            .disabled(repoVM.isBusy || !repoVM.hasRemotes)

            Button {
                Task { await repoVM.pull() }
            } label: {
                ZStack {
                    Label(L("プル"), systemImage: "arrow.down.circle")
                        .opacity(repoVM.isPulling ? 0.4 : 1)
                    if repoVM.isPulling {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .help(L("プル"))
            .disabled(repoVM.isBusy || !repoVM.hasUpstream || repoVM.behind == 0)
            .overlay(alignment: .topTrailing) {
                if repoVM.behind > 0 {
                    Text("\(repoVM.behind)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(nsColor: .systemBlue), in: Capsule())
                        .offset(x: 6, y: -4)
                }
            }

            Button {
                Task { await repoVM.push() }
            } label: {
                ZStack {
                    Label(pushTitle, systemImage: pushIcon)
                        .opacity(repoVM.isPushing ? 0.4 : 1)
                    if repoVM.isPushing {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .help(pushTitle)
            .disabled(repoVM.isBusy || !repoVM.hasRemotes || (repoVM.hasUpstream && repoVM.ahead == 0))
            .overlay(alignment: .topTrailing) {
                if repoVM.ahead > 0 {
                    Text("\(repoVM.ahead)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(nsColor: .systemGreen), in: Capsule())
                        .offset(x: 6, y: -4)
                }
            }
        }
    }
}

// MARK: - Branch Issue Link (toolbar shortcut)

/// Toolbar shortcut to the GitHub issue referenced by the current branch's
/// name (e.g. branch `123-fix-bug` links to issue #123). Hidden entirely
/// when there's no recognized GitHub remote or the branch name doesn't
/// encode an issue number.
private struct BranchIssueLink: View {
    @ObservedObject var repoVM: RepositoryViewModel

    var body: some View {
        if let url = repoVM.branchIssueURL, let number = Int(url.lastPathComponent) {
            Link(destination: url) {
                Image(systemName: "arrow.up.forward.square")
            }
            .help(L("Issue #%d を開く", number))
            .accessibilityLabel(L("Issue #%d を開く", number))
        } else {
            EmptyView()
        }
    }
}
