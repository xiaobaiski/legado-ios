import Foundation
import SwiftSoup

/// 解析完成的本地 EPUB 书籍结构
public struct ParsedEpubBook: Sendable {
    public let title: String
    public let author: String
    public let intro: String?
    public let coverData: Data?
    public let coverExtension: String
    public let chapters: [ParsedTxtChapter]
    public let totalWordCount: Int
}

/// 本地 EPUB 2 / EPUB 3 电子书解析引擎（提取元数据、封面、目录树与正文段落）
public enum EpubParser {
    public static func parse(data: Data, fallbackTitle: String) throws -> ParsedEpubBook {
        let zip = try ZipArchiveReader(data: data)
        guard let opfPath = resolveOpfPath(in: zip),
              let opfData = zip.readFile(at: opfPath) else {
            throw LocalBookImportError.unreadableFile
        }

        let opfXml = CharsetDetector.decode(data: opfData)
        let opfDoc = try SwiftSoup.parse(opfXml, "", Parser.xmlParser())
        let baseDir = directoryPrefix(of: opfPath)

        let title = extractFirstText(in: opfDoc, selectors: ["dc\\:title", "title"]) ?? fallbackTitle
        let author = extractFirstText(in: opfDoc, selectors: ["dc\\:creator", "creator"]) ?? "未知作者"
        let intro = extractFirstText(in: opfDoc, selectors: ["dc\\:description", "description"])

        let manifest = parseManifest(in: opfDoc, baseDir: baseDir)
        let tocMap = parseTocTitles(in: zip, manifest: manifest, baseDir: baseDir)
        let (coverData, coverExt) = extractCover(in: zip, opfDoc: opfDoc, manifest: manifest)
        let chapters = extractSpineChapters(
            in: zip,
            opfDoc: opfDoc,
            manifest: manifest,
            tocMap: tocMap)

        guard !chapters.isEmpty else {
            throw LocalBookImportError.emptyContent
        }

        let wordCount = chapters.reduce(0) { $0 + $1.content.count }
        return ParsedEpubBook(
            title: title.isEmpty ? fallbackTitle : title,
            author: author.isEmpty ? "本地导入" : author,
            intro: intro,
            coverData: coverData,
            coverExtension: coverExt,
            chapters: chapters,
            totalWordCount: wordCount)
    }

    private struct ManifestItem {
        let id: String
        let path: String
        let mediaType: String
        let properties: String
    }

    private static func resolveOpfPath(in zip: ZipArchiveReader) -> String? {
        if let containerData = zip.readFile(at: "META-INF/container.xml") {
            let xml = CharsetDetector.decode(data: containerData)
            if let doc = try? SwiftSoup.parse(xml, "", Parser.xmlParser()),
               let rootfile = try? doc.select("rootfile[full-path]").first(),
               let path = try? rootfile.attr("full-path"),
               !path.isEmpty {
                return path
            }
        }
        return zip.entries.first(where: { $0.path.lowercased().hasSuffix(".opf") })?.path
    }

    private static func parseManifest(in opfDoc: Document, baseDir: String) -> [String: ManifestItem] {
        var result: [String: ManifestItem] = [:]
        guard let items = try? opfDoc.select("manifest item") else { return result }
        for item in items.array() {
            guard let id = try? item.attr("id"), !id.isEmpty,
                  let href = try? item.attr("href"), !href.isEmpty else { continue }
            let decodedHref = href.removingPercentEncoding ?? href
            let fullPath = joinPath(base: baseDir, relative: decodedHref)
            let mediaType = (try? item.attr("media-type")) ?? ""
            let properties = (try? item.attr("properties")) ?? ""
            result[id] = ManifestItem(id: id, path: fullPath, mediaType: mediaType, properties: properties)
        }
        return result
    }

    private static func parseTocTitles(
        in zip: ZipArchiveReader,
        manifest: [String: ManifestItem],
        baseDir: String) -> [String: String] {
        var map: [String: String] = [:]
        parseNavTocTitles(in: zip, manifest: manifest, into: &map)
        parseNcxTocTitles(in: zip, manifest: manifest, into: &map)
        _ = baseDir
        return map
    }

