import Foundation

enum StashListParser {
    /// Field separator (Unit Separator). `%s` is placed last so an embedded
    /// separator in a stash message can't shift the fields after it.
    static let fieldSep = "\u{1F}"

    /// The `git stash list --format=...` template. One record per line —
    /// `git stash list` never embeds raw newlines inside a single entry.
    static let formatTemplate = "%gd\(fieldSep)%H\(fieldSep)%cr\(fieldSep)%s"

    static func parse(_ output: String) -> [StashEntry] {
        var entries: [StashEntry] = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            // maxSplits: 3 keeps anything past the 3rd separator (the message)
            // intact even if it happens to contain the separator character.
            let fields = rawLine
                .split(separator: Character(fieldSep), maxSplits: 3, omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count == 4 else { continue }

            let selector = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let sha = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let relativeDate = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let message = fields[3]

            guard !selector.isEmpty, !sha.isEmpty, let index = parseIndex(selector) else { continue }

            entries.append(StashEntry(
                selector: selector,
                index: index,
                message: message,
                relativeDate: relativeDate,
                sha: sha
            ))
        }
        return entries
    }

    /// Extracts `N` from a `stash@{N}` selector.
    static func parseIndex(_ selector: String) -> Int? {
        guard let open = selector.firstIndex(of: "{"),
              let close = selector.firstIndex(of: "}"),
              open < close else { return nil }
        return Int(selector[selector.index(after: open)..<close])
    }
}
