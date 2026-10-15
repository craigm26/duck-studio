import XCTest
@testable import StudioKit

/// The class's deck: Studio's copy of the deck file, a row saved into it as a Your card, the file
/// shared with another phone, and every sentence the screens around it say.
///
/// THE ROUND TRIP IS THE CONTRACT. A row saved as a card must read back through `DuckCards.read`
/// to the steps the row read to on the table — Repeat numbers, cards under cards and Your cards
/// inside Your cards included — or a class's card would do something nobody saw it do.
final class DuckCardDeckTests: XCTestCase {

    func starter() throws -> DuckCards.Deck { try XCTUnwrap(DuckCards.Deck.bundled, "the bundled deck did not load") }

    /// A class deck in a folder of its own, removed when the test ends.
    func classDeck(starter: DuckCards.Deck? = nil) throws -> DuckCards.ClassDeck {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("duckcards-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return DuckCards.ClassDeck(file: dir.appendingPathComponent(DuckCards.ClassDeck.fileName),
                                   starter: try starter ?? self.starter())
    }

    /// A row on the table, as the reader lays one out: `"walk_forward/fast/look_left"` puts Fast
    /// and Look left under Walk forward, and `"repeat=3"` is a Repeat with 3 read off it.
    func table(_ items: [String], deck: DuckCards.Deck) throws -> DuckCards.Layout {
        let slots = try items.map { item -> DuckCards.Slot in
            var parts = item.split(separator: "/").map(String.init)
            let head = parts.removeFirst().split(separator: "=").map(String.init)
            let card = try XCTUnwrap(deck.card(code: head[0]), head[0])
            let under = try parts.map { DuckCards.saved(try XCTUnwrap(deck.card(code: $0), $0)) }
            return DuckCards.Slot(card: DuckCards.saved(card, times: head.count > 1 ? Int(head[1]) : nil), under: under)
        }
        return DuckCards.Layout(rows: [DuckCards.Row(slots: slots)], turned: [])
    }

    func steps(_ layout: DuckCards.Layout, _ deck: DuckCards.Deck, counts: [Int: Int] = [:]) -> [String] {
        DuckCards.read(layout, deck: deck, counts: counts).steps.map(\.clause)
    }

    // MARK: - the vectors

    struct Vector {
        let name: String
        let detections: [DuckCards.Detection]
        let deckCards: [[String: Any]]
        let counts: [Int: Int]
    }

