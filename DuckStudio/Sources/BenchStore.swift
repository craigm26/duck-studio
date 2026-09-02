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
///
/// AND THE FIRST ROW IS NOT SAVED AT ALL. This phone has a bench of its own now
/// — MuJoCo compiled to WebAssembly, running in a WebView the app keeps alive,
/// answering the same ten endpoints on a loopback port — so `benches` is a
/// COMPOSED list: `BenchEndpoint.thisPhone` first, then whatever is in
/// `UserDefaults`. Composed rather than inserted-on-load for three reasons, all
/// of them mistakes that were available: a persisted phone row would write down
/// a port that is different on the next launch; a phone row that could be
/// deleted would leave somebody with an app that has physics and no way to
/// reach it; and every screen that already reads `benches` — the Control deck's
/// picker, the run screens, My Microduck — gets the phone for free and stays a
/// zero-line diff, which is what makes this reviewable.
@MainActor
final class BenchStore: ObservableObject {
    /// Every bench, the phone first. NOT what gets written down.
    @Published private(set) var benches: [BenchEndpoint] = []
    /// The ones that are actually persisted — the machines on your network.
    private var saved: [BenchEndpoint] = []
    /// The loopback port the app's own listener came up on, or 0 before it has.
    @Published private(set) var phonePort: Int = 0
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

    /// THIS USED TO SAY "no bench" WAS A REAL STATE, and it is not one any
    /// more. The sentence here was: a phone has an on-device model and does not
    /// have a physics engine, so every caller must handle having no bench. The
    /// second half was a claim about a build rather than about the hardware —
    /// see `PhoneBenchReport.premiseWasAboutABuild` — and now that the app
    /// carries MuJoCo, the list is never empty and `selected` is never nil.
    ///
    /// `makePeer` STILL ANSWERS NIL, and that Optional is kept on purpose: it
    /// is the shape every caller is written against, and one of them is
    /// `DriveView`, which this change is not allowed to touch. What was the
    /// no-bench branch is now unreachable rather than removed.
    ///
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
            saved = salvage.benches
            if salvage.unreadable != 0 {
                UserDefaults.standard.set(salvage.unreadable ?? Self.uncountable,
                                          forKey: Self.unreadKey)
            }
        }
        unreadableNote = Self.pendingNote()
        migrateSingleBenchIfNeeded()
        recompose()
        if let raw = UserDefaults.standard.string(forKey: Self.selectedKey) {
            selectedID = UUID(uuidString: raw)
        }
        // A FRESH INSTALL NOW SELECTS THE PHONE, and that is the whole change
        // for somebody who has never set anything up: the app opens with a
        // bench, and Control has something to drive. Anybody who already had a
        // bench already has a `selectedID` — it is written in `init` the first
        // time and on every change — so nothing moves under them.
        if selectedID == nil { selectedID = benches.first?.id }
    }

    /// Rebuild the visible list: the phone, then the saved machines.
    ///
    /// THE PORT IS STAMPED IN HERE AND NOWHERE ELSE. `BenchEndpoint.thisPhone`
    /// carries `127.0.0.1:0`, which `resolved()` refuses with its own sentence;
    /// `servedOn` is what turns it into an address once the listener has one.
    private func recompose() {
        benches = [BenchEndpoint.thisPhone.servedOn(port: phonePort)] + saved
    }

    /// The app's own bench came up on this port.
    ///
    /// PUBLISHED, BECAUSE A SCREEN OPENED BEFORE THE LISTENER WAS UP HAS TO
    /// REDRAW WHEN IT ARRIVES. The WebView is brought up at launch and the
    /// kernel hands out the port at bind time, so there is a real moment where
    /// the first row exists and cannot be dialled — `PhoneBenchReport.notListening`
    /// is the sentence for it, and this is what ends it.
    func notePhoneBench(port: Int) {
        guard port != phonePort else { return }
        phonePort = port
        recompose()
    }

    /// Bring the one unnamed bench across, once.
    private func migrateSingleBenchIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.migratedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.migratedKey)

        let address = (UserDefaults.standard.string(forKey: Self.oldAddressKey) ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        // Only if it is not already here — a re-run must not duplicate it.
        guard !saved.contains(where: { $0.address == address }) else { return }

        let token = UserDefaults.standard.string(forKey: Self.oldTokenKey) ?? ""
        var moved = BenchEndpoint(name: "My bench", address: address,
                                  hasToken: !token.isEmpty)
        moved.token = nil
        saved.append(moved)
        // THE MIGRATED BENCH IS STILL THE SELECTED ONE, AND THAT IS DELIBERATE
        // NOW THAT THE PHONE IS FIRST IN THE LIST. Somebody upgrading had one
        // bench and was using it; putting a new first row in front of them and
        // silently switching them to it would move their work to a different
        // machine without asking.
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

    /// REFUSED FOR THE PHONE, IN THE STORE AND NOT ONLY IN THE SCREEN. The
    /// settings list does not offer an editor on that row, but a guard that
    /// lives only in a view is a guard the next view forgets — and what this
    /// one prevents is writing a loopback port into `UserDefaults` and dialling
    /// it tomorrow, when it belongs to something else.
    func save(_ bench: BenchEndpoint) {
        guard bench.isEditable else { return }
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
        if let index = saved.firstIndex(where: { $0.id == bench.id }) {
            saved[index] = stored
        } else {
            saved.append(stored)
        }
        recompose()
        if selectedID == nil { selectedID = stored.id }
        flush()
    }

    /// The phone cannot be deleted, because an app with physics and no way to
    /// reach it is worse than an app with no physics.
    func delete(_ bench: BenchEndpoint) {
        guard bench.isEditable else { return }
        BenchKeyStore.clear(for: bench.id)
        saved.removeAll { $0.id == bench.id }
        recompose()
        if selectedID == bench.id { selectedID = benches.first?.id }
        flush()
    }

    /// The bench with its token put back, ready to send.
    func armed(_ bench: BenchEndpoint) -> BenchEndpoint {
        var out = bench
        out.token = bench.hasToken ? BenchKeyStore.load(for: bench.id) : nil
        return out
    }

    /// ONLY THE SAVED ONES ARE WRITTEN. `benches` has the phone at the front
    /// and encoding that list would persist a port the kernel picked this
    /// launch — the app would then dial it next time and reach whatever else
    /// the system had given it in the meantime.
    private func flush() {
        if let data = try? JSONEncoder().encode(saved) {
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
