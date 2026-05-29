import SwiftUI
import AppKit

@MainActor
final class RepositoryStore: ObservableObject {
    @Published var repositories: [Repository] = []
    @Published var selectedID: Repository.ID?

    var selectedRepository: Repository? {
        guard let id = selectedID else { return nil }
        return repositories.first { $0.id == id }
    }

    func promptAddRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        panel.message = "Git リポジトリのフォルダを選択してください"
        panel.title = "リポジトリを追加"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await addRepository(at: url) }
    }

    func addRepository(at url: URL) async {
        let client = GitClient(repository: url)
        guard await client.isInsideRepository() else {
            showAlert(
                title: "Git リポジトリではありません",
                message: "\(url.lastPathComponent) は Git で管理されていません。\nまず `git init` するか、別のフォルダを選んでください。"
            )
            return
        }

        let branch = try? await client.currentBranch()

        if let existing = repositories.first(where: { $0.url == url }) {
            selectedID = existing.id
            return
        }

        let repo = Repository(url: url, currentBranch: branch)
        repositories.append(repo)
        selectedID = repo.id
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
