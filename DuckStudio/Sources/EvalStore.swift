import SwiftUI
import StudioKit

/// Every refusal this feature can raise, asked for its own words.
///
/// THE LADDER IS THE ONE `StairsMoveView.message` ALREADY USES, WITH THE EIGHT
/// EVALUATION REFUSALS ADDED. `localizedDescription` is not an option for any
/// of them: a kit refusal has no localisation and renders as
/// "(StudioKit.EvalTask.Refusal error 1.)", which is a sentence about Swift
/// rather than about what went wrong. Every case below already carries a
/// tested `message`; this only picks the right one.
enum EvalMessage {
    static func of(_ error: Error) -> String {
        switch error {
        case let refusal as EvalLogRefusal:              return refusal.message
        case let refusal as EvalTask.Refusal:            return refusal.message
        case let refusal as EvalEpochs.Refusal:          return refusal.message
        case let refusal as EvalScorerSet.Refusal:       return refusal.message
        case let refusal as EvalEmbodiment.Refusal:      return refusal.message
        case let refusal as EvalCompare.Refusal:         return refusal.message
        case let refusal as EvalLogFile.Refusal:         return refusal.message
        case let refusal as EvalShelfRefusal:            return refusal.message
        case let refusal as StairsChallenge.ResourceError: return refusal.message
        case let refusal as StairsChallenge.Move.Refusal: return refusal.message
        case let refusal as BallChallenge.Entrant.Refusal: return refusal.message
        case let refusal as HarnessJSON.ParseError:      return refusal.message
        case let refusal as DuckBench.Refusal:           return refusal.message
        case let refusal as DuckBench.ReadError:         return refusal.message
        case let refusal as BenchEndpoint.Refusal:       return refusal.message
        case let refusal as ExportFile.Failure:          return refusal.message
        default: return error.localizedDescription
        }
    }
}

/// Why a log could not go on the shelf.
///
/// AT FILE SCOPE AND NOT NESTED IN THE STORE. `EvalStore` is `@MainActor`, and
/// a refusal read by `EvalMessage.of` from a `View`'s own context has no
/// business inheriting an actor: an error is a value, and a value that can only
/// be asked for its own words on one thread is a value that eventually cannot
/// be printed where it happened.
enum EvalShelfRefusal: Error, Equatable {
    case alreadyOnTheShelf(String)

    var message: String {
        switch self {
        case .alreadyOnTheShelf(let name):
            return "\(name) is already here. " + EvalLogFile.aLogIsFinished
        }
    }
}

/// The evaluation logs on this phone: the ones it wrote and the ones it was
/// handed.
///
/// WRITE ONCE, AND THE STORE IS WHERE THAT IS TRUE RATHER THAN WHERE IT IS
/// PROMISED. `EvalLogFile.aLogIsFinished` says a log is finished when the run
/// is; a store with a `save` that silently overwrote would make that a slogan.
/// So `save` refuses a name that is already on the shelf, and there is no
/// update, no rename and no re-encode: the bytes that arrive are the bytes on
/// disk for the rest of the file's life.
///
/// ORIGIN IS THE DIRECTORY AND NOT A FLAG. A written log lives in
/// `evaluations/`; a log somebody handed over lives in `evaluations/received/`
/// under the name it arrived with, with its bytes never rewritten. That means
/// the fact `EvalLogFile.canPublish` gates on cannot drift out of step with a
/// sidecar nobody reads, and a person looking at the container in Files sees
/// the same split the app sees.
///
/// NOTHING HERE THROWS INTO A VIEW. Every kit factory in this feature is
/// throwing, `EvalLogFile.imported` deliberately as strict as inspect-robots'
/// own reader, so each call is inside a `do`/`catch` here and what a screen
/// reads is a published sentence. A `View` property initialiser that called
/// one would be a screen that cannot be built.
@MainActor
final class EvalStore: ObservableObject {

    /// Newest first, both kinds together, because the shelf is one shelf.
    @Published private(set) var files: [EvalLogFile] = []

    /// How many files in the directory could not be read, the shape
    /// `ModelEndpoint.Salvage` already established: one bad file must not
    /// empty the list, and a file that was swallowed has to be a number on
    /// screen rather than silence.
    @Published private(set) var unreadable: Int?

