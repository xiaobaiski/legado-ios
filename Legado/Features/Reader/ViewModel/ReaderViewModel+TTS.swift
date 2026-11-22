import Foundation

// MARK: - 朗读与连续跨章听书支持扩展

public extension ReaderViewModel {
    /// 获取下一可读章节正文供连续无缝听书使用（自动应用净化与繁简规则，并跳过空卷章）
    func fetchNextChapterForTTS() async -> (title: String, content: String)? {
        var candidateIndex = state.currentChapterIndex + 1
        while candidateIndex < state.chapters.count {
            let candidate = state.chapters[candidateIndex]
            if let rawContent = try? await getChapterContentUseCase.execute(
                chapter: candidate,
                origin: state.book.origin) {
                let normalized = TextLayoutEngine.shared.normalizeContent(
                    rawContent,
                    chapterTitle: candidate.title,
                    bookName: state.book.name,
                    bookOrigin: state.book.origin,
                    config: state.config)
                let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    self.send(.loadChapter(candidateIndex))
                    return (title: candidate.title, content: normalized)
                }
            }
            candidateIndex += 1
        }
        return nil
    }
}
