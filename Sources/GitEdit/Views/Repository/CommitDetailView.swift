import SwiftUI

struct CommitDetailView: View {
    let commit: Commit

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.lg) {
                Text(commit.summary)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)

                HStack(spacing: DT.Space.lg) {
                    Label {
                        Text(commit.author)
                    } icon: {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(.tint)
                    }
                    Label {
                        Text(Self.absoluteFormatter.string(from: commit.date))
                    } icon: {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.tint)
                    }
                    Label {
                        Text(commit.shortSHA)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    } icon: {
                        Image(systemName: "number")
                            .foregroundStyle(.tint)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Divider()

                if !commit.body.isEmpty {
                    Text(commit.body)
                        .font(.body)
                        .textSelection(.enabled)
                }

                HStack(spacing: DT.Space.sm) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.tertiary)
                    Text("変更ファイルの差分は Phase 3 で対応予定")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, DT.Space.md)
            }
            .padding(DT.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
