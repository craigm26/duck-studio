import Foundation
import Crypto
import DuckKit
import DuckEvidence

/// Everything Microduck Studio currently holds, and what each thing is.
///
/// IDENTITY IS THE WHOLE PROBLEM HERE, and it has two answers rather than one.
/// A policy that loads is identified by `DuckPolicy.fingerprint` — a digest of
/// its parameters — so the same network downloaded twice under two filenames is
/// one entry, and `walking_v2.onnx` that turns out to be byte-identical to
/// `walking.onnx` does not clutter the list. But a file that does NOT load has
/// no parameters to digest, and the refusal screen is the app's best feature, so
/// those files must still be keepable. They are identified by the digest of the
/// file itself.
///
/// The two rules cannot be merged, and the difference is not cosmetic: file
/// digests distinguish exports that are the same network (different producer
/// string, different node order), while parameter digests cannot describe a
/// file that has no readable parameters. Using file digests throughout would
/// show one network three times; using parameter digests throughout would make
/// broken files unstorable. So identity carries which rule produced it, and the
/// UI can say so.
///
/// NOTHING IS FETCHED OR PARSED IN A PROPERTY GETTER. Reading a directory of
/// 800 KB networks is real work; `reload()` is explicit and the entries it
/// produces are values.
public struct PolicyLibrary: Sendable {

    /// Where an entry came from. Ordering depends on this, so it is a rank as
    /// well as a label.
    public enum Origin: Equatable, Sendable, Comparable {
        /// Shipped inside the app.
        case bundled
        /// Opened from Files, AirDrop, or another app.
        case imported
        /// Fetched from a URL the person typed.
        case fetched(host: String)
        /// Made on this phone by the tuning search, out of the named policy.
        ///
        /// A FOURTH ORIGIN AND NOT A FLAVOUR OF `imported`, because it answers
        /// a question the other three cannot. Every other entry in this library
        /// arrived: somebody shipped it, sent it, or downloaded it, and the
        /// weights were somebody else's before they were here. A tuned policy
        /// was MADE here — its digest exists nowhere else in the world, nobody
        /// else can reproduce it without the seed, and it has never been run on
        /// a robot by anyone. Filing it as "Imported" would put the one network
        /// in the list with no outside provenance in the same shelf as the ones
        /// whose provenance is the point.
        ///
        /// IT CARRIES WHAT IT WAS MADE FROM, because that is the only part of
        /// it anybody else has ever measured. The walk is the base policy's;
        /// this changed a per-joint gain and trim.
        case tuned(base: String)

        var rank: Int {
            switch self {
            case .bundled:  return 0
            case .imported: return 1
            case .fetched:  return 2
            // LAST, WHICH IS ALSO NEWEST. A tuned policy is the only kind this
            // app can produce, so it did not exist at the last launch and
            // putting it at the bottom is where somebody will look for a thing
            // they just made.
            case .tuned:    return 3
            }
        }

        public static func < (a: Origin, b: Origin) -> Bool {
            if a.rank != b.rank { return a.rank < b.rank }
            if case .fetched(let x) = a, case .fetched(let y) = b { return x < y }
            if case .tuned(let x) = a, case .tuned(let y) = b { return x < y }
            return false
        }

        public var label: String {
            switch self {
            case .bundled:  return "Bundled"
            case .imported: return "Imported"
            case .fetched(let host): return "From \(host)"
            case .tuned(let base): return "Tuned here from \(base)"
            }
        }

        /// Whose weights these are, in the word a list row has space for.
        ///
        /// "YOU" IS ONLY EVER TRUE OF ONE ORIGIN, and it is worth a field
        /// rather than a guess at a call site. A bundled or fetched policy was
        /// trained by somebody with a GPU cluster and a month; an imported one
        /// might have been trained by anybody. A tuned one is the only entry
        /// whose particular numbers came out of a search this person ran on
        /// this phone — and even then only the residual is theirs, which is
        /// what `caveat` is for.
        public var author: String {
            switch self {
            case .bundled, .fetched: return "somebody else"
            case .imported:          return "whoever sent it"
            case .tuned:             return "you"
            }
        }

        /// The thing a row must say beside an entry, or nil when the origin
        /// carries no warning of its own.
        ///
        /// YELLOW, NOT RED, AND THE DIFFERENCE IS THE CLAIM. A refusal is red
        /// because the file will not run. This will run — it is a valid policy
        /// by every check this app makes — and what is wrong with it is that
        /// nobody has ever run it anywhere but a simulator on a phone. That is
        /// a caution, and a caution that shouted would be lumped in with the
        /// errors and stop being read.
        public var caveat: String? {
            switch self {
            case .bundled, .imported, .fetched: return nil
            case .tuned(let base):
                return "Made on this phone by searching a per-joint gain and trim and folding it "
                     + "into \(base). Nothing was trained: the walk is still the base policy's. "
                     + "Every number behind it came out of a simulator, and it has never run on "
                     + "hardware."
            }
        }
    }

