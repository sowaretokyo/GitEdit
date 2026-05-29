import SwiftUI

struct CommitRow: View {
    let commit: Commit

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ja_JP")
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
        // Deterministic tint per author
        let hash = abs(commit.authorEmail.hashValue)
        return Double(hash % 360) / 360.0
    }

    var body: some View {
        HStack(spacing: DT.Space.md) {
            ZStack {
                Circle()
                    .fill(Color(hue: avatarHue, saturation: 0.45, brightness: 0.92).opacity(0.35))
                    .frame(width: 30, height: 30)
                Text(initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hue: avatarHue, saturation: 0.7, brightness: 0.55))
            }

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
