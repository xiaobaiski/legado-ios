import SwiftUI
import UIKit

/// 书籍封面图片组件（同时支持本地 EPUB 封面 file:// 与网络图片 URL，加载零延迟）
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
                if let uiImage = Self.loadLocalImage(from: url) {
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

    private static func loadLocalImage(from url: URL) -> UIImage? {
        if let direct = UIImage(contentsOfFile: url.path) {
            return direct
        }
        // 兼容 App 更新导致沙盒容器 UUID 变化：按文件名回落至当前 Documents/BookCovers
        let fileName = url.lastPathComponent
        guard !fileName.isEmpty,
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let fallbackPath = docs
            .appendingPathComponent("BookCovers", isDirectory: true)
            .appendingPathComponent(fileName)
            .path
        return UIImage(contentsOfFile: fallbackPath)
    }
}
