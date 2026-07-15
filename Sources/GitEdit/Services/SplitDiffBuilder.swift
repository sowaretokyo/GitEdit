import Foundation

enum SplitLineKind: Equatable {
    case context, added, removed
}

struct SplitCell: Equatable {
    let number: Int
    let text: String
    let kind: SplitLineKind
}

enum SplitRow: Equatable {
    case fileHeader(String)
    case hunkHeader(String)
    case pair(left: SplitCell?, right: SplitCell?)
}

/// Converts the flat unified-diff line sequence produced by `DiffParser` into
/// side-by-side rows for split-view rendering.
///
/// Consecutive `removed` lines are buffered on the left, consecutive `added`
/// lines on the right. A `context` line, a header, or the end of input flushes
/// the buffers: they're zipped positionally (removed[i] across from added[i]),
/// and whichever side is shorter pairs with `nil` for the remaining rows. This
/// keeps replaced blocks aligned without trying to diff word-by-word.
enum SplitDiffBuilder {
    static func rows(from lines: [DiffLine]) -> [SplitRow] {
        var result: [SplitRow] = []
        var removedBuffer: [SplitCell] = []
        var addedBuffer: [SplitCell] = []

        func flushPairs() {
            guard !removedBuffer.isEmpty || !addedBuffer.isEmpty else { return }
            let count = max(removedBuffer.count, addedBuffer.count)
            for i in 0..<count {
                result.append(.pair(
                    left: i < removedBuffer.count ? removedBuffer[i] : nil,
                    right: i < addedBuffer.count ? addedBuffer[i] : nil
                ))
            }
            removedBuffer.removeAll()
            addedBuffer.removeAll()
        }

        for line in lines {
            switch line {
            case .fileHeader(let s):
                flushPairs()
                result.append(.fileHeader(s))
            case .hunkHeader(let s):
                flushPairs()
                result.append(.hunkHeader(s))
            case .removed(let content, let oldLine):
                removedBuffer.append(SplitCell(number: oldLine, text: content, kind: .removed))
            case .added(let content, let newLine):
                addedBuffer.append(SplitCell(number: newLine, text: content, kind: .added))
            case .context(let content, let oldLine, let newLine):
                flushPairs()
                result.append(.pair(
                    left: SplitCell(number: oldLine, text: content, kind: .context),
                    right: SplitCell(number: newLine, text: content, kind: .context)
                ))
            }
        }
        flushPairs()

        return result
    }
}
