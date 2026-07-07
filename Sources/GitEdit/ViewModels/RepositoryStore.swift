import SwiftUI
import AppKit

@MainActor
final class RepositoryStore: ObservableObject {
    @Published var repositories: [Repository] = [] {
        didSet { save() }
    }
    @Published var groups: [RepositoryGroup] = [] {
        didSet { save() }
    }
    @Published var selectedID: Repository.ID? {
        didSet { saveSelection() }
    }

    private static let repositoriesKey = "repositories"
    private static let groupsKey = "repositoryGroups"
    private static let selectionKey = "selectedRepositoryID"

    private var hasLoaded = false

    var selectedRepository: Repository? {
        guard let id = selectedID else { return nil }
        return repositories.first { $0.id == id }
    }

    /// Whether the persisted repository list has finished loading. Standalone
    /// repository windows use this to distinguish "still loading at launch"
    /// from "this repository no longer exists".
    var isLoaded: Bool { hasLoaded }

    func repository(withID id: Repository.ID) -> Repository? {
        repositories.first { $0.id == id }
    }

    /// Whether the sidebar has anything to organize. When false, the sidebar
    /// stays the flat single-section list it has always been.
    var hasOrganization: Bool {
        !groups.isEmpty || repositories.contains { $0.isPinned }
    }

    /// Pinned repositories always surface here regardless of group
    /// membership — pinning takes priority over grouping for display.
    var pinnedRepositories: [Repository] {
        repositories.filter(\.isPinned)
    }

    func repositories(inGroup group: RepositoryGroup) -> [Repository] {
        repositories.filter { $0.groupID == group.id && !$0.isPinned }
    }

    /// Repositories with no group and not pinned.
    var ungroupedRepositories: [Repository] {
        repositories.filter { $0.groupID == nil && !$0.isPinned }
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

    // MARK: - Organization

    func togglePin(_ id: Repository.ID) {
        guard let index = repositories.firstIndex(where: { $0.id == id }) else { return }
        repositories[index].isPinned.toggle()
    }

    func setGroup(_ groupID: RepositoryGroup.ID?, for id: Repository.ID) {
        guard let index = repositories.firstIndex(where: { $0.id == id }) else { return }
        repositories[index].groupID = groupID
    }

    @discardableResult
    func createGroup(name: String, assign repositoryID: Repository.ID? = nil) -> RepositoryGroup {
        let group = RepositoryGroup(name: name)
        groups.append(group)
        if let repositoryID {
            setGroup(group.id, for: repositoryID)
        }
        return group
    }

    func renameGroup(_ id: RepositoryGroup.ID, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
    }

    /// Removes the group. Member repositories are kept and simply
    /// unassigned — grouping is organizational, never destructive.
    func deleteGroup(_ id: RepositoryGroup.ID) {
        groups.removeAll { $0.id == id }
        for index in repositories.indices where repositories[index].groupID == id {
            repositories[index].groupID = nil
        }
    }

    func setGroupCollapsed(_ id: RepositoryGroup.ID, isCollapsed: Bool) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].isCollapsed = isCollapsed
    }

    // MARK: - Persistence

    /// Restore the saved repository list. Repositories whose folder no longer
    /// exists (deleted or moved) are silently dropped. Runs once per launch.
    func loadPersisted() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        let storedGroups = RepositoryPersistence.decodeGroups(
            UserDefaults.standard.data(forKey: Self.groupsKey)
        )
        let storedRepositories = RepositoryPersistence.sanitize(
            repositories: RepositoryPersistence.decodeRepositories(
                UserDefaults.standard.data(forKey: Self.repositoriesKey)
            ),
            groups: storedGroups
        )

        var restored: [Repository] = []
        for item in storedRepositories {
            let url = URL(fileURLWithPath: item.path)
            let client = GitClient(repository: url)
            guard await client.isInsideRepository() else { continue }
            let branch = try? await client.currentBranch()
            restored.append(Repository(
                id: item.id,
                url: url,
                currentBranch: branch,
                isPinned: item.pinned ?? false,
                groupID: item.groupID
            ))
        }

        isRestoring = true
        groups = storedGroups.map {
            RepositoryGroup(id: $0.id, name: $0.name, isCollapsed: $0.collapsed ?? false)
        }
        repositories = restored
        let savedSelection = UserDefaults.standard.string(forKey: Self.selectionKey)
            .flatMap(UUID.init(uuidString:))
        selectedID = restored.contains { $0.id == savedSelection } ? savedSelection : restored.first?.id
        isRestoring = false
    }

    private var isRestoring = false

    private func save() {
        guard !isRestoring else { return }

        let storedRepositories = repositories.map {
            RepositoryPersistence.StoredRepository(
                id: $0.id,
                path: $0.url.path,
                pinned: $0.isPinned,
                groupID: $0.groupID
            )
        }
        if let data = RepositoryPersistence.encodeRepositories(storedRepositories) {
            UserDefaults.standard.set(data, forKey: Self.repositoriesKey)
        }

        let storedGroups = groups.map {
            RepositoryPersistence.StoredGroup(id: $0.id, name: $0.name, collapsed: $0.isCollapsed)
        }
        if let data = RepositoryPersistence.encodeGroups(storedGroups) {
            UserDefaults.standard.set(data, forKey: Self.groupsKey)
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
