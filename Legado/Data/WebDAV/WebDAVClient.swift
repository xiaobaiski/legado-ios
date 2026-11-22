import Foundation

/// WebDAV 认证与配置模型
public struct WebDAVConfig: Codable, Equatable, Sendable {
    public var serverUrl: String
    public var username: String
    public var password: String
    public var remoteDirectory: String
    public var allowInsecureCertificate: Bool

    enum CodingKeys: String, CodingKey {
        case serverUrl
        case username
        case password
        case remoteDirectory
        case allowInsecureCertificate
    }

    public init(
        serverUrl: String = "",
        username: String = "",
        password: String = "",
        remoteDirectory: String = "/Legado/",
        allowInsecureCertificate: Bool = false) {
        self.serverUrl = serverUrl
        self.username = username
        self.password = password
        self.remoteDirectory = remoteDirectory
        self.allowInsecureCertificate = allowInsecureCertificate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverUrl = try container.decodeIfPresent(String.self, forKey: .serverUrl) ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        remoteDirectory = try container.decodeIfPresent(String.self, forKey: .remoteDirectory) ?? "/Legado/"
        allowInsecureCertificate = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowInsecureCertificate) ?? false
    }

    public var trimmedServerUrl: String {
        serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var hasCredentials: Bool {
        !trimmedUsername.isEmpty || !password.isEmpty
    }

    public var isValid: Bool {
        WebDAVClient.normalizeBaseUrl(serverUrl) != nil
    }
}

/// WebDAV 网络异常枚举
public enum WebDAVError: LocalizedError, Sendable {
    case invalidConfig
    case badUrl
    case unauthorized
    case forbidden
    case notFound
    case certificateError(String)
    case serverError(statusCode: Int, message: String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfig:
            return "WebDAV 配置无效，请填写有效的服务器地址"

        case .badUrl:
            return "无效的 WebDAV 服务器地址，请检查链接格式与目录名"

        case .unauthorized:
            return "WebDAV 账号或应用密码错误 (HTTP 401，坚果云需使用第三方应用密码)"

        case .forbidden:
            return "WebDAV 访问被拒绝 (HTTP 403，请检查账号权限或服务器地址路径是否正确)"

        case .notFound:
            return "远程备份文件或目录不存在 (HTTP 404)"

        case let .certificateError(msg):
            return msg

        case let .serverError(code, msg):
            return "WebDAV 服务器异常 (\(code)): \(msg)"

        case let .networkError(msg):
            return "WebDAV 网络请求失败: \(msg)"
        }
    }
}

/// 纯 Swift 原生异步 WebDAV 客户端 (RFC 4918 标准，支持重定向保活、Digest/Basic 鉴权、自签名 TLS 与中文目录)
public final class WebDAVClient: Sendable {
    public static let shared = WebDAVClient()

    private static let propfindXml =
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>" +
        "<d:propfind xmlns:d=\"DAV:\"><d:prop><d:resourcetype/></d:prop></d:propfind>"

    let customSession: URLSession?

    public init(urlSession: URLSession? = nil) {
        self.customSession = urlSession
    }

    // MARK: - URL 规范化与路径解析

    /// 规范化 WebDAV 服务器地址（支持 dav://、davs://、缺省协议自动补全与尾斜杠对齐）
    public static func normalizeBaseUrl(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("davs://") {
            trimmed = "https://" + trimmed.dropFirst("davs://".count)
        } else if lower.hasPrefix("dav://") {
            trimmed = "http://" + trimmed.dropFirst("dav://".count)
        } else if !trimmed.contains("://") {
            let authority = String(trimmed.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
            let defaultScheme = isLocalOrExplicitPort(authority) ? "http://" : "https://"
            trimmed = defaultScheme + trimmed
        }

        let encodedCandidate = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
        guard var components = URLComponents(string: trimmed)
                ?? encodedCandidate.flatMap({ URLComponents(string: $0) }),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return nil
        }

        if components.path.isEmpty {
            components.path = "/"
        } else if !components.path.hasSuffix("/") {
            components.path += "/"
        }
        return components.url
    }

