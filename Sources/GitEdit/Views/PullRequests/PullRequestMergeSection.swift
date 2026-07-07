import SwiftUI

/// Merge-method picker + merge action for an open, unmerged pull request.
/// `PullRequestDetailView` only shows this section while the PR is open and
/// unmerged; merged/closed PRs already convey that via the state badge.
struct PullRequestMergeSection: View {
    let pullRequest: PullRequest
    @ObservedObject var repoVM: RepositoryViewModel
    @ObservedObject var viewModel: PullRequestsViewModel

    @State private var mergeMethod: MergeMethod = .merge
    @State private var isShowingConfirmation = false

    private var ci: CIStatus { viewModel.ciSummaries[pullRequest.number]?.overall ?? .none }
    private var readiness: MergeReadiness { PullRequestMergeability.evaluate(pr: pullRequest, ci: ci) }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            Divider()

            Text(L("マージ"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(L("マージ方法"), selection: $mergeMethod) {
                ForEach(MergeMethod.allCases, id: \.self) { method in
                    Text(label(for: method)).tag(method)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(viewModel.isMerging)
            .frame(maxWidth: 260, alignment: .leading)

            HStack(spacing: DT.Space.sm) {
                Button {
                    isShowingConfirmation = true
                } label: {
                    if viewModel.isMerging {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(L("マージ"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!readiness.canMerge || viewModel.isMerging)

                if let reasonText {
                    Text(reasonText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let message = viewModel.mergeActionErrorMessage {
                mergeErrorView(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            L("プルリクエストをマージしますか？"),
            isPresented: $isShowingConfirmation,
            titleVisibility: .visible
        ) {
            Button(L("マージ")) {
                Task { await merge() }
            }
            Button(L("キャンセル"), role: .cancel) {}
        } message: {
            if readiness.ciWarning {
                Text(L("チェックが失敗していますが、マージしますか？"))
            }
        }
    }

    private func label(for method: MergeMethod) -> String {
        switch method {
        case .merge: return L("マージコミット")
        case .squash: return L("スカッシュしてマージ")
        case .rebase: return L("リベースしてマージ")
        }
    }

    private var reasonText: String? {
        switch readiness.reason {
        case .draft: return L("ドラフトのためマージできません")
        case .conflicts: return L("コンフリクトがあるためマージできません")
        case .computing: return L("マージ可否を判定中です")
        case .blocked: return L("ブランチ保護によりマージがブロックされています")
        case .alreadyMerged, .closed, nil: return nil
        }
    }

    private func mergeErrorView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DT.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: .systemRed))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("マージに失敗しました"))
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

    private func merge() async {
        if let message = await viewModel.mergePullRequest(pullRequest, method: mergeMethod) {
            repoVM.operationSuccess = message
        }
    }
}
