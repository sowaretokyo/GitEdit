import SwiftUI
import AppKit

struct InitSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var store: RepositoryStore

    @State private var folder: URL?
    @State private var initialBranch: String = "main"
    @State private var isInitializing: Bool = false
    @State private var error: GitOperationError?

    private var canInit: Bool { folder != nil && !isInitializing && !initialBranch.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.lg) {
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text(L("新しいリポジトリを作成"))
                    .font(.title2.weight(.semibold))
                Text(L("空のフォルダを選んで Git リポジトリを初期化します"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DT.Space.sm) {
                Text(L("フォルダ"))
                    .font(.callout.weight(.medium))
                folderPicker
            }

            VStack(alignment: .leading, spacing: DT.Space.sm) {
                Text(L("初期ブランチ"))
                    .font(.callout.weight(.medium))
                TextField("main", text: $initialBranch)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isInitializing)
            }

            if let error {
                InlineErrorView(error: error)
            }

            Spacer(minLength: 0)

            HStack {
                if isInitializing {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button(L("キャンセル")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isInitializing)
                Button {
                    Task { await performInit() }
                } label: {
                    Text(L("作成"))
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canInit)
            }
        }
        .padding(DT.Space.xl)
        .frame(width: 520)
    }

    private var folderPicker: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
            Text(folder?.path ?? L("選択されていません"))
                .font(.callout)
                .foregroundStyle(folder == nil ? .tertiary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(L("選択…")) { chooseFolder() }
                .disabled(isInitializing)
        }
        .padding(.horizontal, DT.Space.sm)
        .padding(.vertical, DT.Space.xs + 1)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L("選択")
        panel.message = L("初期化するフォルダを選択")
        if panel.runModal() == .OK { folder = panel.url }
    }

    private func performInit() async {
        guard let folder else { return }
        isInitializing = true
        defer { isInitializing = false }
        error = nil

        do {
            try await GitClient.initRepository(at: folder, initialBranch: initialBranch)
            await store.addRepository(at: folder)
            isPresented = false
        } catch {
            self.error = GitErrorClassifier.classify(error, operation: .initRepo)
        }
    }
}
