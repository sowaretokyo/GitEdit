import SwiftUI

struct SidebarTabBar: View {
    @Binding var selection: RepositoryView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RepositoryView.Tab.allCases) { tab in
                tabButton(tab)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func tabButton(_ tab: RepositoryView.Tab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            Text(tab.title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isSelected ? Color.accentColor : Color.clear)
                        .frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}
