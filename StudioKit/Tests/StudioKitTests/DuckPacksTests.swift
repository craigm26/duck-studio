import XCTest
@testable import StudioKit

/// Duck Card packs in Studio, held to the duck's reader.
///
/// EVERY PACK VECTOR IN `cardreader/vectors`, PLAYED HERE AS THERE. A pack vector is a challenge, a
/// row and the play result `cardreader/duckcards/packs.py` made of it; the JSON this side makes
/// must be the same, field for field. `scripts/check_duckcards_vectors.sh` keeps the fixture copy
/// identical to the source, and the bundled packs identical to the reader's copies.
final class DuckPacksTests: XCTestCase {

    func deck() throws -> DuckCards.Deck { try XCTUnwrap(DuckCards.Deck.bundled, "the bundled deck did not load") }

    // MARK: - the vectors

    func testEveryPackVectorPlaysAsTheDucksReaderPlaysIt() throws {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/DuckCards/vectors", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("pack_") && $0.pathExtension == "json" }
        XCTAssertEqual(files.count, 17, "a pack vector went missing from the fixtures")
        for url in files {
            let name = url.lastPathComponent
            let v = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let yours = try DuckPacks.yourCards(v["yours"], deck: try deck())
            let played = try DuckPacks.lend(yours, to: try deck()).deck
            let b = try XCTUnwrap(v["board"] as? [String: Any])
            let board = DuckPacks.Board(columns: b["columns"] as! Int, rows: b["rows"] as! Int,
                                        squareCm: (b["square_cm"] as! NSNumber).doubleValue,
                                        duckSquareCm: (b["duck_square_cm"] as? NSNumber)?.doubleValue)
            let ch = try DuckPacks.challenge(v["challenge"]!, board: board, cards: v["cards"] as! [String],
                                             deck: played, number: 1)
            let row = try DuckPacks.row(v["row"], deck: played, name, "the row")
            let score = try XCTUnwrap(DuckPacks.Score(rawValue: v["score"] as! String))
            let got = DuckPacks.play(ch, row: row, score: score, deck: played)
            let want = try XCTUnwrap(v["expect"] as? [String: Any])
            // Compared as JSON with its keys sorted: the same text means the same result, and a
            // Swift true and the JSON true the reader wrote are the same once both are JSON.
            func canonical(_ o: Any) throws -> String {
                String(decoding: try JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), as: UTF8.self)
            }
            XCTAssertEqual(try canonical(got.json), try canonical(want), name)
            XCTAssertEqual(got.solved, want["solved"] as? Bool, name)
            XCTAssertEqual(got.said, want["said"] as? String, name)
        }
    }

    // MARK: - the packs this app ships

    func testTheFourPacksShipYoungestFirst() throws {
        XCTAssertEqual(DuckPacks.bundled.map(\.id), ["get-to-the-pond", "duck-maze", "loop-the-course", "design-a-level"])
        XCTAssertEqual(DuckPacks.bundled.map(\.challenges.count), [6, 10, 10, 3])
    }

    func testEveryBundledChallengeIsSolvedByItsSolutionAtPar() throws {
        for pack in DuckPacks.bundled {
            let played = try pack.lent(to: try deck()).deck
            for ch in pack.challenges {
                let reach = try XCTUnwrap(DuckPacks.parSteps(ch, cards: pack.cards), "\(ch.id) cannot be reached")
                if pack.score == .steps { XCTAssertEqual(ch.par, reach, ch.id) } else { XCTAssertLessThanOrEqual(ch.par, reach, ch.id) }
                XCTAssertEqual(DuckPacks.par(ch, in: pack), ch.par, ch.id)
                let r = DuckPacks.play(ch, row: ch.solution, score: pack.score, deck: played)
                XCTAssertTrue(r.solved, "\(ch.id): \(r.said)")
                XCTAssertEqual(r.score, ch.par, ch.id)
                if let buggy = ch.buggy {
                    XCTAssertFalse(DuckPacks.play(ch, row: buggy, score: pack.score, deck: played).solved, ch.id)
                    XCTAssertTrue(DuckPacks.swaps(buggy, in: pack, deck: played).contains {
                        DuckPacks.play(ch, row: $0.row, score: pack.score, deck: played).solved
                    }, ch.id)
                }
            }
        }
    }

    func testAPackIsSharedAsTheBytesItWasReadFrom() throws {
        let pack = try XCTUnwrap(DuckPacks.bundled.first)
        let again = try DuckPacks.Pack.read(pack.source, deck: try deck())
        XCTAssertEqual(again.challenges, pack.challenges)
        // A duck square is the square the closed-loop cards walk, with where it was measured.
        for p in DuckPacks.bundled {
            XCTAssertEqual(p.board.duckSquareCm, DuckCardLoop.spec.squareM * 100, p.id)
            XCTAssertTrue(p.board.duckSquareSource?.contains("not measured") == true, p.id)
        }
    }

    func testADuckSquareComesWithItsSourceAndNotWithout() throws {
        try refused(try tiny { d in
            d["board"] = ["columns": 3, "rows": 3, "square_cm": 30, "duck_square_cm": 30]
        }, "carries duck_square_source")
        try refused(try tiny { d in
            d["board"] = ["columns": 3, "rows": 3, "square_cm": 30, "duck_square_cm": NSNull(),
                          "duck_square_source": "a guess"]
        }, "an unmeasured one carries none")
        let pack = try DuckPacks.Pack.read(try tiny { d in
            d["board"] = ["columns": 3, "rows": 3, "square_cm": 30, "duck_square_cm": 30,
                          "duck_square_source": "measured somewhere"]
        }, deck: try deck())
        XCTAssertEqual(pack.board.duckSquareSource, "measured somewhere")
    }

    // MARK: - reading a pack

    func tiny(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var data: [String: Any] = [
            "format": "duck-pack/0", "id": "tiny", "name": "Tiny", "grades": "K", "grade_from": 0, "grade_to": 0,
            "vocabulary": "r001", "license": "CC-BY-4.0", "credit": "Duck Cards, from microduckstudio.com",
            "about": "One square to walk.",
            "cards": ["start", "end", "walk_forward", "turn_left", "turn_right", "walk_backward", "greet"],
            "score": "steps", "board": ["columns": 3, "rows": 3, "square_cm": 30, "duck_square_cm": NSNull()],
            "challenges": [challenge()], "lessons": [], "yours": []]
        change(&data)
        return try JSONSerialization.data(withJSONObject: data)
    }

    func challenge(_ change: (inout [String: Any]) -> Void = { _ in }) -> [String: Any] {
        var c: [String: Any] = ["id": "t-1", "name": "Step", "start": ["at": [1, 2], "facing": "north"], "goal": [1, 1],
                                "walls": [], "gates": [], "finish_with": NSNull(), "par": 1,
                                "solution": [["card": "walk_forward"]], "buggy": NSNull(), "hint": "One step."]
        change(&c)
        return c
    }

    func refused(_ data: Data, _ words: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertThrowsError(try DuckPacks.Pack.read(data, deck: try deck()), file: file, line: line) { error in
            let message = (error as? DuckPacks.Refusal)?.message ?? "\(error)"
            XCTAssertTrue(message.contains(words), "\(message) does not say \(words)", file: file, line: line)
        }
    }

    func testRefusalsSayWhatToFixInTheReadersWords() throws {
        try refused(Data("{not json".utf8), "not JSON")
        try refused(try tiny { $0["format"] = "duck-cards/0" }, "format is not duck-pack/0")
        try refused(try tiny { $0["vocabulary"] = "r002" }, "vocabulary 'r002'")
        try refused(try tiny { $0["cards"] = ["start", "end", "moonwalk"] }, "'moonwalk', which is not a card")
        try refused(try tiny { $0["cards"] = ["walk_forward"] }, "Every pack plays Start and End.")
        try refused(try tiny { $0["score"] = "time" }, "score is steps or cards")
        try refused(try tiny { $0["grade_from"] = 3; $0["grade_to"] = 1 }, "grade_from to grade_to")
        try refused(try tiny { $0["challenges"] = [self.challenge { $0["goal"] = [3, 0] }] },
                    "t-1: the goal [3, 0] is off the 3 x 3 board.")
        try refused(try tiny { $0["challenges"] = [self.challenge { $0["walls"] = [["between": [[0, 0], [1, 1]]]] }] },
                    "share an edge")
        try refused(try tiny { $0["challenges"] = [self.challenge { $0["gates"] = [["at": [1, 1], "axis": "up"]] }] },
                    "axis is ns or ew")
        try refused(try tiny { $0["challenges"] = [self.challenge { $0["finish_with"] = "walk_forward" }] }, "standing still")
        try refused(try tiny { $0["challenges"] = [self.challenge { $0["solution"] = [["card": "repeat"]] }] },
                    "needs times, 1 to 9")
        try refused(try tiny { $0["challenges"] = [self.challenge(), self.challenge()] }, "same id")
        let yours: [String: Any] = ["tag": 200, "code": "card_1", "name": "Hello twice", "category": "yours",
                                    "kind": "yours", "plan": NSNull(), "row": [["card": "nope"]]]
        try refused(try tiny { $0["yours"] = [yours] }, "A Your card in this pack cannot be read: card_1: its row holds 'nope'")
    }

    func testAPackLendsItsYourCardsButNotOverTheClasssOwn() throws {
        let hello: [String: Any] = ["tag": 200, "code": "card_1", "name": "Double hello", "category": "yours",
                                    "kind": "yours", "plan": NSNull(), "row": [["card": "greet"], ["card": "greet"]]]
        let pack = try DuckPacks.Pack.read(try tiny { $0["yours"] = [hello] }, deck: try deck())
        XCTAssertEqual(try pack.lent(to: try deck()).deck.card(200)?.name, "Double hello")
        let theirs = try deck().replacing([["tag": 200, "code": "card_1", "name": "Roll over", "category": "yours",
                                            "kind": "yours", "plan": NSNull(), "row": [["card": "roll"]]]])
        let kept = try pack.lent(to: theirs)
        XCTAssertEqual(kept.clashes, [200])
        XCTAssertEqual(kept.deck.card(200)?.name, "Roll over")
        XCTAssertEqual(try pack.lent(to: theirs, replacing: true).deck.card(200)?.name, "Double hello")
        XCTAssertEqual(pack.notInPlay(["walk_forward", "roll", "roll"], deck: try deck()), ["Roll is not in Tiny."])
    }

    // MARK: - the board rule

    func testABumpStopsThePlayWhereTheDuckWas() throws {
        let pack = try DuckPacks.Pack.read(try tiny { $0["challenges"] = [self.challenge {
            $0["walls"] = [["between": [[1, 1], [1, 0]]]]; $0["goal"] = [1, 0]; $0["par"] = 5
        }] }, deck: try deck())
        let ch = pack.challenges[0]
        let r = DuckPacks.play(ch, row: [.init(card: "walk_forward"), .init(card: "walk_forward"), .init(card: "turn_left")],
                               score: .steps, deck: try deck())
        XCTAssertEqual(r.bumpedAt, 2)
        XCTAssertEqual(r.path.count, 2)
        XCTAssertEqual(r.ended, DuckPacks.Place(at: .init(1, 1), facing: .north))
        XCTAssertEqual(r.said, "Bumped into a wall on step 2.")
    }

    func testParIsTheShortestPathAndCountsTheFinish() throws {
        let pack = try DuckPacks.Pack.read(try tiny(), deck: try deck())
        let board = pack.board
        func ch(_ change: (inout [String: Any]) -> Void) throws -> DuckPacks.Challenge {
            try DuckPacks.challenge(challenge(change), board: board, cards: pack.cards, deck: try deck(), number: 1)
        }
        XCTAssertEqual(DuckPacks.parSteps(try ch { $0["goal"] = [0, 0] }, cards: pack.cards), 4)
        XCTAssertEqual(DuckPacks.parSteps(try ch { $0["goal"] = [0, 0]; $0["finish_with"] = "greet" }, cards: pack.cards), 5)
        XCTAssertEqual(DuckPacks.parSteps(try ch { $0["goal"] = [1, 2]; $0["start"] = ["at": [1, 0], "facing": "north"] },
                                          cards: ["walk_forward", "turn_left"]), 4)
        XCTAssertNil(DuckPacks.parSteps(try ch {
            $0["gates"] = [["at": [1, 1], "axis": "ew"]]
            $0["walls"] = [["between": [[0, 1], [1, 1]]], ["between": [[2, 1], [1, 1]]]]
        }, cards: pack.cards))
    }

    func testARowCountsItsCardsAndClosesItsLoops() {
        let row: [DuckCards.Entry] = [.init(card: "repeat", times: 3), .init(card: "walk_forward", under: ["slow"]),
                                      .init(card: "end_repeat")]
        XCTAssertEqual(DuckPacks.cardCount(row), 4)
        XCTAssertEqual(DuckPacks.openRepeats(row), 0)
        XCTAssertEqual(DuckPacks.openRepeats(Array(row.prefix(2))), 1)
    }

    // MARK: - chapters (duck-card-loop/6)

    func testALongRowHasItsNestsWhereTheRunnerSplitsIt() throws {
        let deck = try deck()
        let row = Array(repeating: DuckCards.Entry(card: "walk_forward"), count: 10) + [DuckCards.Entry(card: "turn_left")]
        let steps = DuckPacks.steps(of: row, deck: deck)
        XCTAssertEqual(steps.count, 11)
        XCTAssertEqual(DuckPacks.nests(steps), [6], "11 cards at 7 a chapter: 6 and 5")
        XCTAssertEqual(DuckPacks.nests(Array(steps.prefix(7))), [], "a row that fits plays whole")
        XCTAssertEqual(DuckPacks.nests(steps, cards: 4), [4, 8])
        XCTAssertEqual(DuckPacks.Words.chapters(2),
                       "A long row: a duck plays it in 2 chapters. Between them, put the duck back on the nest, "
                     + "the square the board marks, facing the way the board shows.")
    }
}
