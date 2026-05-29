import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var store: RepositoryStore
    @State private var isShowingCloneSheet = false
    @State private var isShowingInitSheet = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.06),
                    Color.clear,
                    Color.accentColor.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: DT.Space.xl) {
                Spacer()

                VStack(spacing: DT.Space.lg) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 72, weight: .ultraLight))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .accentColor.opacity(0.25), radius: 20, y: 6)

                    VStack(spacing: DT.Space.xs) {
                        Text(verbatim: "GitEdit")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(L("Git をもっとシンプルに、もっと安心に。"))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: DT.Space.sm) {
                    ActionCard(
                        icon: "folder.badge.plus",
                        tint: .blue,
                        title: L("ローカルのリポジトリを追加"),
                        subtitle: L("Mac 内の既存リポジトリを取り込む"),
                        shortcut: "⌘ O"
                    ) {
                        store.promptAddRepository()
                    }

                    ActionCard(
                        icon: "square.and.arrow.down",
                        tint: .green,
                        title: L("クローン"),
                        subtitle: L("URL を指定してリポジトリを複製"),
                        shortcut: "⇧ ⌘ O"
                    ) {
                        isShowingCloneSheet = true
                    }

                    ActionCard(
                        icon: "plus.square.on.square",
                        tint: .orange,
                        title: L("新しいリポジトリを作成"),
                        subtitle: L("空のフォルダで git init"),
                        shortcut: "⌘ N"
                    ) {
                        isShowingInitSheet = true
                    }
                }
                .frame(maxWidth: 440)

                Spacer()

                Text(L("Made with ☕️ in Tokyo"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(DT.Space.xxl)
        }
        .sheet(isPresented: $isShowingCloneSheet) {
            CloneSheet(isPresented: $isShowingCloneSheet)
                .environmentObject(store)
        }
        .sheet(isPresented: $isShowingInitSheet) {
            InitSheet(isPresented: $isShowingInitSheet)
                .environmentObject(store)
        }
    }
}

private struct ActionCard: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let shortcut: String
    var comingSoon: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DT.Space.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DT.Space.xs) {
                        Text(title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        if comingSoon {
                            Text(L("近日"))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: DT.Space.md)

                Text(shortcut)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, DT.Space.sm)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.quaternary.opacity(0.5))
                    )
            }
            .padding(.horizontal, DT.Space.lg)
            .padding(.vertical, DT.Space.md)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous)
                    .fill(.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous)
                            .fill(tint.opacity(isHovering ? 0.06 : 0))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous)
                            .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(isHovering ? 0.06 : 0.02), radius: isHovering ? 12 : 4, y: isHovering ? 4 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(comingSoon)
        .opacity(comingSoon ? 0.7 : 1)
        .onHover { isHovering = $0 && !comingSoon }
        .animation(.easeOut(duration: 0.18), value: isHovering)
    }
}
