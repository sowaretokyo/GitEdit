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
                .frame(minWidth: 260, idealWidth: 320)

            VStack(spacing: 0) {
                diffPanel
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
            HStack {
                Text("変更されたファイル")
                    .font(.headline)
                Spacer()
                if !viewModel.changes.isEmpty {
                    Text("\(viewModel.changes.count)")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.18), in: Capsule())
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
                            FileChangeRow(change: change)
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

    private var diffPanel: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            VStack(spacing: DT.Space.sm) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("差分ビューア")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Phase 2 で実装予定")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxHeight: .infinity)
    }
}
