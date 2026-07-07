import SwiftUI

/// Detail pane for a single pull request: header, body, checks, merge
/// action, and review/comment section, in that order.
struct PullRequestDetailView: View {
    let pullRequest: PullRequest
    @ObservedObject var repoVM: RepositoryViewModel
    @ObservedObject var viewModel: PullRequestsViewModel

    @State private var isCheckingOut = false

    private var ciSummary: CIStatusSummary? { viewModel.ciSummaries[pullRequest.number] }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DT.Space.lg) {
                    header

                    if let body = pullRequest.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
                        bodySection(body)
                    }

                    checksSection

                    if pullRequest.isOpen && !pullRequest.isMerged {
                        PullRequestMergeSection(pullRequest: pullRequest, repoVM: repoVM, viewModel: viewModel)
                    }

                    PullRequestReviewSection(pullRequest: pullRequest, repoVM: repoVM, viewModel: viewModel)
                }
                .padding(DT.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            HStack(alignment: .top, spacing: DT.Space.sm) {
                Text(pullRequest.title)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DT.Space.sm)
                stateBadge
            }

            HStack(spacing: DT.Space.sm) {
                if let login = pullRequest.user?.login {
                    AvatarImageView(
                        url: pullRequest.user?.avatarURL.flatMap { URL(string: $0) },
                        initials: String(login.prefix(1)).uppercased(),
                        tintColor: .accentColor,
                        size: 20
                    )
                    Text(login)
                }
                Text("#\(pullRequest.number)")
                    .font(.callout.monospaced())
                Spacer(minLength: 0)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack(spacing: DT.Space.xs) {
                Text(pullRequest.head.label)
                    .font(.caption.monospaced())
                Image(systemName: "arrow.left")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(pullRequest.base.label)
                    .font(.caption.monospaced())
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stateBadge: some View {
        Text(stateBadgeText)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(stateBadgeColor.opacity(0.18), in: Capsule())
            .foregroundStyle(stateBadgeColor)
    }

    private var stateBadgeText: String {
        if pullRequest.isMerged { return L("マージ済み") }
        if !pullRequest.isOpen { return L("クローズ") }
        if pullRequest.isDraft { return L("ドラフト") }
        return L("オープン")
    }

    private var stateBadgeColor: Color {
        if pullRequest.isMerged { return Color(nsColor: .systemPurple) }
        if !pullRequest.isOpen { return Color(nsColor: .systemRed) }
        if pullRequest.isDraft { return Color(nsColor: .systemGray) }
        return Color(nsColor: .systemGreen)
    }

    // MARK: - Body

    private func bodySection(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Checks

    private var checksSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            HStack {
                Text(L("チェック"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let ciSummary, ciSummary.total > 0 {
                    Text(L("成功 %d ・失敗 %d ・実行中 %d", ciSummary.success, ciSummary.failure, ciSummary.pending))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isLoadingDetail && viewModel.detailChecks.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if viewModel.detailChecks.isEmpty {
                Text(L("チェックはありません"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: DT.Space.xs) {
                    ForEach(viewModel.detailChecks) { run in
                        CheckRunRow(run: run)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer (checkout / open in browser)

    private var footer: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            if !pullRequest.isSameRepo {
                Label(
                    L("フォークからのプルリクエストは閲覧のみ対応しています（チェックアウト後はプッシュできません）"),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    Task { await checkout() }
                } label: {
                    if isCheckingOut {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(L("チェックアウト"), systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCheckingOut)

                Spacer()

                if let url = URL(string: pullRequest.htmlURL) {
                    Link(destination: url) {
                        Label(L("ブラウザで開く"), systemImage: "arrow.up.forward.square")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(DT.Space.lg)
    }

    private func checkout() async {
        isCheckingOut = true
        defer { isCheckingOut = false }
        await repoVM.checkoutPullRequest(pullRequest)
    }
}

// MARK: - Check run row

private struct CheckRunRow: View {
    let run: CheckRun
    @Environment(\.openURL) private var openURL

    private var status: CIStatus { CIStatusAggregator.classify(run) }

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            statusIcon
            Text(run.name)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: DT.Space.sm)
            if let urlString = run.detailsURL, let url = URL(string: urlString) {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(nsColor: .systemGreen))
        case .failure:
            Image(systemName: "xmark.circle.fill").foregroundStyle(Color(nsColor: .systemRed))
        case .pending:
            Image(systemName: "circle.dotted").foregroundStyle(Color(nsColor: .systemYellow))
        case .none:
            Image(systemName: "circle.dashed").foregroundStyle(.tertiary)
        }
    }
}
