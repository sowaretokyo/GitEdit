import SwiftUI

/// Root content of the standalone "repository" `WindowGroup` scene — a
/// sidebar-less window pinned to a single repository, opened via "Open in
/// New Window" from the sidebar or the File menu.
///
/// The repository ID is resolved against the shared `RepositoryStore` at
/// render time rather than captured as a `Repository` value, so the window
/// keeps tracking the same repository across store updates (e.g. branch
/// refresh) and can detect removal.
struct RepositoryWindowContent: View {
    let repositoryID: Repository.ID?
    @EnvironmentObject var store: RepositoryStore

    var body: some View {
        Group {
            if let repo = repositoryID.flatMap(store.repository(withID:)) {
                RepositoryView(repository: repo, showsRepositoryPicker: false)
                    .id(repo.id)
                    .navigationTitle(repo.name)
            } else if !store.isLoaded {
                // Restoration can race the store's own persisted-state load;
                // show a spinner instead of jumping straight to "not found".
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                UnavailableRepositoryView()
            }
        }
        // Idempotent: safe to call from every window this scene opens.
        .task { await store.loadPersisted() }
    }
}
