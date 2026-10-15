import XCTest
@testable import StudioKit

/// A class's own challenges, drawn in Studio: the editor's taps, par from the search, the class pack
/// written as a pack a reader takes, a row handed to the plan editor, and the words the screens say.
final class DuckPacksClassTests: XCTestCase {

    func deck() throws -> DuckCards.Deck { try XCTUnwrap(DuckCards.Deck.bundled, "the bundled deck did not load") }

    // MARK: - the shortest row

    func testTheShortestRowSolvesEveryStepsChallengeAtPar() throws {
        for pack in DuckPacks.bundled where pack.score == .steps {
            let played = try pack.lent(to: try deck()).deck
            for ch in pack.challenges {
                let row = try XCTUnwrap(DuckPacks.shortestRow(ch, cards: pack.cards), ch.id)
                XCTAssertEqual(row.count, DuckPacks.parSteps(ch, cards: pack.cards), ch.id)
                let r = DuckPacks.play(ch, row: row, score: .steps, deck: played)
                XCTAssertTrue(r.solved, "\(ch.id): \(r.said)")
                XCTAssertEqual(r.score, ch.par, ch.id)
            }
        }
    }

    // MARK: - drawing

    func testADraftStartsClearAndTapsDoWhatTheyShow() {
        var d = DuckPacks.Draft(columns: 3, rows: 3)
        XCTAssertEqual(d.start, DuckPacks.Place(at: .init(0, 2), facing: .north))
        XCTAssertEqual(d.goal, .init(2, 0))
        d.placeStart(.init(0, 2))
        XCTAssertEqual(d.start.facing, .east, "tapping the start again turns it")
        d.cycleGate(.init(1, 1))
        XCTAssertEqual(d.gate(at: .init(1, 1))?.axis, .ns)
        d.cycleGate(.init(1, 1))
        XCTAssertEqual(d.gate(at: .init(1, 1))?.axis, .ew)
        d.cycleGate(.init(1, 1))
        XCTAssertNil(d.gate(at: .init(1, 1)))
        d.cycleGate(d.start.at)
        XCTAssertTrue(d.gates.isEmpty, "a gate never sits on the start")
        d.cycleGate(.init(1, 2))
        d.placeStart(.init(1, 2))
        XCTAssertTrue(d.gates.isEmpty, "moving the start onto a gate takes the gate away")
        d.toggleWall(.init(0, 0), .init(1, 0))
        XCTAssertTrue(d.hasWall(.init(1, 0), .init(0, 0)))
        d.toggleWall(.init(1, 0), .init(0, 0))
        XCTAssertFalse(d.hasWall(.init(0, 0), .init(1, 0)))
        d.toggleWall(.init(0, 0), .init(1, 1))
        XCTAssertTrue(d.walls.isEmpty, "a wall sits only between squares that share an edge")
        d.toggleWall(.init(0, 0), .init(1, 0))
        d.resize(columns: 1, rows: 9)
        XCTAssertEqual(d.columns, DuckPacks.Draft.smallest)
        d.resize(columns: 2, rows: 2)
        XCTAssertEqual(d.goal, .init(1, 0))
        XCTAssertEqual(d.start.at, .init(1, 1))
    }

    func testATapNearASideMeansThatSide() {
        XCTAssertEqual(DuckPacks.Draft.side(across: 0.5, down: 0.05), .north)
        XCTAssertEqual(DuckPacks.Draft.side(across: 0.95, down: 0.5), .east)
        XCTAssertEqual(DuckPacks.Draft.side(across: 0.5, down: 0.9), .south)
        XCTAssertEqual(DuckPacks.Draft.side(across: 0.1, down: 0.4), .west)
        let d = DuckPacks.Draft(columns: 3, rows: 3)
        XCTAssertNil(d.neighbour(.init(0, 0), .north), "the board's edge is not toggled")
        XCTAssertEqual(d.neighbour(.init(0, 0), .east), .init(1, 0))
    }

