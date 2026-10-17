import SwiftUI
import StudioKit

/// Studio's Duck Card packs: the starter packs, any `.duckpack` opened, and the class's own pack.
///
/// ONE, FOR THE SAME REASON AS `DuckCardsStore`. A pack opened through the import door, a challenge
/// saved from the editor and the Packs screen on either camera card all have to see the same packs,
/// so there is one store, and it keeps each pack as the file it came as.
///
/// FILES, KEPT AS THE BYTES THEY ARRIVED AS, ONE PER ID. An opened pack is written to
/// `DuckPacks/Opened/<id>.duckpack` exactly as it came, so sharing it on sends the same file, and
/// two packs with different ids sit side by side. A pack whose id is already open replaces it only
/// after the person says so (`replacing`). The class pack is `DuckPacks/class.duckpack`, written by
/// `DuckPacks.ClassPack` and read back through `Pack.read` before it is kept; its id, name, score
/// and cards in play are `DuckPacks/class-settings.json`, the id minted once per install. Written
/// atomically and never exclusively (`scripts/check_no_atomic_exclusive_write.sh`).
///
/// A PACK'S YOUR CARDS ARE ASKED ABOUT, NOT TAKEN. Opening a pack lends its Your cards to the class
/// deck the way `Pack.lent` does: a number the class already saved something else for keeps the
/// class's meaning, and `asking` holds the question until the person answers it on the Packs screen.
///
/// ONE RULE FOR WHICH MEANING PLAYS. On a clash the class deck's own meaning wins: the camera reads
/// it, the board plays it and the duck runs it (`playDeck`). A pack's Your cards are lent only where
/// the class has none, unless the person replaces the class's own.
///
/// IT DECIDES NOTHING. Reading, checking, par and the sentences are the kit's; this holds the values
/// so a screen redraws when they change.
@MainActor
final class DuckPacksStore: ObservableObject {

    static let shared = DuckPacksStore()

    /// Packs opened through the import door, by name.
    @Published private(set) var opened: [DuckPacks.Pack] = []
    /// The class's own challenges, or nil until one is saved.
    @Published private(set) var classPack: DuckPacks.Pack?
    /// The class pack's id, name, score and cards in play.
    @Published private(set) var settings: DuckPacks.ClassPack.Settings
    /// A pack through the import door whose id is already open, waiting for the person to say.
    @Published var replacing: Replacing?
    /// What the last `.duckpack` through the import door did.
    @Published private(set) var lastOpened: String?
    /// A pack whose Your cards clash with the class deck, waiting for the person to say.
    @Published var asking: Asking?
    /// Packs taken through the import door, so `Imports` can tell an arrival from a refusal.
    private(set) var taken = 0

    struct Asking: Identifiable {
        let pack: DuckPacks.Pack
        let clashes: [Int]
        var id: String { pack.id }
    }

    struct Replacing: Identifiable {
        let incoming: DuckPacks.Pack
        let existing: DuckPacks.Pack
        var id: String { incoming.id }
    }

    private let folder: URL
    private var openedFolder: URL { folder.appendingPathComponent("Opened", isDirectory: true) }
    private var classFile: URL { folder.appendingPathComponent(DuckPacks.ClassPack.fileName) }
    private var settingsFile: URL { folder.appendingPathComponent(DuckPacks.ClassPack.settingsFileName) }
    private func openedFile(_ id: String) -> URL {
        openedFolder.appendingPathComponent("\(id).\(DuckPacks.fileExtension)")
    }

