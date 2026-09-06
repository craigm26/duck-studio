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
            return EvalLogFile.alreadyOnTheShelfSaid(name)
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
        landingNames = [:]
        // THE SHELF IS RE READ AND THE LAST REFUSAL GOES WITH IT. It used to
        // outlive whatever raised it: one cancelled import put a sentence under
        // every successful one for the rest of the launch. Whoever raises a
        // refusal after this says so after this, which is why `delete` assigns
        // its own on the far side of the reload.
        failure = nil

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
                let file = try EvalLogFile.imported(data, named: url.lastPathComponent)
                // THE NAME ON DISK IS REMEMBERED HERE BECAUSE IT CANNOT BE
                // REBUILT. `importedName` has been through `EvalText.foreign`,
                // which trims, strips control characters and caps at 240, so a
                // path assembled back out of it points at nothing for exactly
                // the arrival names those rules changed, and delete then did
                // nothing at all, silently, in a feature whose rule is that
                // every refusal has words.
                landingNames[file.name] = url.lastPathComponent
                found.append((file, landed(url)))
            } catch {
                bad += 1
            }
        }

        files = found.sorted { $0.when > $1.when }.map(\.file)
        unreadable = bad == 0 ? nil : bad
    }

    /// An imported log's name on the shelf, against the file name its bytes
    /// actually landed under in `received/`. Rebuilt by every `reload`.
    private var landingNames: [String: String] = [:]

    /// THE EXTENSION IS COMPARED IN ONE CASE, which `PolicyLibrary` and
    /// `LibraryModel` already do for `onnx`. `.fileImporter` matches a UTI's
    /// extension without regard to case, so `LOG.JSON`, an ordinary name off a
    /// desktop, passed the picker, passed the reader, was copied into the
    /// container, and then matched nothing here: not a row, and not part of the
    /// unreadable count that exists so a swallowed file is a number on screen
    /// rather than silence.
    private func jsonFiles(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension.lowercased() == Self.jsonExtension }
    }

    private static let jsonExtension = "json"

    private func landed(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date.distantPast
    }

    // MARK: - writing one, once

    /// Put a finished run on the shelf.
    ///
    /// NON DESTRUCTIVE, AND NOT ATOMIC, BECAUSE IT CANNOT BE BOTH.
    /// `withoutOverwriting` is the option that makes the write-once rule the
    /// file system's rather than this app's — `O_EXCL` on the open — so two
    /// runs that somehow produced the same eight hex end with a refusal instead
    /// of one of them disappearing. It was paired with `.atomic`, and on the
    /// Swift-native Foundation every iPhone since iOS 18 runs, that pair is a
    /// `fatalError` ("withoutOverwriting is not supported with atomic"), not an
    /// error: an atomic write is a temp file renamed over the name, and a
    /// rename cannot be exclusive. Build 58 crashed at the end of every
    /// evaluation run and on every imported log, right here, with the run's
    /// three minutes of measurements in memory. The Linux gates never saw it
    /// because the parity gate writes with Python, and no test on any platform
    /// can catch a trap in Foundation; `scripts/check_no_atomic_exclusive_write.sh`
    /// is what keeps the pair out now.
    @discardableResult
    func save(_ file: EvalLogFile) -> Bool {
        // THE LAST REFUSAL IS CLEARED BY THE NEXT SUCCESS, not left under the
        // shelf for the rest of the launch. One cancelled import used to put a
        // sentence under every later import that worked.
        failure = nil
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(file.name)
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw EvalShelfRefusal.alreadyOnTheShelf(file.name)
            }
            try file.bytes.write(to: url, options: [.withoutOverwriting])
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
        failure = nil
        do {
            let data = try Data(contentsOf: url)
            // Read first, so an unreadable file is refused rather than stored.
            _ = try EvalLogFile.imported(data, named: url.lastPathComponent)
            try FileManager.default.createDirectory(at: receivedDirectory,
                                                    withIntermediateDirectories: true)
            let safe = landingName(for: url)
            let landing = receivedDirectory.appendingPathComponent(safe)
            guard !FileManager.default.fileExists(atPath: landing.path) else {
                throw EvalShelfRefusal.alreadyOnTheShelf(EvalText.foreign(safe))
            }
            // `.withoutOverwriting` ALONE — see `save(_:)` for the crash the
            // pair with `.atomic` was.
            try data.write(to: landing, options: [.withoutOverwriting])
            reload()
            return true
        } catch {
            failure = EvalMessage.of(error)
            return false
        }
    }

    /// What an arriving file is called once it is inside the container: the
    /// name it came with, made safe, and always ending in a lower case `.json`.
    ///
    /// THE EXTENSION IS NORMALISED ON THE WAY IN so the listing above and the
    /// picker that admitted the file agree about what a log is called.
    private func landingName(for url: URL) -> String {
        let safe = ExportFile.safeName(url.lastPathComponent) ?? url.lastPathComponent
        guard safe.lowercased().hasSuffix(".\(Self.jsonExtension)") else {
            return safe + ".\(Self.jsonExtension)"
        }
        let stem = safe.dropLast(Self.jsonExtension.count)
        return stem + Self.jsonExtension
    }

    // MARK: - putting one down

    /// Take a log off the shelf. The only edit this store has: a log cannot be
    /// changed, and deleting it is not changing it.
    ///
    /// AND IT SAYS SO WHEN IT COULD NOT. A `try?` here meant a delete that
    /// found nothing at the path put the row straight back with no sentence
    /// anywhere, which reads as a control that ignored the swipe.
    func delete(_ file: EvalLogFile) {
        var refusal: String?
        do {
            try FileManager.default.removeItem(at: location(of: file))
        } catch {
            refusal = EvalMessage.of(error)
        }
        // AFTER THE RELOAD, WHICH CLEARS THE LAST ONE. A refusal set before it
        // would be wiped by the very listing that proves the row came back.
        reload()
        failure = refusal
    }

    /// Where a log's bytes are, which is decided by where it came from.
    ///
    /// AN IMPORTED LOG IS FOUND BY THE NAME IT LANDED UNDER, remembered by
    /// `reload`, rather than by rebuilding one from `importedName`: that string
    /// has been capped and stripped for a screen, and a path built back out of
    /// it missed every arrival name those rules changed. The rebuild is kept as
    /// the fallback for a file this store has not listed, where it is the only
    /// guess available and a wrong one now reports itself.
    func location(of file: EvalLogFile) -> URL {
        switch file.origin {
        case .written:
            return directory.appendingPathComponent(file.name)
        case .imported:
            if let landing = landingNames[file.name] {
                return receivedDirectory.appendingPathComponent(landing)
            }
            let name = file.importedName ?? file.name
            return receivedDirectory.appendingPathComponent(
                ExportFile.safeName(name) ?? file.name)
        }
    }

    // MARK: - what a person reads

    /// The whole shelf, named so a Compare row does not reach past the store
    /// for it. It filters nothing: which two logs can actually be put side by
    /// side is `EvalCompare.checked`'s answer and it needs both files to say
    /// so, which is why the row it gates only asks whether there are two.
    var comparable: [EvalLogFile] { files }
}

// WHY `reload()` READS THROUGH A THIRD CONSTRUCTOR.
//
// `EvalLogFile` has three: `written(_ run:)` builds a file from a run,
// `imported(_:named:)` stamps `origin == .imported`, and `onDisk(_:named:)`
// is the one this file needs. Coming back after a launch there is no run any
// more, only bytes and a filename, and reading this phone's own measurements
// back through `imported` would put the Imported badge on them and turn
// `canPublish` off, which is the kit's own gate answering the wrong question.
// The third one keeps the origin the directory already decided, takes the
// producer clause out of the log rather than off the running build, and never
// re-encodes the bytes.
