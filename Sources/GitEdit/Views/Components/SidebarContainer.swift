import SwiftUI

/// Shared header/content shell for primary sidebars.
struct SidebarContainer<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content

    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }
}
