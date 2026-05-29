import Foundation

/// Module-aware localized string lookup.
///
/// Strategy: the key IS the Japanese source text. When no translation is found
/// in the user's locale, we fall back to the key itself, so Japanese readers
/// always see Japanese without needing a full ja.lproj.
///
/// English (and future locales) live in their respective `.lproj` directories
/// under `Sources/GitEdit/Resources/`.
@inline(__always)
func L(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .module, value: key, comment: "")
}

/// Localized string with `printf`-style formatting.
/// Example: `L("%d / %d", staged, total)`
@inline(__always)
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, tableName: nil, bundle: .module, value: key, comment: "")
    if args.isEmpty { return format }
    return String(format: format, locale: Locale.current, arguments: args)
}
