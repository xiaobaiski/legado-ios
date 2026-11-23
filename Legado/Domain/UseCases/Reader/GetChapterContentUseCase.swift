import Foundation

/// 章节正文两级本地缓存与读取用例 (L1 内存 -> L2 磁盘)
public final class GetChapterContentUseCase: @unchecked Sendable {
    private let cacheRepository: BookCacheRepository
    private let memoryCache = NSCache<NSString, NSString>()

    public init(cacheRepository: BookCacheRepository = BookCacheRepositoryImpl()) {
        self.cacheRepository = cacheRepository
        memoryCache.countLimit = 24
        memoryCache.totalCostLimit = 8 * 1024 * 1024
    }

    /// 获取章节正文内容（先查 L1 内存，未命中时读取 L2 磁盘持久化）
    public func execute(
        chapter: Chapter,
        origin _: String = "local",
        forceRefresh: Bool = false) async throws -> String {
        let cacheKey = "\(chapter.bookUrl)_\(chapter.index)" as NSString

        if !forceRefresh, let cachedMemory = memoryCache.object(forKey: cacheKey) {
            return cachedMemory as String
        }

        if let diskContent = cacheRepository.getCachedChapterContent(
            bookUrl: chapter.bookUrl,
            index: chapter.index) {
            memoryCache.setObject(
                diskContent as NSString,
                forKey: cacheKey,
                cost: max(diskContent.utf8.count, 1))
            return diskContent
        }

        return ""
    }

    /// 预热下一章正文至内存缓存
    public func preload(chapter: Chapter, origin _: String = "local") {
        let keyString = "\(chapter.bookUrl)_\(chapter.index)"
        guard memoryCache.object(forKey: keyString as NSString) == nil else { return }
        let bookUrl = chapter.bookUrl
        let index = chapter.index
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if let diskContent = self.cacheRepository.getCachedChapterContent(
                bookUrl: bookUrl,
                index: index) {
                self.memoryCache.setObject(
                    diskContent as NSString,
                    forKey: keyString as NSString,
                    cost: max(diskContent.utf8.count, 1))
            }
        }
    }

    /// 写入离线章节缓存
    public func saveChapterCache(content: String, bookUrl: String, index: Int) {
        try? cacheRepository.saveChapterContent(bookUrl: bookUrl, index: index, content: content)
        let cacheKey = "\(bookUrl)_\(index)" as NSString
        memoryCache.setObject(content as NSString, forKey: cacheKey, cost: max(content.utf8.count, 1))
    }

    /// 判断指定章节是否已缓存在磁盘
    public func isChapterCached(bookUrl: String, index: Int) -> Bool {
        cacheRepository.isChapterCached(bookUrl: bookUrl, index: index)
    }
}