    /// The last thing that went wrong, in the refusal's own words.
    @Published var failure: String?

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("evaluations", isDirectory: true)
    }

    private var receivedDirectory: URL {
        directory.appendingPathComponent("received", isDirectory: true)
    }

    init() { reload() }

    // MARK: - reading the shelf

    /// Both directories, newest first.
    ///
    /// THE ORDER IS THE FILE'S OWN DATE AND NOT THE LOG'S. A log carries
    /// `stats.started_at` as a string, and sorting a shelf by parsing a foreign
    /// timestamp would put an imported log wherever its own clock happened to
    /// be. The file system knows when each one landed here, which is the
    /// question a list sorted "newest first" is actually answering.
    func reload() {
        var found: [(file: EvalLogFile, when: Date)] = []
        var bad = 0

        for url in jsonFiles(in: directory) {
            guard let data = try? Data(contentsOf: url) else { bad += 1; continue }
            do {
                found.append((try EvalLogFile.onDisk(data, named: url.lastPathComponent),
                              landed(url)))
            } catch {
                bad += 1
            }
        }

        for url in jsonFiles(in: receivedDirectory) {
            guard let data = try? Data(contentsOf: url) else { bad += 1; continue }
            do {
                found.append((try EvalLogFile.imported(data, named: url.lastPathComponent),
                              landed(url)))
            } catch {
                bad += 1
            }
        }

        files = found.sorted { $0.when > $1.when }.map(\.file)
        unreadable = bad == 0 ? nil : bad
    }

    private func jsonFiles(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "json" }
    }

    private func landed(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date.distantPast
    }

    // MARK: - writing one, once

    /// Put a finished run on the shelf.
    ///
    /// ATOMIC AND NON DESTRUCTIVE. `withoutOverwriting` is the option that
    /// makes the write-once rule the file system's rather than this app's, so
    /// two runs that somehow produced the same eight hex end with a refusal
    /// instead of one of them disappearing.
    @discardableResult
    func save(_ file: EvalLogFile) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(file.name)
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw EvalShelfRefusal.alreadyOnTheShelf(file.name)
            }
            try file.bytes.write(to: url, options: [.atomic, .withoutOverwriting])
            reload()
            return true
        } catch {
            failure = EvalMessage.of(error)
            return false
        }
    }

    // MARK: - a log from somewhere else

    /// Read a file somebody handed over, as strictly as their own reader reads
    /// it, and keep the bytes that arrived.
    ///
    /// THE SECURITY SCOPE IS NOT OPTIONAL. A URL from `.fileImporter` points
    /// outside this app's container and reading it without asking gives an
    /// empty `Data` and no error at all, which would arrive here as "that log
    /// has no version inside the log": a refusal about the schema for a file
    /// nobody was allowed to open.
    ///
    /// IT IS REFUSED BEFORE IT IS COPIED. A file that is not an EvalLog v1
    /// never reaches the container, so the received folder cannot fill up with
    /// things the list will not show.
    @discardableResult
    func importLog(at url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            // Read first, so an unreadable file is refused rather than stored.
            _ = try EvalLogFile.imported(data, named: url.lastPathComponent)
            try FileManager.default.createDirectory(at: receivedDirectory,
                                                    withIntermediateDirectories: true)
            let safe = ExportFile.safeName(url.lastPathComponent) ?? url.lastPathComponent
            let landing = receivedDirectory.appendingPathComponent(safe)
            guard !FileManager.default.fileExists(atPath: landing.path) else {
                throw EvalShelfRefusal.alreadyOnTheShelf(EvalText.foreign(safe))
            }
            try data.write(to: landing, options: [.atomic, .withoutOverwriting])
            reload()
            return true
        } catch {
            failure = EvalMessage.of(error)
            return false
        }
    }

    // MARK: - putting one down

    /// Take a log off the shelf. The only edit this store has: a log cannot be
    /// changed, and deleting it is not changing it.
    func delete(_ file: EvalLogFile) {
        let url = location(of: file)
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    /// Where a log's bytes are, which is decided by where it came from.
    func location(of file: EvalLogFile) -> URL {
        switch file.origin {
        case .written:
            return directory.appendingPathComponent(file.name)
        case .imported:
            let name = file.importedName ?? file.name
            return receivedDirectory.appendingPathComponent(
                ExportFile.safeName(name) ?? file.name)
        }
    }

    // MARK: - what a person reads

    /// The two counts a Compare row needs before it decides whether to offer
    /// itself, kept here so a view never filters the shelf twice.
    var comparable: [EvalLogFile] { files }
}

// THE ONE THING THIS FILE NEEDS FROM THE KIT AND CANNOT WRITE ITSELF.
//
// `EvalLogFile` has exactly two public constructors: `written(_ run:)`, which
// builds a file FROM A RUN, and `imported(_:named:)`, which stamps
// `origin == .imported`. Coming back after a launch there is no run any more,
// only bytes and a filename, and reading a log this app wrote back through
// `imported` would put the Imported badge on it and turn `canPublish` off,
// which is the kit's own gate answering the wrong question about this phone's
// own measurements. Its memberwise initialiser is internal to StudioKit, so
// nothing in the app target can spell the third case.
//
// So `reload()` above calls `EvalLogFile.onDisk(_:named:)`, which is this, and
// which belongs in `StudioKit/Sources/StudioKit/EvalLogWriter.swift` beside the
// two constructors it joins:
//
//     /// A log this app wrote, read back off the disk it was written to.
//     ///
//     /// `wroteIt` COMES OUT OF THE LOG AND NOT OFF THE RUNNING BUILD.
//     /// `eval.inspect_robots_version` is `EvalRun.producerSaid`, which was
//     /// written by whichever build made the run, and stamping today's version
//     /// on an archived file would make every old log claim to be new.
//     public static func onDisk(_ data: Data, named name: String) throws -> EvalLogFile {
//         let log = try EvalLogReader.read(data)
//         return EvalLogFile(log: log, bytes: data, origin: .written, name: name,
//                            importedName: nil,
//                            wroteIt: EvalRun.wroteItSaid(from: log.eval.inspectRobotsVersion))
//     }
//
// with `EvalRun.wroteItSaid(from:)` returning the `Microduck Studio 1.1 (58)`
// clause `producerSaid` built, or nil for a producer sentence this app did not
// write. Nil is what `EvalReport.shareSentence` already turns into
// `passedOnSaid`.
