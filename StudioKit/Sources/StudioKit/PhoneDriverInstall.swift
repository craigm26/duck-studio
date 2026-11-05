import Foundation

/// The phone driver this build offers, pinned by commit and by hash.
///
/// WHY PINNED TWICE. The commit fixes what Hugging Face serves; the hashes mean a file that is not
/// the measured one is never installed, even if a repo were rewritten. `policy.json` then pins the
/// golden answers and its own copy of the weights' hash, so one pinned file vouches for the rest.
///
/// PUBLIC FILES, NO TOKEN. The weights are public and the app asks Hugging Face's plain resolve URLs.
///
/// THE NUMBERS ARE THE M1 TABLE'S FROM THE APP'S OWN START (`m1_trial.py --app-start`, in
/// `docs/plans/build-90-phone-driver.md`), the lower of the two starts, on the new seeds 8001 to
/// 8020 that nothing was trained or tuned on, played with the snap and the stand latch.
public struct DriverRelease: Equatable, Sendable {
    public let repo: String
    public let revision: String
    public let policySHA256: String
    public let weightsSHA256: String
    /// All three files together, shown before the download starts.
    public let bytes: Int
    public let freshRuns: Int
    public let freshReached: Int
    public let freshParked: Int

    public init(repo: String, revision: String, policySHA256: String, weightsSHA256: String, bytes: Int,
                freshRuns: Int, freshReached: Int, freshParked: Int) {
        self.repo = repo; self.revision = revision
        self.policySHA256 = policySHA256; self.weightsSHA256 = weightsSHA256
        self.bytes = bytes
        self.freshRuns = freshRuns; self.freshReached = freshReached; self.freshParked = freshParked
    }

    /// M1 pick of 2026-11-05: v6, weights commit 4ba66af plus the snap block.
    public static let walkToBall = DriverRelease(
        repo: "craigm26/duck-driver-walk-to-ball-v6",
        revision: "5985110aefdef3da98dfcbebe939a77da631de5a",
        policySHA256: "cd0f5aa692d77e7f43954e16c904be33459ad549fd2b50aaabacc4ff649d8f7e",
        weightsSHA256: "d1a1015708306b2153c7139a58906d10776a5bfb06b6a9123d1cc13f8515246f",
        bytes: 1229 + 4_364_856 + 10_754,
        freshRuns: 20, freshReached: 19, freshParked: 17)

    /// Its folder on this device: changing the pin is a new install, and never a mixed one.
    public var folder: String {
        (repo.split(separator: "/").last.map(String.init) ?? repo) + "-" + revision.prefix(7)
    }

    public func url(_ file: String) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file)")!
    }

    /// "4.4 MB": what Get shows before anything is fetched.
    public var size: String { DriverInstall.size(bytes) }
}

/// Getting a driver onto this device: where it is, and what can go wrong, in plain words.
public enum DriverInstall {
    public enum Phase: Equatable, Sendable {
        case absent
        case getting(done: Int, total: Int)
        /// Every file is here: the golden replay is running on this device.
        case checking
        case installed
        case failed(String)

        public var isInstalled: Bool { self == .installed }
        /// 0 to 1 while files come down, nil otherwise.
        public var fraction: Double? {
            guard case .getting(let done, let total) = self, total > 0 else { return nil }
            return min(max(Double(done) / Double(total), 0), 1)
        }
    }

    public enum Problem: Error, Equatable, Sendable {
        case download(String), notThePinnedFile(String), manifest(String), golden(String), disk(String)

        public var message: String {
            switch self {
            case .download(let why): return "The download stopped: \(why)"
            case .notThePinnedFile(let name):
                return "\(name) is not the file this app was tested with, so it was not installed."
            case .manifest(let why), .golden(let why): return why
            case .disk(let why): return "This device could not keep the driver: \(why)"
            }
        }
    }

    public static func size(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }
}

/// Downloads, checks and keeps a driver, and says what is on disk.
///
/// NOTHING COUNTS AS INSTALLED UNTIL IT PASSED EVERYTHING. The files are written to a side folder,
/// `DriverTrial.load` runs on it (the manifest, both files' sizes and SHA-256, the weights' shapes,
/// the golden replay, as M1 loaded a driver), and only then is it renamed into place. A kill at any
/// moment leaves no half a driver under the real name.
///
/// NO FILE LOCK IS HELD AND NO FILE STAYS OPEN ACROSS AN AWAIT. An app suspended holding a `flock`
/// is killed with 0xdead10cc (swift-huggingface did that to this app in build 77). `fetch` hands
/// back whole bytes, and each file is written in one call.
public struct DriverInstaller: Sendable {
    /// One file: its URL, the most bytes it may be, a callback with bytes so far. Whole bytes back;
    /// throws `CancellationError` when cancelled.
    public typealias Fetch = @Sendable (URL, Int, @escaping @Sendable (Int) -> Void) async throws -> Data

    /// `policy.json` is a page of numbers; anything bigger is not one.
    public static let policyLimit = 64 * 1024
    static let partialSuffix = ".partial"
    /// Every pinned driver's folder starts with this; `clearOtherPins` touches nothing else.
    static let pinPrefix = "duck-driver-"

