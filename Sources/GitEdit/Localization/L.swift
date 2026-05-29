import Foundation

/// Module-aware localized string lookup with user override.
///
/// - If the user has explicitly chosen a language in Settings, look it up in
///   that locale's `.lproj` directly so the choice doesn't require app restart.
/// - Otherwise, fall back to `Bundle.module`'s standard lookup (system locale).
/// - In all cases, when no translation is found, return the key itself
///   (which is the Japanese source string).
@inline(__always)
func L(_ key: String) -> String {
    if let code = AppLanguage.current.bundleLanguageCode,
       let lprojPath = Bundle.module.path(forResource: code, ofType: "lproj"),
       let lprojBundle = Bundle(path: lprojPath) {
        return NSLocalizedString(key, tableName: nil, bundle: lprojBundle, value: key, comment: "")
    }
    return NSLocalizedString(key, tableName: nil, bundle: .module, value: key, comment: "")
}

/// `printf`-style formatted localized string.
@inline(__always)
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = L(key)
    if args.isEmpty { return format }
    return String(format: format, locale: Locale.current, arguments: args)
}
