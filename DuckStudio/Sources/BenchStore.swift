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
/// side, as the app having forgotten. It becomes a bench called "My bench", and
/// the old keys are then REMOVED — including the cleartext token, which this
/// first left sitting in the plist it had just been moved out of.
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
    /// The last policy this app loaded on each bench, by bench id.
    ///
    /// THE BENCH DOES NOT SAY WHICH POLICY IS LOADED. `/health` lists what a
    /// bench HOLDS and nothing else, so the only thing that knows what is on
    /// the servos is whichever screen last posted `/policy` — and there are
    /// two of those now, the Control picker and My Microduck's quick actions.
    /// Kept here so the Control tab, opening after a quick action, can show
    /// that policy in its picker WITHOUT posting a swap that would undo it.
    /// Not persisted: a bench restarted between launches holds whatever it
    /// holds, and a record that outlived the bench would be a guess.
    @Published private(set) var lastLoadedPolicy: [UUID: String] = [:]

    func noteLoaded(_ policy: String, on id: UUID) {
        lastLoadedPolicy[id] = policy
    }

    func lastLoaded(for id: UUID?) -> String? {
        id.flatMap { lastLoadedPolicy[$0] }
    }

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
        moved.token = nil
        benches.append(moved)
        selectedID = moved.id
        flush()

        // MOVED, NOT COPIED. This wrote the token into the Keychain and left
        // the cleartext original in `UserDefaults` — in the exact place the
        // Keychain exists to keep it out of, since a device backup copies the
        // plist. A migration that leaves the credential where it found it has
        // not migrated anything.
        //
        // THE READ-BACK IS WHAT MAKES DELETING SAFE. `migratedKey` is already
        // set above, so this runs once and never again; if the Keychain write
        // silently failed, deleting the plist copy would lose the token for
        // good. So the old keys go only after the new home answers with the
        // same value.
        guard !token.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.oldAddressKey)
            return
        }
        BenchKeyStore.save(token, for: moved.id)
        if BenchKeyStore.load(for: moved.id) == token {
            UserDefaults.standard.removeObject(forKey: Self.oldTokenKey)
            UserDefaults.standard.removeObject(forKey: Self.oldAddressKey)
        }
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

// MARK: - the peer for whichever bench is chosen

extension BenchStore {

    /// A peer pointed at the selected bench, or nil when there is no bench.
    ///
    /// IT IS HERE BECAUSE TWO SCREENS NOW NEED THE SAME PEER AND ONLY ONE OF
    /// THEM WROTE IT. `DriveView.makePeer` built this — the address off the
    /// armed endpoint, the errand that reads the token per request — and the
    /// front door needs exactly the same object to say hello with. A second
    /// copy in a second view is two errands that eventually disagree about
    /// something small and load-bearing: which token, read when, on whose
    /// thread. This is the store's answer, because the store is the thing that
    /// already knows which bench is chosen and where its credential lives.
    ///
    /// NIL RATHER THAN A THROW FOR "NO BENCH", AND A THROW FOR EVERYTHING ELSE.
    /// Having no bench is not an error: this app ships with none, and a fresh
    /// install opening the front door would otherwise be met with a refusal for
    /// not yet having done something nobody asked it to do. An address that
    /// will not resolve IS an error, and `BenchEndpoint.resolved()` already has
    /// the paragraph for each way it can be wrong — those go up to the caller
    /// so the screen can print them.
    ///
    /// THE ERRAND IS ALL THE APP TARGET LENDS IT, AND THE TOKEN IS READ PER
    /// REQUEST. Both are `DriveView.makePeer`'s decisions, kept: `BenchPeer`
    /// takes a closure rather than a `URLSession` so the kit stays testable on
    /// a machine with no phone, and a token snapshotted at construction goes
    /// stale the moment somebody replaces it in Settings. One
    /// `SecItemCopyMatching` per call, on the errand's own thread, is what the
    /// old path cost and it never showed in the intent rate.
    @MainActor func makePeer() throws -> BenchPeer? {
        guard let bench = selected else { return nil }
        let address = try armed(bench).resolved()
        let name = bench.name
        let id = bench.id
        let hasToken = bench.hasToken
        return try BenchPeer(address: address, name: name, errand: { call in
            let token = hasToken ? BenchKeyStore.load(for: id) : nil
            return try await URLSession.shared.data(
                for: DuckBench.urlRequest(for: call, token: token)).0
        })
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
