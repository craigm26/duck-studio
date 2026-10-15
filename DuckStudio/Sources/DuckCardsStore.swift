import SwiftUI
import StudioKit

/// Studio's copy of the class's Duck Cards deck, one per app.
///
/// ONE, BECAUSE THE MEANING LIVES IN ONE FILE. The camera card on the Play tab and the one on My
/// Microduck read cards with it, a row saved as a Your card is written into it, and a `.duckcards`
/// file arriving through the import door replaces it — so all of them have to be holding the same
/// deck, the way `CelebrationStore` is the one shelf of goal celebrations.
///
/// IT DRAWS NOTHING AND DECIDES NOTHING. `DuckCards.ClassDeck` reads, checks, refuses and writes
/// the file; this holds the value so a screen redraws when it changes, and hands back the sentence
/// the kit already wrote for whatever happened.
@MainActor
final class DuckCardsStore: ObservableObject {

    static let shared = DuckCardsStore()

    /// Nil only if the starter deck did not ship, which `DuckCardsTests` pins against.
    @Published private(set) var classDeck: DuckCards.ClassDeck?
    /// What the last `.duckcards` file through the import door did, for the class deck screen.
    @Published private(set) var lastOpened: String?
    /// Decks taken through the import door, so `Imports` can tell an arrival from a refusal.
    private(set) var taken = 0

    private init() {
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DuckCards", isDirectory: true)
            .appendingPathComponent(DuckCards.ClassDeck.fileName)
        classDeck = DuckCards.ClassDeck.opened(at: file)
    }

    /// The deck cards are read with: the class's, or the starter deck if there is no class deck.
    var deck: DuckCards.Deck? { classDeck?.deck ?? DuckCards.Deck.bundled }

    /// Write a row into the deck as a Your card. Throws the kit's refusal.
    @discardableResult
    func save(row: [DuckCards.Entry], asCard tag: Int, name: String, does: String?,
              replacing: Bool) throws -> DuckCards.Card {
        guard var held = classDeck else { throw DuckCards.Refusal.noDeck }
        let card = try held.save(row: row, asCard: tag, name: name, does: does, replacing: replacing)
        classDeck = held
        return card
    }

    /// Take a card's meaning out of the deck. Throws the kit's refusal.
    func forget(_ tag: Int) throws {
        guard var held = classDeck else { throw DuckCards.Refusal.noDeck }
        try held.forget(tag)
        classDeck = held
    }

    /// A pack's Your cards, lent into the deck the way `Pack.lent` lends them. Returns the numbers
    /// the class already saved something else for; unless `replacing`, those keep the class's own
    /// meaning, so a screen can ask. Throws the kit's refusal.
    @discardableResult
    func lend(_ pack: DuckPacks.Pack, replacing: Bool) throws -> [Int] {
        guard var held = classDeck else { throw DuckCards.Refusal.noDeck }
        let (lent, clashes) = try pack.lent(to: held.deck, replacing: replacing)
        if lent.source != held.deck.source {
            try held.take(lent.source)
            classDeck = held
        }
        return clashes
    }

    /// A `.duckcards` file through the import door, as the sentence that says what happened.
    func take(_ data: Data) -> String {
        let said: String
        if var held = classDeck {
            do {
                let opened = try held.take(data)
                classDeck = held
                taken += 1
                said = DuckCards.Words.opened(opened)
            } catch let refusal as DuckCards.Refusal {
                said = refusal.message
            } catch {
                said = error.localizedDescription
            }
        } else {
            said = DuckCards.Refusal.noDeck.message
        }
        lastOpened = said
        return said
    }
}
