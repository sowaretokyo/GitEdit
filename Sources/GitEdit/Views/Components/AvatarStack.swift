import SwiftUI

/// Up to `maxCount` circular avatars overlaid into a single horizontal
/// cluster. The primary author sits at the leading edge in front; each
/// subsequent author shifts to the trailing side and slides behind the
/// previous one, GitHub Desktop / GitHub.com style.
struct AvatarStack: View {
    let authors: [CommitAuthor]
    var size: CGFloat = 30
    /// Pixels each subsequent avatar shifts to the trailing side.
    var overlap: CGFloat = 14
    var maxCount: Int = 3

    private var visible: [CommitAuthor] {
        Array(authors.prefix(maxCount))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Render trailing avatars first so the primary author ends up
            // on top. `zIndex` makes the ordering explicit regardless of
            // future ZStack changes.
            ForEach(Array(visible.enumerated()).reversed(), id: \.offset) { idx, author in
                AvatarImageView(
                    url: GitHubAvatar.url(for: author.email, size: Int(size * 2.5)),
                    initials: AvatarHash.initials(for: author.name),
                    tintColor: AvatarHash.tintColor(for: author.email),
                    size: size
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            Color(nsColor: .controlBackgroundColor),
                            lineWidth: idx == 0 ? 0 : 1.5
                        )
                )
                .offset(x: CGFloat(idx) * overlap)
                .zIndex(Double(visible.count - idx))
            }
        }
        .frame(
            width: size + CGFloat(max(0, visible.count - 1)) * overlap,
            height: size,
            alignment: .leading
        )
    }
}