    func testParIsTheSearchAndAnUnreachableGoalIsRefusedInASentence() throws {
        let cards = DuckPacks.ClassPack.cards(try deck())
        var d = DuckPacks.Draft(columns: 3, rows: 3)
        d.name = "Corner"
        d.hint = "Up, then right."
        XCTAssertEqual(d.par(cards: cards), 5)
        let ch = try d.checked(id: "class-1", cards: cards)
        XCTAssertEqual(ch.par, 5)
        XCTAssertEqual(DuckPacks.play(ch, row: ch.solution, score: .steps, deck: try deck()).solved, true)
        // Walled in: the goal's two open sides closed.
        d.toggleWall(.init(2, 0), .init(1, 0))
        d.toggleWall(.init(2, 0), .init(2, 1))
        XCTAssertNil(d.par(cards: cards))
        XCTAssertThrowsError(try d.checked(id: "class-1", cards: cards)) {
            XCTAssertEqual($0 as? DuckPacks.DraftRefusal, .unreachable)
        }
        XCTAssertEqual(DuckPacks.Words.draftPar(nil), DuckPacks.DraftRefusal.unreachable.message)
        var blank = DuckPacks.Draft(columns: 3, rows: 3)
        blank.hint = "x"
        XCTAssertThrowsError(try blank.checked(id: "a", cards: cards)) { XCTAssertEqual($0 as? DuckPacks.DraftRefusal, .noName) }
        blank.name = "Home"
        blank.placeGoal(blank.start.at)
        XCTAssertThrowsError(try blank.checked(id: "a", cards: cards)) {
            XCTAssertEqual($0 as? DuckPacks.DraftRefusal, .alreadyThere)
        }
        blank.cycleGate(.init(0, 1))
        XCTAssertNotNil(try? blank.checked(id: "a", cards: cards), "a gate makes going round and home a challenge")
    }

    // MARK: - the class pack

    func testTheClassPackIsAPackAReaderTakesWithItsBytes() throws {
        let deck = try deck()
        let cards = DuckPacks.ClassPack.cards(deck)
        XCTAssertTrue(cards.contains("start") && cards.contains("end") && cards.contains("walk_forward"))
        XCTAssertFalse(cards.contains("normal"), "a card the deck does not print is not in play")
        XCTAssertNil(try DuckPacks.ClassPack.written([], settings: .init(), deck: deck), "a pack holds at least one challenge")
        var d = DuckPacks.Draft(columns: 4, rows: 4)
        d.name = "Through the tunnel"
        d.hint = "Walk along the arrows."
        d.cycleGate(.init(0, 1))
        d.toggleWall(.init(1, 3), .init(1, 2))
        let one = try d.checked(id: DuckPacks.ClassPack.nextID(after: []), cards: cards)
        XCTAssertEqual(one.id, "class-1")
        let settings = DuckPacks.ClassPack.Settings()
        let pack = try XCTUnwrap(try DuckPacks.ClassPack.written([one], settings: settings, deck: deck))
        XCTAssertEqual(pack.id, settings.id)
        XCTAssertEqual(pack.name, DuckPacks.ClassPack.name, "the name until the teacher gives one")
        XCTAssertEqual(pack.cards, cards, "every printed card is in play until the teacher narrows them")
        XCTAssertEqual(pack.score, .steps)
        XCTAssertNil(pack.board.duckSquareCm)
        XCTAssertEqual(pack.challenges, [one])
        let again = try DuckPacks.Pack.read(pack.source, deck: deck)
        XCTAssertEqual(again.challenges, [one], "the shared bytes read back to the same challenge")
        XCTAssertEqual(DuckPacks.par(one, in: again), one.par)
        XCTAssertEqual(DuckPacks.ClassPack.nextID(after: [one]), "class-2")
    }

    func testAChallengeWritesWhatItWasReadFrom() throws {
        let deck = try deck()
        for pack in DuckPacks.bundled {
            let played = try pack.lent(to: deck).deck
            for (n, ch) in pack.challenges.enumerated() {
                let back = try DuckPacks.challenge(DuckPacks.json(ch), board: pack.board, cards: pack.cards,
                                                   deck: played, number: n + 1)
                XCTAssertEqual(back, ch, ch.id)
            }
        }
    }

    // MARK: - each class its own pack

