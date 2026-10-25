import Foundation
import Security

enum Credentials {
    private static let service = "org.regionalsignal.client.credentials"
    static func read(for address: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: address, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String, for address: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: address]
        let update: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(update) { _, new in new }.merging([kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ClientFailure.authentication }
        } else if status != errSecSuccess { throw ClientFailure.authentication }
    }
}
