import SwiftUI
import AppKit

/// A circular avatar that asynchronously loads from `url`,
/// falling back to a tinted initials circle while loading or on failure.
struct AvatarImageView: View {
    let url: URL?
    let initials: String
    let tintColor: Color
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else {
                Circle()
                    .fill(tintColor.opacity(0.20))
                    .frame(width: size, height: size)
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(tintColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            let loaded = await AvatarImageStore.shared.image(for: url)
            // Avoid a flicker if the view was reassigned to a different url.
            if !Task.isCancelled {
                image = loaded
            }
        }
        .animation(.easeOut(duration: 0.22), value: image)
    }
}