    func vectors() throws -> [Vector] {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/DuckCards/vectors", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { url in
            let top = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let dets = (top["detections"] as? [[String: Any]] ?? []).map { d -> DuckCards.Detection in
                let corners = (d["corners"] as? [[Double]] ?? []).map { DuckCards.Point($0[0], $0[1]) }
                return DuckCards.Detection(id: d["id"] as? Int ?? -1, hamming: d["hamming"] as? Int ?? 0,
                                           margin: (d["margin"] as? NSNumber)?.doubleValue ?? 0, corners: corners,
                                           count: d["count"] as? Int)
            }
            var counts: [Int: Int] = [:]
            for (k, v) in top["counts"] as? [String: Int] ?? [:] { counts[Int(k)!] = v }
            return Vector(name: top["name"] as? String ?? url.lastPathComponent, detections: dets,
                          deckCards: top["deck_cards"] as? [[String: Any]] ?? [], counts: counts)
        }
    }

    func deck(for v: Vector) throws -> DuckCards.Deck {
        v.deckCards.isEmpty ? try starter() : try starter().replacing(v.deckCards)
    }

    // MARK: - Studio's copy of the deck file

    func testAClassDeckStartsAsTheStarterDeckAndWritesNothingUntilAChange() throws {
        let classDeck = try classDeck()
        XCTAssertEqual(classDeck.deck.source, try starter().source)
        XCTAssertEqual(classDeck.exported, try starter().source, "an untouched class deck exports the starter deck")
        XCTAssertNil(classDeck.problem)
        XCTAssertTrue(classDeck.saved.isEmpty)
        XCTAssertEqual(Array(classDeck.free.prefix(10)), Array(200...209), "the printed blanks first")
        XCTAssertEqual(classDeck.free.count, 100)
        XCTAssertEqual(classDeck.numbers, classDeck.free)
        XCTAssertEqual(classDeck.suggested, 200)
        XCTAssertTrue(classDeck.isPrinted(208))
        XCTAssertFalse(classDeck.isPrinted(209))
        XCTAssertFalse(FileManager.default.fileExists(atPath: classDeck.file.path))
    }

    func testARowSavedAsACardReadsBackToTheSameSteps() throws {
        var classDeck = try classDeck()
        // A Your card first, so the row can hold one: twice round, turning fast, then a roll.
        let spin = try classDeck.save(row: [DuckCards.Entry(card: "repeat", times: 2),
                                            DuckCards.Entry(card: "turn_left", under: ["fast"]),
                                            DuckCards.Entry(card: "roll"),
                                            DuckCards.Entry(card: "end_repeat")],
                                      asCard: 202, name: "Spin and roll")
        XCTAssertEqual(spin.code, "card_3")
        let deck = classDeck.deck

        // On the table: a Repeat nobody could read, cards under a card, and that Your card inside.
        let layout = try table(["start", "greet", "repeat", "walk_forward/slow/look_left", "card_3", "end_repeat",
                                "turn_right/fast", "end"], deck: deck)
        let asked = DuckCards.read(layout, deck: deck)
        XCTAssertEqual(asked.asks, [0])
        XCTAssertThrowsError(try DuckCards.savedRow(layout, deck: deck)) {
            XCTAssertEqual($0 as? DuckCards.Refusal, .asks(1))
        }
        let counts = [0: 3]
        let onTable = steps(layout, deck, counts: counts)
        XCTAssertEqual(onTable.count, 1 + 3 * (1 + 4) + 1)

        let row = try DuckCards.savedRow(layout, deck: deck, counts: counts)
        XCTAssertEqual(row, [DuckCards.Entry(card: "greet"),
                             DuckCards.Entry(card: "repeat", times: 3),
                             DuckCards.Entry(card: "walk_forward", under: ["slow", "look_left"]),
                             DuckCards.Entry(card: "card_3"),
                             DuckCards.Entry(card: "end_repeat"),
                             DuckCards.Entry(card: "turn_right", under: ["fast"])])

        let card = try classDeck.save(row: row, asCard: 204, name: "  Victory lap ", does: "Round and round.")
        XCTAssertEqual(card.name, "Victory lap", "the name is kept without the spaces typed round it")
        XCTAssertEqual(card.does, "Round and round.")
        XCTAssertEqual(card.row, row)

        // Held up on its own, and in a row of its own, it is the row from the table.
        let held = try table(["card_5"], deck: classDeck.deck)
        XCTAssertEqual(DuckCards.read(held, deck: classDeck.deck).kind, .card)
        XCTAssertEqual(steps(held, classDeck.deck), onTable)
        XCTAssertEqual(classDeck.reads(204)?.steps.map(\.clause), onTable)
        XCTAssertEqual(classDeck.reads(204)?.complete, true)

        // Written to the file, which is a deck the reader reads, and opened again from it.
        let onDisk = try Data(contentsOf: classDeck.file)
        XCTAssertEqual(onDisk, classDeck.deck.source)
        XCTAssertEqual(try DuckCards.Deck.read(onDisk).card(204)?.row, row)
        let again = DuckCards.ClassDeck(file: classDeck.file, starter: try starter())
        XCTAssertNil(again.problem)
        XCTAssertEqual(again.saved.map(\.tag), [202, 204])
        XCTAssertEqual(steps(held, again.deck), onTable)
        // and the rest of the starter deck is still in it
        let top = try XCTUnwrap(try JSONSerialization.jsonObject(with: onDisk) as? [String: Any])
        XCTAssertEqual(top["license"] as? String, "CC-BY-4.0")
        XCTAssertEqual(again.deck.cards.count, try starter().cards.count)
        let printed = try XCTUnwrap((top["cards"] as? [[String: Any]])?.first { $0["tag"] as? Int == 204 })
        XCTAssertEqual(printed["printed"] as? Bool, true, "a printed blank stays printed once it means something")
        XCTAssertEqual(printed["kind"] as? String, "yours")
    }

    /// Every row in the shared vectors that can be saved is saved, and reads back the same.
    func testEveryVectorRowThatCanBeSavedReadsBackTheSame() throws {
        var saved = 0, refused: [String] = []
        for v in try vectors() {
            let deck = try deck(for: v)
            let reading = DuckCards.reading(v.detections, deck: deck, counts: v.counts)
            guard DuckCards.savable(reading) else {
                XCTAssertThrowsError(try DuckCards.savedRow(reading, deck: deck, counts: v.counts), v.name)
                continue
            }
            var counts = DuckCards.answers(reading.program.asks, given: [:])
            for (k, n) in v.counts { counts[k] = n }
            let answered = DuckCards.answered(reading, deck: deck, counts: counts)
            XCTAssertTrue(answered.program.complete, v.name)
            let row = try DuckCards.savedRow(answered, deck: deck, counts: counts)
            var classDeck = try classDeck(starter: deck)
            let tag = try XCTUnwrap(classDeck.suggested)
            if v.name == "your_card_too_deep" {
                // 204's row holds card_6, so 205 is spoken for: saved as 205 the row would loop.
                XCTAssertEqual(classDeck.free.first, 205)
                XCTAssertEqual(classDeck.heldBy(205), [204])
                XCTAssertEqual(tag, 206)
                XCTAssertThrowsError(try classDeck.save(row: row, asCard: 205, name: v.name)) {
                    XCTAssertEqual($0 as? DuckCards.Refusal, .loop(205, through: 200))
                }
            }
            do {
                try classDeck.save(row: row, asCard: tag, name: v.name)
            } catch let refusal as DuckCards.Refusal {
                refused.append(v.name)
                XCTAssertEqual(refusal, .tooDeep(tag), v.name)
                continue
            }
            saved += 1
            XCTAssertEqual(classDeck.reads(tag)?.steps, answered.program.steps, v.name)
            let held = try table([try XCTUnwrap(classDeck.deck.card(tag)).code], deck: classDeck.deck)
            XCTAssertEqual(DuckCards.read(held, deck: classDeck.deck).steps, answered.program.steps, v.name)
        }
        XCTAssertEqual(saved, 20, "a vector row stopped being savable")
        // On the table that chain is already four deep; saved as a card it would be six.
        XCTAssertEqual(refused, ["your_card_too_deep"])
    }

    func testWhatCanBeHeldAndWhatCanBeSaved() throws {
        let all = Dictionary(uniqueKeysWithValues: try vectors().map { ($0.name, $0) })
        func reading(_ name: String) throws -> DuckCards.Reading {
            let v = try XCTUnwrap(all[name], name)
            return DuckCards.reading(v.detections, deck: try self.deck(for: v), counts: v.counts)
        }
        // usable, savable
        let cases: [(String, Bool, Bool)] = [
            ("example_row", true, true), ("one_card", true, false), ("your_card_held", true, false),
            ("repeat", true, true), ("start_without_end", false, false), ("no_start", false, false),
            ("not_duck_cards", false, false), ("your_card_unsaved", false, false),
        ]
        for (name, usable, savable) in cases {
            XCTAssertEqual(DuckCards.usable(try reading(name)), usable, name)
            XCTAssertEqual(DuckCards.savable(try reading(name)), savable, name)
        }
        let deck = try starter()
        let refusals: [(String, DuckCards.Refusal)] = [
            ("one_card", .noRow), ("no_start", .noRow), ("start_without_end", .noEnd),
            ("repeat", .asks(1)), ("repeat_nested_asked", .asks(2)), ("your_card_unsaved", .empty),
        ]
        for (name, why) in refusals {
            XCTAssertThrowsError(try DuckCards.savedRow(try reading(name), deck: deck), name) {
                XCTAssertEqual($0 as? DuckCards.Refusal, why, name)
            }
        }
        XCTAssertThrowsError(try DuckCards.savedRow(try table(["start", "end"], deck: deck), deck: deck)) {
            XCTAssertEqual($0 as? DuckCards.Refusal, .empty)
        }
    }

    // MARK: - refused, by name

    func testASaveIsRefusedByName() throws {
        var classDeck = try classDeck()
        let walk = [DuckCards.Entry(card: "walk_forward")]
        func refuses(_ row: [DuckCards.Entry], _ tag: Int, name: String = "A card",
                     _ why: DuckCards.Refusal, _ says: String, line: UInt = #line) {
            XCTAssertThrowsError(try classDeck.save(row: row, asCard: tag, name: name), line: line) {
                XCTAssertEqual($0 as? DuckCards.Refusal, why, line: line)
                XCTAssertEqual(($0 as? DuckCards.Refusal)?.message, says, line: line)
            }
        }
        refuses(walk, 201, name: "   ", .noName, "Give the card a name first.")
        refuses(walk, 199, .notYours(199, 200...299), "199 is not a Your card. Your cards are numbered 200 to 299.")
        refuses(walk, 300, .notYours(300, 200...299), "300 is not a Your card. Your cards are numbered 200 to 299.")
        refuses(walk, 61, .notYours(61, 200...299), "61 is not a Your card. Your cards are numbered 200 to 299.")
        refuses([], 201, .empty, "Nothing between Start and End makes a step, so there is nothing to save.")
        refuses([DuckCards.Entry(card: "card_2")], 201, .holdsItself(201),
                "The row holds card 201 itself, so it cannot be saved as 201.")

        // 202 holds 201, so 201 may not hold 202.
        try classDeck.save(row: [DuckCards.Entry(card: "card_2"), DuckCards.Entry(card: "roll")], asCard: 202, name: "Roll after")
        refuses([DuckCards.Entry(card: "card_3"), DuckCards.Entry(card: "kick_left")], 201, .loop(201, through: 202),
                "The row holds card 202, which leads back to 201, so it cannot be saved as 201.")

        // Four deep is as deep as a reader goes: 205 holding 204 holding 203 holding 202 holding 201.
        try classDeck.save(row: walk, asCard: 201, name: "Walk")
        try classDeck.save(row: [DuckCards.Entry(card: "card_3")], asCard: 203, name: "Three")
        try classDeck.save(row: [DuckCards.Entry(card: "card_4")], asCard: 204, name: "Four")
        refuses([DuckCards.Entry(card: "card_5")], 205, .tooDeep(205),
                "Saved as card 205, the row would hold Your cards inside Your cards more than 4 deep. "
              + "A reader stops at 4, so it was not saved.")

        // A number that means something is not replaced unless the caller says so, and that is said
        // last, so a screen never asks about replacing with a row that could not be saved anyway.
        refuses([DuckCards.Entry(card: "card_2")], 201, .holdsItself(201),
                "The row holds card 201 itself, so it cannot be saved as 201.")
        let walkCard = try XCTUnwrap(classDeck.means(201))
        refuses([DuckCards.Entry(card: "roll")], 201, .wouldReplace(walkCard),
                "Card 201 already means Walk, so it was not replaced.")
        XCTAssertEqual(classDeck.deck.card(201)?.row, walk, "a refused save changes nothing")
        let replaced = try classDeck.save(row: [DuckCards.Entry(card: "roll")], asCard: 201, name: "Roll",
                                          replacing: true)
        XCTAssertEqual(replaced.row, [DuckCards.Entry(card: "roll")])
        XCTAssertEqual(classDeck.heldBy(201), [202])
        XCTAssertNil(classDeck.means(205), "nothing refused was written")
    }

    // MARK: - numbers

    func testNumbersAreOfferedPrintedBlanksFirst() throws {
        var classDeck = try classDeck()
        let roll = [DuckCards.Entry(card: "roll")]
        try classDeck.save(row: roll, asCard: 200, name: "Roll")
        try classDeck.save(row: roll, asCard: 205, name: "Roll again")
        let bow = try classDeck.save(row: [DuckCards.Entry(card: "sit_or_stand")], asCard: 250, name: "Bow")
        XCTAssertEqual(bow.code, "card_51")
        XCTAssertEqual(Array(classDeck.free.prefix(8)), [201, 202, 203, 204, 206, 207, 208, 209])
        XCTAssertFalse(classDeck.free.contains(250))
        XCTAssertEqual(classDeck.free.count, 97)
        XCTAssertEqual(Array(classDeck.numbers.suffix(3)), [200, 205, 250], "then the numbers that would replace")
        XCTAssertEqual(classDeck.saved.map(\.name), ["Roll", "Roll again", "Bow"])
        XCTAssertEqual(DuckCards.Words.number(250, meaning: classDeck.means(250), printed: classDeck.isPrinted(250)),
                       "250: Bow")
        XCTAssertEqual(DuckCards.Words.number(209, meaning: nil, printed: classDeck.isPrinted(209)),
                       "209, not in the starter deck")
        XCTAssertEqual(DuckCards.Words.number(201, meaning: nil, printed: classDeck.isPrinted(201)), "201")
    }

    // MARK: - forgetting

    func testForgettingACardPutsTheBlankBack() throws {
        var classDeck = try classDeck()
        let starter = try starter()
        try classDeck.save(row: [DuckCards.Entry(card: "roll")], asCard: 201, name: "Roll")
        try classDeck.save(row: [DuckCards.Entry(card: "card_2"), DuckCards.Entry(card: "greet")], asCard: 202,
                           name: "Roll and hello")
        try classDeck.save(row: [DuckCards.Entry(card: "greet")], asCard: 250, name: "Hello")
        XCTAssertEqual(DuckCards.Words.forgetQuestion(try XCTUnwrap(classDeck.means(201)), heldBy: classDeck.heldBy(201)),
                       "Card 201 goes back to a blank, and Roll is gone from the deck. Card 202 holds it, so it changes too.")

        try classDeck.forget(201)
        XCTAssertNil(classDeck.means(201))
        XCTAssertEqual(classDeck.deck.card(201)?.name, "Your card")
        // Compared as JSON: Linux's NSDictionary does not find two `true`s equal.
        let restored = try XCTUnwrap(DuckCards.ClassDeck.entry(201, in: classDeck.deck.source))
        let blank = try XCTUnwrap(DuckCards.ClassDeck.entry(201, in: starter.source))
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: restored, options: [.sortedKeys]),
                       try JSONSerialization.data(withJSONObject: blank, options: [.sortedKeys]),
                       "a printed blank goes back to the starter deck's own entry")
        XCTAssertEqual(classDeck.reads(202)?.notes, ["Your card 201 has no meaning saved yet, so it was skipped."])
        XCTAssertEqual(classDeck.reads(202)?.words, "Hello.")

        try classDeck.forget(250)
        XCTAssertNil(classDeck.deck.cards[250], "a number the starter deck does not list leaves the file")
        XCTAssertEqual(classDeck.deck.card(250)?.name, "Your card", "and is still a Your card")
        XCTAssertEqual(Array(classDeck.free.prefix(2)), [200, 201])
        XCTAssertTrue(classDeck.free.contains(250))
        XCTAssertEqual(try Data(contentsOf: classDeck.file), classDeck.deck.source)

        XCTAssertThrowsError(try classDeck.forget(203)) {
            XCTAssertEqual($0 as? DuckCards.Refusal, .notSaved(203))
            XCTAssertEqual(($0 as? DuckCards.Refusal)?.message, "Card 203 means nothing yet, so there is nothing to forget.")
        }
        XCTAssertEqual(DuckCards.Words.forgot(201), "Card 201 is a blank again.")
    }

    // MARK: - sharing

    func testTheDeckTravelsAsADuckcardsFileByteForByte() throws {
        var mine = try classDeck()
        try mine.save(row: [DuckCards.Entry(card: "walk_forward", under: ["fast"]), DuckCards.Entry(card: "roll")],
                      asCard: 201, name: "Victory dance", does: "Walk forward fast, then roll.")
        try mine.save(row: [DuckCards.Entry(card: "repeat", times: 2), DuckCards.Entry(card: "card_2"),
                            DuckCards.Entry(card: "end_repeat")], asCard: 202, name: "Twice")
        var theirs = try classDeck()
        let bow = try theirs.save(row: [DuckCards.Entry(card: "sit_or_stand")], asCard: 204, name: "Bow")

        let taken = try theirs.take(mine.exported)
        XCTAssertEqual(theirs.deck.source, mine.exported)
        XCTAssertEqual(try Data(contentsOf: theirs.file), mine.exported)
        XCTAssertEqual(taken.cards, mine.saved)
        XCTAssertEqual(taken.replaced, [bow])
        XCTAssertEqual(DuckCards.Words.opened(taken),
                       "Opened the class deck. It gives a meaning to 2 Your cards: 201 Victory dance and 202 Twice. "
                     + "It replaced what this phone had saved for 204 Bow.")
        // and a Your card reads the same on both phones
        XCTAssertEqual(theirs.reads(202)?.steps, mine.reads(202)?.steps)
        XCTAssertEqual(theirs.reads(202)?.words, "Walk forward, fast. Roll. Walk forward, fast. Roll.")
        XCTAssertEqual(DuckCards.Words.runs(theirs.reads(202)), "Walk forward, fast. Roll. Walk forward, fast. Roll.")
        XCTAssertEqual(theirs.deck.card(201)?.does, "Walk forward fast, then roll.")
    }

    func testADeckFileTheReaderCannotFollowIsRefusedInItsWords() throws {
        var classDeck = try classDeck()
        let bad: [String: Any] = ["tag": 200, "code": "card_1", "name": "Fly", "category": "yours", "kind": "yours",
                                  "row": [["card": "fly"]]]
        var top = try XCTUnwrap(try JSONSerialization.jsonObject(with: try starter().source) as? [String: Any])
        top["cards"] = [bad] + (top["cards"] as? [[String: Any]] ?? []).filter { $0["tag"] as? Int != 200 }
        let cases: [(Data, DuckCards.Refusal, String)] = [
            (Data("not json".utf8), .notADeck("not a duck-cards/0 deck"),
             "That deck was not opened: not a duck-cards/0 deck."),
            (Data(#"{"format": "duck-cards/9", "cards": [], "categories": []}"#.utf8),
             .notADeck("not a duck-cards/0 deck"), "That deck was not opened: not a duck-cards/0 deck."),
            (try JSONSerialization.data(withJSONObject: top), .notADeck("card_1: its row holds 'fly', which is not a card"),
             "That deck was not opened: card_1: its row holds 'fly', which is not a card."),
        ]
        for (data, why, says) in cases {
            XCTAssertThrowsError(try classDeck.take(data)) {
                XCTAssertEqual($0 as? DuckCards.Refusal, why)
                XCTAssertEqual(($0 as? DuckCards.Refusal)?.message, says)
            }
        }
        XCTAssertEqual(classDeck.deck.source, try starter().source, "a refused deck changes nothing")
        XCTAssertFalse(FileManager.default.fileExists(atPath: classDeck.file.path))
    }

    func testAFileThatCannotBeReadIsSaidAndTheStarterDeckIsUsed() throws {
        let first = try classDeck()
        try FileManager.default.createDirectory(at: first.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ half a deck".utf8).write(to: first.file)
        var classDeck = DuckCards.ClassDeck(file: first.file, starter: try starter())
        XCTAssertEqual(classDeck.deck.source, try starter().source)
        XCTAssertEqual(classDeck.problem,
                       "Studio's copy of the class deck could not be read (not a duck-cards/0 deck), so cards are read "
                     + "with the starter deck. The next card saved writes over it.")
        try classDeck.save(row: [DuckCards.Entry(card: "roll")], asCard: 200, name: "Roll")
        XCTAssertNil(classDeck.problem)
        XCTAssertNil(DuckCards.ClassDeck(file: first.file, starter: try starter()).problem)
    }

    /// iOS hands a `.duckcards` file to the app only for a type it declares and a document row that
    /// names it, and the extension has to be the one the kit writes.
    func testTheAppDeclaresTheDeckFileItWritesAndOpens() throws {
        let yml = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("DuckStudio/project.yml")
        let text = try String(contentsOf: yml, encoding: .utf8)
        let exported = try XCTUnwrap(text.range(of: "UTExportedTypeDeclarations:"))
        let documents = try XCTUnwrap(text.range(of: "CFBundleDocumentTypes:"))
        let declared = try XCTUnwrap(text.range(of: "- UTTypeIdentifier: com.duckstudio.duckcards"))
        XCTAssertTrue(exported.lowerBound < declared.lowerBound && declared.lowerBound < documents.lowerBound,
                      "declared among the exported types: this app writes the format")
        let declaration = String(text[declared.upperBound...].prefix(300))
        XCTAssertTrue(declaration.contains("- public.json\n"))
        XCTAssertTrue(declaration.contains("- \(DuckCards.ClassDeck.fileExtension)\n"))
        XCTAssertTrue(text[documents.upperBound...].contains("- com.duckstudio.duckcards\n"), "no document row")
    }

    // MARK: - into the plan editor

    func testARowOpensInThePlanEditorAsTheCardsProposedIt() throws {
        let all = Dictionary(uniqueKeysWithValues: try vectors().map { ($0.name, $0) })
        let deck = try starter()
        let example = try XCTUnwrap(all["example_row"])
        let handed = try DuckCards.handed(DuckCards.reading(example.detections, deck: deck), deck: deck)
        XCTAssertEqual(handed.plan.model, "duck-cards/0")
        XCTAssertEqual(handed.plan.nodes.map(\.action), ["make_sound", "walk_forward", "turn_left", "kick_right"])
        XCTAssertEqual(handed.by, DuckIntentPlan.RouterIdentity(model: "duck-cards/0", revision: "deck sha256 4889f6e245f0"))
        XCTAssertEqual(handed.notes, [])
        XCTAssertEqual(PlanEditorWords.proposedBy(handed.plan.model, seconds: nil), "Read from Duck Cards.")
        XCTAssertEqual(PlanEditorWords.proposedBy("decide", seconds: nil), "Proposed by decide.")

        // A When it falls row stays with the reader, and the editor says so under the reader's notes.
        let falls = try XCTUnwrap(all["when_it_falls"])
        XCTAssertEqual(try DuckCards.handed(DuckCards.reading(falls.detections, deck: deck), deck: deck).notes,
                       ["A plan has no events, so the When it falls row is not in it."])
        let loose = try XCTUnwrap(all["loose_speed"])
        XCTAssertEqual(try DuckCards.handed(DuckCards.reading(loose.detections, deck: deck), deck: deck).notes,
                       ["Fast is not under any card, so it was not used."])

        // A Repeat asked about, answered, opens unrolled; the class's own deck is the provenance.
        let nested = try XCTUnwrap(all["repeat_nested_asked"])
        let asked = DuckCards.reading(nested.detections, deck: deck)
        let counts = DuckCards.answers(asked.program.asks, given: [1: 3])
        XCTAssertEqual(counts, [0: 2, 1: 3])
        let answered = try DuckCards.handed(DuckCards.answered(asked, deck: deck, counts: counts), deck: deck)
        XCTAssertEqual(answered.plan.nodes.count, 8)
        var classDeck = try classDeck()
        try classDeck.save(row: [DuckCards.Entry(card: "roll")], asCard: 200, name: "Roll")
        XCTAssertNotEqual(DuckIntentPlan.RouterIdentity.cards(classDeck.deck), .cards(deck))
        XCTAssertThrowsError(try DuckCards.handed(DuckCards.reading([], deck: deck), deck: deck)) {
            XCTAssertEqual($0 as? DuckIntentPlan.ReadError, .noSteps)
        }
    }

    // MARK: - the words

    func testRepeatQuestionsStartAtTwoAndStayInTheBox() {
        XCTAssertEqual(DuckCards.repeatOffered, 2)
        XCTAssertEqual(DuckCards.repeatRange, 1...9)
        XCTAssertEqual(DuckCards.answers([0, 1, 2], given: [1: 12, 2: 0]), [0: 2, 1: 9, 2: 1])
        XCTAssertEqual(DuckCards.answers([], given: [0: 3]), [:], "only what was asked is answered")
        XCTAssertEqual(DuckCards.Words.repeatTimes(0, of: 1, times: 2), "Repeat 2 times")
        XCTAssertEqual(DuckCards.Words.repeatTimes(0, of: 2, times: 1), "Repeat 1: 1 time")
        XCTAssertEqual(DuckCards.Words.repeatTimes(1, of: 2, times: 9), "Repeat 2: 9 times")
        XCTAssertEqual(DuckCards.Words.howManyTimes, "How many times?")
        XCTAssertEqual(DuckCards.Words.useTheseNumbers, "Use these numbers")
        XCTAssertEqual(DuckCards.Words.repeatAsked,
                       "Studio does not read the number written on a Repeat card, so it asks. Repeats are counted from Start.")
    }

    func testWhatTheCardScreensSay() throws {
        typealias W = DuckCards.Words
        let card = DuckCards.Card(tag: 201, code: "card_2", name: "Victory dance", category: "yours", kind: "yours",
                                  plan: nil, row: [DuckCards.Entry(card: "roll")], does: nil)
        XCTAssertEqual(W.title, "Duck Cards")
        XCTAssertEqual(W.openInPlanEditor, "Open in the plan editor")
        XCTAssertEqual(W.saveAsCard, "Save as a card")
        XCTAssertEqual(W.classDeck, "Class deck")
        XCTAssertEqual(W.close, "Close")
        XCTAssertEqual(W.heldHeading, "From the cards")
        XCTAssertEqual(W.heldFooter, "Read once and held still. Change the cards and read them again to change this.")
        XCTAssertEqual(W.saved(card), "Saved as card 201. Write \"Victory dance\" on the blank card numbered 201.")
        XCTAssertEqual(W.replaceTitle(card), "Replace card 201?")
        XCTAssertEqual(W.replaceQuestion(card, heldBy: []), "Card 201 already means Victory dance. Saving this row replaces it.")
        XCTAssertEqual(W.replaceQuestion(card, heldBy: [202]),
                       "Card 201 already means Victory dance. Saving this row replaces it. Card 202 holds it, so it changes too.")
        XCTAssertEqual(W.replaceQuestion(card, heldBy: [202, 203, 230]),
                       "Card 201 already means Victory dance. Saving this row replaces it. "
                     + "Cards 202, 203 and 230 hold it, so they change too.")
        XCTAssertEqual(W.replace, "Replace it")
        XCTAssertEqual(W.keepIt, "Keep it")
        XCTAssertEqual(W.saveTitle, "Save as a card")
        XCTAssertEqual(W.numberHeading, "Card number")
        XCTAssertEqual(W.numberLabel, "Number")
        XCTAssertEqual(W.nameHeading, "Name")
        XCTAssertEqual(W.namePlaceholder, "Victory dance")
        XCTAssertEqual(W.doesHeading, "What it does")
        XCTAssertEqual(W.doesPlaceholder, "Walk forward fast, then roll.")
        XCTAssertEqual(W.doesFooter, "Optional. The deck keeps it beside the row, and the printed card has a line for it.")
        XCTAssertEqual(W.save, "Save")
        XCTAssertEqual(W.fallNotInCard,
                       "A Your card holds the row from Start to End. The When it falls row is not saved with it.")
        XCTAssertEqual(W.deckTitle, "Class deck")
        XCTAssertEqual(W.yourCardsHeading, "Your cards")
        XCTAssertEqual(W.noYourCards, "No Your card means anything yet. Read a row from Start to End, then Save as a card.")
        XCTAssertEqual(W.deckFooter,
                       "What a Your card means lives in the deck file, not on the phone. Open a .duckcards file "
                     + "someone shared and it becomes this deck.")
        XCTAssertEqual(W.yourCard(card), "201  Victory dance")
        XCTAssertEqual(W.runs(nil), "It makes no step.")
        XCTAssertEqual(W.forget, "Forget")
        XCTAssertEqual(W.forgetTitle(card), "Forget card 201?")
        XCTAssertEqual(W.forgetQuestion(card, heldBy: []), "Card 201 goes back to a blank, and Victory dance is gone from the deck.")
        XCTAssertEqual(W.shareDeck, "Share the class deck")
        XCTAssertEqual(W.shareFooter,
                       "Sends class.duckcards, the deck file with your cards in it. Open it in Microduck Studio on "
                     + "another phone or Mac, or give it to the duck's card reader with --deck.")
        XCTAssertEqual(W.opened(.init(cards: [], replaced: [])),
                       "Opened the class deck. None of its Your cards means anything yet.")
        XCTAssertEqual(W.opened(.init(cards: [card], replaced: [])),
                       "Opened the class deck. It gives a meaning to 1 Your card: 201 Victory dance.")
        XCTAssertEqual(W.readFromCards, "Read from Duck Cards.")
        XCTAssertEqual(W.fallNotInPlan, "A plan has no events, so the When it falls row is not in it.")
        // The remaining refusals, letter by letter; the rest are read where they are thrown.
        XCTAssertEqual(DuckCards.Refusal.noRow.message, "There is no Start in the picture, so there is no row to save.")
        XCTAssertEqual(DuckCards.Refusal.noEnd.message, "The row has no End yet. Put End after its last card, then save it.")
        XCTAssertEqual(DuckCards.Refusal.asks(1).message, "Say how many times the Repeat goes first.")
        XCTAssertEqual(DuckCards.Refusal.asks(2).message, "Say how many times each Repeat goes first.")
        XCTAssertEqual(DuckCards.Refusal.readsDifferently(201).message,
                       "Saved as card 201, the row would not read the same, so it was not saved.")
        XCTAssertEqual(DuckCards.Refusal.notWritten("No space left.").message,
                       "The class deck could not be written. No space left.")
        XCTAssertEqual(DuckCards.Refusal.noDeck.message,
                       "The starter deck did not load, so there is no class deck to keep cards in.")
    }
}
