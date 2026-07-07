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

    /// Checked in this order because a same-branch mistake and an unpushed
    /// branch are both more actionable than "you forgot a title".
    private func validate(hasUpstream: Bool) -> String? {
        if !baseBranch.isEmpty && baseBranch == headBranch {
            return L("ベースブランチと比較ブランチが同じです")
        }
        if !hasUpstream {
            return L("先にブランチをプッシュしてください")
        }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L("タイトルを入力してください")
        }
        return nil
    }

    func create(ref: GitHubRepositoryRef, token: String, hasUpstream: Bool) async -> PullRequest? {
        if let validationMessage = validate(hasUpstream: hasUpstream) {
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