    /// How an entry's identity was established — because the two rules mean
    /// different things and a person comparing two entries deserves to know
    /// which question was answered.
    public enum Identity: Equatable, Sendable {
        /// A digest of the trained parameters. Two entries with the same value
        /// ARE the same network, whatever the files look like.
        case parameters(String)
        /// A digest of the file. Used only when the file will not load, so
        /// there are no parameters to digest.
        case fileOnly(String)

        public var value: String {
            switch self {
            case .parameters(let v), .fileOnly(let v): return v
            }
        }

        public var isNetworkIdentity: Bool {
            if case .parameters = self { return true }
            return false
        }
    }

    /// WHERE A TITLE CAME FROM, which is the whole reason it is safe to show
    /// one. Every rung is a different kind of claim — a person's word, a
    /// checked fact about the weights, a stranger's claim about them, what was
    /// on the envelope, or nothing at all — and the screen says which.
    public enum TitleSource: Equatable, Sendable {
        case typed, release, manifest, fileName, digest
    }

    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: String { identity.value }

        /// The name the BYTES arrived under, and the only name anything MATCHES
        /// on: the bundle lookup, the action-scale kind, the clip link, the
        /// export.
        public let fileName: String

        /// What a person reads. NEVER A KEY — see
        /// `scripts/check_no_policy_name_keys.sh`.
        public let title: String
        public let titleSource: TitleSource

        public let origin: Origin
        public let identity: Identity
        public let byteCount: Int
        public let report: PolicyReport

        /// False for a policy persisted before nameplates existed: its host
        /// cannot be recovered and the screen must not invent one.
        public let arrivalWasRecorded: Bool

        public init(fileName: String, title: String, titleSource: TitleSource,
                    origin: Origin, identity: Identity, byteCount: Int,
                    report: PolicyReport, arrivalWasRecorded: Bool = false) {
            self.fileName = fileName
            self.title = title
            self.titleSource = titleSource
            self.origin = origin
            self.identity = identity
            self.byteCount = byteCount
            self.report = report
            self.arrivalWasRecorded = arrivalWasRecorded
        }

        /// The sixteen characters a person compares at a glance.
        public var shortIdentity: String { String(identity.value.prefix(16)) }

        /// True when this file can actually drive the robot.
        public var isRunnable: Bool { report.outcome == .runnable }