    /// 优先解析 EPUB 3 Navigation Document（优先锁定 toc 导航，避免 landmarks/page-list 覆盖真实章名）
    private static func parseNavTocTitles(
        in zip: ZipArchiveReader,
        manifest: [String: ManifestItem],
        into map: inout [String: String]) {
        guard let navItem = manifest.values.first(where: { $0.properties.contains("nav") }),
              let navData = zip.readFile(at: navItem.path) else {
            return
        }
        let navDir = directoryPrefix(of: navItem.path)
        let html = CharsetDetector.decode(data: navData)
        guard let doc = try? SwiftSoup.parse(html) else { return }
        let tocLinks = try? doc.select(
            "nav[epub\\:type=toc] a[href], nav[type=toc] a[href], nav[role=doc-toc] a[href], nav#toc a[href]")
        let fallbackLinks = (tocLinks?.isEmpty() ?? true)
            ? (try? doc.select("nav").first()?.select("a[href]"))
            : nil
        guard let links = (tocLinks?.isEmpty() ?? true) ? fallbackLinks : tocLinks else { return }
        for link in links.array() {
            let href = ((try? link.attr("href")) ?? "").components(separatedBy: "#").first ?? ""
            let text = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty, !text.isEmpty else { continue }
            let resolved = joinPath(base: navDir, relative: href.removingPercentEncoding ?? href)
            let key = resolved.lowercased()
            if map[key] == nil {
                map[key] = text
            }
        }
    }

