import SwiftUI
import AppKit

@MainActor
final class RepositoryStore: ObservableObject {
    @Published var repositories: [Repository] = [] {
        didSet { save() }
    }
    @Published var selectedID: Repository.ID? {
        didSet { saveSelection() }
    }

    private static let repositoriesKey = "repositories"
    private static let selectionKey = "selectedRepositoryID"

    /// Lightweight, on-disk representation. We persist only the identity and
    /// path — `currentBranch` is derived state and is re-fetched on launch so
    /// the UI never shows a stale branch.
    private struct PersistedRepository: Codable {
        let id: UUID
        let path: String
    }

    private var hasLoaded = false

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

    func removeRepository(_ id: Repository.ID) {
        repositories.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = repositories.first?.id
        }
    }

    // MARK: - Persistence

    /// Restore the saved repository list. Repositories whose folder no longer
    /// exists (deleted or moved) are silently dropped. Runs once per launch.
    func loadPersisted() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        guard let data = UserDefaults.standard.data(forKey: Self.repositoriesKey),
              let items = try? JSONDecoder().decode([PersistedRepository].self, from: data)
        else { return }

        var restored: [Repository] = []
        for item in items {
            let url = URL(fileURLWithPath: item.path)
            let client = GitClient(repository: url)
            guard await client.isInsideRepository() else { continue }
            let branch = try? await client.currentBranch()
            restored.append(Repository(id: item.id, url: url, currentBranch: branch))
        }

        isRestoring = true
        repositories = restored
        let savedSelection = UserDefaults.standard.string(forKey: Self.selectionKey)
            .flatMap(UUID.init(uuidString:))
        selectedID = restored.contains { $0.id == savedSelection } ? savedSelection : restored.first?.id
        isRestoring = false
    }

    private var isRestoring = false

    private func save() {
        guard !isRestoring else { return }
        let items = repositories.map { PersistedRepository(id: $0.id, path: $0.url.path) }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.repositoriesKey)
        }
    }

    private func saveSelection() {
        guard !isRestoring else { return }
        if let id = selectedID {
            UserDefaults.standard.set(id.uuidString, forKey: Self.selectionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectionKey)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
