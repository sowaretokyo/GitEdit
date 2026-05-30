import SwiftUI

struct CommitRow: View {
    let commit: Commit

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale.current
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(spacing: DT.Space.md) {
            AvatarStack(authors: commit.allAuthors, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(commit.allAuthorDisplayNames)
                        .lineLimit(1)
                        .truncationMode(.tail)
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
