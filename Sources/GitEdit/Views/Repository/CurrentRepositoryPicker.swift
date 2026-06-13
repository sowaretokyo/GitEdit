import SwiftUI
import AppKit

/// Toolbar item showing the currently selected repository with a popover for
/// switching between repositories and adding new ones. Matches GitHub Desktop's
/// "Current Repository" dropdown.
struct CurrentRepositoryPicker: View {
    @EnvironmentObject var store: RepositoryStore
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)

                if let repo = store.selectedRepository {
                    Text(repo.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                } else {
                    Text(L("未選択"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            RepositoryPickerPopover { action in
                isPresented = false
                switch action {
                case .select(let id):
                    store.selectedID = id
                case .add:
                    store.promptAddRepository()
                case .none:
                    break
                }
            }
            .frame(width: 320, height: 380)
        }
    }
}

private enum RepositoryPickerAction {
    case select(Repository.ID)
    case add
    case none
}

private struct RepositoryPickerPopover: View {
    @EnvironmentObject var store: RepositoryStore
    let onAction: (RepositoryPickerAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Text(L("リポジトリ"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if !store.repositories.isEmpty {
                Text("\(store.repositories.count)")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DT.Space.md)
    }

    @ViewBuilder
    private var content: some View {
        if store.repositories.isEmpty {
            VStack(spacing: DT.Space.sm) {
                Spacer()
                Image(systemName: "tray")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(L("リポジトリがありません"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(store.repositories) { repo in
                        RepositoryPickerRow(
                            repository: repo,
                            isCurrent: store.selectedID == repo.id
                        )
                        .onTapGesture { onAction(.select(repo.id)) }
                    }
                }
                .padding(DT.Space.xs)
            }
        }
    }

    private var footer: some View {
        Button {
            onAction(.add)
        } label: {
            HStack(spacing: DT.Space.sm) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tint)
                Text(L("リポジトリを追加…"))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(DT.Space.md)
    }
}

private struct RepositoryPickerRow: View {
    let repository: Repository
    let isCurrent: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: isCurrent ? "checkmark.circle.fill" : "folder.fill")
                .imageScale(.medium)
                .foregroundStyle(isCurrent ? Color(nsColor: .systemGreen) : Color.accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(repository.name)
                    .font(.callout)
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DT.Space.sm)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovering)
    }
}
