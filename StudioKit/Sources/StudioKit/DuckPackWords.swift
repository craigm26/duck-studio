import Foundation

/// Every sentence Studio's pack screens say. Here rather than in a view, so `swift test` reads them.
///
/// THE BOARD IS THE BOARD RULE. One Walk card is one square and one Turn card a quarter turn on the
/// board. On a duck, Walk and Turn are timed cards for now: closed-loop cards (`DuckCardLoop`) ship
/// off for real ducks until docs/PACKS.md "Acceptance" passes, and these sentences say so
/// (`DuckCardLoop.offNote`). Nothing here says a duck will stop on a square. `DuckPacksClassTests`
/// holds every sentence to that.
extension DuckPacks {

    public enum Words {

        // MARK: - the packs

        public static let packs = "Packs"
        public static let title = "Duck Card packs"
        public static let packsFooter =
            "A pack is a game for Duck Cards: the cards in play, a board, and challenges from easy to hard. "
          + "Open a .duckpack file someone shared and it joins this list."
        public static let openedHeading = "Opened packs"
        public static let classHeading = "Your class"
        public static let noClassPack =
            "No challenges of your own yet. Open any pack and choose Design a challenge."

        /// A grade band's heading: "PreK to K", "Grades 1 to 2".
        public static func band(_ pack: Pack) -> String {
            pack.gradeFrom >= 1 ? "Grades \(pack.grades)" : pack.grades
        }

        /// A pack's line in the list, under its name.
        public static func packLine(_ pack: Pack) -> String {
            let n = pack.challenges.count
            return "\(n) challenge\(n == 1 ? "" : "s"), scored by \(pack.score.rawValue)"
        }

        // MARK: - one pack

        public static let aboutHeading = "About"
        public static let cardsHeading = "Cards in play"
        public static let lessonsHeading = "Lessons"
        public static let challengesHeading = "Challenges"
        public static let yoursHeading = "Your cards in this pack"

        /// The cards in play, by the names printed on them.
        public static func cardsInPlay(_ pack: Pack, deck: DuckCards.Deck) -> String {
            pack.cards.map { deck.card(code: $0)?.name ?? $0 }.joined(separator: ", ")
        }

        public static func scoredBy(_ score: Score) -> String {
            switch score {
            case .steps: return "Scored by steps: the fewest steps the row makes on the board."
            case .cards: return "Scored by cards: the fewest cards in the row, so Repeat and Your cards pay off."
            }
        }

        /// Beside every board. Closed-loop cards are off for real ducks (`DuckCardLoop.spec.enabledOnRobot`),
        /// so a duck's Walk and Turn are timed and the board is the rule, not a map of where it stops.
        public static var boardRule: String {
            let rule = "On the board, one Walk card moves one square and one Turn card is a quarter turn. "
            guard DuckCardLoop.spec.enabledOnRobot else { return rule + DuckCardLoop.offNote }
            return rule + "On a duck that reports where it is, a Walk card walks one "
              + String(format: "%.0f", DuckCardLoop.spec.squareM * 100)
              + " cm square by the duck's own odometry and a Turn card turns a quarter turn by it, so the board "
              + "is the rule and the duck tries to follow it."
        }

        public static func ask(_ lesson: Lesson) -> String { "Ask: \(lesson.ask)" }
        public static func skill(_ lesson: Lesson) -> String { "Skill: \(lesson.skill)" }

        /// A challenge's line in the pack: its place in the ramp and its name.
        public static func challengeLine(_ index: Int, _ ch: Challenge) -> String { "\(index + 1). \(ch.name)" }
        public static let findTheBug = "Find the bug"

        public static func par(_ par: Int, _ score: Score) -> String {
            "Par \(par) \(score == .steps ? "step" : "card")\(par == 1 ? "" : "s")"
        }

