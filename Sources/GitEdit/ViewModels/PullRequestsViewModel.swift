import Foundation

@MainActor
final class PullRequestsViewModel: ObservableObject {
    @Published private(set) var pullRequests: [PullRequest] = []
    @Published var selectedPullRequest: PullRequest?
    @Published private(set) var ciSummaries: [Int: CIStatusSummary] = [:]
    @Published private(set) var detailChecks: [CheckRun] = []
    @Published private(set) var isLoadingList: Bool = false
    @Published private(set) var isLoadingDetail: Bool = false
    @Published private(set) var reviews: [PullRequestReview] = []
    @Published private(set) var comments: [IssueComment] = []
    @Published private(set) var isSubmittingReviewAction: Bool = false
    @Published var reviewActionErrorMessage: String?
    @Published private(set) var isMerging: Bool = false
    @Published var mergeActionErrorMessage: String?
    /// Whether the list endpoint reported a further page (i.e. more than the
    /// 50 PRs we fetch). Drives the "上位 N 件を表示しています" footnote.
    @Published private(set) var hasMorePages: Bool = false
    @Published var loadErrorMessage: String?
    /// Set when a detail load/refresh (`select`) fails. Cleared on every new
    /// `select` call. Distinct from `loadErrorMessage`, which covers the PR
    /// list itself.
    @Published private(set) var detailLoadErrorMessage: String?
    /// Set when the load failure was `.unauthorized` / `.insufficientScopes`,
    /// so the sidebar can offer "再サインイン" instead of a generic retry.
    @Published private(set) var needsReauth: Bool = false
    @Published var isShowingCreateSheet: Bool = false

    private var currentRef: GitHubRepositoryRef?
    private var currentToken: String?
    /// Bumped at the start of every `select`. A detail load only clears
    /// `isLoadingDetail` if its captured generation is still the latest — a
    /// stale load finishing after the user picked another PR (or re-selected
    /// the same one) must not flip the spinner off mid-load.
    private var detailLoadGeneration = 0

    // MARK: - Loading

    func load(ref: GitHubRepositoryRef, token: String) async {
        currentRef = ref
        currentToken = token
        isLoadingList = true
        loadErrorMessage = nil
        needsReauth = false
        defer { isLoadingList = false }

        let api = GitHubAPI(token: token)
        do {
            let response = try await api.listPullRequests(owner: ref.owner, repo: ref.repo)
            pullRequests = response.value
            hasMorePages = response.nextPageURL != nil
            await loadCIStatuses(api: api, ref: ref)

            if let selected = selectedPullRequest,
               let match = pullRequests.first(where: { $0.number == selected.number }) {
                await select(match)
            } else {
                selectedPullRequest = nil
                detailChecks = []
                reviews = []
                comments = []
            }
        } catch {
            pullRequests = []
            ciSummaries = [:]
            hasMorePages = false
            applyLoadError(error)
        }
    }

    /// Re-runs `load` against the last-used repository/token. No-op if
    /// nothing has been loaded yet (there's nothing to refresh against).
    func refresh() async {
        guard let ref = currentRef, let token = currentToken else { return }
        await load(ref: ref, token: token)
    }

