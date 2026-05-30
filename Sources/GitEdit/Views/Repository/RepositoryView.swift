import SwiftUI

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
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 480)

            detail
                .frame(minWidth: 480)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await repoVM.bootstrap()
            await changesVM.refreshAll()
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .history && historyVM.commits.isEmpty {
                Task { await historyVM.load() }
            }
        }
        .onChange(of: repoVM.dataVersion) { _, _ in
            Task {
                await changesVM.refreshAll()
                if selectedTab == .history {
                    await historyVM.load()
                }
            }
        }
        // After a commit, refresh the repo-level branch info (ahead / behind /
        // upstream) so the Push toolbar button lights up immediately, GHD-style.
        .onChange(of: changesVM.commitVersion) { _, _ in
            Task {
                await repoVM.refreshBranchInfo()
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
            ToolbarItemGroup(placement: .primaryAction) {
                NetworkOpsToolbarItems(repoVM: repoVM)
            }
        }
        .sheet(isPresented: $repoVM.isShowingCreateBranchSheet) {
            CreateBranchSheet(repoVM: repoVM)
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
            Button(L("キャンセル"), role: .cancel) {
                repoVM.cancelSwitchAfterDirtyWarning()
            }
        } message: { _ in
            Text(L("先に変更をコミットするか退避してから切り替えてください。"))
        }
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
                CommitDetailView(commit: commit, viewModel: historyVM)
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
