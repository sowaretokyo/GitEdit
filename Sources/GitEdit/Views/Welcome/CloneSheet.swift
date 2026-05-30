import SwiftUI
import AppKit

struct CloneSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var store: RepositoryStore

    @State private var url: String = ""
    @State private var destination: URL?
    @State private var isCloning: Bool = false
    @State private var error: GitOperationError?

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canClone: Bool {
        !trimmedURL.isEmpty && destination != nil && !isCloning
    }

    private var derivedFolderName: String {
        let stripped = trimmedURL.hasSuffix(".git") ? String(trimmedURL.dropLast(4)) : trimmedURL
        return String(stripped.split(separator: "/").last ?? "repository")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.lg) {
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text(L("リポジトリをクローン"))
                    .font(.title2.weight(.semibold))
                Text(L("Git リポジトリの URL とローカルの保存先を指定してください"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DT.Space.sm) {
                Text(L("URL"))
                    .font(.callout.weight(.medium))
                TextField("https://github.com/owner/repo.git", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isCloning)
            }

            VStack(alignment: .leading, spacing: DT.Space.sm) {
                Text(L("保存先"))
                    .font(.callout.weight(.medium))
                destinationPicker
                if let destination, !trimmedURL.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .imageScale(.small)
                            .foregroundStyle(.tertiary)
                        Text(destination.appending(component: derivedFolderName).path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            if let error {
                InlineErrorView(error: error)
            }

            Spacer(minLength: 0)

            HStack {
                if isCloning {
                    ProgressView().controlSize(.small)
                    Text(L("クローン中…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("キャンセル")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCloning)
                Button {
                    Task { await performClone() }
                } label: {
                    Text(L("クローン"))
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canClone)
            }
        }
        .padding(DT.Space.xl)
        .frame(width: 560)
    }

    private var destinationPicker: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
            Text(destination?.path ?? L("選択されていません"))
                .font(.callout)
                .foregroundStyle(destination == nil ? .tertiary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(L("選択…")) { chooseDestination() }
                .disabled(isCloning)
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

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L("選択")
        panel.message = L("保存先を選択")
        if panel.runModal() == .OK { destination = panel.url }
    }

    private func performClone() async {
        guard let destination else { return }
        let target = destination.appending(component: derivedFolderName)

        isCloning = true
        defer { isCloning = false }
        error = nil

        do {
            try await GitClient.clone(url: trimmedURL, into: target)
            await store.addRepository(at: target)
            isPresented = false
        } catch {
            self.error = GitErrorClassifier.classify(error, operation: .clone)
        }
    }
}