    public let release: DriverRelease
    /// The folder drivers live in (Application Support on a device).
    public let root: URL

    public init(release: DriverRelease, root: URL) {
        self.release = release; self.root = root
    }

    public var folder: URL { root.appendingPathComponent(release.folder, isDirectory: true) }
    private var partial: URL { root.appendingPathComponent(release.folder + Self.partialSuffix, isDirectory: true) }

    /// What is really on disk: installed only when the pinned policy and both files are all there
    /// and match. Anything else is removed, so a damaged driver is offered again, not run.
    public func status() -> DriverInstall.Phase {
        let fm = FileManager.default
        try? fm.removeItem(at: partial)
        clearOtherPins()
        guard fm.fileExists(atPath: folder.path) else { return .absent }
        if isWhole() { return .installed }
        try? fm.removeItem(at: folder)
        return .absent
    }

    /// AN OLD PIN IS NOT KEPT. A new pin is a new folder, and nothing here would ever reach the old
    /// one: no run loads it and Delete does not see it, so it would sit on the device for good.
    private func clearOtherPins() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where name.hasPrefix(Self.pinPrefix) && name != release.folder {
            try? fm.removeItem(at: root.appendingPathComponent(name, isDirectory: true))
        }
    }

    private func isWhole() -> Bool {
        func read(_ name: String) -> Data? { try? Data(contentsOf: folder.appendingPathComponent(name)) }
        guard let policy = read(DriverManifest.policyFile), DriverHash.hex(policy) == release.policySHA256,
              let manifest = try? DriverManifest.read(policy),
              let weights = read(DriverManifest.weightsFile), let golden = read(DriverManifest.goldenFile) else {
            return false
        }
        return manifest.matches(weights, path: DriverManifest.weightsFile)
            && manifest.matches(golden, path: DriverManifest.goldenFile)
    }

    /// Takes the driver off this device.
    public func delete() throws {
        let fm = FileManager.default
        for url in [partial, folder] where fm.fileExists(atPath: url.path) {
            do { try fm.removeItem(at: url) } catch { throw DriverInstall.Problem.disk(error.localizedDescription) }
        }
    }

    /// Downloads, checks and installs. `report` hears every phase; the driver is installed when this
    /// returns. Throws `DriverInstall.Problem`, or `CancellationError` when cancelled. Either way
    /// nothing is left behind.
    public func install(fetch: @escaping Fetch, report: @escaping @Sendable (DriverInstall.Phase) -> Void) async throws {
        let fm = FileManager.default
        try? fm.removeItem(at: partial)
        defer { try? fm.removeItem(at: partial) }
        let total = release.bytes

        func got(_ name: String, limit: Int, after done: Int) async throws -> Data {
            do {
                return try await fetch(release.url(name), limit) { report(.getting(done: done + $0, total: total)) }
            } catch is CancellationError {
                throw CancellationError()
            } catch let problem as DriverInstall.Problem {
                throw problem
            } catch {
                throw DriverInstall.Problem.download(error.localizedDescription)
            }
        }

        report(.getting(done: 0, total: total))
        let policy = try await got(DriverManifest.policyFile, limit: Self.policyLimit, after: 0)
        guard DriverHash.hex(policy) == release.policySHA256 else {
            throw DriverInstall.Problem.notThePinnedFile(DriverManifest.policyFile)
        }
        let manifest: DriverManifest
        do { manifest = try DriverManifest.read(policy) } catch let problem as DriverManifest.Problem {
            throw DriverInstall.Problem.manifest(problem.message)
        }
        guard manifest.files[DriverManifest.weightsFile]?.sha256.lowercased() == release.weightsSHA256 else {
            throw DriverInstall.Problem.notThePinnedFile(DriverManifest.weightsFile)
        }

        var kept = [(DriverManifest.policyFile, policy)]
        var done = policy.count
        for name in [DriverManifest.weightsFile, DriverManifest.goldenFile] {
            guard let entry = manifest.files[name] else { throw DriverInstall.Problem.notThePinnedFile(name) }
            let data = try await got(name, limit: entry.bytes, after: done)
            guard manifest.matches(data, path: name) else { throw DriverInstall.Problem.notThePinnedFile(name) }
            kept.append((name, data))
            done += data.count
        }
        try Task.checkCancellation()

        report(.checking)
        do {
            try fm.createDirectory(at: partial, withIntermediateDirectories: true)
            for (name, data) in kept { try data.write(to: partial.appendingPathComponent(name), options: .atomic) }
        } catch { throw DriverInstall.Problem.disk(error.localizedDescription) }
        do {
            _ = try DriverTrial.load(folder: partial.path, decode: { _ in nil })
        } catch let problem as DriverTrial.Problem {
            throw DriverInstall.Problem.golden(problem.message)
        } catch {
            throw DriverInstall.Problem.golden(String(describing: error))
        }
        try Task.checkCancellation()
        do {
            try? fm.removeItem(at: folder)
            try fm.moveItem(at: partial, to: folder)
        } catch { throw DriverInstall.Problem.disk(error.localizedDescription) }
        report(.installed)
    }
}
