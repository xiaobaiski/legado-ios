import CoreText
import Foundation
import UniformTypeIdentifiers

/// 已导入的本地字体描述模型
public struct ImportedFont: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public let postScriptName: String
    public let fileName: String

    public init(
        id: String,
        displayName: String,
        postScriptName: String,
        fileName: String) {
        self.id = id
        self.displayName = displayName
        self.postScriptName = postScriptName
        self.fileName = fileName
    }
}

/// 本地字体导入错误定义
public enum LocalFontImportError: LocalizedError, Sendable {
    case unsupportedFormat(String)
    case unreadableFile
    case invalidFontFile
    case registrationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(ext):
            return "暂不支持 .\(ext) 格式，请选择 TTF / OTF / TTC 字体文件"

        case .unreadableFile:
            return "无法读取所选字体文件"

        case .invalidFontFile:
            return "无法解析字体信息，请确认文件为有效的字体文件"

        case let .registrationFailed(reason):
            return "注册字体失败: \(reason)"
        }
    }
}

/// 本地自定义字体管理器（持久化存于 Documents/Fonts，支持通过文件 App 或系统选择器导入）
public final class LocalFontManager: @unchecked Sendable {
    public static let shared = LocalFontManager()

    private static let supportedExtensions: Set<String> = ["ttf", "otf", "ttc", "otc"]

    public static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.font, .data]
        for ext in ["ttf", "otf", "ttc"] {
            if let utType = UTType(filenameExtension: ext) {
                types.insert(utType, at: 0)
            }
        }
        return types
    }

    private let fileManager: FileManager
    private let fontsDirectory: URL

    public init(
        fileManager: FileManager = .default,
        fontsDirectory: URL? = nil) {
        self.fileManager = fileManager
        if let fontsDirectory {
            self.fontsDirectory = fontsDirectory
        } else {
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fontsDirectory = docs.appendingPathComponent("Fonts", isDirectory: true)
        }
    }

    /// 确保 Documents/Fonts 目录存在（同时暴露于 iOS 文件 App）
    public func ensureFontsDirectoryExists() {
        if !fileManager.fileExists(atPath: fontsDirectory.path) {
            try? fileManager.createDirectory(at: fontsDirectory, withIntermediateDirectories: true)
        }
    }

    /// 启动时自动扫描并注册 Documents/Fonts 下全部字体文件
    @discardableResult
    public func registerAllStoredFonts() -> [ImportedFont] {
        ensureFontsDirectoryExists()
        guard let urls = try? fileManager.contentsOfDirectory(
            at: fontsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else {
            return []
        }

        var loaded: [ImportedFont] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else { continue }
            if let font = registerFontFile(at: url) {
                loaded.append(font)
            }
        }
        return loaded.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// 获取全部已导入字体列表（自动发现通过文件 App 拖入的新字体）
    public func listImportedFonts() -> [ImportedFont] {
        registerAllStoredFonts()
    }

    /// 导入并立即注册本地字体文件（TTF / OTF / TTC）
    public func importFont(from sourceUrl: URL) throws -> ImportedFont {
        let ext = sourceUrl.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw LocalFontImportError.unsupportedFormat(ext)
        }

        let accessing = sourceUrl.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceUrl.stopAccessingSecurityScopedResource()
            }
            if sourceUrl.path.contains("LegadoImportStaging") {
                try? fileManager.removeItem(at: sourceUrl.deletingLastPathComponent())
            }
        }

        ensureFontsDirectoryExists()
        let fileName = sourceUrl.lastPathComponent
        let destUrl = fontsDirectory.appendingPathComponent(fileName)

        guard let data = try? Data(contentsOf: sourceUrl), !data.isEmpty else {
            throw LocalFontImportError.unreadableFile
        }

        if fileManager.fileExists(atPath: destUrl.path) {
            CTFontManagerUnregisterFontsForURL(destUrl as CFURL, .process, nil)
            try fileManager.removeItem(at: destUrl)
        }
        try data.write(to: destUrl, options: .atomic)

        guard let descriptorInfo = extractFontMetadata(from: destUrl) else {
            try? fileManager.removeItem(at: destUrl)
            throw LocalFontImportError.invalidFontFile
        }

        var cfError: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(destUrl as CFURL, .process, &cfError)
        if !registered, let error = cfError?.takeRetainedValue() {
            let code = CFErrorGetCode(error)
            // kCTFontManagerErrorAlreadyRegistered == 105 视为已注册成功
            if code != CTFontManagerError.alreadyRegistered.rawValue {
                try? fileManager.removeItem(at: destUrl)
                throw LocalFontImportError.registrationFailed(CFErrorCopyDescription(error) as String)
            }
        }

        return ImportedFont(
            id: fileName,
            displayName: descriptorInfo.displayName,
            postScriptName: descriptorInfo.postScriptName,
            fileName: fileName)
    }

    /// 删除已导入字体并取消注册
    public func deleteFont(_ font: ImportedFont) throws {
        let fileUrl = fontsDirectory.appendingPathComponent(font.fileName)
        if fileManager.fileExists(atPath: fileUrl.path) {
            CTFontManagerUnregisterFontsForURL(fileUrl as CFURL, .process, nil)
            try fileManager.removeItem(at: fileUrl)
        }
    }

    private func registerFontFile(at url: URL) -> ImportedFont? {
        guard let meta = extractFontMetadata(from: url) else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let fileName = url.lastPathComponent
        return ImportedFont(
            id: fileName,
            displayName: meta.displayName,
            postScriptName: meta.postScriptName,
            fileName: fileName)
    }

    private func extractFontMetadata(from url: URL) -> (postScriptName: String, displayName: String)? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first else {
            return nil
        }

        let psName = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
        let displayName = (CTFontDescriptorCopyLocalizedAttribute(first, kCTFontDisplayNameAttribute, nil) as? String)
            ?? (CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String)
            ?? url.deletingPathExtension().lastPathComponent

        guard let postScriptName = psName, !postScriptName.isEmpty else {
            return nil
        }
        return (postScriptName, displayName)
    }
}
