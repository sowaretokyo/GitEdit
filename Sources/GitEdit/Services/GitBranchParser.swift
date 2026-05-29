import Foundation

enum GitBranchParser {
    /// Field separator (Start-of-Heading)
    static let fieldSep = "\u{01}"
    /// Record separator (Start-of-Text)
    static let recordSep = "\u{02}"

    /// The git for-each-ref `--format=...` template producing structured output.
    /// Field order:
    ///   0: refname:short
    ///   1: HEAD ("*" if current, " " otherwise)
    ///   2: upstream:short
    ///   3: upstream:track ("[ahead N, behind M]" / "[gone]" / "")
    ///   4: objectname:short
    ///   5: committerdate:iso-strict
    ///   6: authorname
    ///   7: subject
    static let formatTemplate: String = {
        let f = fieldSep
        return [
            "%(refname:short)", "%(HEAD)", "%(upstream:short)", "%(upstream:track)",
            "%(objectname:short)", "%(committerdate:iso-strict)",
            "%(authorname)", "%(subject)"
        ].joined(separator: f) + recordSep
    }()

    static func parse(_ output: String, kind: Branch.Kind) -> [Branch] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var branches: [Branch] = []
        for record in output.split(separator: Character(recordSep), omittingEmptySubsequences: true) {
            let fields = record
                .split(separator: Character(fieldSep), omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count >= 8 else { continue }

            let refShort = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !refShort.isEmpty else { continue }
            // Skip remote HEAD pointers like "origin/HEAD"
            if refShort.hasSuffix("/HEAD") { continue }

            let isCurrent = fields[1].trimmingCharacters(in: .whitespacesAndNewlines) == "*"
            let upstreamRaw = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let upstream: String? = upstreamRaw.isEmpty ? nil : upstreamRaw
            let track = fields[3]
            let upstreamGone = track.contains("gone")
            let (ahead, behind) = parseAheadBehind(track)

            let date = formatter.date(from: fields[5].trimmingCharacters(in: .whitespacesAndNewlines))

            branches.append(Branch(
                name: refShort,
                kind: kind,
                isCurrent: isCurrent,
                upstream: upstream,
                upstreamGone: upstreamGone,
                ahead: ahead,
                behind: behind,
                sha: fields[4],
                subject: fields[7],
                authorName: fields[6],
                lastCommitDate: date
            ))
        }
        return branches
    }

    static func parseAheadBehind(_ track: String) -> (Int, Int) {
        var ahead = 0
        var behind = 0
        if let r = track.range(of: #"ahead (\d+)"#, options: .regularExpression) {
            let captured = track[r].replacingOccurrences(of: "ahead ", with: "")
            ahead = Int(captured) ?? 0
        }
        if let r = track.range(of: #"behind (\d+)"#, options: .regularExpression) {
            let captured = track[r].replacingOccurrences(of: "behind ", with: "")
            behind = Int(captured) ?? 0
        }
        return (ahead, behind)
    }
}
