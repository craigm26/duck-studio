import Foundation
import Security

/// A write token, kept in the Keychain and nowhere else.
///
/// NOT `UserDefaults`, which is a plist in the app container that any backup
/// carries in the clear. A Hugging Face write token can create and delete
/// repositories under somebody's name, so it belongs where the system puts
/// passwords, and it is read only at the moment a request is signed.
enum TokenStore {
    private static let service = "co.huggingface.write-token"
    private static let account = "duck-studio"

    static func save(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { clear(); return }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(trimmed.utf8)
        // The token is useless to anything but this app on this unlocked
        // device, and it never leaves in a backup.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
