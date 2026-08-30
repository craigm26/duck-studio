import SwiftUI
import DuckKit

/// The goal celebrations this phone holds: motions authored in Duck Studio,
/// arrived here as `.duckmove` files, played by YOUR team when it scores.
///
/// THE WHOLE PIPELINE THIS COMPLETES: pose the robot keyframe by keyframe in
/// Duck Studio, export, AirDrop or save to Files, open here — and the next
/// goal your duck scores, it performs the thing you wrote. The file is read
/// through DuckKit's `DuckMoveFile`, the format's single door, so a motion
/// that plays in the editor plays identically on the pitch: same reader, same
/// refusals, same joint-order check.
@MainActor
final class CelebrationStore: ObservableObject {

    static let shared = CelebrationStore()

    struct Celebration: Identifiable, Equatable {
        let name: String
        let move: DuckMove
        /// The caveat that travelled with the file — "no physics ran".
        let note: String?
        var id: String { name }

        static func == (a: Celebration, b: Celebration) -> Bool { a.name == b.name }
    }

    @Published private(set) var imported: [Celebration] = []
    /// What the last file-open did, for a one-line alert at the root.
    @Published var lastImport: String?
    /// The chosen celebration's name, or nil for the canon roulade.
    @Published var chosenName: String? {
        didSet { UserDefaults.standard.set(chosenName, forKey: Self.choiceKey) }
    }

    private static let choiceKey = "soccer.celebration"

    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent("Celebrations", isDirectory: true)
    }

    private init() {
        chosenName = UserDefaults.standard.string(forKey: Self.choiceKey)
        reload()
    }

    /// The move your team performs, or nil for the canon roulade clip.
    var chosen: Celebration? {
        imported.first { $0.name == chosenName }
    }

    func reload() {
        // IMPORTED FIRST, THEN BUNDLED: motions authored in the sim harness,
        // verified in MuJoCo, ship inside the app as built-ins — and an
        // import with the same name shadows the bundled copy, so an improved
        // version wins.
        let bundled = Bundle.main.urls(forResourcesWithExtension:
            DuckMoveFile.fileExtension, subdirectory: nil) ?? []
        let importedURLs = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        var seen = Set<String>()
        imported = (importedURLs + bundled)
            .filter { $0.pathExtension == DuckMoveFile.fileExtension }
            .compactMap { url -> Celebration? in
                guard let data = try? Data(contentsOf: url),
                      let contents = try? DuckMoveFile.decode(data),
                      !seen.contains(contents.name) else { return nil }
                seen.insert(contents.name)
                return Celebration(name: contents.name, move: contents.move,
                                   note: contents.note)
            }
            .sorted { $0.name < $1.name }
    }

    /// A `.duckmove` the system handed over.
    func importFile(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            lastImport = "That file could not be read."
            return
        }
        do {
            let contents = try DuckMoveFile.decode(data)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            // Keyed by the motion's name: re-importing a revision replaces it.
            let destination = directory.appendingPathComponent(
                "\(contents.name).\(DuckMoveFile.fileExtension)")
            try data.write(to: destination, options: .atomic)
            reload()
            chosenName = contents.name
            lastImport = "\(contents.name) is your team's goal celebration now. "
                + "Score, and your duck performs it."
        } catch let refusal as DuckMoveFile.ReadError {
            // The reader's message names what was wrong — the joint, the
            // format — so the author is told where to look, not just that
            // something failed.
            lastImport = refusal.message
        } catch {
            lastImport = "That motion could not be saved."
        }
    }

    func delete(_ celebration: Celebration) {
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(
                "\(celebration.name).\(DuckMoveFile.fileExtension)"))
        if chosenName == celebration.name { chosenName = nil }
        reload()
    }
}
