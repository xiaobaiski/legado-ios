import CoreText
import Foundation
import UIKit
import UniformTypeIdentifiers

/// 本机已安装系统字体描述模型（运行时从 UIFont.familyNames 真实检测，绝不包含缺失字体）
public struct SystemFontOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let postScriptName: String

    public init(displayName: String, postScriptName: String) {
        self.id = postScriptName
        self.displayName = displayName
        self.postScriptName = postScriptName
    }
}

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
    private static let maxFontFileBytes = 64 * 1024 * 1024
    private static let systemFontsLock = NSLock()
    private nonisolated(unsafe) static var cachedSystemFonts: [SystemFontOption]?

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
    private let registeredLock = NSLock()
    private var registeredFontsByPath: [String: ImportedFont] = [:]

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
        var activePaths = Set<String>()
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else { continue }
            activePaths.insert(url.path)
            if let font = registerFontFile(at: url) {
                loaded.append(font)
            }
        }
        pruneStaleCacheEntries(keeping: activePaths)
        return loaded.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// 获取全部已导入字体列表（自动发现通过文件 App 拖入的新字体）
    public func listImportedFonts() -> [ImportedFont] {
        registerAllStoredFonts()
    }

    /// 实时枚举当前设备真实存在的内置字体（进程内缓存，优先排布常用中文/衬线字体）
    public func listAvailableSystemFonts() -> [SystemFontOption] {
        Self.systemFontsLock.lock()
        if let cached = Self.cachedSystemFonts {
            Self.systemFontsLock.unlock()
            return cached
        }
        Self.systemFontsLock.unlock()

        let preferredFamilies = [
            "PingFang SC",
            "Hiragino Sans",
            "Heiti SC",
            "Songti SC",
            "Kaiti SC",
            "STSong",
            "STKaiti",
            "Georgia",
            "Baskerville",
            "Palatino",
            "Charter",
            "Avenir Next",
            "Helvetica Neue",
        ]

        let allFamilyNames = UIFont.familyNames
        let installedSet = Set(allFamilyNames)
        var orderedFamilies: [String] = []
        var addedFamilies = Set<String>()
        for name in preferredFamilies where installedSet.contains(name) {
            orderedFamilies.append(name)
            addedFamilies.insert(name)
        }
        let remaining = allFamilyNames
            .filter { !addedFamilies.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        orderedFamilies.append(contentsOf: remaining)

        var options: [SystemFontOption] = []
        var seenPostScript = Set<String>()
        for family in orderedFamilies {
            let fontNames = UIFont.fontNames(forFamilyName: family)
            guard let regularName = pickRegularFontName(from: fontNames),
                  !seenPostScript.contains(regularName),
                  UIFont(name: regularName, size: 16) != nil else {
                continue
            }
            seenPostScript.insert(regularName)
            options.append(SystemFontOption(
                displayName: localizedFamilyLabel(family),
                postScriptName: regularName))
        }
        Self.systemFontsLock.lock()
        Self.cachedSystemFonts = options
        Self.systemFontsLock.unlock()
        return options
    }

    private func pickRegularFontName(from names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        if let exact = names.first(where: {
            $0.hasSuffix("-Regular") || $0.hasSuffix("Regular") || $0.hasSuffix("-W3")
        }) {
            return exact
        }
        if let nonBoldItalic = names.first(where: {
            let lower = $0.lowercased()
            return !lower.contains("bold") && !lower.contains("italic") && !lower.contains("oblique")
                && !lower.contains("light") && !lower.contains("thin") && !lower.contains("ultralight")
        }) {
            return nonBoldItalic
        }
        return names.first
    }

    private func localizedFamilyLabel(_ family: String) -> String {
        switch family {
        case "PingFang SC": return "苹方简体 (PingFang SC)"
        case "Hiragino Sans": return "冬青黑体 (Hiragino Sans)"
        case "Heiti SC": return "华文黑体 (Heiti SC)"
        case "Songti SC": return "华文宋体 (Songti SC)"
        case "Kaiti SC": return "华文楷体 (Kaiti SC)"
        default: return family
        }
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
        guard let destUrl = safeFontUrl(fileName: fileName) else {
            throw LocalFontImportError.unreadableFile
        }
        if let fileSize = (try? sourceUrl.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           fileSize > Self.maxFontFileBytes {
            throw LocalFontImportError.unreadableFile
        }

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
        try registerFontProcessScope(at: destUrl)

        let imported = ImportedFont(
            id: fileName,
            displayName: descriptorInfo.displayName,
            postScriptName: descriptorInfo.postScriptName,
            fileName: fileName)
        registeredLock.lock()
        registeredFontsByPath[destUrl.path] = imported
        registeredLock.unlock()
        return imported
    }

    /// 删除已导入字体并取消注册（校验单层文件名防止路径穿越删库）
    public func deleteFont(_ font: ImportedFont) throws {
        guard let fileUrl = safeFontUrl(fileName: font.fileName) else { return }
        registeredLock.lock()
        registeredFontsByPath.removeValue(forKey: fileUrl.path)
        registeredLock.unlock()
        if fileManager.fileExists(atPath: fileUrl.path) {
            CTFontManagerUnregisterFontsForURL(fileUrl as CFURL, .process, nil)
            try fileManager.removeItem(at: fileUrl)
        }
    }
}

private extension LocalFontManager {
    func registerFontProcessScope(at destUrl: URL) throws {
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
    }

    func safeFontUrl(fileName: String) -> URL? {
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              !fileName.contains("/"),
              !fileName.contains("\\"),
              !fileName.contains("\0"),
              !fileName.contains("..") else {
            return nil
        }
        let candidate = fontsDirectory.appendingPathComponent(fileName)
        let dirPath = fontsDirectory.standardizedFileURL.path
        let targetPath = candidate.standardizedFileURL.path
        guard targetPath.hasPrefix(dirPath + "/") else { return nil }
        return candidate
    }

    func registerFontFile(at url: URL) -> ImportedFont? {
        registeredLock.lock()
        if let cached = registeredFontsByPath[url.path] {
            registeredLock.unlock()
            return cached
        }
        registeredLock.unlock()

        guard let meta = extractFontMetadata(from: url) else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let fileName = url.lastPathComponent
        let font = ImportedFont(
            id: fileName,
            displayName: meta.displayName,
            postScriptName: meta.postScriptName,
            fileName: fileName)
        registeredLock.lock()
        registeredFontsByPath[url.path] = font
        registeredLock.unlock()
        return font
    }

    func pruneStaleCacheEntries(keeping activePaths: Set<String>) {
        registeredLock.lock()
        for cachedPath in registeredFontsByPath.keys where !activePaths.contains(cachedPath) {
            registeredFontsByPath.removeValue(forKey: cachedPath)
        }
        registeredLock.unlock()
    }

    func extractFontMetadata(from url: URL) -> (postScriptName: String, displayName: String)? {
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
