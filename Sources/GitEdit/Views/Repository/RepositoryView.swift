import SwiftUI

/// The main view shown when a repository is selected.
/// Mirrors GitHub Desktop's layout:
///   • top toolbar with Current Repository / Branch / Network ops
///   • sidebar with Changes / History tab control
///   • detail pane that swaps based on the selected tab
struct RepositoryView: View {
    let repository: Repository

    @StateObject private var repoVM: RepositoryViewModel
    @StateObject private var changesVM: ChangesViewModel
    @StateObject private var historyVM: HistoryViewModel

    @State private var selectedTab: Tab = .changes

    enum Tab: String, CaseIterable, Identifiable {
        case changes
        case history
        var id: String { rawValue }
        var title: String {
            switch self {
            case .changes: return L("変更")
            case .history: return L("履歴")
            }
        }
    }

    init(repository: Repository) {
        self.repository = repository
        _repoVM = StateObject(wrappedValue: RepositoryViewModel(repository: repository))
        _changesVM = StateObject(wrappedValue: ChangesViewModel(repository: repository))
        _historyVM = StateObject(wrappedValue: HistoryViewModel(repository: repository))
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
        .overlay(alignment: .top) {
            OperationFeedbackBanner(repoVM: repoVM)
        }
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
        }
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
                banner(text: error, icon: "exclamationmark.triangle.fill", color: Color(nsColor: .systemRed))
            } else if let success = repoVM.operationSuccess {
                banner(text: success, icon: "checkmark.circle.fill", color: Color(nsColor: .systemGreen))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: repoVM.operationError)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: repoVM.operationSuccess)
    }

    private func banner(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text)
                .font(.callout)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Spacer(minLength: DT.Space.md)
            Button {
                repoVM.dismissFeedback()
            } label: {
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
                        .strokeBorder(color.opacity(0.4), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
        )
        .frame(maxWidth: 520)
        .padding(.top, DT.Space.md)
        .task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run { repoVM.dismissFeedback() }
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
