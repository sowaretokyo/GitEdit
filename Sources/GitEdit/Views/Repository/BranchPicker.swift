import SwiftUI

struct BranchPicker: View {
    @ObservedObject var repoVM: RepositoryViewModel
    @State private var isPresented = false
    @State private var search = ""

    var body: some View {
        Button {
            isPresented.toggle()
            if isPresented {
                Task { await repoVM.refreshBranches() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .imageScale(.medium)
                Text(repoVM.currentBranchName ?? L("ブランチ未選択"))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if repoVM.ahead > 0 || repoVM.behind > 0 {
                    AheadBehindBadge(ahead: repoVM.ahead, behind: repoVM.behind)
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
            BranchPopover(repoVM: repoVM, search: $search) {
                isPresented = false
            }
            .frame(width: 380, height: 460)
        }
        .onChange(of: isPresented) { _, presented in
            if !presented { search = "" }
        }
    }
}

struct BranchPopover: View {
    @ObservedObject var repoVM: RepositoryViewModel
    @Binding var search: String
    let dismiss: () -> Void

    private var filteredLocal: [Branch] {
        guard !search.isEmpty else { return repoVM.localBranches }
        return repoVM.localBranches.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var filteredRemote: [Branch] {
        guard !search.isEmpty else { return repoVM.remoteBranches }
        return repoVM.remoteBranches.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            content
            Divider()
            footer
        }
    }

    private var searchField: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L("ブランチを検索"), text: $search)
                .textFieldStyle(.plain)
        }
        .padding(DT.Space.md)
    }

    @ViewBuilder
    private var content: some View {
        if repoVM.isLoadingBranches && repoVM.localBranches.isEmpty {
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if filteredLocal.isEmpty && filteredRemote.isEmpty {
            VStack(spacing: DT.Space.sm) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(L("見つかりません"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DT.Space.xs) {
                    if !filteredLocal.isEmpty {
                        SectionHeader(title: L("ローカル"), count: filteredLocal.count)
                        ForEach(filteredLocal) { branch in
                            BranchRow(
                                branch: branch,
                                isCurrent: branch.isCurrent,
                                onSelect: {
                                    dismiss()
                                    Task { await repoVM.requestSwitchBranch(branch) }
                                }
                            )
                        }
                    }
                    if !filteredRemote.isEmpty {
                        SectionHeader(title: L("リモート"), count: filteredRemote.count)
                            .padding(.top, DT.Space.xs)
                        ForEach(filteredRemote) { branch in
                            BranchRow(
                                branch: branch,
                                isCurrent: false,
                                onSelect: {
                                    dismiss()
                                    Task { await repoVM.requestSwitchBranch(branch) }
                                }
                            )
                        }
                    }
                }
                .padding(DT.Space.xs)
            }
        }
    }

    private var footer: some View {
        Button {
            dismiss()
            repoVM.isShowingCreateBranchSheet = true
        } label: {
            HStack(spacing: DT.Space.sm) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tint)
                Text(L("新しいブランチを作成…"))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(DT.Space.md)
    }
}

private struct SectionHeader: View {
    let title: String
    let count: Int
    var body: some View {
        HStack(spacing: DT.Space.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, DT.Space.sm)
        .padding(.top, DT.Space.xs)
    }
}

struct BranchRow: View {
    let branch: Branch
    let isCurrent: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    private var icon: String {
        if isCurrent { return "checkmark.circle.fill" }
        if branch.isRemote { return "cloud.fill" }
        return "arrow.triangle.branch"
    }

    private var iconColor: Color {
        if isCurrent { return Color(nsColor: .systemGreen) }
        if branch.isRemote { return .secondary }
        return .secondary
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DT.Space.sm) {
                Image(systemName: icon)
                    .imageScale(.medium)
                    .foregroundStyle(iconColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(branch.name)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if isCurrent {
                            Text(L("このブランチ"))
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(nsColor: .systemGreen).opacity(0.18), in: Capsule())
                                .foregroundStyle(Color(nsColor: .systemGreen))
                        }
                    }
                    if !branch.subject.isEmpty {
                        Text(branch.subject)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if branch.ahead > 0 || branch.behind > 0 {
                    AheadBehindBadge(ahead: branch.ahead, behind: branch.behind)
                }
            }
            .padding(.horizontal, DT.Space.sm)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct AheadBehindBadge: View {
    let ahead: Int
    let behind: Int

    var body: some View {
        HStack(spacing: 6) {
            if ahead > 0 {
                HStack(spacing: 1) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(ahead)")
                        .font(.caption2.monospaced())
                }
                .foregroundStyle(Color(nsColor: .systemGreen))
            }
            if behind > 0 {
                HStack(spacing: 1) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(behind)")
                        .font(.caption2.monospaced())
                }
                .foregroundStyle(Color(nsColor: .systemBlue))
            }
        }
    }
}
