import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: RepositoryStore

    var body: some View {
        if let repo = store.selectedRepository {
            RepositoryView(repository: repo)
                .id(repo.id)
        } else {
            WelcomeView()
        }
    }
}
