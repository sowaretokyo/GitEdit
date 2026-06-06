import SwiftUI

/// Leftmost column — the persistent repository list, collapsible via the
/// NavigationSplitView sidebar toggle. Sits outside `RepositoryView`.
struct RepositorySidebar: View {
    @EnvironmentObject var store: RepositoryStore

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $store.selectedID) {
                Section {
                    ForEach(store.repositories) { repo in
                        RepositoryRow(repository: repo)
                            .tag(repo.id)
                            .contextMenu {
                                Button(L("リストから削除")) {
                                    store.removeRepository(repo.id)
                                }
                            }
                    }
                } header: {
                    Text(L("リポジトリ"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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
