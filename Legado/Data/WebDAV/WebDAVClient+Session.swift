import CryptoKit
import Foundation

// MARK: - WebDAV 会话连接池、重定向安全策略与 TLS/Auth 质询处理

extension WebDAVClient {
    /// 校验重定向目标是否允许继承 Authorization 认证头（严格禁止 HTTPS 降级、跨主机与跨端口）
    static func shouldPreserveAuth(from originalUrl: URL?, to redirectedUrl: URL?) -> Bool {
        guard let originalUrl,
              let redirectedUrl,
              let oldScheme = originalUrl.scheme?.lowercased(),
              let newScheme = redirectedUrl.scheme?.lowercased(),
              newScheme == "http" || newScheme == "https",
              let oldHost = originalUrl.host?.lowercased(),
              let newHost = redirectedUrl.host?.lowercased(),
              !oldHost.isEmpty,
              oldHost == newHost else {
            return false
        }
        if oldScheme == "https" && newScheme != "https" {
            return false
        }
        let oldPort = originalUrl.port ?? (oldScheme == "https" ? 443 : 80)
        let newPort = redirectedUrl.port ?? (newScheme == "https" ? 443 : 80)
        return oldPort == newPort
    }
}

/// LRU WebDAV URLSession 复用池（按认证凭据哈希与自签名 TLS 配置隔离，复用 HTTP/2 与 TLS 会话）
final class WebDAVSessionPool: @unchecked Sendable {
    static let shared = WebDAVSessionPool()

    private struct PoolEntry {
        let key: String
        let session: URLSession
        var lastUsedAt: Date
    }

    private let lock = NSLock()
    private var entries: [PoolEntry] = []
    private let maxSessions = 4

    func session(for config: WebDAVConfig) -> URLSession {
        let key = Self.cacheKey(for: config)
        let now = Date()

        var evicted: URLSession?
        lock.lock()
        if let idx = entries.firstIndex(where: { $0.key == key }) {
            entries[idx].lastUsedAt = now
            let existing = entries[idx].session
            lock.unlock()
            return existing
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 120
        let delegate = WebDAVSessionDelegate(config: config)
        let newSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        if entries.count >= maxSessions,
           let oldestIdx = entries.indices.min(by: { entries[$0].lastUsedAt < entries[$1].lastUsedAt }) {
            evicted = entries[oldestIdx].session
            entries.remove(at: oldestIdx)
        }
        entries.append(PoolEntry(key: key, session: newSession, lastUsedAt: now))
        lock.unlock()

        evicted?.finishTasksAndInvalidate()
        return newSession
    }

    private static func cacheKey(for config: WebDAVConfig) -> String {
        let credDigest = SHA256.hash(data: Data("\(config.trimmedUsername):\(config.password)".utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(config.allowInsecureCertificate ? 1 : 0)|\(credDigest)"
    }
}

private final class WebDAVSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let config: WebDAVConfig

    init(config: WebDAVConfig) {
        self.config = config
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest) async -> URLRequest? {
        guard let targetScheme = request.url?.scheme?.lowercased(),
              targetScheme == "http" || targetScheme == "https" else {
            return nil
        }

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
            if WebDAVClient.shouldPreserveAuth(from: original.url, to: updated.url) {
                if let auth = original.value(forHTTPHeaderField: "Authorization") {
                    updated.setValue(auth, forHTTPHeaderField: "Authorization")
                } else {
                    WebDAVClient.applyBasicAuth(to: &updated, config: config)
                }
            }
        }
        return updated
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let method = challenge.protectionSpace.authenticationMethod
        if method == NSURLAuthenticationMethodServerTrust {
            if config.allowInsecureCertificate,
               let serverTrust = challenge.protectionSpace.serverTrust {
                return (.useCredential, URLCredential(trust: serverTrust))
            }
            return (.performDefaultHandling, nil)
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
            return (.useCredential, credential)
        }

        return (.performDefaultHandling, nil)
    }
}
