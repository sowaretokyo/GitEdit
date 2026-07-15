import SwiftUI

struct CreatePullRequestSheet: View {
    @ObservedObject var repoVM: RepositoryViewModel
    @ObservedObject var pullRequestsVM: PullRequestsViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var accountStore = AccountStore.shared
    @StateObject private var viewModel: CreatePullRequestViewModel

    init(repoVM: RepositoryViewModel, pullRequestsVM: PullRequestsViewModel) {
        self.repoVM = repoVM
        self.pullRequestsVM = pullRequestsVM
        let head = repoVM.currentBranchName ?? ""
        _viewModel = StateObject(wrappedValue: CreatePullRequestViewModel(
            headBranch: head,
            defaultTitle: "",
            baseBranch: Self.defaultBaseBranch(repoVM: repoVM, head: head)
        ))
    }

    /// Best-effort default: prefer `main`/`master` if either is present among
    /// the remote branches, otherwise the first remote branch that isn't the
    /// branch being proposed. There's no dedicated "get repository" API call
    /// in this pass to read GitHub's actual `default_branch`, so this is a
    /// heuristic rather than an authoritative lookup.
    private static func defaultBaseBranch(repoVM: RepositoryViewModel, head: String) -> String {
        let remoteNames = repoVM.remoteBranches.map { shortName($0.name) }
        for candidate in ["main", "master"] where candidate != head && remoteNames.contains(candidate) {
            return candidate
        }
        return remoteNames.first(where: { $0 != head }) ?? ""
    }

    private static func shortName(_ remoteQualified: String) -> String {
        guard let slashIndex = remoteQualified.firstIndex(of: "/") else { return remoteQualified }
        return String(remoteQualified[remoteQualified.index(after: slashIndex)...])
    }

    private var baseOptions: [String] {
        var seen = Set<String>()
        return repoVM.remoteBranches
            .map { Self.shortName($0.name) }
            .filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.lg) {
            Text(L("プルリクエストを作成"))
                .font(.title2.weight(.semibold))

            branchRow
            titleField
            bodyField

            if let message = viewModel.errorMessage {
                errorMessageView(message)
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(DT.Space.xl)
        .frame(width: 520, height: 480)
        .task {
            guard viewModel.title.isEmpty else { return }
            viewModel.title = await repoVM.git.headCommitMessage()?.summary ?? ""
        }
    }

    // MARK: - Branches

    private var branchRow: some View {
        HStack(alignment: .bottom, spacing: DT.Space.sm) {
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text(L("ベースブランチ"))
                    .font(.callout.weight(.medium))
                Picker("", selection: $viewModel.baseBranch) {
                    ForEach(baseOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Image(systemName: "arrow.left")
                .foregroundStyle(.tertiary)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text(L("比較ブランチ"))
                    .font(.callout.weight(.medium))
                Text(viewModel.headBranch)
                    .font(.callout.monospaced())
                    .padding(.horizontal, DT.Space.sm)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }
        }
    }

    // MARK: - Title / body

    private var titleField: some View {
        VStack(alignment: .leading, spacing: DT.Space.xs) {
            Text(L("タイトル"))
                .font(.callout.weight(.medium))
            TextField("", text: $viewModel.title)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.isCreating)
        }
    }

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: DT.Space.xs) {
            Text(L("本文"))
                .font(.callout.weight(.medium))
            HistoryAwareTextEditor(text: $viewModel.body, history: [], placeholder: "")
                .frame(minHeight: 100, maxHeight: 160)
                .padding(DT.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        }
    }

    private func errorMessageView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DT.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: .systemRed))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DT.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                .fill(Color(nsColor: .systemRed).opacity(0.08))
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if viewModel.isCreating {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button(L("キャンセル")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isCreating)
            Button {
                Task { await submit() }
            } label: {
                Text(L("プルリクエストを作成"))
                    .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.isCreating)
        }
    }

    private func submit() async {
        guard let ref = repoVM.githubRepository, let token = accountStore.currentToken else { return }
        guard let created = await viewModel.create(ref: ref, token: token, hasUpstream: repoVM.hasUpstream, ahead: repoVM.ahead) else { return }

        dismiss()
        await pullRequestsVM.load(ref: ref, token: token)
        if let match = pullRequestsVM.pullRequests.first(where: { $0.number == created.number }) {
            await pullRequestsVM.select(match)
        }
        repoVM.operationSuccess = L("プルリクエストを作成しました: #%d", created.number)
    }
}