    /// A generator that says the same numbers every run, so a minted id can be held to its shape.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    func testEachClassPackHasItsOwnIdThatAReaderTakes() throws {
        let deck = try deck()
        var rng = Seeded(state: 7)
        let a = DuckPacks.ClassPack.mintID(using: &rng), b = DuckPacks.ClassPack.mintID(using: &rng)
        XCTAssertNotEqual(a, b)
        for id in [a, b, DuckPacks.ClassPack.mintID()] {
            XCTAssertTrue(id.hasPrefix("class-") && id.count == 12, id)
            XCTAssertTrue(DuckPacks.isID(id), "\(id) is an id Pack.read and packs.py take")
            XCTAssertNil(id.dropFirst(6).rangeOfCharacter(from: CharacterSet(charactersIn: "01lo")), id)
        }
        var d = DuckPacks.Draft(columns: 3, rows: 3)
        d.name = "Corner"; d.hint = "Up, then right."
        let ch = try d.checked(id: "class-1", cards: DuckPacks.ClassPack.cards(deck))
        var room12 = DuckPacks.ClassPack.Settings(id: a)
        room12.name = "  Room 12's pack\n"
        let mine = try XCTUnwrap(try DuckPacks.ClassPack.written([ch], settings: room12, deck: deck))
        let theirs = try XCTUnwrap(try DuckPacks.ClassPack.written([ch], settings: .init(id: b), deck: deck))
        XCTAssertEqual(mine.name, "Room 12's pack", "one line, trimmed")
        XCTAssertEqual(theirs.name, DuckPacks.ClassPack.name)
        XCTAssertNotEqual(mine.id, theirs.id, "two classes' packs are two packs")
        XCTAssertEqual(try DuckPacks.Pack.read(mine.source, deck: deck).id, a)

