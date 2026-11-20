import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 基于 UIKit UIDocumentPickerViewController(asCopy: true) 的文件选择器
/// 避免 iOS 18 SwiftUI .fileImporter 在打开文件时无响应或安全作用域失效问题
public struct DocumentPickerView: UIViewControllerRepresentable {
    public let allowedContentTypes: [UTType]
    public let allowsMultipleSelection: Bool
    public let onPick: ([URL]) -> Void
    public let onCancel: () -> Void

    public init(
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool = true,
        onPick: @escaping ([URL]) -> Void,
        onCancel: @escaping () -> Void = {}) {
        self.allowedContentTypes = allowedContentTypes
        self.allowsMultipleSelection = allowsMultipleSelection
        self.onPick = onPick
        self.onCancel = onCancel
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: allowedContentTypes,
            asCopy: true)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_: UIDocumentPickerViewController, context _: Context) {}

    public final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        public func documentPicker(
            _: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]) {
            let stagedUrls = urls.map { Self.stagePickedFile(from: $0) }
            onPick(stagedUrls)
        }

        public func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
            onCancel()
        }

        private static func stagePickedFile(from sourceUrl: URL) -> URL {
            let fileManager = FileManager.default
            let stagingDir = fileManager.temporaryDirectory
                .appendingPathComponent("LegadoImportStaging/\(UUID().uuidString)", isDirectory: true)
            let targetUrl = stagingDir.appendingPathComponent(sourceUrl.lastPathComponent)

            let accessing = sourceUrl.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    sourceUrl.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
                try fileManager.copyItem(at: sourceUrl, to: targetUrl)
                return targetUrl
            } catch {
                return sourceUrl
            }
        }
    }
}
