import ImageIO
import SwiftUI
import UIKit

/// 本地封面降采样内存缓存（避免书架滚动时主线程重复磁盘 I/O 与全尺寸图片解码卡顿）
private final class LocalCoverImageCache: @unchecked Sendable {
    static let shared = LocalCoverImageCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 40 * 1024 * 1024
        return cache
    }()

    func image(for url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let resolvedURL = Self.resolveExistingURL(from: url)
        guard let resolvedURL,
              let image = Self.downsample(url: resolvedURL, maxPixelSize: 600) else {
            return nil
        }
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    private static func resolveExistingURL(from url: URL) -> URL? {
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // 兼容 App 更新导致沙盒容器 UUID 变化：按文件名回落至当前 Documents/BookCovers
        let fileName = url.lastPathComponent
        guard !fileName.isEmpty,
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let fallbackURL = docs
            .appendingPathComponent("BookCovers", isDirectory: true)
            .appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil
    }

    private static func downsample(url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return UIImage(contentsOfFile: url.path)
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return UIImage(contentsOfFile: url.path)
        }
        return UIImage(cgImage: cgImage)
    }
}

/// 纯本地书籍封面图片组件（仅读取本地 file:// 缓存，绝不自动发起非必要网络请求）
public struct BookCoverImage<Placeholder: View>: View {
    private let coverUrl: String?
    private let placeholder: () -> Placeholder

    public init(
        coverUrl: String?,
        @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.coverUrl = coverUrl
        self.placeholder = placeholder
    }

    public var body: some View {
        if let coverUrl,
           let url = URL(string: coverUrl),
           url.isFileURL,
           let uiImage = LocalCoverImageCache.shared.image(for: url) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            placeholder()
        }
    }
}

/// 典雅纸质书脊风格的差异化默认封面（按书名稳定映射低饱和度色板）
public struct BookDefaultCoverView: View {
    private let title: String
    private let author: String
    private let formatBadge: String?
    private let compact: Bool

    private static let palettes: [(Color, Color)] = [
        (Color(red: 0.24, green: 0.34, blue: 0.45), Color(red: 0.14, green: 0.20, blue: 0.29)),
        (Color(red: 0.24, green: 0.37, blue: 0.36), Color(red: 0.14, green: 0.23, blue: 0.22)),
        (Color(red: 0.44, green: 0.36, blue: 0.31), Color(red: 0.28, green: 0.22, blue: 0.18)),
        (Color(red: 0.36, green: 0.29, blue: 0.42), Color(red: 0.22, green: 0.17, blue: 0.27)),
        (Color(red: 0.30, green: 0.38, blue: 0.28), Color(red: 0.18, green: 0.24, blue: 0.17)),
        (Color(red: 0.48, green: 0.32, blue: 0.29), Color(red: 0.31, green: 0.19, blue: 0.17)),
    ]

    public init(
        title: String,
        author: String = "",
        formatBadge: String? = nil,
        compact: Bool = false) {
        self.title = title
        self.author = author
        self.formatBadge = formatBadge
        self.compact = compact
    }

    private var palette: (Color, Color) {
        var hash: UInt32 = 2_166_136_261
        for byte in title.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Self.palettes[Int(hash) % Self.palettes.count]
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [palette.0, palette.1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            // 模拟纸质书左侧书脊压痕
            HStack(spacing: 0) {
                Color.black.opacity(0.18)
                    .frame(width: compact ? 3 : 5)
                Color.white.opacity(0.14)
                    .frame(width: 1)
                Spacer(minLength: 0)
            }

            if compact {
                Text(String(title.prefix(2)))
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.leading, 4)
            } else {
                fullCoverOverlay
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.5))
    }

    private var fullCoverOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                if let formatBadge, !formatBadge.isEmpty {
                    Text(formatBadge)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.16))
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 2)

            Text(title)
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            Rectangle()
                .fill(Color.white.opacity(0.28))
                .frame(width: 18, height: 1)

            if !author.isEmpty {
                Text(author)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
    }
}