        /// The same entry under a new title. A rename touches NOTHING else —
        /// not the identity, not the file name, not the report — which is
        /// exactly what makes it a thing that cannot break a match.
        func retitled(_ title: String, _ source: TitleSource) -> Entry {
            Entry(fileName: fileName, title: title, titleSource: source,
                  origin: origin, identity: identity, byteCount: byteCount,
                  report: report, arrivalWasRecorded: arrivalWasRecorded)
        }
    }

    public private(set) var entries: [Entry] = []

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    // MARK: - reading files in

    /// Read one file into an entry. Never throws for a bad policy: a file that
    /// cannot be parsed is a thing this app has something to say about, not an
    /// error to swallow.
    ///
    /// KEPT AT THREE ARGUMENTS because it is the shape every caller that has no
    /// sidecar to offer already uses, and because a parameter that can be
    /// omitted is a parameter that will be.
    public static func entry(for data: Data, name: String, origin: Origin) -> Entry {
        entry(for: data, name: name, origin: origin,
              nameplate: nil, manifest: nil,
              // A BUNDLED FILE'S ARRIVAL IS RECORDED BY THE BUNDLE. It came
              // with the app, which is not a fact that can go missing, so the
              // "we did not write down where this came from" footnote must
              // never appear beside one.
              arrivalWasRecorded: origin == .bundled)
    }

    /// The full ladder: what the file is called, what it should be titled, and
    /// which of those two answers each screen is allowed to use.
    ///
    /// - Parameters:
    ///   - name: the name on disk. For anything in the container that is
    ///     `<identity>.onnx`, which is why `nameplate` exists.
    ///   - nameplate: what was written down when the file arrived.
    ///   - manifest: the author's own claim about their policy.
    ///   - arrivalWasRecorded: whether this app was keeping arrival notes when
    ///     this one came in. False is not a defect; it is every policy imported
    ///     before build 47, and the screen says so rather than inventing a host.
    public static func entry(for data: Data, name: String, origin: Origin,
                             nameplate: PolicyNameplate?, manifest: PolicyManifest?,
                             arrivalWasRecorded: Bool) -> Entry {
        entry(for: data, name: name, origin: origin, nameplate: nameplate,
              authorName: manifest?.name, arrivalWasRecorded: arrivalWasRecorded)
    }

    /// The same ladder for a caller that has the author's WORD but not a whole
    /// manifest object.
    ///
    /// THE COMMUNITY INSTALLER IS THAT CALLER. It has already decoded the
    /// manifest to draw the browse screen, and reaching back through a second
    /// decode to hand the same name over would be two chances for the two
    /// screens to disagree about what a policy is called.
    public static func entry(for data: Data, name: String, origin: Origin,
                             nameplate: PolicyNameplate?, authorName: String?,
                             arrivalWasRecorded: Bool) -> Entry {
        entry(for: data, name: name, origin: origin, nameplate: nameplate,
              authorName: authorName, arrivalWasRecorded: arrivalWasRecorded,
              knowing: weighed(data))
    }

    /// What one walk of the bytes establishes: which identity rule applies, and
    /// whether these exact parameters are one of Pollen's nine.
    ///
    /// ONE PARSE PER FILE, AND THE TYPE IS WHAT ENFORCES IT. `read` needs the
    /// identity BEFORE it can find a policy's sidecars, and the entry factory
    /// needs it again — so passing it in is what stops a nine-policy `reload()`
    /// costing eighteen ONNX loads. `reload()` runs at init and after every
    /// removal, which is exactly when nobody is willing to wait.
    struct Weighed {
        let identity: Identity
        let release: DuckOfficialPolicies.Release?
    }

    static func weighed(_ data: Data) -> Weighed {
        guard let policy = try? DuckPolicy.load(from: data) else {
            return Weighed(identity: .fileOnly(fileDigest(data)), release: nil)
        }
        if case .released(let matched) = DuckOfficialPolicies.standing(of: policy) {
            return Weighed(identity: .parameters(policy.fingerprint), release: matched)
        }
        return Weighed(identity: .parameters(policy.fingerprint), release: nil)
    }

    static func entry(for data: Data, name: String, origin: Origin,
                      nameplate: PolicyNameplate?, authorName: String?,
                      arrivalWasRecorded: Bool, knowing weighed: Weighed) -> Entry {
        let identity = weighed.identity
        let release = weighed.release

        // THE PLATE KNOWS WHAT THE ENVELOPE SAID; the directory only knows what
        // this app filed it under — BUT ONLY WHERE THE DIRECTORY'S NAME CARRIES
        // NO INFORMATION, which is a container read (`persist` files weights as
        // `<64-hex identity>.onnx`). A bundled file's name, like its origin, is
        // a fact about the bundle, and a sidecar written for an imported copy
        // of the same weights may not contradict it: `fileName` is the only
        // name anything MATCHES on, and a plate that replaced a bundled name
        // broke every clip, kind and export keyed on it.
        let recorded = PolicyNaming.isDigestName(name) ? (nameplate?.fileName ?? name) : name
        let fileName = repairedFileName(recorded, identity: identity, release: release)

        // A NAMEPLATE'S HOST OVERRIDES `.imported` AND NOTHING ELSE. A bundled
        // file's origin is a fact about the bundle, and a sidecar sitting in
        // the container may not contradict it; a fetched origin already knows
        // its host from the call that fetched it.
        var origin = origin
        if origin == .imported, let host = nameplate?.originHost {
            origin = .fetched(host: host)
        }

        // BUILT FROM THE FILE NAME ONLY, so a title change can never make a
        // verdict stale. There is no second headline field and nothing
        // recomposes one at draw time.
        let report = PolicyReport.of(data, name: fileName)

        let (title, source) = titleLadder(typed: nameplate?.title, release: release,
                                          manifestName: authorName,
                                          fileName: fileName, identity: identity)
        return Entry(fileName: fileName, title: title, titleSource: source,
                     origin: origin, identity: identity, byteCount: data.count,
                     report: report, arrivalWasRecorded: arrivalWasRecorded)
    }

    /// THE FINGERPRINT ALSO REPAIRS THE FILE NAME, and only where there is
    /// nothing to lose.
    ///
    /// A policy persisted before nameplates comes back called
    /// `<64 hex>.onnx`, and that name matches nothing: `BenchView`'s action
    /// scale falls to walking's 0.9 for a roulade that declares 1.0, and a
    /// policy's own recordings stop being listed under it. When the weights are
    /// bit-identical to one of Pollen's nine, the release's own filename is a
    /// better answer than a hash and costs nothing, because there was no name
    /// there to overwrite.
    ///
    /// THE `.parameters` GUARD MATTERS. A `.fileOnly` digest means the file
    /// would not load, so there are no parameters that could have matched —
    /// repairing there would name an unloadable file after a Pollen network.
    static func repairedFileName(_ name: String, identity: Identity,
                                 release: DuckOfficialPolicies.Release?) -> String {
        guard PolicyNaming.isDigestName(name), identity.isNetworkIdentity,
              let release else { return name }
        return release.filename
    }

    /// The five rungs, in this order. Each one is a different kind of claim and
    /// the order is the order of how much this app can stand behind them.
    static func titleLadder(typed: String?, release: DuckOfficialPolicies.Release?,
                            manifestName: String?, fileName: String,
                            identity: Identity) -> (String, TitleSource) {
        // 1. A person's own word beats everything.
        if let typed {
            let cleaned = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return (cleaned, .typed) }
        }
        // 2. A CHECKED FACT ABOUT THE WEIGHTS BEATS A STRANGER'S CLAIM ABOUT
        // THEM. A repo republishing `alpha_walking` as "SuperWalk" does not get
        // to relabel Pollen's network in somebody's library — and the title
        // then agrees with the provenance pill and with what the bench matches.
        if let release {
            return (PolicyNaming.title(fromFileName: release.filename), .release)
        }
        // 3. The author's word for their own policy.
        if let manifestName {
            let stem = PolicyNaming.title(fromFileName: manifestName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stem.isEmpty, !PolicyNaming.isDigestName(stem) { return (stem, .manifest) }
        }
        // 4. What was on the envelope.
        if !PolicyNaming.isDigestName(fileName) {
            let stem = PolicyNaming.title(fromFileName: fileName)
            if !stem.isEmpty { return (stem, .fileName) }
        }
        // 5. THE REPORTED CASE. It says the app does not know, and the eight
        // characters are enough to tell two of them apart in a list.
        return ("Unnamed policy \(String(identity.value.prefix(8)))", .digest)
    }

    /// Add an entry, or decline because the same thing is already held.
    ///
    /// FIRST ONE WINS, and that is deliberate: the bundled seed loads first, so
    /// a person who imports a copy of a policy the app already ships keeps
    /// seeing it labelled "Bundled" rather than watching a familiar entry
    /// silently change origin. Returns whether it was added, so the UI can say
    /// "already in your library" instead of appearing to do nothing.
    @discardableResult
    public mutating func add(_ entry: Entry) -> Bool {
        guard !entries.contains(where: { $0.identity == entry.identity }) else { return false }
        entries.append(entry)
        entries.sort(by: Self.ordering)
        return true
    }

    /// Swap an entry for its retitled self, keeping the list sorted.
    ///
    /// A RENAME COSTS NO `reload()`, and therefore no re-parse of nine ONNX
    /// files. The only thing that changed is a string a screen draws.
    public mutating func replace(_ entry: Entry) {
        guard let index = entries.firstIndex(where: { $0.identity == entry.identity }) else {
            return
        }
        entries[index] = entry
        entries.sort(by: Self.ordering)
    }

    /// Deterministic and stable: origin rank, then title, then identity.
    ///
    /// The last key is the one that matters. Two different networks exported
    /// under the same filename — which happens constantly during a training run
    /// — would otherwise sort by a tie nothing breaks, and the list would
    /// reshuffle between launches for no visible reason. It is also what makes
    /// a rename reorder DETERMINISTICALLY rather than shuffling two entries
    /// somebody gave the same name.
    static func ordering(_ a: Entry, _ b: Entry) -> Bool {
        if a.origin != b.origin { return a.origin < b.origin }
        if a.title != b.title {
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        return a.identity.value < b.identity.value
    }

    // MARK: - what to say when one arrives

    /// The line the Behaviours list shows after an import.
    ///
    /// IT NAMES WHAT THE PERSON WILL SEE IN THE LIST, which after a rename is
    /// not the file name they just handed over. Being told "policy.onnx is
    /// already in your library" while the row says "Flamingo cycle" is the app
    /// answering a different question from the one that was asked.
    public static func arrivalMessage(added: Bool, incoming: Entry, held: Entry?) -> String {
        guard !added else { return "Added \(incoming.title)." }
        guard let held else { return "\(incoming.title) is already in your library." }
        if held.titleSource == .typed {
            return "You already have these weights. They are in your library as \(held.title)."
        }
        return "\(held.title) is already in your library."
    }

    /// Labels for a picker, so two policies a person called the same thing are
    /// still two rows they can tell apart.
    ///
    /// THE SUFFIX GOES ONLY ON THE ONES THAT COLLIDE. Eight hex characters
    /// beside every row is a picker that has stopped showing names; beside the
    /// two that need it, it is the only thing that distinguishes them.
    public static func pickerLabels(_ entries: [Entry]) -> [String: String] {
        var counts: [String: Int] = [:]
        for entry in entries { counts[entry.title, default: 0] += 1 }
        var labels: [String: String] = [:]
        for entry in entries {
            labels[entry.id] = (counts[entry.title] ?? 0) > 1
                ? "\(entry.title) · \(String(entry.identity.value.prefix(8)))"
                : entry.title
        }
        return labels
    }

    // MARK: - the seed and the container

    /// Load every `.onnx` in a directory, in filename order so the seed is the
    /// same on every launch.
    ///
    /// - Parameter nameplateDirectory: where the sidecars live. It is a
    ///   SEPARATE argument from `directory` because a bundled policy's
    ///   nameplate cannot live beside the weights — the app bundle is read-only
    ///   — and a nickname on `alpha_walking.onnx` has to attach somewhere. The
    ///   container is that somewhere, and the plate is keyed by identity, so it
    ///   finds its policy whichever directory the bytes came out of.
    public static func read(directory: URL, origin: Origin,
                            nameplatesIn nameplateDirectory: URL? = nil,
                            using fileManager: FileManager = .default) -> [Entry] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents
            // THE SIDECARS ARE INVISIBLE HERE, and this is why they are files
            // with their own extensions rather than anything cleverer.
            .filter { $0.pathExtension.lowercased() == "onnx" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                // ONE WALK OF THE BYTES, HANDED ON. The identity is what finds
                // the sidecars, and re-deriving it inside the factory would
                // parse every policy in the directory twice.
                let weighed = weighed(data)
                let identity = weighed.identity.value
                let plate = nameplateDirectory.flatMap {
                    nameplate(forIdentity: identity, in: $0, using: fileManager)
                }
                let manifest = nameplateDirectory.flatMap {
                    storedManifest(forIdentity: identity, in: $0, using: fileManager)
                }
                return entry(for: data, name: url.lastPathComponent, origin: origin,
                             nameplate: plate, authorName: manifest?.name,
                             arrivalWasRecorded: plate?.arrivalRecorded ?? (origin == .bundled),
                             knowing: weighed)
            }
    }

    /// Seed from the bundle, then add anything previously imported.
    ///
    /// BOTH READS LOOK IN THE CONTAINER FOR NAMEPLATES. A bundled policy is
    /// renamable, and it has to be: the split between what a file is called and
    /// what a person calls it is what makes renaming safe at all, so refusing
    /// it for nine of the entries would be a rule with no reason behind it.
    public static func assembled(bundled: URL?, container: URL?,
                                 using fileManager: FileManager = .default) -> PolicyLibrary {
        var library = PolicyLibrary()
        if let bundled {
            for entry in read(directory: bundled, origin: .bundled,
                              nameplatesIn: container, using: fileManager) {
                library.add(entry)
            }
        }
        if let container {
            for entry in read(directory: container, origin: .imported,
                              nameplatesIn: container, using: fileManager) {
                library.add(entry)
            }
        }
        return library
    }

    /// The identity a set of bytes would be filed under, without building a
    /// whole entry for it. `read` needs it before it can look up a sidecar.
    static func identityValue(for data: Data) -> String {
        weighed(data).identity.value
    }

    // MARK: - the nameplate

    static func nameplateURL(forIdentity id: String, in container: URL) -> URL {
        container.appendingPathComponent("\(id).nameplate.json")
    }

    /// The nameplate stored for a set of weights, if one was.
    public static func nameplate(forIdentity id: String, in container: URL,
                                 using fileManager: FileManager = .default) -> PolicyNameplate? {
        let url = nameplateURL(forIdentity: id, in: container)
        guard let data = try? Data(contentsOf: url) else { return nil }
        // A PLATE THAT WILL NOT DECODE IS A PLATE THAT IS NOT THERE. It is a
        // label; losing one costs a name and nothing else, and throwing here
        // would take the policy down with it.
        return try? PolicyNameplate.decode(data)
    }

    @discardableResult
    public static func persistNameplate(_ plate: PolicyNameplate, forIdentity id: String,
                                        into container: URL,
                                        using fileManager: FileManager = .default) -> Bool {
        do {
            try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
            try plate.encoded().write(to: nameplateURL(forIdentity: id, in: container))
            return true
        } catch {
            return false
        }
    }

    static func storedManifest(forIdentity id: String, in container: URL,
                               using fileManager: FileManager = .default) -> PolicyManifest? {
        let url = container.appendingPathComponent("\(id).manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PolicyManifest.decode(data)
    }

    /// The host a fetched origin names, or nil for every other origin.
    static func host(of origin: Origin) -> String? {
        if case .fetched(let host) = origin { return host }
        return nil
    }

    /// Change what a policy is CALLED, and nothing else.
    ///
    /// `nil` clears back to the recomputed ladder. Writes ONLY the nameplate:
    /// the identity, the weights' path, the manifest sidecar, the file name and
    /// the report are untouched, which is exactly what makes a rename a thing
    /// that cannot break a match.
    @discardableResult
    public static func rename(_ entry: Entry, to typed: String?, in container: URL,
                              using fileManager: FileManager = .default)
        -> Result<Entry, PolicyTitleRule.Refusal> {
        var cleaned: String?
        if let typed {
            switch PolicyTitleRule.check(typed) {
            case .success(let ok): cleaned = ok
            case .failure(let refusal): return .failure(refusal)
            }
        }
        let existing = nameplate(forIdentity: entry.id, in: container, using: fileManager)
        // THE PLATE SURVIVES A CLEARED NAME, because it is also where the file
        // name lives. Deleting it to clear a title would throw away the one
        // record of what the file was called.
        // A RENAME OBSERVES NOTHING ABOUT WHERE THE BYTES CAME FROM, so the
        // plate it writes for a legacy entry keeps saying so.
        let plate = PolicyNameplate(fileName: existing?.fileName ?? entry.fileName,
                                    title: cleaned,
                                    originHost: existing?.originHost ?? host(of: entry.origin),
                                    arrivalRecorded: existing?.arrivalRecorded ?? false)
        persistNameplate(plate, forIdentity: entry.id, into: container, using: fileManager)

        let release: DuckOfficialPolicies.Release?
        if case .released(let matched) = DuckOfficialPolicies.standing(ofFingerprint: entry.id),
           entry.identity.isNetworkIdentity {
            release = matched
        } else {
            release = nil
        }
        let manifestName = storedManifest(forIdentity: entry.id, in: container,
                                          using: fileManager)?.name
        let (title, source) = titleLadder(typed: cleaned, release: release,
                                          manifestName: manifestName,
                                          fileName: entry.fileName, identity: entry.identity)
        return .success(entry.retitled(title, source))
    }

    /// Copy an imported file into the container so it survives the next launch.
    ///
    /// The stored filename is the identity, not the original name: two people
    /// send you `policy.onnx` and the second must not overwrite the first. The
    /// display name is what was typed on the outside of the envelope; the
    /// identity is what is in it.
    /// Where a policy's manifest is kept beside its weights.
    ///
    /// KEYED BY IDENTITY, LIKE THE WEIGHTS. A manifest belongs to a specific
    /// set of weights, and storing it under the display name would attach one
    /// person's `policy.onnx` manifest to another's.
    static func manifestURL(for entry: Entry, in container: URL) -> URL {
        container.appendingPathComponent("\(entry.identity.value).manifest.json")
    }

    /// Keep a policy's manifest with it.
    ///
    /// THE MANIFEST WAS BEING READ AND THEN THROWN AWAY. The community browser
    /// fetched it, showed the command layout and the author's caveats, and then
    /// installed the `.onnx` alone — so the moment a policy was in the library,
    /// everything the manifest knew was gone. The most expensive loss is
    /// `action_scale`: without it the bench guesses from the FILE NAME, matches
    /// nothing for a community policy, and silently applies walking's 0.9. A
    /// policy declaring 1.0 is then driven 10% short, which is the same error
    /// `BenchView` already documents for roulade.
    @discardableResult
    public static func persistManifest(_ data: Data, for entry: Entry, into container: URL,
                                       using fileManager: FileManager = .default) -> Bool {
        do {
            try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
            try data.write(to: manifestURL(for: entry, in: container))
            return true
        } catch {
            return false
        }
    }

    /// The manifest stored with a policy, if one was.
    public static func manifest(for entry: Entry, in container: URL,
                                using fileManager: FileManager = .default) -> PolicyManifest? {
        let url = manifestURL(for: entry, in: container)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PolicyManifest.decode(data)
    }

    /// The action scale a policy DECLARED, as opposed to one inferred from its
    /// file name.
    ///
    /// A NAMED ACCESSOR RATHER THAN A FIELD READ, because the app-target gate
    /// forbids `actionScale` there and is right to: the number is a fact about
    /// the robot, and a view reaching into a manifest for it is a view one edit
    /// away from doing arithmetic with it. Nil means the policy came with no
    /// manifest, and the caller should fall back to the guess — which is what
    /// `DuckGait.stages` does with a nil `scale`.
    public static func declaredScale(for entry: Entry, in container: URL,
                                     using fileManager: FileManager = .default) -> Double? {
        manifest(for: entry, in: container, using: fileManager)?.actionScale
    }

    /// Take a policy back out of the container.
    ///
    /// BY IDENTITY, THE SAME WAY IT WENT IN. `persist` stores under the digest
    /// rather than the display name precisely so two files called `policy.onnx`
    /// cannot collide, and a removal that went looking for the display name
    /// would delete the wrong one — or, more often, nothing at all while
    /// reporting success.
    ///
    /// - Returns: whether a file was actually removed. False for a bundled
    ///   policy, whose bytes are inside the read-only app bundle.
    @discardableResult
    public static func remove(_ entry: Entry, from container: URL,
                              using fileManager: FileManager = .default) -> Bool {
        guard entry.isRemovable else { return false }
        let url = container.appendingPathComponent("\(entry.identity.value).onnx")
        guard fileManager.fileExists(atPath: url.path) else { return false }
        do {
            try fileManager.removeItem(at: url)
            // THE MANIFEST GOES WITH IT. Leaving it behind would attach the
            // departed policy's command layout and action scale to the next
            // file that happens to hash the same — which is nothing, in
            // practice, but it is also just litter nobody can see or clear.
            try? fileManager.removeItem(at: manifestURL(for: entry, in: container))
            // AND SO DOES THE NAME, for the same reason and one more: a name is
            // the most personal thing in the container, and an app that keeps
            // one after you delete the thing it was on is keeping something you
            // asked it to throw away.
            try? fileManager.removeItem(
                at: nameplateURL(forIdentity: entry.identity.value, in: container))
            return true
        } catch {
            return false
        }
    }

    /// Write the bytes, the nameplate and — when one came with them — the
    /// manifest, in ONE call.
    ///
    /// THE ROOT FIX. `persist` wrote `<identity>.onnx` and nothing else, so the
    /// name a file arrived under was never written down anywhere and the next
    /// `reload()` named every imported policy after its own hash. That reload
    /// runs at init and after every successful removal, which is why deleting
    /// one policy renamed all the others mid-session.
    ///
    /// AND THE MANIFEST GOES IN THE SAME CALL. It used to be a second hop that
    /// looked the entry back up by display name and returned silently when the
    /// name it was given did not match the one on disk — which, for a
    /// digest-named entry, was always.
    ///
    /// AN EXISTING TYPED TITLE IS PRESERVED: re-importing a policy you renamed
    /// must not wipe the name, the same way the `fileExists` guard below
    /// already protects the bytes.
    @discardableResult
    public static func persist(_ data: Data, entry: Entry, into container: URL,
                               manifest: Data? = nil,
                               using fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
        let url = container.appendingPathComponent("\(entry.identity.value).onnx")
        if !fileManager.fileExists(atPath: url.path) {
            try data.write(to: url)
        }

        let existing = nameplate(forIdentity: entry.identity.value, in: container,
                                 using: fileManager)
        // A DIGEST IS NEVER AN IMPROVEMENT ON A REAL NAME. If these bytes are
        // arriving a second time under `<identity>.onnx` — which is what a
        // re-persist of an already-held entry looks like — the plate keeps what
        // it had.
        // AND AN EXISTING REAL NAME ALWAYS WINS, the way the `fileExists`
        // guard above protects the bytes: the name a file first arrived under
        // is a recorded observation of that import, not something a later
        // arrival of the same weights under another name gets to restate —
        // `add` would refuse that arrival as already held while the on-disk
        // name quietly moved.
        let recordedName: String = {
            if let held = existing?.fileName, !PolicyNaming.isDigestName(held) { return held }
            return entry.fileName
        }()
        let plate = PolicyNameplate(
            fileName: recordedName,
            // ONLY A TYPED TITLE IS EVER WRITTEN DOWN. Storing the ladder's
            // answer would freeze a computed name as if a person had chosen it,
            // and the next release table or manifest would be unable to correct
            // it.
            title: existing?.title ?? (entry.titleSource == .typed ? entry.title : nil),
            originHost: host(of: entry.origin) ?? existing?.originHost,
            // THIS CALL IS THE ARRIVAL BEING RECORDED.
            arrivalRecorded: true)
        persistNameplate(plate, forIdentity: entry.identity.value, into: container,
                         using: fileManager)

        if let manifest {
            persistManifest(manifest, for: entry, into: container, using: fileManager)
        }
        return url
    }

    // MARK: - counting

    /// How many entries actually run — the number worth showing beside a total,
    /// because a library of twelve files where four load is not a library of
    /// twelve policies.
    public var runnableCount: Int { entries.filter(\.isRunnable).count }

    static func fileDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension PolicyLibrary.Entry {

    /// Whether this entry can be removed from the app at all.
    ///
    /// BUNDLED POLICIES CANNOT BE, AND THE REASON IS NOT A POLICY DECISION.
    /// The nine Pollen ship live inside the app bundle, which is read-only and
    /// is restored whole on every update — deleting one is not something the
    /// filesystem permits, and an app that offered the button anyway would be
    /// offering a control that cannot work. Everything a person brought in
    /// themselves, by file or by download, lives in the container and is theirs
    /// to throw away.
    public var isRemovable: Bool {
        switch origin {
        case .bundled: return false
        case .imported, .fetched, .tuned: return true
        }
    }

    /// The sentence to confirm a removal with.
    ///
    /// IT NAMES WHAT CANNOT BE UNDONE. A policy somebody was sent, or trained
    /// themselves and imported, may exist nowhere else — this app is not a
    /// backup and deleting the file is deleting the weights. A download from a
    /// repository can be fetched again and says so, because those are two very
    /// different risks wearing the same button.
    public var removalWarning: String {
        switch origin {
        case .bundled:
            return "This one came with the app and cannot be removed."
        case .fetched(let host):
            return "Removes \(title) from this phone. It came from \(host), so it can be "
                 + "downloaded again."
        case .imported:
            return "Removes \(title) from this phone. It was brought in as a file, so if "
                 + "this is the only copy, the weights are gone with it."
        // THE ONLY ENTRY THAT EXISTS NOWHERE ELSE IN THE WORLD. A bundled file
        // comes back with the app and a fetched one comes back off a server;
        // even an imported policy is usually a copy of something. This was
        // produced by a search on this phone, and the search is reproducible
        // only from its seed and its base — which the manifest carries and a
        // deleted policy does not.
        case .tuned(let base):
            return "Removes \(title) from this phone. It was made here by tuning "
                 + "\(base), and this is the only copy there has ever been — no server has it "
                 + "and no other machine made it. Export it first if the run was worth keeping."
        }
    }

    // MARK: - what the screen says about the name

    /// Why this policy is called what it is, or nil when nothing needs saying.
    ///
    /// EVERY RUNG OF THE LADDER IS A DIFFERENT KIND OF CLAIM, and a screen that
    /// showed the name without saying where it came from would be presenting a
    /// stranger's word and a checked fact in the same typeface.
    public var titleExplanation: String? {
        switch titleSource {
        case .typed:
            return PolicyNaming.isDigestName(fileName)
                ? "You named this one. This phone did not keep what the file was called."
                : "You named this one. The file it came in as is \(fileName)."
        case .release:
            return "Named after the Pollen release these exact weights match. The fingerprint "
                 + "is what matched, not the file name."
        case .manifest:
            return "The name its author wrote in the manifest that came with it."
        // Nothing to explain: the row already shows the file name, and the
        // title is that name with `.onnx` taken off.
        case .fileName:
            return nil
        case .digest:
            return "Nothing on this phone says what this file was called, so it is named after "
                 + "its fingerprint. Give it a name you will recognise."
        }
    }

    /// The row seal's accessibility label.
    ///
    /// THE REPORT'S HEADLINE NAMES THE FILE AND THIS NAMES THE POLICY. A seal
    /// labelled from `report.headline` reads "This file is a Microduck policy"
    /// for every digest-named entry in the list — an accessibility label that
    /// identifies nothing, on the one control whose whole job is to say which
    /// row you are on.
    public var runnabilityLabel: String {
        switch report.outcome {
        case .runnable:   return "\(title), a Microduck policy"
        case .refused:    return "\(title), will not load in Microduck Studio"
        case .unreadable: return "\(title), not an ONNX model"
        }
    }

    /// The name a COPY leaves under.
    ///
    /// NEVER THE TYPED TITLE WHILE A REAL FILE NAME EXISTS. A nickname is a
    /// thing on this phone; the file that lands in somebody else's downloads
    /// keeps the name its author gave it, so the two of you are talking about
    /// the same artefact. The title is only reached for when there is no file
    /// name to use — and then the message that goes with it says whose word it
    /// is.
    public var exportFileName: String {
        if !PolicyNaming.isDigestName(fileName) { return fileName }
        if titleSource == .typed, let stem = Self.componentSafe(title) {
            return "\(stem).onnx"
        }
        // Twelve characters, because this one is a file name in somebody's
        // downloads folder rather than a digest to compare — long enough that
        // two of them do not collide and short enough to type.
        return "policy-\(String(identity.value.prefix(12))).onnx"
    }

    /// A typed name made safe to be ONE path component.
    ///
    /// A TITLE HAS NO CHARACTER RULE and this is where that stops being free:
    /// `appendingPathComponent("up/down.onnx")` makes a directory called "up"
    /// that does not exist, and the write then fails for a reason that has
    /// nothing to do with anything the person can see. Same substitution the
    /// app's own `ExportFile.safeName` makes, so the two agree.
    static func componentSafe(_ title: String) -> String? {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:\u{0}")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.contains(where: { $0 != "." }) else { return nil }
        return cleaned.hasPrefix(".") ? String(cleaned.dropFirst()) : cleaned
    }
}
