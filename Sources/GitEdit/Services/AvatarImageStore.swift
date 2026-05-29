import Foundation
import AppKit

/// Process-wide cache for avatar images. Combines an in-memory NSCache
/// with URLSession's URLCache for on-disk caching.
@MainActor
final class AvatarImageStore: ObservableObject {
    static let shared = AvatarImageStore()

    private let cache = NSCache<NSURL, NSImage>()
    private var loadingTasks: [URL: Task<NSImage?, Never>] = [:]
    private let urlSession: URLSession

    private init() {
        cache.countLimit = 500

        let memoryCapacity = 16 * 1024 * 1024
        let diskCapacity = 64 * 1024 * 1024
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let diskURL = cachesDir?.appendingPathComponent("GitEditAvatars", isDirectory: true)

        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            directory: diskURL
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 15
        urlSession = URLSession(configuration: config)
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        if let existing = loadingTasks[url] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            defer { loadingTasks[url] = nil }
            do {
                let (data, response) = try await urlSession.data(from: url)
                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    return nil
                }
                guard let image = NSImage(data: data) else { return nil }
                cache.setObject(image, forKey: url as NSURL)
                return image
            } catch {
                return nil
            }
        }
        loadingTasks[url] = task
        return await task.value
    }
}