    private func applyLoadError(_ error: Error) {
        if let apiError = error as? GitHubAPI.APIError {
            switch apiError {
            case .unauthorized, .insufficientScopes:
                needsReauth = true
            default:
                needsReauth = false
            }
            loadErrorMessage = apiError.errorDescription
        } else {
            needsReauth = false
            loadErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Selection & detail

    func select(_ pr: PullRequest) async {
        // Switching to a different PR must not leave the previous PR's
        // checks/reviews/comments on screen if the detail request below
        // fails — clear them up front. A refresh of the already-selected PR
        // intentionally keeps the old data on failure (see the catch below).
        let isNewSelection = selectedPullRequest?.number != pr.number
        detailLoadErrorMessage = nil
        if isNewSelection {
            detailChecks = []
            reviews = []
            comments = []
        }
        selectedPullRequest = pr
        guard let ref = currentRef, let token = currentToken else { return }

        detailLoadGeneration += 1
        let generation = detailLoadGeneration
        isLoadingDetail = true
        defer {
            if generation == detailLoadGeneration { isLoadingDetail = false }
        }

        let api = GitHubAPI(token: token)
        do {
            let detail = try await api.pullRequest(owner: ref.owner, repo: ref.repo, number: pr.number)
            // A newer select() may have started while this was in flight —
            // bail rather than clobber it. `generation` is stronger than a
            // PR-number check: it also distinguishes overlapping loads of the
            // same PR (e.g. a refresh landing on top of a manual re-select).
            guard generation == detailLoadGeneration else { return }
            selectedPullRequest = detail

            async let runsResult = try? api.checkRuns(owner: ref.owner, repo: ref.repo, ref: detail.head.sha)
            async let combinedResult = try? api.combinedStatus(owner: ref.owner, repo: ref.repo, ref: detail.head.sha)
            async let reviewsResult = try? api.reviews(owner: ref.owner, repo: ref.repo, number: pr.number)
            async let commentsResult = try? api.issueComments(owner: ref.owner, repo: ref.repo, number: pr.number)
            let runs = await runsResult?.checkRuns ?? []
            let combined = await combinedResult
            let loadedReviews = await reviewsResult ?? []
            let loadedComments = await commentsResult ?? []

            guard generation == detailLoadGeneration else { return }
            detailChecks = runs
            ciSummaries[pr.number] = CIStatusAggregator.aggregate(checkRuns: runs, combined: combined)
            reviews = loadedReviews
            comments = loadedComments
        } catch {
            // A failed detail refresh isn't fatal — keep showing whatever
            // summary/checks/reviews/comments we already had (cleared above
            // if this was a new selection). Only surface the error if this is
            // still the newest load — a newer select() (including a refresh of
            // the same PR that has since succeeded) may have superseded it.
            guard generation == detailLoadGeneration else { return }
            detailLoadErrorMessage = Self.errorDetail(for: error)
        }
    }

    // MARK: - Review & comment actions

    /// Posts a plain conversation comment (not tied to review state).
    /// Requires non-empty text — fails fast rather than sending GitHub an
    /// empty comment.
    func postComment(on pr: PullRequest, body: String) async -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            reviewActionErrorMessage = L("コメントを入力してください")
            return nil
        }
        return await performReviewAction(pr: pr) { api, ref in
            _ = try await api.createIssueComment(owner: ref.owner, repo: ref.repo, number: pr.number, body: trimmed)
            return L("コメントを投稿しました")
        }
    }

