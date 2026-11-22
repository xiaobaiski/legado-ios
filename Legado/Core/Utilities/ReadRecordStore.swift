import Foundation

/// 阅读统计与时长记录持久化存储（对标 Legado「阅读记录」，带内存缓存与每日时长统计）
public final class ReadRecordStore: @unchecked Sendable {
    public static let shared = ReadRecordStore()

    private struct StoragePayload: Codable {
        var records: [ReadRecord]
        var dailySeconds: [String: TimeInterval]
    }

    private let storageUrl: URL
    private let lock = NSLock()
    private var cachedPayload: StoragePayload?

    public init(storageUrl: URL? = nil) {
        if let storageUrl {
            self.storageUrl = storageUrl
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.storageUrl = docs.appendingPathComponent("read_records.json")
        }
    }

    /// 记录一次有效阅读会话（自动过滤不足 2 秒的瞬时切出）
    public func recordSession(
        bookName: String,
        bookAuthor: String,
        durationSeconds: TimeInterval,
        wordsRead: Int = 0,
        date: Date = Date()) {
        guard durationSeconds >= 2, !bookName.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var payload = loadPayloadUnlocked()
        let key = "\(bookName)_\(bookAuthor)"
        if let idx = payload.records.firstIndex(where: { $0.id == key }) {
            payload.records[idx].readTimeSeconds += durationSeconds
            payload.records[idx].lastReadDate = date
            payload.records[idx].wordsRead += max(wordsRead, 0)
        } else {
            payload.records.append(ReadRecord(
                bookName: bookName,
                bookAuthor: bookAuthor,
                readTimeSeconds: durationSeconds,
                lastReadDate: date,
                wordsRead: max(wordsRead, 0)))
        }

        let dayKey = Self.dayKey(for: date)
        payload.dailySeconds[dayKey, default: 0] += durationSeconds
        savePayloadUnlocked(payload)
    }

    public func allRecordsSorted() -> [ReadRecord] {
        lock.lock()
        defer { lock.unlock() }
        return loadPayloadUnlocked().records.sorted { $0.readTimeSeconds > $1.readTimeSeconds }
    }

    public func todayReadSeconds(now: Date = Date()) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return loadPayloadUnlocked().dailySeconds[Self.dayKey(for: now)] ?? 0
    }

    public func totalReadSeconds() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return loadPayloadUnlocked().records.reduce(0) { $0 + $1.readTimeSeconds }
    }

    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        savePayloadUnlocked(StoragePayload(records: [], dailySeconds: [:]))
    }

    /// 合并远端备份的阅读时长记录（按书名+作者取较大累计值，不丢失已有记录）
    public func mergeRecords(_ incoming: [ReadRecord]) {
        guard !incoming.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var payload = loadPayloadUnlocked()
        for remote in incoming {
            if let idx = payload.records.firstIndex(where: { $0.id == remote.id }) {
                payload.records[idx].readTimeSeconds = max(
                    payload.records[idx].readTimeSeconds,
                    remote.readTimeSeconds)
                payload.records[idx].wordsRead = max(
                    payload.records[idx].wordsRead,
                    remote.wordsRead)
                if remote.lastReadDate > payload.records[idx].lastReadDate {
                    payload.records[idx].lastReadDate = remote.lastReadDate
                }
            } else {
                payload.records.append(remote)
            }
        }
        savePayloadUnlocked(payload)
    }

    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 1 {
            return seconds >= 1 ? "\(Int(seconds)) 秒" : "0 分钟"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分钟" : "\(hours) 小时"
        }
        return "\(minutes) 分钟"
    }

    private func loadPayloadUnlocked() -> StoragePayload {
        if let cachedPayload {
            return cachedPayload
        }
        let loaded: StoragePayload
        if FileManager.default.fileExists(atPath: storageUrl.path),
           let data = try? Data(contentsOf: storageUrl),
           let decoded = try? JSONDecoder().decode(StoragePayload.self, from: data) {
            loaded = decoded
        } else {
            loaded = StoragePayload(records: [], dailySeconds: [:])
        }
        cachedPayload = loaded
        return loaded
    }

    private func savePayloadUnlocked(_ payload: StoragePayload) {
        cachedPayload = payload
        let parent = storageUrl.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: storageUrl, options: .atomic)
        }
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
