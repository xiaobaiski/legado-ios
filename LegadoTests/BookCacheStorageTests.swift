import Foundation
@testable import Legado
import Testing

@Suite("Book Cache Storage Suite")
struct BookCacheStorageTests {
    @Test("Test BookCacheRepository CRUD and Size Calculations")
    func bookCacheRepositoryCRUD() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestCache_\(UUID().uuidString)", isDirectory: true)
        let repository = BookCacheRepositoryImpl(baseDirectory: tempDir)
        let bookUrl = "https://example.com/test_book"

        #expect(!repository.isChapterCached(bookUrl: bookUrl, index: 0))

        // 1. 写入章节缓存
        try repository.saveChapterContent(bookUrl: bookUrl, index: 0, content: "第一章 始于微末")
        try repository.saveChapterContent(bookUrl: bookUrl, index: 1, content: "第二章 潜龙在渊")
        try repository.saveChapterContent(bookUrl: bookUrl, index: 2, content: "第三章 惊鸿一瞥")

        // 2. 读取与命中检验
        #expect(repository.isChapterCached(bookUrl: bookUrl, index: 0))
        #expect(repository.isChapterCached(bookUrl: bookUrl, index: 1))
        #expect(!repository.isChapterCached(bookUrl: bookUrl, index: 99))

        let ch0 = repository.getCachedChapterContent(bookUrl: bookUrl, index: 0)
        #expect(ch0 == "第一章 始于微末")

        let indices = repository.getCachedChapterIndices(bookUrl: bookUrl)
        #expect(indices.count == 3)
        #expect(indices.contains(0))
        #expect(indices.contains(1))
        #expect(indices.contains(2))

        // 3. 统计容量与信息
        let size = repository.calculateBookCacheSize(bookUrl: bookUrl)
        #expect(size > 0)

        let info = repository.getBookCacheInfo(bookUrl: bookUrl, totalChapters: 10)
        #expect(info.cachedCount == 3)
        #expect(info.totalCount == 10)
        #expect(info.percentage == 30)
        #expect(!info.formattedSize.isEmpty)

        // 4. 清除本书缓存
        try repository.clearBookCache(bookUrl: bookUrl)
        #expect(repository.getCachedChapterIndices(bookUrl: bookUrl).isEmpty)
        #expect(repository.calculateBookCacheSize(bookUrl: bookUrl) == 0)

        // 清理临时测试文件夹
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Test SettingsViewModel Cache Clean Intent")
    @MainActor
    func settingsViewModelCache() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestCache_\(UUID().uuidString)", isDirectory: true)
        let cacheRepo = BookCacheRepositoryImpl(baseDirectory: tempDir)
        let manageCacheUseCase = ManageBookCacheUseCase(bookCacheRepository: cacheRepo)

        try cacheRepo.saveChapterContent(bookUrl: "https://book.com/1", index: 0, content: "临时正文缓存...")
        #expect(manageCacheUseCase.calculateTotalCacheSize() > 0)

        let provider = ModelContainerProvider(inMemory: true)
        let vm = SettingsViewModel(
            backupUseCase: BackupToWebDAVUseCase(
                bookRepository: BookRepositoryImpl(modelContainer: provider.container)),
            restoreUseCase: RestoreFromWebDAVUseCase(
                bookRepository: BookRepositoryImpl(modelContainer: provider.container)),
            manageBookCacheUseCase: manageCacheUseCase)

        #expect(vm.state.cacheSizeBytes > 0)
        #expect(!vm.state.formattedCacheSize.isEmpty)

        // 清理全部临时缓存
        vm.send(.clearAllCache)
        #expect(vm.state.cacheSizeBytes == 0)

        try? FileManager.default.removeItem(at: tempDir)
    }
}
