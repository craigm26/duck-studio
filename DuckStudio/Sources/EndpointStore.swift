import Foundation
import Security
import StudioKit

/// The models this app can draft with, and which one is chosen.
///
/// KEPT IN `UserDefaults` EXCEPT THE KEYS. An address and a model name are
/// settings; a bearer token is a credential, and credentials go in the
/// Keychain — the same split `TokenStore` already makes for Hugging Face.
@MainActor
final class EndpointStore: ObservableObject {
    @Published private(set) var endpoints: [ModelEndpoint] = []
    /// What could not be read back out of storage, in one sentence, or nil when
    /// everything was.
    ///
    /// THE MODELS SCREEN HAS TO DRAW THIS. It is a person's only notice that
    /// something they configured is gone, and it is a one-time notice: the next
    /// `save()` flushes the salvaged list back over the stored one, and the
    /// rows that could not be read are then gone for good. Losing them is the
    /// right outcome — a row this build cannot read is a row it cannot use —
    /// but losing them WITHOUT SAYING SO is the bug this exists to end.
    @Published private(set) var unreadableNote: String? = nil
    @Published var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.selectedKey) }
    }

    private static let listKey = "duckstudio.modelEndpoints"
    private static let selectedKey = "duckstudio.selectedEndpoint"

    var selected: ModelEndpoint {
        endpoints.first { $0.id == selectedID } ?? .onDevice
    }

    init() {
        // ELEMENT BY ELEMENT, NOT ALL-OR-NOTHING. This was one
        // `try? JSONDecoder().decode([ModelEndpoint].self, …)`, and a JSON
        // array throws for the whole array when a single element is
        // unreadable — so one bad row erased every endpoint a person had, put
        // Apple's on-device model in their place, and said nothing at all.
        // `decodeList` keeps what it can read and counts what it cannot; the
        // counting is in StudioKit where a test asserts the sentence.
        if let data = UserDefaults.standard.data(forKey: Self.listKey) {
            let salvage = ModelEndpoint.decodeList(from: data)
            endpoints = salvage.endpoints
            unreadableNote = salvage.note
        }
        // Apple's is always in the list and cannot be deleted: a device with
        // Apple Intelligence should never end up with nowhere to draft.
        if !endpoints.contains(where: { $0.kind == .appleOnDevice }) {
            endpoints.insert(.onDevice, at: 0)
        }
        if let raw = UserDefaults.standard.string(forKey: Self.selectedKey) {
            selectedID = UUID(uuidString: raw)
        }
        if selectedID == nil || !endpoints.contains(where: { $0.id == selectedID }) {
            selectedID = endpoints.first?.id
        }
    }

    func save(_ endpoint: ModelEndpoint) {
        var stored = endpoint
        // The key lives in the Keychain, never in the plist that backups carry.
        if let key = endpoint.apiKey, !key.isEmpty {
            EndpointKeyStore.save(key, for: endpoint.id)
            stored.apiKey = nil
        }
        if let index = endpoints.firstIndex(where: { $0.id == endpoint.id }) {
            endpoints[index] = stored
        } else {
            endpoints.append(stored)
        }
        flush()
    }

    func delete(_ endpoint: ModelEndpoint) {
        guard endpoint.kind != .appleOnDevice else { return }
        EndpointKeyStore.clear(for: endpoint.id)
        endpoints.removeAll { $0.id == endpoint.id }
        if selectedID == endpoint.id { selectedID = endpoints.first?.id }
        flush()
    }

    /// The endpoint with its key put back, ready to send.
    func armed(_ endpoint: ModelEndpoint) -> ModelEndpoint {
        var armed = endpoint
        armed.apiKey = EndpointKeyStore.load(for: endpoint.id)
        return armed
    }

    private func flush() {
        if let data = try? JSONEncoder().encode(endpoints) {
            UserDefaults.standard.set(data, forKey: Self.listKey)
        }
    }
}

/// One Keychain item per endpoint, keyed by its id.
enum EndpointKeyStore {
    private static let service = "duck-studio.model-endpoint"

    static func save(_ key: String, for id: UUID) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(for id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear(for id: UUID) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ] as CFDictionary)
    }
}
