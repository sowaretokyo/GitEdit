import Foundation

@MainActor
final class PullRequestsViewModel: ObservableObject {
    @Published private(set) var pullRequests: [PullRequest] = []
    @Published var selectedPullRequest: PullRequest?
    @Published private(set) var ciSummaries: [Int: CIStatusSummary] = [:]
    @Published private(set) var detailChecks: [CheckRun] = []
    @Published private(set) var isLoadingList: Bool = false
    @Published private(set) var isLoadingDetail: Bool = false
    /// Whether the list endpoint reported a further page (i.e. more than the
    /// 50 PRs we fetch). Drives the "上位 N 件を表示しています" footnote.
    @Published private(set) var hasMorePages: Bool = false
    @Published var loadErrorMessage: String?
    /// Set when the load failure was `.unauthorized` / `.insufficientScopes`,
    /// so the sidebar can offer "再サインイン" instead of a generic retry.
    @Published private(set) var needsReauth: Bool = false
    @Published var isShowingCreateSheet: Bool = false

    private var currentRef: GitHubRepositoryRef?
    private var currentToken: String?

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
        selectedPullRequest = pr
        guard let ref = currentRef, let token = currentToken else { return }

        isLoadingDetail = true
        defer { isLoadingDetail = false }

        let api = GitHubAPI(token: token)
        do {
            let detail = try await api.pullRequest(owner: ref.owner, repo: ref.repo, number: pr.number)
            // The user may have already clicked a different row while this
            // was in flight — don't clobber their new selection.
            guard selectedPullRequest?.number == pr.number else { return }
            selectedPullRequest = detail

            async let runsResult = try? api.checkRuns(owner: ref.owner, repo: ref.repo, ref: detail.head.sha)
            async let combinedResult = try? api.combinedStatus(owner: ref.owner, repo: ref.repo, ref: detail.head.sha)
            let runs = await runsResult?.checkRuns ?? []
            let combined = await combinedResult

            guard selectedPullRequest?.number == pr.number else { return }
            detailChecks = runs
            ciSummaries[pr.number] = CIStatusAggregator.aggregate(checkRuns: runs, combined: combined)
        } catch {
            // A failed detail refresh isn't fatal — keep showing the summary
            // from the list and whatever checks we already had.
        }
    }

    // MARK: - Per-row CI status fan-out

    /// Loads CI status for every PR in the current list concurrently so the
    /// sidebar's badges populate without waiting on a serial N-request chain.
    private func loadCIStatuses(api: GitHubAPI, ref: GitHubRepositoryRef) async {
        let prs = pullRequests
        await withTaskGroup(of: (Int, CIStatusSummary).self) { group in
            for pr in prs {
                group.addTask {
                    async let runsResult = try? api.checkRuns(owner: ref.owner, repo: ref.repo, ref: pr.head.sha)
                    async let combinedResult = try? api.combinedStatus(owner: ref.owner, repo: ref.repo, ref: pr.head.sha)
                    let runs = await runsResult?.checkRuns ?? []
                    let combined = await combinedResult
                    return (pr.number, CIStatusAggregator.aggregate(checkRuns: runs, combined: combined))
                }
            }
            var results: [Int: CIStatusSummary] = [:]
            for await (number, summary) in group {
                results[number] = summary
            }
            ciSummaries = results
        }
    }
}
