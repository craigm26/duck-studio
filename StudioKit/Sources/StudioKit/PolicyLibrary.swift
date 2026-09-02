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

    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: String { identity.value }
        public let displayName: String
        public let origin: Origin
        public let identity: Identity
        public let byteCount: Int
        public let report: PolicyReport

        /// The sixteen characters a person compares at a glance.
        public var shortIdentity: String { String(identity.value.prefix(16)) }

        /// True when this file can actually drive the robot.
        public var isRunnable: Bool { report.outcome == .runnable }
    }

    public private(set) var entries: [Entry] = []

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    // MARK: - reading files in

    /// Read one file into an entry. Never throws for a bad policy: a file that
    /// cannot be parsed is a thing this app has something to say about, not an
    /// error to swallow.
    public static func entry(for data: Data, name: String, origin: Origin) -> Entry {
        let report = PolicyReport.of(data, name: name)
        let identity: Identity
        if let policy = try? DuckPolicy.load(from: data) {
            identity = .parameters(policy.fingerprint)
        } else {
            identity = .fileOnly(fileDigest(data))
        }
        return Entry(displayName: name, origin: origin, identity: identity,
                     byteCount: data.count, report: report)
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

    /// Deterministic and stable: origin rank, then name, then identity.
    ///
    /// The last key is the one that matters. Two different networks exported
    /// under the same filename — which happens constantly during a training run
    /// — would otherwise sort by a tie nothing breaks, and the list would
    /// reshuffle between launches for no visible reason.
    static func ordering(_ a: Entry, _ b: Entry) -> Bool {
        if a.origin != b.origin { return a.origin < b.origin }
        if a.displayName != b.displayName {
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
        return a.identity.value < b.identity.value
    }

    // MARK: - the seed and the container

    /// Load every `.onnx` in a directory, in filename order so the seed is the
    /// same on every launch.
    public static func read(directory: URL, origin: Origin,
                            using fileManager: FileManager = .default) -> [Entry] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "onnx" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return entry(for: data, name: url.lastPathComponent, origin: origin)
            }
    }

    /// Seed from the bundle, then add anything previously imported.
    public static func assembled(bundled: URL?, container: URL?,
                                 using fileManager: FileManager = .default) -> PolicyLibrary {
        var library = PolicyLibrary()
        if let bundled {
            for entry in read(directory: bundled, origin: .bundled, using: fileManager) {
                library.add(entry)
            }
        }
        if let container {
            for entry in read(directory: container, origin: .imported, using: fileManager) {
                library.add(entry)
            }
        }
        return library
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
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public static func persist(_ data: Data, entry: Entry, into container: URL,
                               using fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
        let url = container.appendingPathComponent("\(entry.identity.value).onnx")
        if !fileManager.fileExists(atPath: url.path) {
            try data.write(to: url)
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
            return "Removes \(displayName) from this phone. It came from \(host), so it can be "
                 + "downloaded again."
        case .imported:
            return "Removes \(displayName) from this phone. It was brought in as a file, so if "
                 + "this is the only copy, the weights are gone with it."
        // THE ONLY ENTRY THAT EXISTS NOWHERE ELSE IN THE WORLD. A bundled file
        // comes back with the app and a fetched one comes back off a server;
        // even an imported policy is usually a copy of something. This was
        // produced by a search on this phone, and the search is reproducible
        // only from its seed and its base — which the manifest carries and a
        // deleted policy does not.
        case .tuned(let base):
            return "Removes \(displayName) from this phone. It was made here by tuning "
                 + "\(base), and this is the only copy there has ever been — no server has it "
                 + "and no other machine made it. Export it first if the run was worth keeping."
        }
    }
}
