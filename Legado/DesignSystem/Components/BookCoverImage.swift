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

/// 书籍封面图片组件（同时支持本地 EPUB 封面 file:// 内存降采样缓存与网络图片 URL）
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
        if let coverUrl, let url = URL(string: coverUrl) {
            if url.isFileURL {
                if let uiImage = LocalCoverImageCache.shared.image(for: url) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder()
                }
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()

                    default:
                        placeholder()
                    }
                }
            }
        } else {
            placeholder()
        }
    }
}
