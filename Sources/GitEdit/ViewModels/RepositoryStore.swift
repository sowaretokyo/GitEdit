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
        panel.prompt = L("選択")
        panel.message = L("ローカルの Git リポジトリを選択してください")
        panel.title = L("リポジトリを追加")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await addRepository(at: url) }
    }

    func addRepository(at url: URL) async {
        let client = GitClient(repository: url)
        guard await client.isInsideRepository() else {
            showAlert(
                title: L("Git リポジトリではありません"),
                message: L("%@ は Git リポジトリではありません", url.lastPathComponent)
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
