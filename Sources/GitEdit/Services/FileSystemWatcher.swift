import Foundation
import CoreServices

/// Thin Swift wrapper over FSEventStream that watches one or more directories
/// recursively and fires a callback whenever any descendant changes.
/// Used by `RepositoryViewModel` to keep status / branch info in sync with
/// the working tree and `.git` state.
final class FileSystemWatcher: @unchecked Sendable {
    typealias Callback = (Set<String>) -> Void

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "co.sowaretokyo.GitEdit.fswatcher", qos: .utility)
    private let callback: Callback

    init(paths: [String], latency: TimeInterval = 0.25, callback: @escaping Callback) {
        self.callback = callback
        start(paths: paths, latency: latency)
    }

    deinit { stop() }

    private func start(paths: [String], latency: TimeInterval) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let cb: FSEventStreamCallback = { _, contextInfo, numEvents, eventPaths, _, _ in
            guard let info = contextInfo else { return }
            let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue()

            // With `kFSEventStreamCreateFlagUseCFTypes`, eventPaths is a
            // CFArrayRef of CFStringRefs. Without it, it's a `const char **`
            // and casting to NSArray crashes — see rdar://... .
            let cfArray = unsafeBitCast(eventPaths, to: CFArray.self)
            let nsArray = cfArray as NSArray
            var paths: Set<String> = []
            paths.reserveCapacity(numEvents)
            for case let path as String in nsArray {
                paths.insert(path)
            }
            watcher.callback(paths)
        }

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagUseCFTypes
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            cb,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(flags)
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }
}
