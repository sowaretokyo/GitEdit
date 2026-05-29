import SwiftUI

struct CommitDetailView: View {
    let commit: Commit
    @ObservedObject var viewModel: HistoryViewModel

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            metadataHeader
            Divider()
            HSplitView {
                fileList
                    .frame(minWidth: 260, idealWidth: 320)
                fileDiff
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: commit.id) {
            await viewModel.loadFilesForCommit(commit.id)
        }
    }

    // MARK: - Header

    private var metadataHeader: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            Text(commit.summary)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DT.Space.lg) {
                Label {
                    Text(commit.author)
                } icon: {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(.tint)
                }
                Label {
                    Text(Self.absoluteFormatter.string(from: commit.date))
                } icon: {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.tint)
                }
                Label {
                    Text(commit.shortSHA)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "number")
                        .foregroundStyle(.tint)
                }
                Spacer(minLength: 0)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if !commit.body.isEmpty {
                Text(commit.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, DT.Space.xs)
            }
        }
        .padding(DT.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - File list

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("変更ファイル"))
                    .font(.headline)
                Spacer()
                if !viewModel.commitFiles.isEmpty {
                    Text("\(viewModel.commitFiles.count)")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, DT.Space.md)
            .padding(.vertical, DT.Space.sm + 2)

            Divider()

            if viewModel.isLoadingCommitFiles && viewModel.commitFiles.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.commitFiles.isEmpty {
                VStack(spacing: DT.Space.sm) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(L("ファイル変更なし"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(viewModel.commitFiles) { file in
                            CommitFileRow(
                                file: file,
                                isSelected: viewModel.selectedCommitFilePath == file.path
                            )
                            .onTapGesture {
                                Task { await viewModel.selectCommitFile(file) }
                            }
                        }
                    }
                    .padding(.horizontal, DT.Space.xs)
                    .padding(.vertical, DT.Space.xs)
                }
            }
        }
    }

    // MARK: - Diff

    private var fileDiff: some View {
        DiffView(
            diffText: viewModel.commitFileDiff,
            isLoading: viewModel.isLoadingCommitFileDiff,
            selectedFile: viewModel.selectedCommitFile?.displayPath
        )
    }
}
