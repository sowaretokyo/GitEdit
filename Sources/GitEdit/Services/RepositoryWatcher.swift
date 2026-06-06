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

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepositoryWatcher>.fromOpaque(info).takeUnretainedValue()
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
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
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
