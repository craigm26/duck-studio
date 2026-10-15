import SwiftUI
import StudioKit

/// Studio's Duck Card packs: the starter packs, any `.duckpack` opened, and the class's own pack.
///
/// ONE, FOR THE SAME REASON AS `DuckCardsStore`. A pack opened through the import door, a challenge
/// saved from the editor and the Packs screen on either camera card all have to see the same packs,
/// so there is one store, and it keeps each pack as the file it came as.
///
/// FILES, KEPT AS THE BYTES THEY ARRIVED AS. An opened pack is written to
/// `DuckPacks/Opened/<id>.duckpack` exactly as it came, so sharing it on sends the same file; the
/// class pack is `DuckPacks/class.duckpack`, written by `DuckPacks.ClassPack` and read back through
/// `Pack.read` before it is kept. Written atomically and never exclusively
/// (`scripts/check_no_atomic_exclusive_write.sh`).
///
/// A PACK'S YOUR CARDS ARE ASKED ABOUT, NOT TAKEN. Opening a pack lends its Your cards to the class
/// deck the way `Pack.lent` does: a number the class already saved something else for keeps the
/// class's meaning, and `asking` holds the question until the person answers it on the Packs screen.
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

    private let folder: URL
    private var openedFolder: URL { folder.appendingPathComponent("Opened", isDirectory: true) }
    private var classFile: URL { folder.appendingPathComponent(DuckPacks.ClassPack.fileName) }

    private init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DuckPacks", isDirectory: true)
        reload()
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

    /// The deck a pack is played with: the class deck with the pack's own Your cards in it, so a
    /// solution that holds them plays as the pack means it. The same deck hands a row to the duck,
    /// so the duck runs the steps the board played.
    func playDeck(_ pack: DuckPacks.Pack) -> DuckCards.Deck? {
        guard let deck else { return nil }
        return (try? pack.lent(to: deck, replacing: true).deck) ?? deck
    }

    func isOpened(_ pack: DuckPacks.Pack) -> Bool { opened.contains { $0.id == pack.id } }

    // MARK: - through the import door

    /// A `.duckpack` file through the import door, as the sentence that says what happened. Kept as
    /// the file it came as, then its Your cards lent to the class deck, asking about any clash.
    func take(_ data: Data) -> String {
        let said: String
        if let deck {
            do {
                let pack = try DuckPacks.Pack.read(data, deck: deck)
                try write(data, to: openedFolder.appendingPathComponent("\(pack.id).\(DuckPacks.fileExtension)"))
                reload()
                taken += 1
                let clashes = lend(pack, replacing: false)
                said = clashes.isEmpty ? DuckPacks.Words.opened(pack) : DuckPacks.Words.openedWithClashes(pack, clashes)
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
        let ch = try draft.checked(id: DuckPacks.ClassPack.nextID(after: held), cards: DuckPacks.ClassPack.cards(deck))
        try keepClass(held + [ch], deck: deck)
        return ch
    }

    func remove(_ challenge: DuckPacks.Challenge) throws {
        guard let deck else { throw DuckCards.Refusal.noDeck }
        try keepClass((classPack?.challenges ?? []).filter { $0.id != challenge.id }, deck: deck)
    }

    private func keepClass(_ challenges: [DuckPacks.Challenge], deck: DuckCards.Deck) throws {
        if let pack = try DuckPacks.ClassPack.written(challenges, deck: deck) {
            try write(pack.source, to: classFile)
            classPack = pack
        } else {
            try? FileManager.default.removeItem(at: classFile)
            classPack = nil
        }
    }

    /// Take an opened pack off the list. Its file goes; the cards it lent stay in the class deck.
    func remove(_ pack: DuckPacks.Pack) {
        try? FileManager.default.removeItem(at: openedFolder.appendingPathComponent("\(pack.id).\(DuckPacks.fileExtension)"))
        reload()
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
