import SwiftUI

/// Leftmost column — the persistent repository list, collapsible via the
/// NavigationSplitView sidebar toggle. Sits outside `RepositoryView`.
struct RepositorySidebar: View {
    @EnvironmentObject var store: RepositoryStore
    @Environment(\.openWindow) private var openWindow

    @State private var groupSheet: GroupSheetContext?
    @State private var pendingDeleteGroup: RepositoryGroup?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $store.selectedID) {
                if store.hasOrganization {
                    organizedContent
                } else {
                    flatContent
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if store.repositories.isEmpty {
                    VStack(spacing: DT.Space.sm) {
                        Image(systemName: "tray")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text(L("リポジトリがありません"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(L("下のボタンから追加"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, DT.Space.xxxl)
                }
            }

            Divider()
            addRepositoryButton
        }
        .navigationTitle("GitEdit")
        .sheet(item: $groupSheet) { context in
            GroupNameSheet(
                title: context.title,
                confirmTitle: context.confirmTitle,
                name: context.initialName
            ) { name in
                switch context {
                case .create(let repositoryID):
                    store.createGroup(name: name, assign: repositoryID)
                case .rename(let group):
                    store.renameGroup(group.id, to: name)
                }
            }
        }
        .confirmationDialog(
            deleteGroupTitle,
            isPresented: Binding(
                get: { pendingDeleteGroup != nil },
                set: { if !$0 { pendingDeleteGroup = nil } }
            ),
            presenting: pendingDeleteGroup
        ) { group in
            Button(L("グループを削除"), role: .destructive) {
                store.deleteGroup(group.id)
            }
            Button(L("キャンセル"), role: .cancel) {}
        } message: { _ in
            Text(L("グループを削除してもリポジトリは残ります。"))
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var organizedContent: some View {
        if !store.pinnedRepositories.isEmpty {
            Section {
                ForEach(store.pinnedRepositories) { repo in
                    repositoryRow(repo)
                }
            } header: {
                sectionHeader(L("ピン留め済み"))
            }
        }

        ForEach(store.groups) { group in
            Section(isExpanded: isExpandedBinding(for: group)) {
                ForEach(store.repositories(inGroup: group)) { repo in
                    repositoryRow(repo)
                }
            } header: {
                groupHeader(group)
            }
        }

        if !store.ungroupedRepositories.isEmpty {
            Section {
                ForEach(store.ungroupedRepositories) { repo in
                    repositoryRow(repo)
                }
            } header: {
                sectionHeader(L("その他"))
            }
        }
    }

    private var flatContent: some View {
        Section {
            ForEach(store.repositories) { repo in
                repositoryRow(repo)
            }
        } header: {
            sectionHeader(L("リポジトリ"))
        }
    }

    @ViewBuilder
    private func repositoryRow(_ repo: Repository) -> some View {
        RepositoryRow(repository: repo)
            .tag(repo.id)
            .contextMenu {
                Button(L("新しいウィンドウで開く")) {
                    openWindow(id: "repository", value: repo.id)
                }
                Divider()
                Button(repo.isPinned ? L("ピン留めを解除") : L("ピン留め")) {
                    store.togglePin(repo.id)
                }
                Menu(L("グループへ移動")) {
                    ForEach(store.groups) { group in
                        Button(group.name) {
                            store.setGroup(group.id, for: repo.id)
                        }
                    }
                    if repo.groupID != nil {
                        Button(L("グループから外す")) {
                            store.setGroup(nil, for: repo.id)
                        }
                    }
                    Divider()
                    Button(L("新規グループ…")) {
                        groupSheet = .create(repositoryID: repo.id)
                    }
                }
                Divider()
                Button(L("リストから削除")) {
                    store.removeRepository(repo.id)
                }
            }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func groupHeader(_ group: RepositoryGroup) -> some View {
        Text(group.name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .contextMenu {
                Button(L("名前を変更…")) {
                    groupSheet = .rename(group)
                }
                Button(L("グループを削除"), role: .destructive) {
                    pendingDeleteGroup = group
                }
            }
    }

    private func isExpandedBinding(for group: RepositoryGroup) -> Binding<Bool> {
        Binding(
            get: { !group.isCollapsed },
            set: { isExpanded in store.setGroupCollapsed(group.id, isCollapsed: !isExpanded) }
        )
    }

    private var deleteGroupTitle: String {
        L("グループ「%@」を削除しますか？", pendingDeleteGroup?.name ?? "")
    }

    private var addRepositoryButton: some View {
        Button {
            store.promptAddRepository()
        } label: {
            HStack(spacing: DT.Space.sm) {
                Image(systemName: "plus.circle.fill")
                    .imageScale(.medium)
                    .foregroundStyle(.tint)
                Text(L("リポジトリを追加…"))
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, DT.Space.md)
            .padding(.vertical, DT.Space.sm + 2)
        }
        .buttonStyle(.plain)
    }
}

/// Identifies which flow presents `GroupNameSheet` — creating a new group
/// (optionally assigning a repository to it right away) or renaming one.
private enum GroupSheetContext: Identifiable {
    case create(repositoryID: Repository.ID?)
    case rename(RepositoryGroup)

    var id: String {
        switch self {
        case .create: "create"
        case .rename(let group): "rename-\(group.id)"
        }
    }

    var title: String {
        switch self {
        case .create: L("新しいグループ")
        case .rename: L("グループ名を変更")
        }
    }

    var confirmTitle: String {
        switch self {
        case .create: L("作成")
        case .rename: L("保存")
        }
    }

    var initialName: String {
        switch self {
        case .create: ""
        case .rename(let group): group.name
        }
    }
}

private struct RepositoryRow: View {
    let repository: Repository

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "folder.fill")
                .imageScale(.medium)
                .foregroundStyle(.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(repository.name)
                    .font(.body)
                    .lineLimit(1)
                if let branch = repository.currentBranch {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                        Text(branch)
                            .font(.caption2.monospaced())
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
