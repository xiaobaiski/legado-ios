import CryptoKit
import Foundation

/// WebDAV 跨设备同步辅助工具：负责书籍匹配、归档命名、封面读写与进度合并
enum WebDAVSyncHelper {
    static let genericAuthors: Set<String> = ["", "本地导入", "未知", "未知作者"]
    static let maxCoverArchiveBytes = 4 * 1024 * 1024

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isGenericAuthor(_ author: String) -> Bool {
        genericAuthors.contains(normalize(author))
    }

    static func authorsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalize(lhs)
        let right = normalize(rhs)
        if left == right {
            return true
        }
        return isGenericAuthor(left) || isGenericAuthor(right)
    }

    /// 跨设备匹配本地已有书籍：优先按精确 bookUrl 匹配，其次按规范化书名+作者匹配
    static func findMatchingBook(
        name: String,
        author: String,
        bookUrl: String,
        in localBooks: [Book]) -> Book? {
        if let exact = localBooks.first(where: { $0.bookUrl == bookUrl }) {
            return exact
        }
        let targetName = normalize(name)
        guard !targetName.isEmpty else { return nil }

        let candidates = localBooks.filter { normalize($0.name) == targetName }
        guard !candidates.isEmpty else { return nil }

        let targetAuthor = normalize(author)
        if let authorExact = candidates.first(where: { normalize($0.author) == targetAuthor }) {
            return authorExact
        }
        if candidates.count == 1, authorsMatch(candidates[0].author, author) {
            return candidates[0]
        }
        return nil
    }

    /// 计算跨设备一致的书籍归档文件名（`books/<sha256>.legadobook`）
    static func archiveFileName(name: String, author: String, bookUrl: String) -> String {
        let cleanName = normalize(name)
        let cleanAuthor = isGenericAuthor(author) ? "" : normalize(author)
        let seed = cleanName.isEmpty ? normalize(bookUrl) : "\(cleanName)|\(cleanAuthor)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return "\(hex).legadobook"
    }

    /// 读取本地封面文件（仅限 `file://` 本地封面）
    static func loadLocalCoverData(from coverUrl: String?) -> (data: Data, ext: String)? {
        guard let raw = coverUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              url.isFileURL,
              let data = try? Data(contentsOf: url),
              !data.isEmpty,
              data.count <= maxCoverArchiveBytes else {
            return nil
        }
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return (data, ext.isEmpty ? "jpg" : ext.lowercased())
    }

    /// 将归档内的封面写入本机 Documents/BookCovers 目录并更新路径
    static func saveRestoredCoverData(_ data: Data, fileExtension: String?, seed: String) -> String? {
        guard !data.isEmpty,
              let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let coversDir = docDir.appendingPathComponent("BookCovers", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: coversDir, withIntermediateDirectories: true)
            let digest = SHA256.hash(data: Data(seed.utf8))
            let hex = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
            let ext = (fileExtension?.isEmpty == false ? fileExtension : nil) ?? "jpg"
            let fileUrl = coversDir.appendingPathComponent("\(hex).\(ext)")
            try data.write(to: fileUrl, options: .atomic)
            return fileUrl.absoluteString
        } catch {
            return nil
        }
    }

    /// 合并远端进度与本地书籍元数据，始终保留本地真实 bookUrl 与本地封面
    static func mergeRemoteProgress(remote: Book, into local: Book) -> Book {
        var merged = local
        let shouldAdoptProgress = remote.durChapterTime >= local.durChapterTime
        if shouldAdoptProgress {
            merged.durChapterIndex = remote.durChapterIndex
            merged.durChapterPos = remote.durChapterPos
            if let title = remote.durChapterTitle, !title.isEmpty {
                merged.durChapterTitle = title
            }
            merged.durChapterTime = remote.durChapterTime
        }
        if merged.groupName == nil, let remoteGroup = remote.groupName {
            merged.groupName = remoteGroup
        }
        if !merged.isLocalFile, remote.lastCheckTime >= local.lastCheckTime {
            merged.latestChapterTitle = remote.latestChapterTitle ?? merged.latestChapterTitle
            merged.latestChapterTime = max(merged.latestChapterTime, remote.latestChapterTime)
            if remote.totalChapterNum > 0 {
                merged.totalChapterNum = remote.totalChapterNum
            }
            merged.lastCheckTime = remote.lastCheckTime
        }
        merged.syncTime = Int64(Date().timeIntervalSince1970 * 1000)
        return merged
    }

    /// 判断本地/云端实体是否为无源本地导入书籍
    static func isLocalImportedBook(_ book: Book) -> Bool {
        book.isLocalFile || book.origin == "local"
    }
}
