import Foundation

@MainActor
final class CreatePullRequestViewModel: ObservableObject {
    let headBranch: String
    @Published var title: String
    @Published var body: String = ""
    @Published var baseBranch: String
    @Published private(set) var isCreating: Bool = false
    @Published var errorMessage: String?

    init(headBranch: String, defaultTitle: String, baseBranch: String) {
        self.headBranch = headBranch
        self.title = defaultTitle
        self.baseBranch = baseBranch
    }

    /// Checked in this order because a same-branch mistake, an unpushed branch,
    /// and unpushed commits are all more actionable than "you forgot a title".
    private func validate(hasUpstream: Bool, ahead: Int) -> String? {
        if !baseBranch.isEmpty && baseBranch == headBranch {
            return L("ベースブランチと比較ブランチが同じです")
        }
        if !hasUpstream {
            return L("先にブランチをプッシュしてください")
        }
        // The remote branch exists but is behind local: opening a PR now would
        // create it from a stale head. Push first so the PR reflects all commits.
        if ahead > 0 {
            return L("先に未pushのコミットをプッシュしてください")
        }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L("タイトルを入力してください")
        }
        return nil
    }

    func create(ref: GitHubRepositoryRef, token: String, hasUpstream: Bool, ahead: Int) async -> PullRequest? {
        if let validationMessage = validate(hasUpstream: hasUpstream, ahead: ahead) {
            errorMessage = validationMessage
            return nil
        }

        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        let api = GitHubAPI(token: token)
        do {
            return try await api.createPullRequest(
                owner: ref.owner,
                repo: ref.repo,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                head: headBranch,
                base: baseBranch,
                body: body
            )
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? GitHubAPI.APIError {
            return apiError.errorDescription ?? L("プルリクエストの作成に失敗しました")
        }
        return error.localizedDescription
    }
}
