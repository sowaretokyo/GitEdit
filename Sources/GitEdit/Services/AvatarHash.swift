import Foundation
import SwiftUI

/// Deterministic display fallback for author avatars when no remote image
/// (Gravatar / GitHub) is available — generates initials and a stable hue
/// from the author's name or email.
enum AvatarHash {
    /// Up to 2 uppercase initials for the given display name. Falls back to
    /// the first character when the name has no whitespace. Returns an
    /// empty string for an empty input.
    static func initials(for name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace })
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        if let first = parts.first {
            return String(first.prefix(1)).uppercased()
        }
        return ""
    }

    /// Deterministic hue in 0..1 derived from `seed`. Stable across runs as
    /// long as `String.hashValue` is — for avatar fallbacks that's fine
    /// (mismatched colors across launches are not a correctness issue).
    static func hue(for seed: String) -> Double {
        let h = abs(seed.hashValue)
        return Double(h % 360) / 360.0
    }

    /// Convenience: avatar tint color at the standard saturation/brightness.
    static func tintColor(for seed: String) -> Color {
        Color(hue: hue(for: seed), saturation: 0.55, brightness: 0.7)
    }
}
