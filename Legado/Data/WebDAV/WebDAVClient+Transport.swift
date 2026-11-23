import Foundation

// MARK: - WebDAV 请求执行、子目录传输、重定向保活与错误诊断扩展

extension WebDAVClient {
    /// 检查并逐级创建远程目录与可选子目录
    public func createDirectoryIfNeeded(subdirectories: [String], config: WebDAVConfig) async throws {
        guard config.isValid else { throw WebDAVError.invalidConfig }
        let cleanSubdirs = subdirectories.filter { !$0.isEmpty }
        let segments = Self.remotePathSegments(from: config.remoteDirectory) + cleanSubdirs
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

    /// 上传数据至指定子目录下的远程文件（稳态实时同步可设 ensureDirectory = false，仅遇 404/409 时补建目录）
    public func upload(
        data: Data,
        subdirectories: [String],
        filename: String,
        contentType: String = "application/octet-stream",
        config: WebDAVConfig,
        ensureDirectory: Bool = true) async throws {
        guard config.isValid else { throw WebDAVError.invalidConfig }
        let cleanSubdirs = subdirectories.filter { !$0.isEmpty }
        if ensureDirectory {
            try await createDirectoryIfNeeded(subdirectories: cleanSubdirs, config: config)
        }

        let segments = Self.remotePathSegments(from: config.remoteDirectory) + cleanSubdirs + [filename]
        guard let targetUrl = Self.buildUrl(base: config.serverUrl, pathSegments: segments, isDirectory: false) else {
            throw WebDAVError.badUrl
        }

        let code = try await performPutUpload(
            data: data,
            targetUrl: targetUrl,
            contentType: contentType,
            config: config)
        if !ensureDirectory, code == 404 || code == 409 {
            try await createDirectoryIfNeeded(subdirectories: cleanSubdirs, config: config)
            let retryCode = try await performPutUpload(
                data: data,
                targetUrl: targetUrl,
                contentType: contentType,
                config: config)
            try mapUploadStatusCode(retryCode)
            return
        }
        try mapUploadStatusCode(code)
    }

    private func performPutUpload(
        data: Data,
        targetUrl: URL,
        contentType: String,
        config: WebDAVConfig) async throws -> Int {
        let request = makeRequest(
            url: targetUrl,
            method: "PUT",
            config: config,
            headers: ["Content-Type": contentType],
            body: data)
        let (_, httpResponse) = try await performRequest(request, config: config)
        return httpResponse.statusCode
    }

    private func mapUploadStatusCode(_ statusCode: Int) throws {
        switch statusCode {
        case 200 ... 204, 207:
            return

        case 401:
            throw WebDAVError.unauthorized

        case 403:
            throw WebDAVError.forbidden

        default:
            throw WebDAVError.serverError(statusCode: statusCode, message: "文件上传失败")
        }
    }

    /// 从指定子目录下载远程文件
    public func download(
        subdirectories: [String],
        filename: String,
        config: WebDAVConfig) async throws -> Data {
        guard config.isValid else { throw WebDAVError.invalidConfig }
        let cleanSubdirs = subdirectories.filter { !$0.isEmpty }
        let segments = Self.remotePathSegments(from: config.remoteDirectory) + cleanSubdirs + [filename]
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

    func makeRequest(
        url: URL,
        method: String,
        config: WebDAVConfig,
        headers: [String: String] = [:],
        body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        Self.applyBasicAuth(to: &request, config: config)
        return request
    }

    func performRequest(
        _ request: URLRequest,
        config: WebDAVConfig) async throws -> (Data, HTTPURLResponse) {
        let session = customSession ?? WebDAVSessionPool.shared.session(for: config)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebDAVError.networkError("未能收到有效 HTTP 响应")
            }
            return (data, httpResponse)
        } catch let webError as WebDAVError {
            throw webError
        } catch {
            throw Self.mapNetworkError(error, url: request.url)
        }
    }

    static func applyBasicAuth(to request: inout URLRequest, config: WebDAVConfig) {
        if config.hasCredentials {
            let credential = "\(config.trimmedUsername):\(config.password)"
            if let credData = credential.data(using: .utf8) {
                let base64 = credData.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }
        request.setValue("Legado-iOS/1.3.0", forHTTPHeaderField: "User-Agent")
    }

    static func mapNetworkError(_ error: Error, url: URL?) -> WebDAVError {
        guard let urlError = error as? URLError else {
            return .networkError(error.localizedDescription)
        }

        let hostHint = url?.host ?? "目标服务器"
        switch urlError.code {
        case .badURL, .unsupportedURL:
            return .badUrl

        case .cannotFindHost:
            return .networkError("无法解析服务器域名「\(hostHint)」(-1003)，请核对地址拼写或 DNS 设置")

        case .cannotConnectToHost:
            return .networkError(
                "无法连接到服务器「\(hostHint)」(-1004)，请检查端口、服务是否启动及系统「本地网络」权限")

        case .timedOut:
            return .networkError("连接服务器「\(hostHint)」超时 (-1001)，请检查网络或防火墙设置")

        case .notConnectedToInternet, .networkConnectionLost:
            return .networkError("当前设备网络连接异常 (\(urlError.errorCode))，请检查 Wi-Fi 或蜂窝网络")

        case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
             .serverCertificateHasBadDate, .serverCertificateNotYetValid, .secureConnectionFailed:
            return .certificateError(
                "HTTPS 证书校验未通过 (\(urlError.errorCode))；若为自签名 NAS，请开启「允许自签名证书」")

        case .appTransportSecurityRequiresSecureConnection:
            return .networkError("系统安全策略阻止了当前连接 (-1022)，请优先使用 HTTPS 地址")

        default:
            return .networkError("\(urlError.localizedDescription) (\(urlError.errorCode))")
        }
    }
}
