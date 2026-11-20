import Foundation

extension BookshelfViewModel {
    /// 处理单个或多个本地书籍文件导入 (TXT)
    func handleImportLocalBooks(urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let importUseCase = importLocalBookUseCase else {
            emitEffect(.showToast("未配置本地导入服务"))
            return
        }

        updateState { $0.isLoading = true }
        emitEffect(.hapticFeedback)

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                var imported: [Book] = []
                var lastError: Error?
                for url in urls {
                    do {
                        let book = try await importUseCase.execute(fileUrl: url)
                        imported.append(book)
                    } catch {
                        lastError = error
                    }
                }
                return (imported, lastError)
            }.value

            updateState { $0.isLoading = false }

            let importedBooks = result.0
            let lastError = result.1

            if importedBooks.count == 1, let firstBook = importedBooks.first {
                emitEffect(.showToast("成功导入书籍《\(firstBook.name)》"))
                emitEffect(.hapticFeedback)
                send(.onAppear)
            } else if importedBooks.count > 1 {
                let failCount = urls.count - importedBooks.count
                let msg = failCount > 0
                    ? "成功导入 \(importedBooks.count) 本，\(failCount) 本失败"
                    : "成功导入 \(importedBooks.count) 本本地书籍"
                emitEffect(.showToast(msg))
                emitEffect(.hapticFeedback)
                send(.onAppear)
            } else if let lastError {
                emitEffect(.showToast("导入失败: \(lastError.localizedDescription)"))
            }
        }
    }
}
