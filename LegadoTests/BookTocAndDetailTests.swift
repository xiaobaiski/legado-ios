import Foundation
@testable import Legado
import SwiftData
import Testing

@Suite("Book Detail and TOC Suite")
struct BookTocAndDetailTests {
    @Test("Test GetBookTocUseCase with Local Caching")
    func getBookTocUseCaseLocalCache() async throws {
        let provider = ModelContainerProvider(inMemory: true)
        let bookRepo = BookRepositoryImpl(modelContainer: provider.container)

        let book = Book(
            bookUrl: "local://book/test",
            origin: "local",
            originName: "本地导入",
            name: "缓存测试书",
            author: "测试作者")
        try await bookRepo.saveBook(book)

        let cachedChapters = [
            Chapter(url: "local://book/test/0", title: "第一章", bookUrl: book.bookUrl, index: 0),
            Chapter(url: "local://book/test/1", title: "第二章", bookUrl: book.bookUrl, index: 1),
        ]
        try await bookRepo.saveChapters(cachedChapters, for: book.bookUrl)

        let useCase = GetBookTocUseCase(bookRepository: bookRepo)
        let result = try await useCase.execute(book: book, forceRefresh: false)

        #expect(result.count == 2)
        #expect(result[0].title == "第一章")
    }

    @Test("Test BookDetailViewModel Local Flow (TOC, Search, Reverse and Shelf Toggle)")
    @MainActor
    func bookDetailViewModelLocalFlow() async throws {
        let provider = ModelContainerProvider(inMemory: true)
        let bookRepo = BookRepositoryImpl(modelContainer: provider.container)

        let book = Book(
            bookUrl: "local://book/detail_test",
            origin: "local",
            originName: "本地 EPUB",
            name: "星辰大海",
            author: "测试作者")
        let chapters = [
            Chapter(url: "local://book/detail_test/0", title: "第一章 启航", bookUrl: book.bookUrl, index: 0),
            Chapter(url: "local://book/detail_test/1", title: "第二章 航线", bookUrl: book.bookUrl, index: 1),
        ]
        try await bookRepo.saveBook(book)
        try await bookRepo.saveChapters(chapters, for: book.bookUrl)

        let vm = BookDetailViewModel(
            book: book,
            getBookDetailUseCase: GetBookDetailUseCase(bookRepository: bookRepo),
            getBookTocUseCase: GetBookTocUseCase(bookRepository: bookRepo),
            saveBookToShelfUseCase: SaveBookToShelfUseCase(bookRepository: bookRepo),
            removeBookFromShelfUseCase: RemoveBookFromShelfUseCase(bookRepository: bookRepo),
            bookRepository: bookRepo)

        for _ in 0 ..< 30 where vm.state.isLoading || !vm.state.isInBookshelf {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(vm.state.isInBookshelf)
        #expect(vm.state.chapters.count == 2)

        vm.send(.openToc)
        #expect(vm.state.isTocPresented)
        vm.send(.toggleTocReverse)
        #expect(vm.state.isReverseToc)
        vm.send(.updateTocSearch("航线"))
        #expect(vm.state.tocSearchText == "航线")
        vm.send(.selectChapter(chapters[1]))
        #expect(!vm.state.isTocPresented)

        vm.send(.toggleBookshelf)
        for _ in 0 ..< 30 where vm.state.isInBookshelf {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(!vm.state.isInBookshelf)
    }
}
