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
    /// THE MODELS SCREEN HAS TO DRAW THIS, AND IT WAITS UNTIL SOMEBODY HAS.
    /// It is a person's only notice that something they configured is gone. It
    /// used to live for exactly one launch: the first `save()` or `delete()`
    /// flushed the salvaged list back over the stored one, the unreadable rows
    /// went with it, and the next launch had nothing left to notice — so
    /// anybody who did not happen to open the Models screen in between was told
    /// nothing at all, which is the silent failure this whole thing exists to
    /// end. The count now outlives the flush and every relaunch after it, and
    /// is cleared only by `dismissUnreadableNote()` — a person tapping "Got it"
    /// on the screen that showed it.
    ///
    /// THE ROWS THEMSELVES ARE STILL LOST AT THE NEXT FLUSH, and that part is
    /// deliberate: a row this build cannot read is a row it cannot use. The
    /// sentence says to add them again, because that is the only remedy.
    @Published private(set) var unreadableNote: String? = nil
    @Published var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.selectedKey) }
    }

    private static let listKey = "duckstudio.modelEndpoints"
    private static let selectedKey = "duckstudio.selectedEndpoint"
    /// How many stored endpoints could not be read, kept until somebody has
    /// been told to their face.
    ///
    /// THE COUNT IS STORED, NOT THE SENTENCE. `Salvage.note` is written in
    /// StudioKit where a test asserts it letter by letter, and a sentence
    /// copied into a plist by one build and drawn by the next is a sentence no
    /// test owns any more.
    ///
    /// -1 STANDS FOR "COULD NOT BE COUNTED", because `Salvage.unreadable` is
    /// nil when the stored blob was not a list at all, and nil is not zero:
    /// nobody can say how many endpoints were in something that was never read
    /// as a list.
    private static let unreadKey = "duckstudio.modelEndpoints.unread"
    private static let uncountable = -1

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
            // Only a fresh loss writes; a clean read must not wipe a notice
            // nobody has seen yet, because after the first flush every read is
            // a clean one.
            if salvage.note != nil {
                UserDefaults.standard.set(salvage.unreadable ?? Self.uncountable,
                                          forKey: Self.unreadKey)
            }
        }
        unreadableNote = Self.pendingNote()
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

    /// The outstanding notice, recomposed by StudioKit from the count that was
    /// written down. nil when there is nothing owed.
    private static func pendingNote() -> String? {
        guard let stored = UserDefaults.standard.object(forKey: unreadKey) as? Int else {
            return nil
        }
        // ANNOTATED, AND IT HAS TO BE: a bare `nil` in a ternary has no
        // contextual type to be nil OF, and this is exactly the kind of thing
        // `swiftc -parse` waves through and a real compiler stops.
        let counted: Int? = stored == uncountable ? nil : stored
        return ModelEndpoint.Salvage(endpoints: [], unreadable: counted).note
    }

    /// Somebody has read it. This is the ONLY thing that clears it — not a
    /// save, not a delete, not the next launch.
    func dismissUnreadableNote() {
        UserDefaults.standard.removeObject(forKey: Self.unreadKey)
        unreadableNote = nil
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

    /// Remove an endpoint — and, for a downloaded model, the weights with it.
    ///
    /// THE ROW IS NOT THE ONLY THING THAT TAKES SPACE. This removed the Keychain
    /// item and the list entry and nothing else, which is right for an address
    /// and wrong for three gigabytes of weights: the list would say the model
    /// was gone while the phone was still full of it, and nothing in the app
    /// would offer to free it. A person who deletes something expects the space
    /// back.
    func delete(_ endpoint: ModelEndpoint) {
        guard endpoint.kind != .appleOnDevice else { return }
        if endpoint.kind == .downloadedMLX {
            PhoneModelFiles.delete(endpoint.model)
        }
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
