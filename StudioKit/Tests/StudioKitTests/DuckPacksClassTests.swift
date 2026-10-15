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
        XCTAssertNil(try DuckPacks.ClassPack.written([], deck: deck), "a pack holds at least one challenge")
        var d = DuckPacks.Draft(columns: 4, rows: 4)
        d.name = "Through the tunnel"
        d.hint = "Walk along the arrows."
        d.cycleGate(.init(0, 1))
        d.toggleWall(.init(1, 3), .init(1, 2))
        let one = try d.checked(id: DuckPacks.ClassPack.nextID(after: []), cards: cards)
        XCTAssertEqual(one.id, "class-1")
        let pack = try XCTUnwrap(try DuckPacks.ClassPack.written([one], deck: deck))
        XCTAssertEqual(pack.id, DuckPacks.ClassPack.id)
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
            DuckPacks.Words.designFooter, DuckPacks.Words.lendFooter, DuckPacks.Words.cameraOff,
            DuckPacks.Words.cameraRepeats, DuckPacks.Words.buggyFooter, DuckPacks.Words.noClassPack,
            DuckPacks.Words.board(ch), DuckPacks.Words.shareFooter(pack), DuckPacks.Words.opened(pack),
            DuckPacks.Words.openedWithClashes(pack, [200, 201]), DuckPacks.Words.clashQuestion(pack, [200]),
            DuckPacks.Words.cardsInPlay(pack, deck: deck), DuckPacks.Words.draftPar(4), DuckPacks.Words.draftPar(0),
        ]
        sentences += DuckPacks.Words.Tool.allCases.map(\.help)
        sentences += [DuckPacks.DraftRefusal.noName, .noHint, .unreachable, .alreadyThere, .tooLong(41)].map(\.message)
        for s in sentences {
            XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), s)
            XCTAssertNil(s.range(of: "(will|would) (land|stop) on", options: .regularExpression), s)
        }
        XCTAssertTrue(DuckPacks.Words.runFooter.contains("has not been measured"))
    }
}
