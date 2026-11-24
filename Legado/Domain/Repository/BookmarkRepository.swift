import Foundation

/// 书签数据持久化仓储协议
public protocol BookmarkRepository: Sendable {
    /// 获取全部书签（用于跨设备 WebDAV 同步）
    func getAllBookmarks() async throws -> [Bookmark]

    /// 获取指定书籍的所有书签
    func getBookmarks(bookName: String, bookAuthor: String) async throws -> [Bookmark]

    /// 保存或更新书签
    func saveBookmark(_ bookmark: Bookmark) async throws

    /// 删除指定书签
    func deleteBookmark(id: String) async throws

    /// 批量删除指定书签
    func deleteBookmarks(ids: [String]) async throws

    /// 根据书籍唯一 URL 获取书签
    func getBookmarks(bookUrl: String) async throws -> [Bookmark]

    /// 清理指定书籍关联的全部书签
    func deleteBookmarks(forBookUrl bookUrl: String) async throws

    /// 重命名书籍元数据后同步更新关联书签的书名与作者
    func updateBookMetadata(bookUrl: String, bookName: String, bookAuthor: String) async throws
}
