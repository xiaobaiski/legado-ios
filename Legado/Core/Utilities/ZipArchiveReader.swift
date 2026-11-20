import Compression
import Foundation

/// 轻量纯 Swift ZIP 归档读取器（基于系统 Compression 框架，专用于本地 EPUB 解析，零第三方依赖）
public final class ZipArchiveReader: Sendable {
    public struct Entry: Sendable {
        public let path: String
        public let compressionMethod: UInt16
        public let compressedSize: UInt32
        public let uncompressedSize: UInt32
        public let localHeaderOffset: UInt32
    }

    private let data: Data
    private let entriesMap: [String: Entry]
    public let entries: [Entry]

    public init(data: Data) throws {
        self.data = data
        let parsed = try Self.parseCentralDirectory(from: data)
        self.entries = parsed
        var map: [String: Entry] = [:]
        for entry in parsed {
            map[entry.path] = entry
        }
        self.entriesMap = map
    }

    /// 按路径读取归档内文件原始字节（自动忽略前导 `/`）
    public func readFile(at rawPath: String) -> Data? {
        let normalized = rawPath.hasPrefix("/") ? String(rawPath.dropFirst()) : rawPath
        let entry = entriesMap[normalized]
            ?? entries.first(where: { $0.path.caseInsensitiveCompare(normalized) == .orderedSame })
        guard let entry else { return nil }
        return extract(entry: entry)
    }

    private func extract(entry: Entry) -> Data? {
        let headerOffset = Int(entry.localHeaderOffset)
        guard headerOffset + 30 <= data.count else { return nil }
        guard readUInt32(at: headerOffset) == 0x0403_4B50 else { return nil }

        let nameLength = Int(readUInt16(at: headerOffset + 26))
        let extraLength = Int(readUInt16(at: headerOffset + 28))
        let dataStart = headerOffset + 30 + nameLength + extraLength
        let compressedLength = Int(entry.compressedSize)
        guard dataStart >= 0, dataStart + compressedLength <= data.count else { return nil }

        let slice = data.subdata(in: dataStart ..< (dataStart + compressedLength))
        switch entry.compressionMethod {
        case 0:
            return slice

        case 8:
            return Self.inflateRawDeflate(slice, expectedSize: Int(entry.uncompressedSize))

        default:
            return nil
        }
    }

    private static func inflateRawDeflate(_ compressed: Data, expectedSize: Int) -> Data? {
        if compressed.isEmpty {
            return Data()
        }
        var capacity = max(expectedSize, compressed.count * 4, 4096)
        for _ in 0 ..< 6 {
            var destination = Data(count: capacity)
            let decodedSize = destination.withUnsafeMutableBytes { dstPtr in
                compressed.withUnsafeBytes { srcPtr in
                    guard let dstBase = dstPtr.bindMemory(to: UInt8.self).baseAddress,
                          let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress else {
                        return 0
                    }
                    return compression_decode_buffer(
                        dstBase,
                        capacity,
                        srcBase,
                        compressed.count,
                        nil,
                        COMPRESSION_ZLIB)
                }
            }

            if decodedSize == 0 {
                return nil
            }
            if decodedSize < capacity || (expectedSize > 0 && decodedSize == expectedSize) {
                destination.count = decodedSize
                return destination
            }
            capacity *= 2
        }
        return nil
    }

    private static func parseCentralDirectory(from data: Data) throws -> [Entry] {
        guard let eocdOffset = findEOCDOffset(in: data) else {
            throw LocalBookImportError.unreadableFile
        }

        let cdSize = Int(readUInt32(in: data, at: eocdOffset + 12))
        let cdOffset = Int(readUInt32(in: data, at: eocdOffset + 16))
        guard cdOffset >= 0, cdOffset + cdSize <= data.count else {
            throw LocalBookImportError.unreadableFile
        }

        var cursor = cdOffset
        let end = cdOffset + cdSize
        var result: [Entry] = []

        while cursor + 46 <= end {
            guard readUInt32(in: data, at: cursor) == 0x0201_4B50 else { break }

            let method = readUInt16(in: data, at: cursor + 10)
            let compressedSize = readUInt32(in: data, at: cursor + 20)
            let uncompressedSize = readUInt32(in: data, at: cursor + 24)
            let nameLen = Int(readUInt16(in: data, at: cursor + 28))
            let extraLen = Int(readUInt16(in: data, at: cursor + 30))
            let commentLen = Int(readUInt16(in: data, at: cursor + 32))
            let localOffset = readUInt32(in: data, at: cursor + 42)

            let nameStart = cursor + 46
            guard nameStart + nameLen <= end else { break }
            let nameData = data.subdata(in: nameStart ..< (nameStart + nameLen))
            let path = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: CharsetDetector.gbkEncoding)
                ?? ""

            if !path.isEmpty && !path.hasSuffix("/") {
                result.append(Entry(
                    path: path,
                    compressionMethod: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localOffset))
            }

            cursor = nameStart + nameLen + extraLen + commentLen
        }

        return result
    }

    private static func findEOCDOffset(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let minOffset = max(0, data.count - 65557)
        for offset in stride(from: data.count - 22, through: minOffset, by: -1) {
            if readUInt32(in: data, at: offset) == 0x0605_4B50 {
                return offset
            }
        }
        return nil
    }

    private func readUInt16(at offset: Int) -> UInt16 {
        Self.readUInt16(in: data, at: offset)
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        Self.readUInt32(in: data, at: offset)
    }

    private static func readUInt16(in data: Data, at offset: Int) -> UInt16 {
        let low = UInt16(data[data.startIndex + offset])
        let high = UInt16(data[data.startIndex + offset + 1]) << 8
        return low | high
    }

    private static func readUInt32(in data: Data, at offset: Int) -> UInt32 {
        let byte0 = UInt32(data[data.startIndex + offset])
        let byte1 = UInt32(data[data.startIndex + offset + 1]) << 8
        let byte2 = UInt32(data[data.startIndex + offset + 2]) << 16
        let byte3 = UInt32(data[data.startIndex + offset + 3]) << 24
        return byte0 | byte1 | byte2 | byte3
    }
}
