import SwiftUI

struct ChangesView: View {
    let repository: Repository
    @StateObject private var viewModel: ChangesViewModel

    init(repository: Repository) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: ChangesViewModel(repository: repository))
    }

    var body: some View {
        HSplitView {
            fileList
                .frame(minWidth: 300, idealWidth: 360)

            VStack(spacing: 0) {
                DiffView(
                    diffText: viewModel.diffText,
                    isLoading: viewModel.isLoadingDiff,
                    selectedFile: viewModel.selectedChange?.displayPath
                )
                Divider()
                CommitMessageEditor(viewModel: viewModel)
                    .padding(DT.Space.lg)
            }
        }
        .task {
            await viewModel.refreshAll()
        }
        .alert("エラー", isPresented: Binding(
            get: { viewModel.lastError != nil },
            set: { if !$0 { viewModel.lastError = nil } }
        )) {
            Button("OK") { viewModel.lastError = nil }
        } message: {
            Text(viewModel.lastError ?? "")
        }
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack(spacing: DT.Space.sm) {
                Toggle("", isOn: Binding(
                    get: { viewModel.allStaged },
                    set: { _ in Task { await viewModel.toggleAll() } }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(viewModel.changes.isEmpty)

                Text("変更されたファイル")
                    .font(.headline)

                Spacer()

                if !viewModel.changes.isEmpty {
                    Text("\(viewModel.stagedCount) / \(viewModel.changes.count)")
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

            if viewModel.changes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(viewModel.changes) { change in
                            FileChangeRow(
                                change: change,
                                isSelected: viewModel.selectedPath == change.path,
                                onToggle: {
                                    Task { await viewModel.toggleInclusion(of: change) }
                                }
                            )
                            .onTapGesture { viewModel.select(change) }
                        }
                    }
                    .padding(.horizontal, DT.Space.xs)
                    .padding(.vertical, DT.Space.xs)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DT.Space.md) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .green.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Text("変更はありません")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("作業ツリーはクリーンです ✨")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