    /// Approves the pull request. `body` is optional for an approval.
    func approvePullRequest(_ pr: PullRequest, body: String) async -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return await performReviewAction(pr: pr) { api, ref in
            _ = try await api.createReview(owner: ref.owner, repo: ref.repo, number: pr.number, event: .approve, body: trimmed.isEmpty ? nil : trimmed)
            return L("承認しました")
        }
    }

    /// Requests changes on the pull request. Requires non-empty text —
    /// GitHub rejects a `REQUEST_CHANGES` review with no body.
    func requestChanges(on pr: PullRequest, body: String) async -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            reviewActionErrorMessage = L("コメントを入力してください")
            return nil
        }
        return await performReviewAction(pr: pr) { api, ref in
            _ = try await api.createReview(owner: ref.owner, repo: ref.repo, number: pr.number, event: .requestChanges, body: trimmed)
            return L("変更をリクエストしました")
        }
    }

    /// Shared plumbing for the three review actions above: guards on having
    /// a loaded repo/token, tracks the in-flight flag, reloads the
    /// review/comment lists on success, and normalizes the error message on
    /// failure. `action` performs the actual API call and returns the
    /// success toast text.
    private func performReviewAction(
        pr: PullRequest,
        _ action: (GitHubAPI, GitHubRepositoryRef) async throws -> String
    ) async -> String? {
        guard let ref = currentRef, let token = currentToken else { return nil }
        isSubmittingReviewAction = true
        reviewActionErrorMessage = nil
        defer { isSubmittingReviewAction = false }

        let api = GitHubAPI(token: token)
        do {
            let successMessage = try await action(api, ref)
            await reloadReviewsAndComments(pr: pr, api: api, ref: ref)
            return successMessage
        } catch {
            reviewActionErrorMessage = Self.errorDetail(for: error)
            return nil
        }
    }

    private func reloadReviewsAndComments(pr: PullRequest, api: GitHubAPI, ref: GitHubRepositoryRef) async {
        async let reviewsResult = try? api.reviews(owner: ref.owner, repo: ref.repo, number: pr.number)
        async let commentsResult = try? api.issueComments(owner: ref.owner, repo: ref.repo, number: pr.number)
        let loadedReviews = await reviewsResult ?? []
        let loadedComments = await commentsResult ?? []
        guard selectedPullRequest?.number == pr.number else { return }
        reviews = loadedReviews
        comments = loadedComments
    }

    private static func errorDetail(for error: Error) -> String {
        (error as? GitHubAPI.APIError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Merge

    /// Merges the pull request, pinning to its current head SHA so GitHub
    /// rejects the merge (409 → `.conflict`) if the branch moved since this
    /// PR was last fetched. Re-fetches the PR afterwards either way, so a
    /// stale `mergeable`/`mergeable_state` doesn't linger in the UI.
    func mergePullRequest(_ pr: PullRequest, method: MergeMethod) async -> String? {
        guard let ref = currentRef, let token = currentToken else { return nil }
        isMerging = true
        mergeActionErrorMessage = nil
        defer { isMerging = false }

        let api = GitHubAPI(token: token)
        do {
            _ = try await api.mergePullRequest(
                owner: ref.owner,
                repo: ref.repo,
                number: pr.number,
                method: method,
                sha: pr.head.sha,
                commitTitle: nil,
                commitMessage: nil
            )
            await refetchAfterMerge(pr: pr, api: api, ref: ref)
            return L("マージしました")
        } catch {
            mergeActionErrorMessage = Self.errorDetail(for: error)
            await refetchAfterMerge(pr: pr, api: api, ref: ref)
            return nil
        }
    }

    private func refetchAfterMerge(pr: PullRequest, api: GitHubAPI, ref: GitHubRepositoryRef) async {
        guard let updated = try? await api.pullRequest(owner: ref.owner, repo: ref.repo, number: pr.number) else { return }
        if let index = pullRequests.firstIndex(where: { $0.number == pr.number }) {
            pullRequests[index] = updated
        }
        guard selectedPullRequest?.number == pr.number else { return }
        selectedPullRequest = updated
    }

    // MARK: - Per-row CI status fan-out

    /// Loads CI status for every PR in the current list concurrently so the
    /// sidebar's badges populate without waiting on a serial N-request chain.
    private func loadCIStatuses(api: GitHubAPI, ref: GitHubRepositoryRef) async {
        let prs = pullRequests
        // Cap in-flight PRs to avoid firing up to 50×2 = 100 concurrent
        // GitHub API requests at once, which can trip the secondary rate
        // limit. A sliding window keeps at most `maxConcurrent` PRs'
        // requests (~2 each) in flight at a time: start with a batch, then
        // add one more each time a task completes.
        let maxConcurrent = 5
        await withTaskGroup(of: (Int, CIStatusSummary).self) { group in
            var nextIndex = 0

            func addTask(for pr: PullRequest) {
                group.addTask {
                    async let runsResult = try? api.checkRuns(owner: ref.owner, repo: ref.repo, ref: pr.head.sha)
                    async let combinedResult = try? api.combinedStatus(owner: ref.owner, repo: ref.repo, ref: pr.head.sha)
                    let runs = await runsResult?.checkRuns ?? []
                    let combined = await combinedResult
                    return (pr.number, CIStatusAggregator.aggregate(checkRuns: runs, combined: combined))
                }
            }

            while nextIndex < prs.count && nextIndex < maxConcurrent {
                addTask(for: prs[nextIndex])
                nextIndex += 1
            }

            var results: [Int: CIStatusSummary] = [:]
            for await (number, summary) in group {
                results[number] = summary
                if nextIndex < prs.count {
                    addTask(for: prs[nextIndex])
                    nextIndex += 1
                }
            }
            ciSummaries = results
        }
    }
}
