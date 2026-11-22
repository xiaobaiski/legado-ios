import Foundation

// MARK: - WebDAV 请求执行、重定向保活与错误诊断扩展

extension WebDAVClient {
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
        let session: URLSession
        let ownsSession: Bool
        if let customSession {
            session = customSession
            ownsSession = false
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 25
            configuration.timeoutIntervalForResource = 60
            let delegate = WebDAVSessionDelegate(config: config)
            session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            ownsSession = true
        }
        defer {
            if ownsSession {
                session.finishTasksAndInvalidate()
            }
        }

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
        request.setValue("Legado-iOS/1.0.1", forHTTPHeaderField: "User-Agent")
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

/// WebDAV 会话代理：处理 HTTP 重定向方法与凭证保留、Basic/Digest 质询与可选自签名 TLS 证书放行
private final class WebDAVSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let config: WebDAVConfig

    init(config: WebDAVConfig) {
        self.config = config
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void) {
        var updated = request
        if let original = task.originalRequest {
            if let method = original.httpMethod, !method.isEmpty {
                updated.httpMethod = method
            }
            if let body = original.httpBody, updated.httpBody == nil {
                updated.httpBody = body
            }
            for header in ["Depth", "Content-Type", "User-Agent"] {
                if let value = original.value(forHTTPHeaderField: header) {
                    updated.setValue(value, forHTTPHeaderField: header)
                }
            }
            if shouldPreserveAuth(from: original.url, to: updated.url) {
                if let auth = original.value(forHTTPHeaderField: "Authorization") {
                    updated.setValue(auth, forHTTPHeaderField: "Authorization")
                } else {
                    WebDAVClient.applyBasicAuth(to: &updated, config: config)
                }
            }
        }
        completionHandler(updated)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        if method == NSURLAuthenticationMethodServerTrust {
            if config.allowInsecureCertificate,
               let serverTrust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
            return
        }

        let isBasicOrDigest = method == NSURLAuthenticationMethodHTTPBasic
            || method == NSURLAuthenticationMethodHTTPDigest
        if isBasicOrDigest,
           challenge.previousFailureCount == 0,
           config.hasCredentials {
            let credential = URLCredential(
                user: config.trimmedUsername,
                password: config.password,
                persistence: .forSession)
            completionHandler(.useCredential, credential)
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }

    private func shouldPreserveAuth(from originalUrl: URL?, to redirectedUrl: URL?) -> Bool {
        guard let oldHost = originalUrl?.host?.lowercased(),
              let newHost = redirectedUrl?.host?.lowercased() else {
            return false
        }
        return oldHost == newHost
    }
}