        /// A Your card the pack lends: its number, name and what it does.
        public static func lends(_ card: DuckCards.Card) -> String {
            "\(card.tag)  \(card.name)" + (card.does.map { ". \($0)" } ?? "")
        }
        public static let lendFooter =
            "Lending writes these cards into the class deck, so the camera reads them as this pack means them. "
          + "A card your class already saved something else for is asked about first."
        public static let lend = "Lend them to the class deck"
        public static func clashTitle(_ clashes: [Int]) -> String {
            clashes.count == 1 ? "Replace card \(clashes[0])?" : "Replace \(clashes.count) cards?"
        }
        public static func clashQuestion(_ pack: Pack, _ clashes: [Int]) -> String {
            let cards = DuckCards.Words.listed(clashes.map { String($0) })
            return clashes.count == 1
                ? "Card \(cards) already means something else in your class deck. Replace it with what it means in \(pack.name), or keep your class's own."
                : "Cards \(cards) already mean something else in your class deck. Replace them with what they mean in \(pack.name), or keep your class's own."
        }
        public static let replaceThem = "Replace with the pack's"
        public static let keepOurs = "Keep our own"

        /// Said on a pack and its challenges when its Your cards clash with the class deck: the one
        /// rule the board, the duck and the camera all keep.
        public static func classMeaningWins(_ pack: Pack, _ clashes: [Int]) -> String {
            let which = clashes.count == 1 ? "Card \(clashes[0]) means" : "Cards \(DuckCards.Words.listed(clashes.map { String($0) })) mean"
            return "\(which) something else in your class deck. Your class's meaning is the one that plays, here on "
                 + "the board, on the duck and on the camera; \(pack.name)'s own is lent only where your class has none. "
                 + "Lend them to the class deck to use the pack's instead."
        }

        /// What lending did.
        public static func lent(_ pack: Pack, clashes: [Int], replaced: Bool) -> String {
            let kept = clashes.count == 1 ? "card \(clashes[0])" : "cards \(DuckCards.Words.listed(clashes.map { String($0) }))"
            if clashes.isEmpty || replaced {
                return "The class deck now holds \(pack.name)'s Your cards."
            }
            return "Kept your class's own \(kept). The rest of \(pack.name)'s Your cards are in the class deck."
        }

        public static let shareHeading = "Share"
        public static let share = "Share this pack"
        public static func shareFooter(_ pack: Pack) -> String {
            "Sends \(pack.id).\(fileExtension), the pack file itself. Open it in Microduck Studio on another "
          + "phone or Mac, or give it to the duck's card reader with --pack."
        }
        public static let remove = "Remove this pack"
        public static func removeQuestion(_ pack: Pack) -> String {
            "\(pack.name) leaves this list. Open its file again to bring it back."
        }

        // MARK: - one challenge

        public static func hint(_ ch: Challenge) -> String { "Hint: \(ch.hint)" }
        public static func note(_ note: String) -> String { "Note: \(note)" }
        public static func finishWith(_ code: String, deck: DuckCards.Deck) -> String {
            "Finish with \(deck.card(code: code)?.name ?? code)."
        }
        public static func gatesToPass(_ n: Int) -> String {
            n == 1 ? "Walk through the gate, along its arrows." : "Walk through all \(n) gates, along their arrows."
        }
        public static let boardHeading = "The board"
        public static let rowHeading = "Your row"
        public static let emptyRow = "Tap a card below to lay it in the row."
        public static let laidHeading = "Cards to lay"
        public static let laidFooter = "Tap a card to lay it at the end of the row. Only this pack's cards are here."
        public static let under = "Put a card under it"
        public static func underIt(_ name: String, on: Bool) -> String { on ? "Take \(name) away" : "Put \(name) under it" }
        public static let clearRow = "Clear the row"
        public static let removeCard = "Remove"
        public static func removeCardLabel(_ entry: DuckCards.Entry, at index: Int, deck: DuckCards.Deck) -> String {
            "Remove card \(index + 1), \(name(entry, deck: deck))"
        }

        /// A card's line in the row: its place, counted from 1, and its name.
        public static func rowCard(_ index: Int, _ entry: DuckCards.Entry, deck: DuckCards.Deck) -> String {
            "\(index + 1). \(name(entry, deck: deck))"
        }