        // Kept as it was written, and read back the same.
        XCTAssertEqual(DuckPacks.ClassPack.Settings.read(room12.data), room12)
        XCTAssertNil(DuckPacks.ClassPack.Settings.read(Data(#"{"id":"Not An Id","name":"x","score":"steps"}"#.utf8)))
        // A pack from before every class had its own id gets a new one, and keeps its name and score.
        let old = try XCTUnwrap(try DuckPacks.ClassPack.written([ch], settings: .init(id: DuckPacks.ClassPack.legacyID),
                                                               deck: deck))
        let moved = DuckPacks.ClassPack.Settings.of(old, deck: deck)
        XCTAssertNotEqual(moved.id, DuckPacks.ClassPack.legacyID)
        XCTAssertTrue(moved.id.hasPrefix(DuckPacks.ClassPack.idPrefix))
        XCTAssertEqual(moved.name, DuckPacks.ClassPack.name)
        XCTAssertNil(moved.cards, "every printed card stays every printed card")
        XCTAssertEqual(DuckPacks.ClassPack.Settings.of(mine, deck: deck).id, a, "an id already its own is kept")
    }

    // MARK: - finish with

    func testFinishWithIsACardInPlayDoneStandingStillAndParCountsIt() throws {
        let deck = try deck()
        let cards = DuckPacks.ClassPack.cards(deck)
        let offered = DuckPacks.Draft.finishes(cards, deck: deck)
        XCTAssertTrue(offered.contains("greet") && offered.contains("stop") && offered.contains("roll"))
        for never in DuckPacks.moves + ["start", "end", "repeat", "end_repeat", "slow", "look_left", "when_falls"] {
            XCTAssertFalse(offered.contains(never), never)
        }
        XCTAssertTrue(offered.allSatisfy(DuckPacks.canFinish(with:)), "the editor offers only what Pack.read takes")
        var d = DuckPacks.Draft(columns: 3, rows: 3)
        d.name = "Hello at the corner"; d.hint = "Up, right, then say hello."
        XCTAssertEqual(d.par(cards: cards), 5)
        d.finishWith = "greet"
        XCTAssertEqual(d.par(cards: cards), 6, "par moves with the finishing card, as the board counts it")
        let ch = try d.checked(id: "class-1", cards: cards)
        XCTAssertEqual(ch.finishWith, "greet")
        XCTAssertEqual(ch.solution.last?.card, "greet")
        let r = DuckPacks.play(ch, row: ch.solution, score: .steps, deck: deck)
        XCTAssertTrue(r.solved, r.said)
        XCTAssertEqual(r.score, 6)
        let pack = try XCTUnwrap(try DuckPacks.ClassPack.written([ch], settings: .init(), deck: deck))
        XCTAssertEqual(pack.challenges.first?.finishWith, "greet", "written and read back")
        XCTAssertThrowsError(try d.checked(id: "class-1", cards: cards.filter { $0 != "greet" })) {
            XCTAssertEqual($0 as? DuckPacks.DraftRefusal, .finishNotInPlay("greet"))
        }
        var home = DuckPacks.Draft(columns: 3, rows: 3)
        home.name = "Home"; home.hint = "x"; home.finishWith = "greet"
        home.placeGoal(home.start.at)
        XCTAssertThrowsError(try home.checked(id: "a", cards: cards)) {
            XCTAssertEqual($0 as? DuckPacks.DraftRefusal, .alreadyThere, "a finish with no moves is no challenge")
        }
        XCTAssertEqual(DuckPacks.Words.draftPar(home.par(cards: cards), finishing: true),
                       DuckPacks.DraftRefusal.alreadyThere.message)
    }

    // MARK: - scored by cards

    /// Two rows deep and eight squares across: up one, right, then seven Walk cards, or a Repeat.
    func hall() -> DuckPacks.Draft {
        var d = DuckPacks.Draft(columns: 8, rows: 2)
        d.name = "Long hall"; d.hint = "Count the squares."; d.note = "Room 12 drew this.\nOne line."
        return d
    }

    func testScoredByCardsParIsThePlainRowUntilARepeatRowBeatsItOnTheBoard() throws {
        let deck = try deck()
        let cards = DuckPacks.ClassPack.cards(deck)
        var d = hall()
        XCTAssertEqual(d.par(cards: cards), 9)
        XCTAssertEqual(d.shorterVerdict(cards: cards, deck: deck), .none)
        let plain = try d.checked(id: "class-1", cards: cards, score: .cards, deck: deck)
        XCTAssertEqual(plain.par, 9, "the plain row's card count")
        XCTAssertEqual(plain.note, "Room 12 drew this. One line.", "a note is one line")

        let loop = [DuckCards.Entry(card: "walk_forward"), DuckCards.Entry(card: "turn_right"),
                    DuckCards.Entry(card: "repeat", times: 7), DuckCards.Entry(card: "walk_forward"),
                    DuckCards.Entry(card: "end_repeat")]
        d.shorter = loop
        XCTAssertEqual(d.shorterVerdict(cards: cards, deck: deck), .beats(cards: 5, plain: 9))
        let ch = try d.checked(id: "class-1", cards: cards, score: .cards, deck: deck)
        XCTAssertEqual(ch.par, 5)
        XCTAssertEqual(ch.solution, loop)
        XCTAssertEqual(try d.checked(id: "class-1", cards: cards).par, 9, "scored by steps, the Repeat row is not par")

        d.shorter = [DuckCards.Entry(card: "walk_forward"), DuckCards.Entry(card: "turn_right"),
                     DuckCards.Entry(card: "repeat", times: 6), DuckCards.Entry(card: "walk_forward"),
                     DuckCards.Entry(card: "end_repeat")]
        guard case .fails = d.shorterVerdict(cards: cards, deck: deck) else { return XCTFail("one square short") }
        XCTAssertThrowsError(try d.checked(id: "class-1", cards: cards, score: .cards, deck: deck)) {
            guard case .shorterDoesNotSolve = $0 as? DuckPacks.DraftRefusal else { return XCTFail("\($0)") }
        }
        d.shorter = try XCTUnwrap(DuckPacks.shortestRow(d.unchecked(id: "x"), cards: cards))
        XCTAssertEqual(d.shorterVerdict(cards: cards, deck: deck), .noBetter(cards: 9, plain: 9))
        XCTAssertEqual(try d.checked(id: "class-1", cards: cards, score: .cards, deck: deck).par, 9)
        d.shorter = [DuckCards.Entry(card: "roll")]
        XCTAssertEqual(d.shorterVerdict(cards: ["start", "end", "walk_forward", "turn_right"], deck: deck),
                       .notInPlay(["Roll"]))

        // The pack the teacher set: scored by cards, fewer cards in play, read back by Pack.read.
        let settings = DuckPacks.ClassPack.Settings(name: "Room 12's pack", score: .cards,
                                                    cards: ["walk_forward", "turn_right", "repeat", "end_repeat"])
        let pack = try XCTUnwrap(try DuckPacks.ClassPack.written([ch], settings: settings, deck: deck))
        XCTAssertEqual(pack.cards, ["walk_forward", "turn_right", "start", "end", "repeat", "end_repeat"]
            .sorted { cards.firstIndex(of: $0)! < cards.firstIndex(of: $1)! }, "Start and End always in play")
        XCTAssertEqual(pack.score, .cards)
        XCTAssertEqual(DuckPacks.par(ch, in: pack), 5)
        XCTAssertEqual(pack.challenges.first?.note, ch.note)
        XCTAssertTrue(DuckPacks.play(ch, row: ch.solution, score: .cards, deck: deck).solved)
    }

    func testNewSettingsRecheckEveryChallengeOrChangeNothing() throws {
        let deck = try deck()
        let cards = DuckPacks.ClassPack.cards(deck)
        var d = hall()
        d.shorter = [DuckCards.Entry(card: "walk_forward"), DuckCards.Entry(card: "turn_right"),
                     DuckCards.Entry(card: "repeat", times: 7), DuckCards.Entry(card: "walk_forward"),
                     DuckCards.Entry(card: "end_repeat")]
        let byCards = try d.checked(id: "class-1", cards: cards, score: .cards, deck: deck)
        var hello = DuckPacks.Draft(columns: 3, rows: 3)
        hello.name = "Hello"; hello.hint = "x"; hello.finishWith = "greet"
        let greet = try hello.checked(id: "class-2", cards: cards)

        let steps = try DuckPacks.ClassPack.rechecked([byCards, greet], settings: .init(score: .steps), deck: deck)
        XCTAssertEqual(steps.map(\.par), [9, 6], "scored by steps, par is the search again")
        let back = try DuckPacks.ClassPack.rechecked([byCards, greet], settings: .init(score: .cards), deck: deck)
        XCTAssertEqual(back.map(\.par), [5, 6], "the author's Repeat row still beats the plain row")
        XCTAssertEqual(try DuckPacks.ClassPack.rechecked(steps, settings: .init(score: .cards), deck: deck).map(\.par),
                       [9, 6], "a row the search wrote is the plain row")
        let leftOnly = ["walk_forward", "turn_left", "greet"]
        XCTAssertEqual(try DuckPacks.ClassPack.rechecked([greet], settings: .init(cards: leftOnly), deck: deck).first?.par,
                       8, "no Turn right: three Turn lefts, and the finish")
        XCTAssertThrowsError(try DuckPacks.ClassPack.rechecked([byCards], settings: .init(cards: ["walk_forward"]), deck: deck)) {
            XCTAssertEqual($0 as? DuckPacks.DraftRefusal, .notSolvable("Long hall"))
        }
        XCTAssertThrowsError(try DuckPacks.ClassPack.rechecked([greet], settings: .init(cards: ["walk_forward", "turn_right"]),
                                                               deck: deck)) {
            XCTAssertEqual($0 as? DuckPacks.DraftRefusal, .finishNotInPlay("Hello"))
        }
    }

    func testANoteIsOneLineOrRefused() throws {
        let deck = try deck()
        let pond = try XCTUnwrap(DuckPacks.bundled.first { $0.id == "get-to-the-pond" })
        var top = try XCTUnwrap(try JSONSerialization.jsonObject(with: pond.source) as? [String: Any])
        var chs = try XCTUnwrap(top["challenges"] as? [[String: Any]])
        chs[0]["note"] = "Try it with your eyes shut."
        top["challenges"] = chs
        let read = try DuckPacks.Pack.read(try JSONSerialization.data(withJSONObject: top), deck: deck)
        XCTAssertEqual(read.challenges[0].note, "Try it with your eyes shut.")
        XCTAssertNil(read.challenges[1].note)
        chs[0]["note"] = "two\nlines"
        top["challenges"] = chs
        XCTAssertThrowsError(try DuckPacks.Pack.read(try JSONSerialization.data(withJSONObject: top), deck: deck)) {
            XCTAssertEqual(($0 as? DuckPacks.Refusal)?.message, "pond-1: a note is one line of words, or null.")
        }
    }

    // MARK: - to the duck

    func testARowOnTheBoardIsHandedAsTheStepsTheBoardPlayed() throws {
        let deck = try deck()
        let row = [DuckCards.Entry(card: "repeat", times: 2), DuckCards.Entry(card: "walk_forward", under: ["slow"]),
                   DuckCards.Entry(card: "end_repeat"), DuckCards.Entry(card: "turn_right")]
        let handed = try DuckPacks.handed(row, deck: deck)
        XCTAssertEqual(handed.plan.nodes.count, DuckPacks.steps(of: row, deck: deck).count)
        XCTAssertEqual(handed.by, .cards(deck))
        XCTAssertThrowsError(try DuckPacks.handed([], deck: deck))
    }

    // MARK: - the words

    func testTheBoardIsDescribedInWords() throws {
        let pond = try XCTUnwrap(DuckPacks.bundled.first { $0.id == "duck-maze" })
        let ch = try XCTUnwrap(pond.challenges.first { !$0.walls.isEmpty && !$0.gates.isEmpty })
        let said = DuckPacks.Words.board(ch)
        XCTAssertTrue(said.hasPrefix("A \(ch.columns) by \(ch.rows) board. The duck starts at column"))
        XCTAssertTrue(said.contains("The goal is at \(DuckPacks.Words.square(ch.goal))."))
        XCTAssertTrue(said.contains("between column"))
        XCTAssertTrue(said.contains("walked through"))
        var d = DuckPacks.Draft(columns: 3, rows: 3)
        d.toggleWall(.init(0, 2), .init(1, 2))
        XCTAssertEqual(DuckPacks.Words.square(.init(0, 2), in: d),
                       "Column 1, row 3, the start, facing north, up the board, a wall to the east")
    }

    func testNoSentenceSaysADuckLandsOnASquareOrUsesADash() throws {
        let deck = try deck()
        let pack = try XCTUnwrap(DuckPacks.bundled.last)
        let ch = try XCTUnwrap(pack.challenges.first)
        var sentences = [
            DuckPacks.Words.packsFooter, DuckPacks.Words.boardRule, DuckPacks.Words.runFooter,
            DuckPacks.Words.designFooter("Room 12's pack"), DuckPacks.Words.lendFooter, DuckPacks.Words.cameraOff,
            DuckPacks.Words.cameraRepeats, DuckPacks.Words.buggyFooter, DuckPacks.Words.noClassPack,
            DuckPacks.Words.board(ch), DuckPacks.Words.shareFooter(pack), DuckPacks.Words.opened(pack),
            DuckPacks.Words.openedWithClashes(pack, [200, 201]), DuckPacks.Words.clashQuestion(pack, [200]),
            DuckPacks.Words.cardsInPlay(pack, deck: deck), DuckPacks.Words.draftPar(4), DuckPacks.Words.draftPar(0),
            DuckPacks.Words.draftPar(9, .cards, finishing: true), DuckPacks.Words.finishFooter,
            DuckPacks.Words.shorterFooter, DuckPacks.Words.settingsCardsFooter, DuckPacks.Words.settingsID("class-k3p9qz"),
            DuckPacks.Words.classMeaningWins(pack, [200, 201]), DuckPacks.Words.classMeaningWins(pack, [200]),
            DuckPacks.Words.sameIDQuestion(pack, pack), DuckPacks.Words.waitingToReplace(pack, pack),
            DuckPacks.Words.ownPack(pack), DuckPacks.Words.alreadyOpen(pack),
        ]
        sentences += [DuckPacks.Draft.Shorter.none, .beats(cards: 5, plain: 9), .noBetter(cards: 9, plain: 9),
                      .fails("Bumped into a wall on step 2."), .notInPlay(["Roll"])].map(DuckPacks.Words.shorter)
        sentences += DuckPacks.Words.Tool.allCases.map(\.help)
        sentences += [DuckPacks.DraftRefusal.noName, .noHint, .unreachable, .alreadyThere, .tooLong(41),
                       .finishNotInPlay("Hello"), .shorterDoesNotSolve("Bumped."), .shorterNotInPlay(["Roll", "Kick"]),
                       .notSolvable("Long hall")].map(\.message)
        for s in sentences {
            XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), s)
            XCTAssertNil(s.range(of: "(will|would) (land|stop) on", options: .regularExpression), s)
        }
        // Closed-loop cards are off for real ducks, so the board and Run on the duck say a duck's cards are timed.
        XCTAssertTrue(DuckPacks.Words.runFooter.hasSuffix(DuckCardLoop.offNote))
        XCTAssertTrue(DuckPacks.Words.boardRule.hasSuffix(DuckCardLoop.offNote))
    }
}
