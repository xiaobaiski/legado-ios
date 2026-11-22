import Foundation

extension BookshelfViewModel {
    /// 处理单个或多个本地书籍文件导入 (TXT / EPUB)
    func handleImportLocalBooks(urls: [URL]) {
        guard !urls.isEmpty, !state.isImporting else { return }
        guard let importUseCase = importLocalBookUseCase else {
            emitEffect(.showToast("未配置本地导入服务"))
            return
        }

        updateState {
            $0.isLoading = true
            $0.isImporting = true
        }
        emitEffect(.hapticFeedback)

        importTask?.cancel()
        importTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                var imported: [Book] = []
                var lastError: Error?
                for url in urls {
                    if Task.isCancelled { break }
                    do {
                        let book = try await importUseCase.execute(fileUrl: url)
                        imported.append(book)
                    } catch {
                        lastError = error
                    }
                }
                return (imported, lastError)
            }.value

            guard let self, !Task.isCancelled else { return }
            self.updateState {
                $0.isLoading = false
                $0.isImporting = false
            }

            let importedBooks = result.0
            let lastError = result.1

            if importedBooks.count == 1, let firstBook = importedBooks.first {
                self.emitEffect(.showToast("成功导入书籍《\(firstBook.name)》"))
                self.emitEffect(.hapticFeedback)
                self.send(.onAppear)
            } else if importedBooks.count > 1 {
                let failCount = urls.count - importedBooks.count
                let msg = failCount > 0
                    ? "成功导入 \(importedBooks.count) 本，\(failCount) 本失败"
                    : "成功导入 \(importedBooks.count) 本本地书籍"
                self.emitEffect(.showToast(msg))
                self.emitEffect(.hapticFeedback)
                self.send(.onAppear)
            } else if let lastError {
                self.emitEffect(.showToast("导入失败: \(lastError.localizedDescription)"))
            }
        }
    }
}
