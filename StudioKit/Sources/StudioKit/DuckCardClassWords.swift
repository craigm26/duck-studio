import Foundation

extension DuckCards.Words {

    // MARK: - the camera card

    public static let title = "Duck Cards"
    public static let openInPlanEditor = "Open in the plan editor"
    public static let saveAsCard = "Save as a card"
    public static let classDeck = "Class deck"
    public static let close = "Close"

    // MARK: - a reading, held still

    public static let heldHeading = "From the cards"
    public static let heldFooter =
        "Read once and held still. Change the cards and read them again to change this."

    // MARK: - Repeat, asked

    public static let howManyTimes = "How many times?"
    public static let repeatAsked =
        "Studio does not read the number written on a Repeat card, so it asks. Repeats are counted from Start."
    /// One Repeat's question, by its place among the Repeats asked about, from 0.
    public static func repeatTimes(_ index: Int, of total: Int, times: Int) -> String {
        let goes = times == 1 ? "1 time" : "\(times) times"
        return total == 1 ? "Repeat \(goes)" : "Repeat \(index + 1): \(goes)"
    }
    public static let useTheseNumbers = "Use these numbers"

    // MARK: - into the plan editor

    /// What the plan editor says of a plan read off cards, in place of a router's name.
    public static let readFromCards = "Read from Duck Cards."
    public static let fallNotInPlan = "A plan has no events, so the When it falls row is not in it."

    /// The reader's notes on a row, and what the plan leaves out, for the editor to show under it.
    public static func planNotes(_ program: DuckCards.Program) -> [String] {
        program.notes + (program.onFall.isEmpty ? [] : [fallNotInPlan])
    }

    // MARK: - saving a row as a Your card

    public static let saveTitle = "Save as a card"
    public static let numberHeading = "Card number"
    public static let numberLabel = "Number"
    /// A number in the picker: what it means already, or that the starter deck did not print it.
    public static func number(_ tag: Int, meaning card: DuckCards.Card?, printed: Bool) -> String {
        if let card { return "\(tag): \(card.name)" }
        return printed ? "\(tag)" : "\(tag), not in the starter deck"
    }
    public static let nameHeading = "Name"
    public static let namePlaceholder = "Victory dance"
    public static let doesHeading = "What it does"
    public static let doesPlaceholder = "Walk forward fast, then roll."
    public static let doesFooter =
        "Optional. The deck keeps it beside the row, and the printed card has a line for it."
    public static let save = "Save"
    public static let fallNotInCard =
        "A Your card holds the row from Start to End. The When it falls row is not saved with it."
    /// Said once the binding is in the deck file: which printed blank gets the name.
    public static func saved(_ card: DuckCards.Card) -> String {
        "Saved as card \(card.tag). Write \"\(card.name)\" on the blank card numbered \(card.tag)."
    }
    public static func replaceTitle(_ card: DuckCards.Card) -> String { "Replace card \(card.tag)?" }
    public static func replaceQuestion(_ card: DuckCards.Card, heldBy: [Int]) -> String {
        "Card \(card.tag) already means \(card.name). Saving this row replaces it." + changesToo(heldBy)
    }
    public static let replace = "Replace it"
    public static let keepIt = "Keep it"

    /// Who else changes: the Your cards that hold this one.
    static func changesToo(_ heldBy: [Int]) -> String {
        switch heldBy.count {
        case 0: return ""
        case 1: return " Card \(heldBy[0]) holds it, so it changes too."
        default: return " Cards \(listed(heldBy.map { String($0) })) hold it, so they change too."
        }
    }

    /// "a", "a and b", "a, b and c".
    static func listed(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    // MARK: - the class deck

    public static let deckTitle = "Class deck"
    public static let yourCardsHeading = "Your cards"
    public static let noYourCards =
        "No Your card means anything yet. Read a row from Start to End, then Save as a card."
    public static let deckFooter =
        "What a Your card means lives in the deck file, not on \(DeviceWords.current.the). Open a "
      + ".duckcards file someone shared and it becomes this deck."
    /// A saved card's line: its number and name.
    public static func yourCard(_ card: DuckCards.Card) -> String { "\(card.tag)  \(card.name)" }
    /// What a saved card runs, in the reader's own words.
    public static func runs(_ program: DuckCards.Program?) -> String {
        guard let words = program?.words, !words.isEmpty else { return makesNoStep }
        return words
    }
    public static let makesNoStep = "It makes no step."
    public static let forget = "Forget"
    public static func forgetTitle(_ card: DuckCards.Card) -> String { "Forget card \(card.tag)?" }
    public static func forgetQuestion(_ card: DuckCards.Card, heldBy: [Int]) -> String {
        "Card \(card.tag) goes back to a blank, and \(card.name) is gone from the deck." + changesToo(heldBy)
    }
    public static func forgot(_ tag: Int) -> String { "Card \(tag) is a blank again." }
    public static let shareDeck = "Share the class deck"
    public static let shareFooter =
        "Sends \(DuckCards.ClassDeck.fileName), the deck file with your cards in it. Open it in "
      + "Microduck Studio on another phone or Mac, or give it to the duck's card reader with --deck."

    /// What opening a deck file did, for the import door to say.
    public static func opened(_ taken: DuckCards.ClassDeck.Taken) -> String {
        var out = "Opened the class deck. "
        let cards = taken.cards.map { "\($0.tag) \($0.name)" }
        switch cards.count {
        case 0: out += "None of its Your cards means anything yet."
        case 1: out += "It gives a meaning to 1 Your card: \(cards[0])."
        default: out += "It gives a meaning to \(cards.count) Your cards: \(listed(cards))."
        }
        if !taken.replaced.isEmpty {
            out += " It replaced what \(DeviceWords.current.this) had saved for "
                 + listed(taken.replaced.map { "\($0.tag) \($0.name)" }) + "."
        }
        if !taken.ignored.isEmpty {
            let cards = listed(taken.ignored.map { String($0) })
            out += taken.ignored.count == 1
                ? " It also said something else about card \(cards), which kept its own meaning: a number never changes what it means."
                : " It also said something else about cards \(cards), which kept their own meanings: a number never changes what it means."
        }
        return out
    }

    /// The class deck on disk could not be read, so the starter deck is in use.
    public static func classDeckUnread(_ refusal: DuckCards.Refusal) -> String {
        let why: String
        if case .notADeck(let words) = refusal { why = words } else { why = refusal.message }
        return "Studio's copy of the class deck could not be read (\(why)), so cards are read with the "
             + "starter deck. The next card saved writes over it."
    }
}