    /// 拆分并清理远程子目录路径段
    public static func remotePathSegments(from directory: String) -> [String] {
        directory
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// 安全构建带 UTF-8 编码路径段的 WebDAV 目标 URL
    public static func buildUrl(
        base: String,
        pathSegments: [String] = [],
        isDirectory: Bool = true) -> URL? {
        guard var url = normalizeBaseUrl(base) else { return nil }
        guard !pathSegments.isEmpty else { return url }

        for (index, segment) in pathSegments.enumerated() {
            let segmentIsDir = index < pathSegments.count - 1 ? true : isDirectory
            url.appendPathComponent(segment, isDirectory: segmentIsDir)
        }
        return url
    }

    private static func isLocalOrExplicitPort(_ authority: String) -> Bool {
        let lower = authority.lowercased()
        let hostOnly = lower.split(separator: ":").first.map(String.init) ?? lower
        if hostOnly == "localhost" || hostOnly.hasSuffix(".local") ||
            hostOnly.hasPrefix("127.") || hostOnly.hasPrefix("10.") || hostOnly.hasPrefix("192.168.") ||
            lower.hasPrefix("[::1]") {
            return true
        }
        if hostOnly.hasPrefix("172.") {
            let parts = hostOnly.split(separator: ".")
            if parts.count == 4, let secondOctet = Int(parts[1]), (16 ... 31).contains(secondOctet) {
                return true
            }
        }
        if let colonIndex = lower.lastIndex(of: ":") {
            let port = lower[lower.index(after: colonIndex)...]
            if !port.isEmpty && port != "443" {
                return true
            }
        }
        return false
    }

    // MARK: - 连接测试 (PROPFIND + OPTIONS 兼容回退)

    /// 测试 WebDAV 连接与鉴权
    public func testConnection(config: WebDAVConfig) async throws -> Bool {
        guard config.isValid else { throw WebDAVError.invalidConfig }
        guard let rootUrl = Self.buildUrl(base: config.serverUrl) else {
            throw WebDAVError.badUrl
        }

        let primaryStatus = try await probeEndpoint(url: rootUrl, config: config)
        if primaryStatus == 403 || primaryStatus == 404 || primaryStatus == 405 {
            let dirSegments = Self.remotePathSegments(from: config.remoteDirectory)
            if !dirSegments.isEmpty,
               let dirUrl = Self.buildUrl(base: config.serverUrl, pathSegments: dirSegments, isDirectory: true) {
                let dirStatus = try await probeEndpoint(url: dirUrl, config: config)
                if (200 ... 207).contains(dirStatus) {
                    return true
                }
            }
        }

        return try mapConnectionResult(statusCode: primaryStatus)
    }

    private func probeEndpoint(url: URL, config: WebDAVConfig) async throws -> Int {
        let propfindBody = Data(Self.propfindXml.utf8)
        let propfindHeaders = ["Depth": "0", "Content-Type": "application/xml; charset=utf-8"]
        let req0 = makeRequest(
            url: url,
            method: "PROPFIND",
            config: config,
            headers: propfindHeaders,
            body: propfindBody)
        let (_, resp0) = try await performRequest(req0, config: config)
        if (200 ... 207).contains(resp0.statusCode) || resp0.statusCode == 401 {
            return resp0.statusCode
        }

        // 部分服务器（如 Alist / 群晖 / 受限目录）禁用 Depth: 0，自动回退 Depth: 1 与 OPTIONS
        if [400, 403, 405, 501].contains(resp0.statusCode) {
            let req1 = makeRequest(
                url: url,
                method: "PROPFIND",
                config: config,
                headers: ["Depth": "1", "Content-Type": "application/xml; charset=utf-8"],
                body: propfindBody)
            let (_, resp1) = try await performRequest(req1, config: config)
            if (200 ... 207).contains(resp1.statusCode) || resp1.statusCode == 401 {
                return resp1.statusCode
            }

            let optionsReq = makeRequest(url: url, method: "OPTIONS", config: config)
            let (_, optionsResp) = try await performRequest(optionsReq, config: config)
            if (200 ... 207).contains(optionsResp.statusCode) || optionsResp.statusCode == 401 {
                return optionsResp.statusCode
            }
        }
        return resp0.statusCode
    }

    private func mapConnectionResult(statusCode: Int) throws -> Bool {
        switch statusCode {
        case 200 ... 207:
            return true

        case 401:
            throw WebDAVError.unauthorized

        case 403:
            throw WebDAVError.forbidden

        case 404:
            throw WebDAVError.notFound

        default:
            throw WebDAVError.serverError(statusCode: statusCode, message: "连接测试未通过")
        }
    }

    // MARK: - 多级目录创建 (MKCOL)

    /// 逐级确保远程备份目录存在
    public func createDirectoryIfNeeded(config: WebDAVConfig) async throws {
        guard config.isValid else { throw WebDAVError.invalidConfig }
        let segments = Self.remotePathSegments(from: config.remoteDirectory)
        guard !segments.isEmpty else { return }

        for count in 1 ... segments.count {
            let partial = Array(segments.prefix(count))
            guard let url = Self.buildUrl(base: config.serverUrl, pathSegments: partial, isDirectory: true) else {
                throw WebDAVError.badUrl
            }
            let request = makeRequest(url: url, method: "MKCOL", config: config)
            let (_, httpResponse) = try await performRequest(request, config: config)
            let code = httpResponse.statusCode

            if code == 401 {
                throw WebDAVError.unauthorized
            }
            if code == 403 {
                throw WebDAVError.forbidden
            }
        }
    }

    // MARK: - 文件上传 (PUT) 与下载 (GET)

    /// 上传备份数据包至远程 WebDAV 路径
    public func upload(data: Data, filename: String, config: WebDAVConfig) async throws {
        guard config.isValid else { throw WebDAVError.invalidConfig }
        try await createDirectoryIfNeeded(config: config)

        let segments = Self.remotePathSegments(from: config.remoteDirectory) + [filename]
        guard let targetUrl = Self.buildUrl(base: config.serverUrl, pathSegments: segments, isDirectory: false) else {
            throw WebDAVError.badUrl
        }

        let request = makeRequest(
            url: targetUrl,
            method: "PUT",
            config: config,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data)
        let (_, httpResponse) = try await performRequest(request, config: config)

        switch httpResponse.statusCode {
        case 200 ... 204, 207:
            return

        case 401:
            throw WebDAVError.unauthorized

        case 403:
            throw WebDAVError.forbidden

        default:
            throw WebDAVError.serverError(statusCode: httpResponse.statusCode, message: "文件上传失败")
        }
    }

    /// 从远程 WebDAV 服务器下载指定文件
    public func download(filename: String, config: WebDAVConfig) async throws -> Data {
        guard config.isValid else { throw WebDAVError.invalidConfig }
        let segments = Self.remotePathSegments(from: config.remoteDirectory) + [filename]
        guard let targetUrl = Self.buildUrl(base: config.serverUrl, pathSegments: segments, isDirectory: false) else {
            throw WebDAVError.badUrl
        }

        let request = makeRequest(url: targetUrl, method: "GET", config: config)
        let (data, httpResponse) = try await performRequest(request, config: config)

        switch httpResponse.statusCode {
        case 200 ... 206:
            return data

        case 401:
            throw WebDAVError.unauthorized

        case 403:
            throw WebDAVError.forbidden

        case 404:
            throw WebDAVError.notFound

        default:
            throw WebDAVError.serverError(statusCode: httpResponse.statusCode, message: "文件下载失败")
        }
    }
}
