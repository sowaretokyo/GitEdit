import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: RepositoryStore

    var body: some View {
        NavigationSplitView {
            RepositorySidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            if let repo = store.selectedRepository {
                RepositoryDetailView(repository: repo)
                    .id(repo.id)
            } else {
                WelcomeView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
