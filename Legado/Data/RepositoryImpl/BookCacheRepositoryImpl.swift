import Foundation

/// 本地章节正文与缓存持久化仓库实现
/// - 临时缓存存于 `Caches/LegadoChapters`
/// - 本地导入书籍（`local://`）优先持久化于 `Application Support/LegadoLocalBooks`，免受系统存储空间自动回收，并兼容读取旧版路径
public final class BookCacheRepositoryImpl: BookCacheRepository, @unchecked Sendable {
    private let fileManager: FileManager
    private let baseDirectory: URL
    private let localBooksDirectory: URL?

    public init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        if let baseDirectory {
            self.baseDirectory = baseDirectory
            self.localBooksDirectory = nil
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.baseDirectory = caches.appendingPathComponent("LegadoChapters", isDirectory: true)
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.localBooksDirectory = appSupport.appendingPathComponent("LegadoLocalBooks", isDirectory: true)
        }
    }

    public static func deterministicKey(for bookUrl: String) -> String {
        Data(bookUrl.utf8).map { String(format: "%02x", $0) }.joined()
    }

    private func readDirectories(for bookUrl: String) -> [URL] {
        let key = Self.deterministicKey(for: bookUrl)
        let cacheDir = baseDirectory.appendingPathComponent(key, isDirectory: true)
        if bookUrl.hasPrefix("local://"), let localBooksDirectory {
            return [
                localBooksDirectory.appendingPathComponent(key, isDirectory: true),
                cacheDir,
            ]
        }
        return [cacheDir]
    }

    private func writeDirectory(for bookUrl: String) -> URL {
        let key = Self.deterministicKey(for: bookUrl)
        if bookUrl.hasPrefix("local://"), let localBooksDirectory {
            return localBooksDirectory.appendingPathComponent(key, isDirectory: true)
        }
        return baseDirectory.appendingPathComponent(key, isDirectory: true)
    }

    public func isChapterCached(bookUrl: String, index: Int) -> Bool {
        readDirectories(for: bookUrl).contains { dir in
            fileManager.fileExists(atPath: dir.appendingPathComponent("\(index).txt").path)
        }
    }

    public func getCachedChapterIndices(bookUrl: String) -> Set<Int> {
        var indices = Set<Int>()
        for dir in readDirectories(for: bookUrl) {
            guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else {
                continue
            }
            for file in files where file.hasSuffix(".txt") {
                let name = (file as NSString).deletingPathExtension
                if let idx = Int(name) {
                    indices.insert(idx)
                }
            }
        }
        return indices
    }

    public func getCachedChapterContent(bookUrl: String, index: Int) -> String? {
        for dir in readDirectories(for: bookUrl) {
            let url = dir.appendingPathComponent("\(index).txt")
            if fileManager.fileExists(atPath: url.path) {
                return try? String(contentsOf: url, encoding: .utf8)
            }
        }
        return nil
    }

    public func saveChapterContent(bookUrl: String, index: Int, content: String) throws {
        let dir = writeDirectory(for: bookUrl)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let fileUrl = dir.appendingPathComponent("\(index).txt")
        try content.write(to: fileUrl, atomically: true, encoding: .utf8)
    }

    public func calculateBookCacheSize(bookUrl: String) -> Int64 {
        for dir in readDirectories(for: bookUrl) where fileManager.fileExists(atPath: dir.path) {
            return directorySize(at: dir)
        }
        return 0
    }

    public func getBookCacheInfo(bookUrl: String, totalChapters: Int) -> BookCacheInfo {
        let cachedIndices = getCachedChapterIndices(bookUrl: bookUrl)
        let size = calculateBookCacheSize(bookUrl: bookUrl)
        return BookCacheInfo(
            bookUrl: bookUrl,
            cachedCount: cachedIndices.count,
            totalCount: totalChapters,
            sizeInBytes: size)
    }

    public func clearBookCache(bookUrl: String) throws {
        for dir in readDirectories(for: bookUrl) where fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    public func clearAllCache() throws {
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return }
        let localPrefix = Self.deterministicKey(for: "local://")
        let entries = try fileManager.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil)
        for entry in entries where !entry.lastPathComponent.hasPrefix(localPrefix) {
            try fileManager.removeItem(at: entry)
        }
    }

    public func calculateTotalCacheSize() -> Int64 {
        guard fileManager.fileExists(atPath: baseDirectory.path),
              let entries = try? fileManager.contentsOfDirectory(
                  at: baseDirectory,
                  includingPropertiesForKeys: [.fileSizeKey],
                  options: [.skipsHiddenFiles]) else {
            return 0
        }

        let localPrefix = Self.deterministicKey(for: "local://")
        var totalSize: Int64 = 0
        for entry in entries where !entry.lastPathComponent.hasPrefix(localPrefix) {
            totalSize += directorySize(at: entry)
        }
        return totalSize
    }

    private func directorySize(at targetUrl: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: targetUrl.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let values = try? targetUrl.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values?.fileSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(
            at: targetUrl,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]) else {
            return 0
        }
        var sum: Int64 = 0
        for case let url as URL in enumerator {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                sum += Int64(size)
            }
        }
        return sum
    }
}
