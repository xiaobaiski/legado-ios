import CoreFoundation
import Foundation

/// 字符集检测与解码器，用于中文小说常见编码（UTF-8 / UTF-16 / GBK / GB18030 / Big5，支持坏字节容错恢复）
public enum CharsetDetector {
    /// GB18030 编码（向下兼容 GBK 和 GB2312）
    public static let gbkEncoding: String.Encoding = {
        let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }()

    /// Big5 繁体中文编码
    public static let big5Encoding: String.Encoding = {
        let cfEncoding = CFStringEncoding(CFStringEncodings.big5.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }()

    /// 自动根据 HTTP 响应头、HTML Meta 标签、BOM 及二进制统计检测并解码（坏字节容错，避免整书乱码）
    public static func decode(data: Data, response: HTTPURLResponse? = nil) -> String {
        guard !data.isEmpty else { return "" }

        // 1. 优先读取 HTTP Header 声明的 charset
        if let response,
           let textEncodingName = response.textEncodingName?.lowercased(),
           let encoding = stringEncoding(from: textEncodingName),
           let decoded = String(data: data, encoding: encoding) {
            return decoded.trimmingLeadingBOM()
        }

        // 2. 尝试从前 1024 字节嗅探 HTML <meta charset="...">
        if let metaDecoded = decodeFromMetaCharset(data: data) {
            return metaDecoded.trimmingLeadingBOM()
        }

        // 3. 检测 BOM (UTF-8 / UTF-16 LE / UTF-16 BE)
        if let bomDecoded = decodeWithBOM(data: data) {
            return bomDecoded
        }

        // 4. 检测无 BOM 的 UTF-16 LE / BE（通过奇偶字节空字节分布识别）
        if let utf16NoBOM = decodeUTF16WithoutBOMIfLikely(data: data) {
            return utf16NoBOM
        }

        // 5. 严格 UTF-8 优先；若因个别坏字节失败但前 64KB 基本为合法 UTF-8，则容错保留 UTF-8（避免误判为 GBK 乱码）
        if let utf8String = String(data: data, encoding: .utf8) {
            return utf8String.trimmingLeadingBOM()
        }
        if isLikelyUTF8Sample(data) {
            return String(decoding: data, as: UTF8.self).trimmingLeadingBOM()
        }

        // 6. 严格 GB18030 / Big5
        if let gbkString = String(data: data, encoding: gbkEncoding) {
            return gbkString.trimmingLeadingBOM()
        }
        if let big5String = String(data: data, encoding: big5Encoding) {
            return big5String.trimmingLeadingBOM()
        }

        // 7. 坏字节容错自动识别（优先 GB18030 / Big5 / UTF-8）
        var converted: NSString?
        var usedLossy = ObjCBool(false)
        let options: [StringEncodingDetectionOptionsKey: Any] = [
            .allowLossyKey: true,
            .suggestedEncodingsKey: [
                gbkEncoding.rawValue,
                big5Encoding.rawValue,
                String.Encoding.utf8.rawValue,
                String.Encoding.utf16LittleEndian.rawValue,
                String.Encoding.utf16BigEndian.rawValue,
            ],
        ]
        _ = NSString.stringEncoding(
            for: data,
            encodingOptions: options,
            convertedString: &converted,
            usedLossyConversion: &usedLossy)
        if let lossy = converted as String?, !lossy.isEmpty {
            return lossy.trimmingLeadingBOM()
        }

        // 8. 兜底 ISO Latin 1
        return (String(data: data, encoding: .isoLatin1) ?? "").trimmingLeadingBOM()
    }

    /// 根据编码名称字符串获取 String.Encoding
    public static func stringEncoding(from charsetName: String) -> String.Encoding? {
        let cleaned = charsetName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch cleaned {
        case "utf-8", "utf8":
            return .utf8

        case "gbk", "gb2312", "gb18030":
            return gbkEncoding

        case "big5", "big-5":
            return big5Encoding

        default:
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(cleaned as CFString)
            guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        }
    }

    /// 使用指定编码进行百分号 URL 编码 (对齐 Android URLEncoder.encode(str, enc))
    public static func percentEncode(string: String, encoding: String.Encoding) -> String {
        guard let data = string.data(using: encoding) else { return string }
        return data.map { byte -> String in
            if (byte >= 0x41 && byte <= 0x5A) ||
                (byte >= 0x61 && byte <= 0x7A) ||
                (byte >= 0x30 && byte <= 0x39) ||
                byte == 0x2D || byte == 0x5F || byte == 0x2E || byte == 0x7E {
                return String(UnicodeScalar(byte))
            } else {
                return String(format: "%%%02X", byte)
            }
        }.joined()
    }

    /// GBK / GB2312 百分号编码
    public static func percentEncodeGBK(_ string: String) -> String {
        percentEncode(string: string, encoding: gbkEncoding)
    }

    private static func decodeFromMetaCharset(data: Data) -> String? {
        let prefixData = data.prefix(min(data.count, 1024))
        let asciiPrefix = String(decoding: prefixData, as: UTF8.self).lowercased()
        let gbkMarkers = ["charset=gbk", "charset=\"gbk\"", "charset=gb2312", "charset=\"gb2312\"",
                          "charset=gb18030", "charset=\"gb18030\""]
        if gbkMarkers.contains(where: { asciiPrefix.contains($0) }) {
            return String(data: data, encoding: gbkEncoding)
        }
        if asciiPrefix.contains("charset=big5") || asciiPrefix.contains("charset=\"big5\"") {
            return String(data: data, encoding: big5Encoding)
        }
        return nil
    }

    private static func decodeWithBOM(data: Data) -> String? {
        let header = Array(data.prefix(3))
        if header.count >= 3, header[0] == 0xEF, header[1] == 0xBB, header[2] == 0xBF {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if header.count >= 2,
           (header[0] == 0xFF && header[1] == 0xFE) || (header[0] == 0xFE && header[1] == 0xFF) {
            return String(data: data, encoding: .utf16)?.trimmingLeadingBOM()
        }
        return nil
    }

    private static func decodeUTF16WithoutBOMIfLikely(data: Data) -> String? {
        guard data.count >= 16, data.count % 2 == 0 else { return nil }
        let sample = data.prefix(2048)
        var oddZero = 0
        var evenZero = 0
        let pairs = sample.count / 2
        for idx in 0 ..< pairs {
            if sample[sample.startIndex + idx * 2] == 0 { evenZero += 1 }
            if sample[sample.startIndex + idx * 2 + 1] == 0 { oddZero += 1 }
        }
        if oddZero > pairs / 4 && evenZero < pairs / 16 {
            return String(data: data, encoding: .utf16LittleEndian)?.trimmingLeadingBOM()
        }
        if evenZero > pairs / 4 && oddZero < pairs / 16 {
            return String(data: data, encoding: .utf16BigEndian)?.trimmingLeadingBOM()
        }
        return nil
    }

    private static func isLikelyUTF8Sample(_ data: Data) -> Bool {
        let sample = Array(data.prefix(65536))
        var index = 0
        var validMultibyte = 0
        var invalidBytes = 0
        while index < sample.count {
            let b0 = sample[index]
            if b0 < 0x80 {
                index += 1
                continue
            }
            let seqLen: Int
            if (b0 & 0xE0) == 0xC0, b0 >= 0xC2 {
                seqLen = 2
            } else if (b0 & 0xF0) == 0xE0 {
                seqLen = 3
            } else if (b0 & 0xF8) == 0xF0, b0 <= 0xF4 {
                seqLen = 4
            } else {
                invalidBytes += 1
                index += 1
                continue
            }
            guard index + seqLen <= sample.count else { break }
            var ok = true
            for offset in 1 ..< seqLen where (sample[index + offset] & 0xC0) != 0x80 {
                ok = false
                break
            }
            if ok {
                validMultibyte += 1
                index += seqLen
            } else {
                invalidBytes += 1
                index += 1
            }
        }
        return validMultibyte >= 8 && invalidBytes * 10 <= validMultibyte
    }
}

private extension String {
    func trimmingLeadingBOM() -> String {
        if hasPrefix("\u{FEFF}") {
            return String(dropFirst())
        }
        return self
    }
}
