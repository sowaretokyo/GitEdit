import Foundation

/// Before/after raw bytes for an image file's diff. Either side may be `nil`
/// (added/deleted image), but never both — that case isn't constructed.
struct ImageDiffContent: Equatable {
    let before: Data?
    let after: Data?

    var hasAny: Bool { before != nil || after != nil }
}

/// Detects whether a path is a common raster image format, so the diff view
/// can render a before/after image comparison instead of a text patch.
enum ImageDiff {
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "bmp", "tiff", "tif"
    ]

    static func isImagePath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }
}