    /// 补充解析 EPUB 2 NCX 目录
    private static func parseNcxTocTitles(
        in zip: ZipArchiveReader,
        manifest: [String: ManifestItem],
        into map: inout [String: String]) {
        guard let ncxItem = manifest.values.first(where: {
            $0.mediaType.contains("ncx") || $0.path.lowercased().hasSuffix(".ncx")
        }), let ncxData = zip.readFile(at: ncxItem.path) else {
            return
        }
        let ncxDir = directoryPrefix(of: ncxItem.path)
        let xml = CharsetDetector.decode(data: ncxData)
        guard let doc = try? SwiftSoup.parse(xml, "", Parser.xmlParser()),
              let navPoints = try? doc.select("navPoint") else {
            return
        }
        for point in navPoints.array() {
            let title = ((try? point.select("navLabel text").first()?.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let src = ((try? point.select("content").first()?.attr("src")) ?? "")
                .components(separatedBy: "#").first ?? ""
            guard !title.isEmpty, !src.isEmpty else { continue }
            let resolved = joinPath(base: ncxDir, relative: src.removingPercentEncoding ?? src)
            if map[resolved.lowercased()] == nil {
                map[resolved.lowercased()] = title
            }
        }
    }

    private static func extractCover(
        in zip: ZipArchiveReader,
        opfDoc: Document,
        manifest: [String: ManifestItem]) -> (Data?, String) {
        var coverItem = manifest.values.first(where: {
            $0.properties.contains("cover-image") && $0.mediaType.hasPrefix("image/")
        })
        if coverItem == nil,
           let metaCover = try? opfDoc.select("meta[name=cover]").first(),
           let coverId = try? metaCover.attr("content"),
           let candidate = manifest[coverId] {
            if candidate.mediaType.hasPrefix("image/") {
                coverItem = candidate
            } else if let nestedImage = extractImageItemFromXhtml(
                candidate.path,
                in: zip,
                manifest: manifest) {
                coverItem = nestedImage
            }
        }
        if coverItem == nil {
            coverItem = manifest.values.first(where: {
                $0.mediaType.hasPrefix("image/") &&
                    ($0.id.lowercased().contains("cover") || $0.path.lowercased().contains("cover"))
            })
        }

        guard let coverItem, let data = zip.readFile(at: coverItem.path) else {
            return (nil, "jpg")
        }
        let ext = URL(fileURLWithPath: coverItem.path).pathExtension.lowercased()
        return (data, ext.isEmpty ? "jpg" : ext)
    }

    private static func extractImageItemFromXhtml(
        _ htmlPath: String,
        in zip: ZipArchiveReader,
        manifest: [String: ManifestItem]) -> ManifestItem? {
        guard let htmlData = zip.readFile(at: htmlPath) else { return nil }
        let html = CharsetDetector.decode(data: htmlData)
        guard let doc = try? SwiftSoup.parse(html),
              let img = try? doc.select("img[src], image[href], image[xlink\\:href]").first() else {
            return nil
        }
        guard let src = firstNonEmptyAttr(img, keys: ["src", "xlink:href", "href"]) else {
            return nil
        }
        let decoded = src.removingPercentEncoding ?? src
        let resolved = joinPath(base: directoryPrefix(of: htmlPath), relative: decoded).lowercased()
        return manifest.values.first {
            $0.mediaType.hasPrefix("image/") && $0.path.lowercased() == resolved
        }
    }

    private static func firstNonEmptyAttr(_ element: Element, keys: [String]) -> String? {
        for key in keys {
            if let raw = try? element.attr(key) {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func extractSpineChapters(
        in zip: ZipArchiveReader,
        opfDoc: Document,
        manifest: [String: ManifestItem],
        tocMap: [String: String]) -> [ParsedTxtChapter] {
        guard let itemrefs = try? opfDoc.select("spine itemref[idref]") else { return [] }
        var chapters: [ParsedTxtChapter] = []

        for ref in itemrefs.array() {
            guard let idref = try? ref.attr("idref"),
                  let item = manifest[idref],
                  let htmlData = zip.readFile(at: item.path) else { continue }

            let html = CharsetDetector.decode(data: htmlData)
            let (extractedTitle, bodyText) = extractChapterText(from: html)
            let cleanedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedBody.isEmpty else { continue }

            let title = tocMap[item.path.lowercased()]
                ?? extractedTitle
                ?? "第 \(chapters.count + 1) 章"
            chapters.append(ParsedTxtChapter(
                title: title,
                content: cleanedBody,
                index: chapters.count))
        }
        return chapters
    }

    private static let blockTags: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6",
        "li", "blockquote", "pre", "tr", "section", "article", "header", "footer", "dt", "dd",
    ]

    private static func extractChapterText(from html: String) -> (String?, String) {
        guard let doc = try? SwiftSoup.parse(html) else {
            return (nil, html)
        }
        _ = try? doc.select("script, style, svg, head").remove()

        let heading = (try? doc.select("h1, h2, h3").first()?.text())?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let titleCandidate = (heading?.isEmpty == false) ? heading : nil

        guard let body = doc.body() else {
            return (titleCandidate, (try? doc.text()) ?? "")
        }

        var raw = ""
        collectText(from: body, into: &raw)
        let paragraphs = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphs.isEmpty {
            let fallback = ((try? body.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (titleCandidate, fallback)
        }
        return (titleCandidate, paragraphs.joined(separator: "\n"))
    }

    private static func collectText(from node: Node, into output: inout String) {
        if let textNode = node as? TextNode {
            output += textNode.text()
            return
        }
        guard let element = node as? Element else { return }
        let tag = element.tagName().lowercased()
        if tag == "br" {
            output += "\n"
            return
        }
        let isBlock = blockTags.contains(tag)
        if isBlock && !output.isEmpty && !output.hasSuffix("\n") {
            output += "\n"
        }
        for child in element.getChildNodes() {
            collectText(from: child, into: &output)
        }
        if isBlock && !output.isEmpty && !output.hasSuffix("\n") {
            output += "\n"
        }
    }

    private static func extractFirstText(in doc: Document, selectors: [String]) -> String? {
        for selector in selectors {
            if let value = try? doc.select(selector).first()?.text() {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func directoryPrefix(of path: String) -> String {
        guard let lastSlash = path.lastIndex(of: "/") else { return "" }
        return String(path[...lastSlash])
    }

    private static func joinPath(base: String, relative: String) -> String {
        let combined = base + relative
        var parts: [String] = []
        for component in combined.components(separatedBy: "/") {
            if component.isEmpty || component == "." {
                continue
            } else if component == ".." {
                if !parts.isEmpty {
                    parts.removeLast()
                }
            } else {
                parts.append(component)
            }
        }
        return parts.joined(separator: "/")
    }
}
