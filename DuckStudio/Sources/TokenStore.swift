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

    static func save(_ token: String) { KeychainSecret.save(token, service: service, account: account) }
    static func load() -> String? { KeychainSecret.load(service: service, account: account) }
    static func clear() { KeychainSecret.clear(service: service, account: account) }
}

/// The bridge's token, kept the same way and under its own name.
///
/// NOT THE HUGGING FACE TOKEN'S SLOT. The two are different credentials for
/// different doors — one publishes under somebody's name on the internet, the
/// other opens a relay to a robot's servos on a LAN — and a store that held
/// "the token" would have one of them silently overwrite the other.
enum BridgeTokenStore {
    private static let service = "com.duckstudio.bridge-token"
    private static let account = "duck-studio"

    static func save(_ token: String) { KeychainSecret.save(token, service: service, account: account) }
    static func load() -> String? { KeychainSecret.load(service: service, account: account) }
    static func clear() { KeychainSecret.clear(service: service, account: account) }
}

/// One generic-password item, by service and account. The two stores above
/// are the only callers, and the only two names.
enum KeychainSecret {
    static func save(_ token: String, service: String, account: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { clear(service: service, account: account); return }
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

    static func load(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    static func clear(service: String, account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
