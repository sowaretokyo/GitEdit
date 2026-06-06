import Foundation
import SwiftUI

@MainActor
final class FilePickerViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [Match] = []
    @Published var selectedIndex: Int = 0
    @Published var isLoading: Bool = false

    private var allPaths: [String] = []
    private let index: RepositoryFileIndex

    init(repository: URL) {
        self.index = RepositoryFileIndex(repository: repository)
    }

    struct Match: Identifiable, Hashable {
        let id: String   // path
        let path: String
        let score: Int
        let matchedRanges: [Range<String.Index>]
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            allPaths = try await index.allPaths()
            recompute()
        } catch {
            allPaths = []
            results = []
        }
    }

    // MARK: - Search

    func recompute() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = allPaths.prefix(200).map {
                Match(id: $0, path: $0, score: 0, matchedRanges: [])
            }
            clampSelection()
            return
        }
        let scored = allPaths.compactMap { path -> Match? in
            guard let scored = FuzzyMatcher.score(path: path, query: trimmed) else { return nil }
            return Match(id: path, path: path, score: scored.score, matchedRanges: scored.ranges)
        }
        results = scored
            .sorted { $0.score > $1.score }
            .prefix(200)
            .map { $0 }
        clampSelection()
    }

    // MARK: - Selection

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let count = results.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    func selectedMatch() -> Match? {
        guard !results.isEmpty, selectedIndex < results.count else { return nil }
        return results[selectedIndex]
    }

    private func clampSelection() {
        if results.isEmpty {
            selectedIndex = 0
        } else if selectedIndex >= results.count {
            selectedIndex = results.count - 1
        }
    }
}

// MARK: - Fuzzy matcher (Sublime-style, lightweight)

enum FuzzyMatcher {
    struct Result {
        let score: Int
        let ranges: [Range<String.Index>]
    }

    /// Returns nil if not all query characters appear in path in order.
    /// Scoring rewards:
    ///   - consecutive matches
    ///   - matches right after a path separator / camelCase boundary
    ///   - matches near the end of the path (filename region)
    static func score(path: String, query: String) -> Result? {
        let queryLower = query.lowercased()
        let pathLower = path.lowercased()
        let qChars = Array(queryLower)
        let pChars = Array(pathLower)

        var qi = 0
        var pi = 0
        var score = 0
        var consecutive = 0
        var ranges: [Range<String.Index>] = []
        var currentStart: Int? = nil

        while qi < qChars.count && pi < pChars.count {
            if qChars[qi] == pChars[pi] {
                score += 1
                consecutive += 1
                score += consecutive * 2  // bonus for runs

                // Bonus for word boundary
                if pi == 0 {
                    score += 5
                } else {
                    let prev = pChars[pi - 1]
                    if prev == "/" || prev == "_" || prev == "-" || prev == "." || prev == " " {
                        score += 5
                    }
                }

                if currentStart == nil { currentStart = pi }
                qi += 1
                pi += 1
            } else {
                if let s = currentStart {
                    let lo = path.index(path.startIndex, offsetBy: s)
                    let hi = path.index(path.startIndex, offsetBy: pi)
                    ranges.append(lo..<hi)
                    currentStart = nil
                }
                consecutive = 0
                pi += 1
            }
        }

        if let s = currentStart {
            let lo = path.index(path.startIndex, offsetBy: s)
            let hi = path.index(path.startIndex, offsetBy: pi)
            ranges.append(lo..<hi)
        }

        // Need to have matched every query character
        guard qi == qChars.count else { return nil }

        // Slight penalty for very long unmatched paths
        score -= max(0, pChars.count - qChars.count) / 8

        return Result(score: score, ranges: ranges)
    }
}
