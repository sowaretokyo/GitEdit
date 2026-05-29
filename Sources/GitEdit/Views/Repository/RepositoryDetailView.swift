import SwiftUI

struct RepositoryDetailView: View {
    let repository: Repository
    @State private var selectedTab: Tab = .changes

    enum Tab: String, CaseIterable, Identifiable {
        case changes = "変更"
        case history = "履歴"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .changes: return "pencil.and.list.clipboard"
            case .history: return "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            switch selectedTab {
            case .changes:
                ChangesView(repository: repository)
            case .history:
                HistoryView(repository: repository)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: DT.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.tint.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: "folder.fill")
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(repository.name)
                    .font(.title3.weight(.semibold))
                if let branch = repository.currentBranch {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .imageScale(.small)
                        Text(branch)
                            .font(.caption.monospaced())
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .labelsHidden()
        }
        .padding(.horizontal, DT.Space.lg)
        .padding(.vertical, DT.Space.md)
    }
}