        /// A card of a row being laid, a Repeat with its number: "3. Repeat 7 times".
        public static func laidCard(_ index: Int, _ entry: DuckCards.Entry, deck: DuckCards.Deck) -> String {
            guard entry.card == "repeat", let times = entry.times else { return rowCard(index, entry, deck: deck) }
            return "\(index + 1). \(DuckCards.Words.repeatTimes(0, of: 1, times: times))"
        }

        /// One card of the row: its name, what is under it.
        public static func name(_ entry: DuckCards.Entry, deck: DuckCards.Deck) -> String {
            let card = deck.card(code: entry.card)?.name ?? entry.card
            guard !entry.under.isEmpty else { return card }
            return "\(card), with \(DuckCards.Words.listed(entry.under.map { deck.card(code: $0)?.name ?? $0 }))"
        }

        public static let useCamera = "Use the row the camera read"
        public static let cameraOff =
            "Turn on Read Duck Cards on the camera card and lay a row from Start to End to use it here."
        public static let cameraNoRow = "The camera has no row from Start to End yet."
        public static let cameraRepeats =
            "Studio does not read the number on a Repeat card, so each Repeat starts at 2 here. Set it to the number on the card."

        public static let useBuggy = "Start from the buggy row"
        public static let buggyFooter = "This row has one wrong card. Play it, find the card, and swap it."

        public static let play = "Play on the board"
        public static let stop = "Stop"
        public static func playing(_ step: Int, of total: Int) -> String { "Step \(step) of \(total)" }
        public static let solved = "Solved"
        public static let notSolved = "Not solved yet"
        /// The score beside par, as the pack scores.
        public static func score(_ play: Play, _ score: Score) -> String {
            let unit = score == .steps ? "step" : "card"
            return "Score \(play.score) \(unit)\(play.score == 1 ? "" : "s"). Par \(play.par)."
        }

        public static let run = "Run on the duck"
        public static var runFooter: String {
            "The duck runs the same row as a plan, and nothing moves until you press Run in the plan editor. "
          + (DuckCardLoop.spec.enabledOnRobot
             ? "How far one Walk card carries a real duck has not been measured on yours, so the board does not say where the duck will stop."
             : DuckCardLoop.offNote)
        }

        // MARK: - the board, in words

        /// A square as VoiceOver says it, counted from 1: column across from the left, row down from the top.
        public static func square(_ s: Square) -> String { "column \(s.x + 1), row \(s.y + 1)" }

        public static func facing(_ f: Facing) -> String {
            switch f {
            case .north: return "north, up the board"
            case .east: return "east, to the right"
            case .south: return "south, down the board"
            case .west: return "west, to the left"
            }
        }

        public static func axis(_ a: Axis) -> String { a == .ns ? "walked through north to south" : "walked through east to west" }

        /// The whole board in sentences: its size, the start and facing, the goal, every wall and gate.
        public static func board(_ ch: Challenge) -> String {
            var out = "A \(ch.columns) by \(ch.rows) board. The duck starts at \(square(ch.start.at)), facing "
                    + "\(facing(ch.start.facing)). The goal is at \(square(ch.goal))."
            let walls = ch.walls.map { $0.squares.sorted { ($0.y, $0.x) < ($1.y, $1.x) } }
                .sorted { ($0[0].y, $0[0].x, $0[1].y, $0[1].x) < ($1[0].y, $1[0].x, $1[1].y, $1[1].x) }
            if walls.isEmpty {
                out += " No walls."
            } else {
                out += " " + (walls.count == 1 ? "A wall" : "\(walls.count) walls") + ": "
                    + walls.map { "between \(square($0[0])) and \(square($0[1]))" }.joined(separator: "; ") + "."
            }
            if !ch.gates.isEmpty {
                out += " " + (ch.gates.count == 1 ? "A gate" : "\(ch.gates.count) gates") + ": "
                    + ch.gates.map { "at \(square($0.at)), \(axis($0.axis))" }.joined(separator: "; ") + "."
            }
            return out
        }

