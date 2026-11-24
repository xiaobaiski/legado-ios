import Foundation

extension BookshelfViewModel {
    /// 处理单个或多个本地书籍文件导入 (TXT / EPUB，支持并发到来排队不丢文件)
    func handleImportLocalBooks(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if state.isImporting {
            pendingImportURLs.append(contentsOf: urls)
            return
        }
        guard let importUseCase = importLocalBookUseCase else {
            cleanupStagingFiles(urls)
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
                defer {
                    for url in urls where url.path.contains("LegadoImportStaging") {
                        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                    }
                }
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
            self.finishImportBatch(
                importedBooks: result.0,
                totalRequested: urls.count,
                lastError: result.1)
        }
    }

    private func finishImportBatch(
        importedBooks: [Book],
        totalRequested: Int,
        lastError: Error?) {
        updateState {
            $0.isLoading = false
            $0.isImporting = false
        }

        if importedBooks.count == 1, let firstBook = importedBooks.first {
            emitEffect(.showToast("成功导入书籍《\(firstBook.name)》"))
            emitEffect(.hapticFeedback)
            send(.onAppear)
        } else if importedBooks.count > 1 {
            let failCount = totalRequested - importedBooks.count
            let msg = failCount > 0
                ? "成功导入 \(importedBooks.count) 本，\(failCount) 本失败"
                : "成功导入 \(importedBooks.count) 本本地书籍"
            emitEffect(.showToast(msg))
            emitEffect(.hapticFeedback)
            send(.onAppear)
        } else if let lastError {
            emitEffect(.showToast("导入失败: \(lastError.localizedDescription)"))
        }

        if !pendingImportURLs.isEmpty {
            let nextBatch = pendingImportURLs
            pendingImportURLs.removeAll()
            handleImportLocalBooks(urls: nextBatch)
        }
    }

    private func cleanupStagingFiles(_ urls: [URL]) {
        for url in urls where url.path.contains("LegadoImportStaging") {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }
}
