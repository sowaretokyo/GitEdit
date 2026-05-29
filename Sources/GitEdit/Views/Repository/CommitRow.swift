import SwiftUI

struct CommitRow: View {
    let commit: Commit

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale.current
        f.unitsStyle = .abbreviated
        return f
    }()

    private var initials: String {
        let parts = commit.author.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(commit.author.prefix(1)).uppercased()
    }

    private var avatarHue: Double {
        let hash = abs(commit.authorEmail.hashValue)
        return Double(hash % 360) / 360.0
    }

    private var avatarURL: URL? {
        GitHubAvatar.url(for: commit.authorEmail, size: 80)
    }

    private var tintColor: Color {
        Color(hue: avatarHue, saturation: 0.55, brightness: 0.7)
    }

    var body: some View {
        HStack(spacing: DT.Space.md) {
            AvatarImageView(
                url: avatarURL,
                initials: initials,
                tintColor: tintColor,
                size: 30
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(commit.author)
                        .lineLimit(1)
                    Text("•").foregroundStyle(.tertiary)
                    Text(Self.relativeFormatter.localizedString(for: commit.date, relativeTo: Date()))
                    Text("•").foregroundStyle(.tertiary)
                    Text(commit.shortSHA)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}
