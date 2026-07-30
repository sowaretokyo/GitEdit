import SwiftUI
import AppKit

/// Left sidebar contents for the Pull Requests tab.
struct PullRequestSidebar: View {
    @ObservedObject var repoVM: RepositoryViewModel
    @ObservedObject var viewModel: PullRequestsViewModel
    @StateObject private var accountStore = AccountStore.shared
    @State private var isShowingSignIn = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale.current
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        SidebarContainer {
            header
        } content: {
            content
        }
        .sheet(isPresented: $isShowingSignIn) {
            DeviceFlowSheet(isPresented: $isShowingSignIn, store: accountStore)
        }
        .sheet(isPresented: $viewModel.isShowingCreateSheet) {
            CreatePullRequestSheet(repoVM: repoVM, pullRequestsVM: viewModel)
        }
    }

    // MARK: - Header

    private var canInteract: Bool {
        accountStore.isSignedIn && repoVM.githubRepository != nil
    }

    private var header: some View {
        HStack(spacing: DT.Space.sm) {
            Text(L("プルリクエスト"))
                .font(.callout.weight(.medium))
            if !viewModel.pullRequests.isEmpty {
                CountBadge(count: viewModel.pullRequests.count)
            }
            Spacer()
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help(L("更新"))
            .disabled(!canInteract || viewModel.isLoadingList)

            Button {
                viewModel.isShowingCreateSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help(L("新規プルリクエスト"))
            .disabled(!canInteract)
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm + 2)
    }

    private func reload() async {
        guard let ref = repoVM.githubRepository, let token = accountStore.currentToken else { return }
        await viewModel.load(ref: ref, token: token)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !accountStore.isSignedIn {
            signInPrompt
        } else if repoVM.githubRepository == nil {
            notGitHubPrompt
        } else if viewModel.isLoadingList && viewModel.pullRequests.isEmpty {
            loadingState
        } else if let message = viewModel.loadErrorMessage {
            errorState(message: message)
        } else if viewModel.pullRequests.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var signInPrompt: some View {
        VStack(spacing: DT.Space.md) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("プルリクエストを表示するには GitHub にサインインしてください"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Space.lg)
            Button(L("GitHub.com にサインイン…")) {
                isShowingSignIn = true
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notGitHubPrompt: some View {
        EmptyStateView(
            icon: "questionmark.circle",
            title: L("このリポジトリは GitHub ではありません"),
            background: .clear
        )
    }

    private var loadingState: some View {
        LoadingStateView()
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "tray",
            title: L("オープンなプルリクエストはありません"),
            background: .clear
        )
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: DT.Space.sm) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color(nsColor: .systemRed))
            Text(L("プルリクエストを読み込めませんでした"))
                .font(.callout.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Space.lg)
            if viewModel.needsReauth {
                Button(L("再サインイン")) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(L("もう一度試す")) {
                    Task { await reload() }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { viewModel.selectedPullRequest?.number },
                set: { newValue in
                    guard let newValue,
                          let pr = viewModel.pullRequests.first(where: { $0.number == newValue }) else { return }
                    Task { await viewModel.select(pr) }
                }
            )) {
                ForEach(viewModel.pullRequests) { pr in
                    PullRequestRow(
                        pr: pr,
                        ciSummary: viewModel.ciSummaries[pr.number],
                        relativeFormatter: Self.relativeFormatter
                    )
                    .tag(pr.number)
                }
            }
            .listStyle(.inset)

            if viewModel.hasMorePages {
                Divider()
                Text(L("上位 %d 件を表示しています", viewModel.pullRequests.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DT.Space.sm)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Row

private struct PullRequestRow: View {
    let pr: PullRequest
    let ciSummary: CIStatusSummary?
    let relativeFormatter: RelativeDateTimeFormatter

    var body: some View {
        HStack(alignment: .top, spacing: DT.Space.sm) {
            AvatarImageView(
                url: pr.user?.avatarURL.flatMap { URL(string: $0) },
                initials: String((pr.user?.login ?? "?").prefix(1)).uppercased(),
                tintColor: .accentColor,
                size: 28
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(pr.title)
                        .font(.callout)
                        .lineLimit(1)
                    if pr.isDraft {
                        Text(L("ドラフト"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(nsColor: .systemGray).opacity(0.18), in: Capsule())
                            .foregroundStyle(Color(nsColor: .systemGray))
                    }
                }

                HStack(spacing: 6) {
                    Text("#\(pr.number)")
                    Text(pr.head.ref)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                    Text(pr.base.ref)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Text(relativeFormatter.localizedString(for: pr.updatedAt, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: DT.Space.sm)

            CIStatusBadge(summary: ciSummary)
        }
        .padding(.vertical, DT.RowDensity.regular)
    }
}
