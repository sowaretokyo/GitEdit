import SwiftUI

struct CommitRow: View {
    let commit: Commit

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale.current
        f.unitsStyle = .abbreviated
        return f
    }()

    private var avatarURL: URL? {
        GitHubAvatar.url(for: commit.authorEmail, size: 80)
    }

    var body: some View {
        HStack(spacing: DT.Space.md) {
            AvatarImageView(
                url: avatarURL,
                initials: AvatarHash.initials(for: commit.author),
                tintColor: AvatarHash.tintColor(for: commit.authorEmail),
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
        .padding(.vertical, DT.RowDensity.tight)
    }
}
