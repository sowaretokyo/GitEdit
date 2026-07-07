import SwiftUI

/// Existing reviews + conversation comments for a pull request, plus a
/// composer for posting a new plain comment or formal review (approve /
/// request changes). Slots into `PullRequestDetailView` below the checks
/// section.
struct PullRequestReviewSection: View {
    let pullRequest: PullRequest
    @ObservedObject var repoVM: RepositoryViewModel
    @ObservedObject var viewModel: PullRequestsViewModel

    @State private var draftText: String = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.md) {
            Divider()

            Text(L("レビュー"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if viewModel.isLoadingDetail && viewModel.reviews.isEmpty && viewModel.comments.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if !viewModel.reviews.isEmpty || !viewModel.comments.isEmpty {
                timeline
            }

            composer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            ForEach(viewModel.reviews) { review in
                reviewRow(review)
            }
            ForEach(viewModel.comments) { comment in
                commentRow(comment)
            }
        }
    }

    private func reviewRow(_ review: PullRequestReview) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.xs) {
            HStack(spacing: DT.Space.xs) {
                Text(review.user?.login ?? "?")
                    .font(.callout.weight(.medium))
                reviewStateBadge(review.state)
                Spacer()
                if let date = review.submittedAt {
                    Text(Self.dateFormatter.string(from: date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if let body = review.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DT.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }

    private func commentRow(_ comment: IssueComment) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.xs) {
            HStack(spacing: DT.Space.xs) {
                Text(comment.user?.login ?? "?")
                    .font(.callout.weight(.medium))
                Spacer()
                Text(Self.dateFormatter.string(from: comment.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(comment.body)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DT.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reviewStateBadge(_ state: String) -> some View {
        let (text, color): (String, Color) = {
            switch state {
            case "APPROVED": return (L("承認"), Color(nsColor: .systemGreen))
            case "CHANGES_REQUESTED": return (L("変更をリクエスト"), Color(nsColor: .systemRed))
            case "COMMENTED": return (L("コメント"), Color(nsColor: .systemGray))
            default: return (state, Color(nsColor: .systemGray))
            }
        }()
        return Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            HistoryAwareTextEditor(text: $draftText, history: [], placeholder: L("コメントを書く…"))
                .frame(minHeight: 70, maxHeight: 120)
                .padding(DT.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .disabled(viewModel.isSubmittingReviewAction)

            if let message = viewModel.reviewActionErrorMessage {
                errorView(message)
            }

            HStack {
                if viewModel.isSubmittingReviewAction {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button(L("コメント")) { Task { await postComment() } }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isSubmittingReviewAction)
                Button(L("承認")) { Task { await approve() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSubmittingReviewAction)
                Button(L("変更をリクエスト")) { Task { await requestChanges() } }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isSubmittingReviewAction)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DT.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: .systemRed))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("レビューの投稿に失敗しました"))
                    .font(.caption.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DT.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                .fill(Color(nsColor: .systemRed).opacity(0.08))
        )
    }

    private func postComment() async {
        if let message = await viewModel.postComment(on: pullRequest, body: draftText) {
            repoVM.operationSuccess = message
            draftText = ""
        }
    }

    private func approve() async {
        if let message = await viewModel.approvePullRequest(pullRequest, body: draftText) {
            repoVM.operationSuccess = message
            draftText = ""
        }
    }

    private func requestChanges() async {
        if let message = await viewModel.requestChanges(on: pullRequest, body: draftText) {
            repoVM.operationSuccess = message
            draftText = ""
        }
    }
}