    private init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DuckPacks", isDirectory: true)
        let url = folder.appendingPathComponent(DuckPacks.ClassPack.settingsFileName)
        settings = (try? Data(contentsOf: url)).flatMap(DuckPacks.ClassPack.Settings.read) ?? DuckPacks.ClassPack.Settings()
        reload()
        settle()
    }

    /// The settings kept, minted once: read from their file, or taken from a class pack written
    /// before there were settings (with a new id if it has the one every class used to share), or
    /// new. A class pack whose id or settings differ from them is written again under them.
    private func settle() {
        if !FileManager.default.fileExists(atPath: settingsFile.path) {
            if let deck, let old = classPack { settings = DuckPacks.ClassPack.Settings.of(old, deck: deck) }
            try? write(settings.data, to: settingsFile)
        }
        guard let deck, let pack = classPack else { return }
        if pack.id != settings.id || pack.name != settings.shownName || pack.score != settings.score
            || pack.cards != settings.inPlay(deck) {
            if let held = try? DuckPacks.ClassPack.rechecked(pack.challenges, settings: settings, deck: deck) {
                try? keepClass(held, deck: deck)
            }
        }
    }

    /// The deck a pack is read with: the class's, or the starter deck.
    private var deck: DuckCards.Deck? { DuckCardsStore.shared.deck }

    private func reload() {
        guard let deck else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: openedFolder, includingPropertiesForKeys: nil)) ?? []
        opened = files.filter { $0.pathExtension == DuckPacks.fileExtension }
            .compactMap { (try? Data(contentsOf: $0)).flatMap { try? DuckPacks.Pack.read($0, deck: deck) } }
            .sorted { ($0.gradeFrom, $0.name) < ($1.gradeFrom, $1.name) }
        classPack = (try? Data(contentsOf: classFile)).flatMap { try? DuckPacks.Pack.read($0, deck: deck) }
    }

    /// The deck a pack is played with: the class deck, with the pack's Your cards lent only where
    /// the class has none. On a clash the class's own meaning plays, as the camera reads it and the
    /// card reader on the duck runs it (`Pack.lend` without replacing). The same deck hands a row to
    /// the duck, so the duck runs the steps the board played.
    func playDeck(_ pack: DuckPacks.Pack) -> DuckCards.Deck? {
        guard let deck else { return nil }
        return (try? pack.lent(to: deck, replacing: false).deck) ?? deck
    }

    /// The pack's Your card numbers that mean something else in the class deck, where the class's
    /// meaning is the one that plays.
    func clashes(_ pack: DuckPacks.Pack) -> [Int] {
        guard let deck, !pack.yours.isEmpty else { return [] }
        return (try? pack.lent(to: deck, replacing: false).clashes) ?? []
    }

    func isOpened(_ pack: DuckPacks.Pack) -> Bool { opened.contains { $0.id == pack.id } }

    /// The cards in play in the class pack, as the teacher set them.
    var classCards: [String] { deck.map(settings.inPlay) ?? [] }

    // MARK: - through the import door

    /// A `.duckpack` file through the import door, as the sentence that says what happened. Kept as
    /// the file it came as, then its Your cards lent to the class deck, asking about any clash.
    func take(_ data: Data) -> String {
        let said: String
        if let deck {
            do {
                let pack = try DuckPacks.Pack.read(data, deck: deck)
                if pack.id == settings.id {
                    said = DuckPacks.Words.ownPack(pack)
                } else if let existing = opened.first(where: { $0.id == pack.id }) {
                    if existing.source == data {
                        said = DuckPacks.Words.alreadyOpen(pack)
                    } else {
                        replacing = Replacing(incoming: pack, existing: existing)
                        said = DuckPacks.Words.waitingToReplace(pack, existing)
                    }
                } else {
                    said = try keep(pack)
                }
            } catch let refusal as DuckPacks.Refusal {
                said = refusal.message
            } catch {
                said = DuckPacks.Words.notKept(error.localizedDescription)
            }
        } else {
            said = DuckCards.Refusal.noDeck.message
        }
        lastOpened = said
        return said
    }

    /// Keep an opened pack's file and lend its Your cards, as the sentence that says what happened.
    private func keep(_ pack: DuckPacks.Pack) throws -> String {
        try write(pack.source, to: openedFile(pack.id))
        reload()
        taken += 1
        let clashes = lend(pack, replacing: false)
        return clashes.isEmpty ? DuckPacks.Words.opened(pack) : DuckPacks.Words.openedWithClashes(pack, clashes)
    }

    /// The person's answer to a pack opened with an id already open: replace the one there, or keep it.
    func answer(_ question: Replacing, replace: Bool) {
        replacing = nil
        guard replace else {
            lastOpened = DuckPacks.Words.keptOpened(question.existing)
            return
        }
        do {
            lastOpened = try keep(question.incoming)
        } catch {
            lastOpened = DuckPacks.Words.notKept(error.localizedDescription)
        }
    }

    // MARK: - lending Your cards

    /// Lend a pack's Your cards to the class deck. Returns the numbers that clashed; when there are
    /// some and `replacing` is false, the class's own were kept and `asking` holds the question.
    @discardableResult
    func lend(_ pack: DuckPacks.Pack, replacing: Bool) -> [Int] {
        guard !pack.yours.isEmpty else { return [] }
        do {
            let clashes = try DuckCardsStore.shared.lend(pack, replacing: replacing)
            asking = clashes.isEmpty || replacing ? nil : Asking(pack: pack, clashes: clashes)
            lastOpened = DuckPacks.Words.lent(pack, clashes: clashes, replaced: replacing)
            return clashes
        } catch let refusal as DuckPacks.Refusal {
            lastOpened = refusal.message
        } catch let refusal as DuckCards.Refusal {
            lastOpened = refusal.message
        } catch {
            lastOpened = error.localizedDescription
        }
        return []
    }

    // MARK: - the class pack

    /// A drawn challenge, checked by the kit and saved into the class pack. Throws the kit's
    /// refusal, a sentence.
    @discardableResult
    func save(_ draft: DuckPacks.Draft) throws -> DuckPacks.Challenge {
        guard let deck else { throw DuckCards.Refusal.noDeck }
        let held = classPack?.challenges ?? []
        let ch = try draft.checked(id: DuckPacks.ClassPack.nextID(after: held), cards: settings.inPlay(deck),
                                   score: settings.score, deck: deck)
        try keepClass(held + [ch], deck: deck)
        return ch
    }

    /// New settings for the class pack: every challenge held to them first (`ClassPack.rechecked`),
    /// and nothing changed if one cannot be. The id is the one minted; it is never changed here.
    func apply(_ new: DuckPacks.ClassPack.Settings) throws {
        guard let deck else { throw DuckCards.Refusal.noDeck }
        var next = new
        next.id = settings.id
        next.name = next.shownName
        let challenges = try DuckPacks.ClassPack.rechecked(classPack?.challenges ?? [], settings: next, deck: deck)
        let before = settings
        settings = next
        do {
            try keepClass(challenges, deck: deck)
            try write(next.data, to: settingsFile)
        } catch {
            settings = before
            throw error
        }
    }

    func remove(_ challenge: DuckPacks.Challenge) throws {
        guard let deck else { throw DuckCards.Refusal.noDeck }
        try keepClass((classPack?.challenges ?? []).filter { $0.id != challenge.id }, deck: deck)
    }

    private func keepClass(_ challenges: [DuckPacks.Challenge], deck: DuckCards.Deck) throws {
        if let pack = try DuckPacks.ClassPack.written(challenges, settings: settings, deck: deck) {
            try write(pack.source, to: classFile)
            classPack = pack
        } else {
            try? FileManager.default.removeItem(at: classFile)
            classPack = nil
        }
    }

    /// Take an opened pack off the list. Its file goes; the cards it lent stay in the class deck.
    func remove(_ pack: DuckPacks.Pack) {
        try? FileManager.default.removeItem(at: openedFile(pack.id))
        reload()
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
