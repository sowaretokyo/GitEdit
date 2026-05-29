import SwiftUI

struct RepositoryDetailView: View {
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
        var icon: String {
            switch self {
            case .changes: return "pencil.and.list.clipboard"
            case .history: return "clock.arrow.circlepath"
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
        VStack(spacing: 0) {
            header
            Divider()

            switch selectedTab {
            case .changes:
                ChangesView(viewModel: changesVM)
            case .history:
                HistoryView(viewModel: historyVM)
            }
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
        ) { branch in
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

    private var header: some View {
        HStack(spacing: DT.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: "folder.fill")
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(repository.name)
                    .font(.title3.weight(.semibold))
                if let branch = repoVM.currentBranchName {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .imageScale(.small)
                        Text(branch)
                            .font(.caption.monospaced())
                        if repoVM.hasUncommittedChanges {
                            Text(L("•"))
                                .foregroundStyle(.tertiary)
                            Text(L("未コミット"))
                                .font(.caption)
                                .foregroundStyle(Color(nsColor: .systemOrange))
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .labelsHidden()
        }
        .padding(.horizontal, DT.Space.lg)
        .padding(.vertical, DT.Space.md)
    }
}

// MARK: - Feedback Banner

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
            Image(systemName: icon)
                .foregroundStyle(color)
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

// MARK: - Network Ops Toolbar Items

struct NetworkOpsToolbarItems: View {
    @ObservedObject var repoVM: RepositoryViewModel

    private var pushTitle: String {
        repoVM.hasUpstream ? L("反映") : L("公開")
    }

    private var pushIcon: String {
        repoVM.hasUpstream ? "arrow.up.circle" : "paperplane.circle"
    }

    var body: some View {
        Group {
            // Fetch
            Button {
                Task { await repoVM.fetch() }
            } label: {
                Label(L("取得"), systemImage: repoVM.isFetching
                      ? "arrow.triangle.2.circlepath"
                      : "arrow.triangle.2.circlepath")
                    .rotationEffect(.degrees(repoVM.isFetching ? 360 : 0))
                    .animation(
                        repoVM.isFetching
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: repoVM.isFetching
                    )
            }
            .help(L("取得"))
            .disabled(repoVM.isBusy || !repoVM.hasRemotes)

            // Pull
            Button {
                Task { await repoVM.pull() }
            } label: {
                ZStack {
                    Label(L("取り込み"), systemImage: "arrow.down.circle")
                        .opacity(repoVM.isPulling ? 0.4 : 1)
                    if repoVM.isPulling {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .help(L("取り込み"))
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

            // Push
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
