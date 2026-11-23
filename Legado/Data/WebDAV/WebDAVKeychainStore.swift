import Foundation
import Security

/// WebDAV 密码安全存储抽象（默认由 iOS Keychain 实现，便于测试替身注入）
public protocol WebDAVSecretStore: Sendable {
    func savePassword(_ password: String, account: String) -> Bool
    func loadPassword(account: String) -> String?
    func deletePassword(account: String)
}

/// 基于 iOS Keychain（kSecClassGenericPassword）的 WebDAV 密码安全仓库
public final class WebDAVKeychainStore: WebDAVSecretStore, @unchecked Sendable {
    public static let shared = WebDAVKeychainStore()

    private let service = "io.github.theliser.legado.webdav"

    public init() {}

    public func savePassword(_ password: String, account: String) -> Bool {
        if password.isEmpty {
            deletePassword(account: account)
            return true
        }
        let encoded = Data(password.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: encoded]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            return false
        }

        var insertItem = query
        insertItem[kSecValueData as String] = encoded
        insertItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insertItem as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    public func loadPassword(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func deletePassword(account: String) {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
