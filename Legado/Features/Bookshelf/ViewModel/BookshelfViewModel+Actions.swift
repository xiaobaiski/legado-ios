import Foundation

extension BookshelfViewModel {
    func performBatchRemove() {
        let targets = Array(state.selectedBookUrls)
        guard !targets.isEmpty else { return }

        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }
            for bookUrl in targets {
                try? await self.removeBookFromShelfUseCase.execute(bookUrl: bookUrl)
            }
            let books = (try? await self.getBookshelfUseCase.execute()) ?? []
            self.updateState {
                $0.books = books
                $0.selectedBookUrls.removeAll()
                $0.isBatchMode = false
            }
            self.emitEffect(.showToast("已成功移出 \(targets.count) 本书"))
            self.emitEffect(.hapticFeedback)
        }
    }

    func performBatchMove(groupName: String?) {
        let targets = state.selectedBookUrls
        guard !targets.isEmpty, let saveBookToShelfUseCase else { return }

        let snapshot = state.books
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }
            for book in snapshot where targets.contains(book.bookUrl) {
                var updated = book
                updated.groupName = groupName
                try? await saveBookToShelfUseCase.execute(updated)
            }
            let books = (try? await self.getBookshelfUseCase.execute()) ?? []
            self.updateState {
                $0.books = books
                $0.selectedBookUrls.removeAll()
                $0.isBatchMode = false
            }
            let targetTitle = groupName ?? "未分组"
            self.emitEffect(.showToast("已将 \(targets.count) 本书移动至「\(targetTitle)」"))
            self.emitEffect(.hapticFeedback)
        }
    }

    func performMoveSingleBook(bookUrl: String, groupName: String?) {
        guard let book = state.books.first(where: { $0.bookUrl == bookUrl }),
              let saveBookToShelfUseCase else { return }

        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }
            var updated = book
            updated.groupName = groupName
            try? await saveBookToShelfUseCase.execute(updated)
            let books = (try? await self.getBookshelfUseCase.execute()) ?? []
            self.updateState { $0.books = books }
            let targetTitle = groupName ?? "未分组"
            self.emitEffect(.showToast("已将《\(book.name)》移动至「\(targetTitle)」"))
            self.emitEffect(.hapticFeedback)
        }
    }

    func performAddGroup(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if state.groups.contains(trimmed) {
            emitEffect(.showToast("分组「\(trimmed)」已存在或为系统内置分组"))
            return
        }
        let nextOrder = (state.customGroups.map(\.order).max() ?? -1) + 1
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }
            let group = BookGroup(name: trimmed, order: nextOrder)
            try? await self.saveBookGroupUseCase?.execute(group)
            self.loadData()
            self.emitEffect(.showToast("分组「\(trimmed)」创建成功"))
            self.emitEffect(.hapticFeedback)
        }
    }

    func performDeleteGroup(id: String) {
        let deletedName = state.customGroups.first(where: { $0.id == id })?.name
        let snapshotBooks = state.books
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }
            try? await self.deleteBookGroupUseCase?.execute(id: id)
            if let deletedName, let saveBookToShelfUseCase {
                for book in snapshotBooks where book.groupName == deletedName {
                    var updated = book
                    updated.groupName = nil
                    try? await saveBookToShelfUseCase.execute(updated)
                }
                if self.state.selectedGroup == deletedName {
                    self.updateState { $0.selectedGroup = "全部" }
                }
            }
            self.loadData()
            self.emitEffect(.showToast("已删除分组"))
            self.emitEffect(.hapticFeedback)
        }
    }

    func performUpdateBookMetadata(bookUrl: String, name: String, author: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let book = state.books.first(where: { $0.bookUrl == bookUrl }),
              let saveBookToShelfUseCase else { return }

        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAuthor = trimmedAuthor.isEmpty ? "本地导入" : trimmedAuthor
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }
            var updated = book
            updated.name = trimmedName
            updated.author = resolvedAuthor
            try? await saveBookToShelfUseCase.execute(updated)
            try? await self.bookmarkRepository?.updateBookMetadata(
                bookUrl: bookUrl,
                bookName: trimmedName,
                bookAuthor: resolvedAuthor)
            let books = (try? await self.getBookshelfUseCase.execute()) ?? []
            self.updateState { $0.books = books }
            self.emitEffect(.showToast("已更新《\(trimmedName)》信息"))
            self.emitEffect(.hapticFeedback)
        }
    }
}
