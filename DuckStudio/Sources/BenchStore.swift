import Foundation
import Security
import StudioKit

/// The benches this app can run things on, and which one is chosen.
///
/// DELIBERATELY THE SAME SHAPE AS `EndpointStore`, because it is the same
/// problem: a named list in `UserDefaults`, one selected, and the credential in
/// the Keychain rather than in the plist a device backup copies. Two designs for
/// "a saved connection" is how one of them ends up missing the salvage the other
/// learned to do.
///
/// IT MIGRATES THE ONE BENCH THERE USED TO BE. Every bench screen read a single
/// `@AppStorage("duckbench.address")` string, so anybody who had set one up had
/// exactly one and it had no name. Shipping a list without bringing that across
/// would silently empty a working setup on upgrade — which reads, from the other
/// side, as the app having forgotten. It becomes a bench called "My bench" and
/// the old keys are left alone.
@MainActor
final class BenchStore: ObservableObject {
    @Published private(set) var benches: [BenchEndpoint] = []
    @Published private(set) var unreadableNote: String? = nil
    @Published var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.selectedKey) }
    }

    private static let listKey = "duckstudio.benches"
    private static let selectedKey = "duckstudio.selectedBench"
    private static let unreadKey = "duckstudio.benches.unread"
    private static let migratedKey = "duckstudio.benches.migrated"
    private static let uncountable = -1

    /// The legacy single-bench keys. Read once, never written again.
    private static let oldAddressKey = "duckbench.address"
    private static let oldTokenKey = "duckbench.token"

    /// The chosen bench, or nil when nothing is set up yet. UNLIKE THE MODEL
    /// STORE THERE IS NO FALLBACK: a phone has an on-device model and does not
    /// have a physics engine, so "no bench" is a real state every caller has to
    /// handle rather than something to paper over with a default.
    var selected: BenchEndpoint? {
        benches.first { $0.id == selectedID } ?? benches.first
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.listKey) {
            let salvage = BenchEndpoint.decodeList(from: data)
            benches = salvage.benches
            if salvage.unreadable != 0 {
                UserDefaults.standard.set(salvage.unreadable ?? Self.uncountable,
                                          forKey: Self.unreadKey)
            }
        }
        unreadableNote = Self.pendingNote()
        migrateSingleBenchIfNeeded()
        if let raw = UserDefaults.standard.string(forKey: Self.selectedKey) {
            selectedID = UUID(uuidString: raw)
        }
        if selectedID == nil { selectedID = benches.first?.id }
    }

    /// Bring the one unnamed bench across, once.
    private func migrateSingleBenchIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.migratedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.migratedKey)

        let address = (UserDefaults.standard.string(forKey: Self.oldAddressKey) ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        // Only if it is not already here — a re-run must not duplicate it.
        guard !benches.contains(where: { $0.address == address }) else { return }

        let token = UserDefaults.standard.string(forKey: Self.oldTokenKey) ?? ""
        var moved = BenchEndpoint(name: "My bench", address: address,
                                  hasToken: !token.isEmpty)
        if !token.isEmpty { BenchKeyStore.save(token, for: moved.id) }
        moved.token = nil
        benches.append(moved)
        selectedID = moved.id
        flush()
    }

    private static func pendingNote() -> String? {
        guard let stored = UserDefaults.standard.object(forKey: unreadKey) as? Int else {
            return nil
        }
        switch stored {
        case 0: return nil
        case uncountable:
            return "The saved list of benches could not be read at all, so this app has none. "
                 + "Add them again — nothing else was affected."
        case 1:
            return "One saved bench could not be read and is gone. Add it again; the others are "
                 + "fine."
        default:
            return "\(stored) saved benches could not be read and are gone. Add them again; the "
                 + "others are fine."
        }
    }

    func dismissUnreadableNote() {
        UserDefaults.standard.removeObject(forKey: Self.unreadKey)
        unreadableNote = nil
    }

    func save(_ bench: BenchEndpoint) {
        var stored = bench
        if let token = bench.token, !token.isEmpty {
            BenchKeyStore.save(token, for: bench.id)
            stored.hasToken = true
        } else if bench.token != nil {
            // An emptied field is a deliberate removal, not an absence.
            BenchKeyStore.clear(for: bench.id)
            stored.hasToken = false
        }
        stored.token = nil
        if let index = benches.firstIndex(where: { $0.id == bench.id }) {
            benches[index] = stored
        } else {
            benches.append(stored)
        }
        if selectedID == nil { selectedID = stored.id }
        flush()
    }

    func delete(_ bench: BenchEndpoint) {
        BenchKeyStore.clear(for: bench.id)
        benches.removeAll { $0.id == bench.id }
        if selectedID == bench.id { selectedID = benches.first?.id }
        flush()
    }

    /// The bench with its token put back, ready to send.
    func armed(_ bench: BenchEndpoint) -> BenchEndpoint {
        var out = bench
        out.token = bench.hasToken ? BenchKeyStore.load(for: bench.id) : nil
        return out
    }

    private func flush() {
        if let data = try? JSONEncoder().encode(benches) {
            UserDefaults.standard.set(data, forKey: Self.listKey)
        }
    }
}

/// One Keychain item per bench, keyed by its id.
enum BenchKeyStore {
    private static let service = "duck-studio.bench"

    static func save(_ token: String, for id: UUID) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(token.utf8)
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
