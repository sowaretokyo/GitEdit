import Foundation

/// Watches a repository directory tree (working tree + `.git`) via FSEvents and
/// invokes a debounced callback whenever anything changes on disk, so the UI can
/// refresh itself without the user pressing a refresh button.
///
/// Both the app's own git operations and external changes (e.g. running git in a
/// terminal) land here.
final class RepositoryWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private let debounce: TimeInterval

    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?

    init(url: URL, debounce: TimeInterval = 0.3, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepositoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            // Ignore git's own noisy `.git` housekeeping; reacting to it loops forever.
            guard paths.contains(where: { RepositoryWatcher.isInteresting($0) }) else { return }
            watcher.scheduleFire()
        }

        // 0.5s latency lets FSEvents coalesce the burst of file events a single
        // git operation (checkout, pull, …) produces into one callback.
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagUseCFTypes  // eventPaths as CFArray<CFString>
            )
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    func stop() {
        pending?.cancel()
        pending = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Decide whether a changed path warrants a UI refresh.
    ///
    /// `.git` is full of churn we must not react to — objects, logs, lock files,
    /// FETCH_HEAD, COMMIT_EDITMSG — so inside `.git` we react only to the few
    /// entries that reflect state the UI shows: HEAD / refs (branch & checkout
    /// changes) and `index` (staging done from an external terminal).
    /// Working-tree changes (anything outside `.git`) always pass.
    ///
    /// Note: this filter is defence-in-depth, not the primary loop guard. The
    /// actual fix for the old "status → index rewrite → FSEvent → status …"
    /// loop is `GIT_OPTIONAL_LOCKS=0` in GitClient, which stops our own read
    /// commands from rewriting the index in the first place. With that in place
    /// it's safe to watch `index` here for genuine external staging.
    nonisolated static func isInteresting(_ path: String) -> Bool {
        guard let range = path.range(of: "/.git/") else {
            return true  // outside .git → a working-tree change
        }
        let entry = path[range.upperBound...]
        return entry == "HEAD"
            || entry == "index"
            || entry == "packed-refs"
            || entry == "MERGE_HEAD"
            || entry == "ORIG_HEAD"
            || entry.hasPrefix("refs/")
    }

    /// Coalesce rapid bursts of FSEvents callbacks into a single UI refresh.
    private func scheduleFire() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.onChange() }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            self.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + self.debounce, execute: work)
        }
    }

    deinit { stop() }
}
