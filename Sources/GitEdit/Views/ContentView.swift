import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: RepositoryStore

    var body: some View {
        NavigationSplitView {
            RepositorySidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            if let repo = store.selectedRepository {
                RepositoryView(repository: repo)
                    .id(repo.id)
            } else {
                WelcomeView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
