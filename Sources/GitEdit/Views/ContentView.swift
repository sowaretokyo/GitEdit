import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: RepositoryStore

    var body: some View {
        NavigationSplitView {
            RepositorySidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
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
