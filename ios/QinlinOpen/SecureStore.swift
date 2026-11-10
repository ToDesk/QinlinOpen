import Foundation
import Security

/// 极简 Keychain 封装：只存一条通用密码项。
enum Keychain {
    private static let service = "top.rpone.qinlinopen"

    static func save(_ value: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = value
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.save(status)
        }
    }

    static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case save(OSStatus)
    }
}

/// 设备标识：Android 端用的是 ANDROID_ID，这里用一次生成、长期保存在 Keychain 的随机串，
/// 作为 openid 请求头，保证同一台设备上保持不变。
enum DeviceIdentity {
    private static let account = "openid"

    static var openId: String {
        if let data = Keychain.load(account: account),
           let text = String(data: data, encoding: .utf8),
           text.count == 16 {
            return text
        }
        let generated = String((0..<16).map { _ in "0123456789abcdef".randomElement()! })
        _ = try? Keychain.save(Data(generated.utf8), account: account)
        return generated
    }
}
