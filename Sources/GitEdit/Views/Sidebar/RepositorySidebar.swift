import SwiftUI

struct RepositorySidebar: View {
    @EnvironmentObject var store: RepositoryStore

    var body: some View {
        List(selection: $store.selectedID) {
            Section {
                ForEach(store.repositories) { repo in
                    RepositoryRow(repository: repo)
                        .tag(repo.id)
                }
            } header: {
                Text(L("リポジトリ"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("GitEdit")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.promptAddRepository()
                } label: {
                    Image(systemName: "plus")
                }
                .help(L("リポジトリを追加"))
            }
        }
        .overlay {
            if store.repositories.isEmpty {
                VStack(spacing: DT.Space.sm) {
                    Image(systemName: "tray")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(L("リポジトリがありません"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(L("+ ボタンから追加"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, DT.Space.xxxl)
            }
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