        /// Where the board's duck is, as a play goes.
        public static func duckAt(_ p: Place) -> String { "The duck is at \(square(p.at)), facing \(facing(p.facing))." }

        // MARK: - drawing a challenge

        public static let design = "Design a challenge"
        public static func designFooter(_ name: String) -> String {
            "Draw a board of your own. It is checked and saved in \(name), which you can share as a .duckpack file."
        }
        public static let toolHeading = "Tap to place"

        public enum Tool: String, CaseIterable, Sendable {
            case start, goal, walls, gates
            public var name: String {
                switch self {
                case .start: return "Start"
                case .goal: return "Goal"
                case .walls: return "Walls"
                case .gates: return "Gates"
                }
            }
            public var help: String {
                switch self {
                case .start: return "Tap a square to put the duck there. Tap it again to turn it a quarter."
                case .goal: return "Tap a square to put the goal there."
                case .walls: return "Tap near the side of a square to put a wall there. Tap it again to take it down."
                case .gates: return "Tap a square for a gate. Tap again to turn it, and once more to take it away."
                }
            }
        }

        public static let sizeHeading = "Board size"
        public static func columns(_ n: Int) -> String { "Columns: \(n)" }
        public static func rows(_ n: Int) -> String { "Rows: \(n)" }
        public static let nameHeading = "Name"
        public static let namePlaceholder = "Round the reeds"
        public static let hintHeading = "Hint"
        public static let hintPlaceholder = "Count the squares before you lay a card."
        public static let parHeading = "Par"
        /// Par while drawing, worked out by the search, or why there is none. Scored by cards, it is
        /// the plain row's card count, which a shorter row the author lays may lower.
        public static func draftPar(_ par: Int?, _ score: Score = .steps, finishing: Bool = false) -> String {
            guard let par else { return DraftRefusal.unreachable.message }
            if par == (finishing ? 1 : 0) { return DraftRefusal.alreadyThere.message }
            let finish = finishing ? ", and the card it finishes with" : ""
            switch score {
            case .steps:
                return "Par \(par) step\(par == 1 ? "" : "s"): the fewest Walk and Turn cards that reach the goal"
                     + " through every gate\(finish). Worked out on the board, not typed in."
            case .cards:
                return "Par \(par) card\(par == 1 ? "" : "s"): the plain row, one card for each Walk and Turn on the"
                     + " shortest way through every gate\(finish). Worked out on the board, not typed in. You may"
                     + " lower it by finding a shorter row with Repeat, below; the board plays it to check."
            }
        }

        public static let finishHeading = "Finish with"
        public static let finishNone = "None"
        public static let finishFooter =
            "A card the duck does standing still, as the last card of the row, like Hello at the pond. It adds one to par."
        public static let noteHeading = "Note"
        public static let notePlaceholder = "One line for the class, if you like"

        public static let shorterHeading = "A shorter row"
        public static let shorterFooter =
            "Scored by cards, Repeat can beat the plain row. Lay the shortest row you can find, without Start and End. "
          + "It counts only if the board plays it to the goal in fewer cards."
        /// What the board said of the shorter row.
        public static func shorter(_ verdict: Draft.Shorter) -> String {
            switch verdict {
            case .none: return "No shorter row yet, so par is the plain row."
            case .beats(let n, let plain):
                return "Solved in \(n) card\(n == 1 ? "" : "s"), fewer than the plain row's \(plain). Par will be \(n)."
            case .noBetter(let n, let plain):
                return "Solved in \(n) card\(n == 1 ? "" : "s"), but the plain row takes \(plain), so par stays \(plain)."
            case .fails(let said): return "Not solved: \(said)"
            case .notInPlay(let names):
                return DraftRefusal.shorterNotInPlay(names).message
            }
        }

        public static func save(to name: String) -> String { "Save to \(name)" }
        public static func saved(_ ch: Challenge, in name: String) -> String { "Saved \(ch.name) to \(name)." }
        public static func removeChallenge(from name: String) -> String { "Remove from \(name)" }

