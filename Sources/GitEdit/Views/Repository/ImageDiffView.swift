import SwiftUI

/// Side-by-side before/after comparison for image files, shown instead of a
/// text patch since a binary diff of image bytes isn't useful to look at.
struct ImageDiffView: View {
    let content: ImageDiffContent

    private static let maxImageDimension: CGFloat = 480

    var body: some View {
        HStack(spacing: 0) {
            pane(title: L("変更前"), data: content.before, missingLabel: L("新規追加された画像"))
            Divider()
            pane(title: L("変更後"), data: content.after, missingLabel: L("削除された画像"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func pane(title: String, data: Data?, missingLabel: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DT.Space.md)
                .padding(.vertical, DT.Space.sm)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            paneContent(data: data, missingLabel: missingLabel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func paneContent(data: Data?, missingLabel: String) -> some View {
        if let data {
            if let image = NSImage(data: data) {
                imageContent(image: image)
            } else {
                EmptyStateView(icon: "exclamationmark.triangle", title: L("画像を表示できません"))
            }
        } else {
            EmptyStateView(icon: "photo", title: missingLabel)
        }
    }

    private func imageContent(image: NSImage) -> some View {
        VStack(spacing: DT.Space.sm) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: Self.maxImageDimension, maxHeight: Self.maxImageDimension)
            }
            Text(L("%d × %d ピクセル", Int(image.size.width), Int(image.size.height)))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(DT.Space.md)
    }
}
