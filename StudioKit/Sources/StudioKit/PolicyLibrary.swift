import Foundation
import Crypto
import DuckKit
import DuckEvidence

/// Everything Duck Studio currently holds, and what each thing is.
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

        var rank: Int {
            switch self {
            case .bundled:  return 0
            case .imported: return 1
            case .fetched:  return 2
            }
        }

        public static func < (a: Origin, b: Origin) -> Bool {
            if a.rank != b.rank { return a.rank < b.rank }
            if case .fetched(let x) = a, case .fetched(let y) = b { return x < y }
            return false
        }

        public var label: String {
            switch self {
            case .bundled:  return "Bundled"
            case .imported: return "Imported"
            case .fetched(let host): return "From \(host)"
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