        // MARK: - the class pack's settings

        public static let settings = "Class pack settings"
        public static let settingsNameHeading = "Pack name"
        public static let settingsNamePlaceholder = "Room 12's pack"
        public static let settingsScoreHeading = "Score"
        public static func scoreName(_ score: Score) -> String { score == .steps ? "Steps" : "Cards" }
        public static let settingsCardsHeading = "Cards in play"
        public static let settingsCardsFooter =
            "Start and End are always in play. A challenge is solved with the cards in play, so taking away a Walk or "
          + "Turn card a challenge needs is refused."
        public static let applySettings = "Save settings"
        public static func settingsSaved(_ name: String) -> String { "Saved. \(name) uses these settings." }
        public static func settingsID(_ id: String) -> String {
            "This pack's id is \(id). It stays the same, so another phone keeps your class's pack apart from another class's."
        }

        /// One square while drawing, for VoiceOver: where it is and what is on it.
        public static func square(_ s: Square, in draft: Draft) -> String {
            var parts = [square(s).prefix(1).uppercased() + square(s).dropFirst()]
            if draft.start.at == s { parts.append("the start, facing \(facing(draft.start.facing))") }
            if draft.goal == s { parts.append("the goal") }
            if let g = draft.gate(at: s) { parts.append("a gate \(axis(g.axis))") }
            let sides = Facing.allCases.filter { side in draft.neighbour(s, side).map { draft.hasWall(s, $0) } ?? false }
            if !sides.isEmpty {
                parts.append("a wall to the " + DuckCards.Words.listed(sides.map(\.rawValue)))
            }
            return parts.joined(separator: ", ")
        }
        public static let placeStart = "Put the start here, or turn it"
        public static let placeGoal = "Put the goal here"
        public static let cycleGate = "Add, turn or take away a gate"
        public static func wall(_ side: Facing, on: Bool) -> String {
            on ? "Take down the wall to the \(side.rawValue)" : "Put a wall to the \(side.rawValue)"
        }

        // MARK: - through the import door

        public static func opened(_ pack: Pack) -> String {
            let n = pack.challenges.count
            return "Opened the pack \(pack.name): \(n) challenge\(n == 1 ? "" : "s") for \(pack.grades). It is in Packs, on the camera card."
        }
        public static func openedWithClashes(_ pack: Pack, _ clashes: [Int]) -> String {
            opened(pack) + " " + lent(pack, clashes: clashes, replaced: false) + " Open the pack to replace them."
        }
        public static func notKept(_ why: String) -> String { "The pack could not be kept. \(why)" }

        /// A pack opened again with the same id as one already in Packs.
        public static let sameIDTitle = "Replace an opened pack?"
        public static func sameIDQuestion(_ incoming: Pack, _ existing: Pack) -> String {
            let same = incoming.name == existing.name
            return "\(existing.name) (\(existing.id), \(existing.challenges.count) challenge\(existing.challenges.count == 1 ? "" : "s")) "
                 + "is already in Packs with the same id. Replace it with "
                 + (same ? "this copy" : incoming.name)
                 + " (\(incoming.challenges.count) challenge\(incoming.challenges.count == 1 ? "" : "s")), or keep the one you have."
        }
        public static func waitingToReplace(_ incoming: Pack, _ existing: Pack) -> String {
            "\(existing.name) is already open with the same id as \(incoming.name). Open Packs to choose which to keep."
        }
        public static let replaceOpened = "Replace it"
        public static let keepOpened = "Keep the one I have"
        public static func keptOpened(_ existing: Pack) -> String { "Kept \(existing.name) as it was." }
        public static func alreadyOpen(_ pack: Pack) -> String { "\(pack.name) is already in Packs, exactly as this file has it." }
        public static func ownPack(_ pack: Pack) -> String {
            "This is your own class pack, \(pack.name). It is already in Packs under Your class."
        }
    }
}
