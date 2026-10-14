import XCTest
import CAprilTag
@testable import StudioKit

/// Studio's card reader, held to the duck's.
///
/// EVERY VECTOR IN `cardreader/vectors`, READ HERE AS THERE. A vector is what
/// the AprilTag library answered (ids and corners) and what the Python reader
/// made of it: rows, words, notes, the When it falls steps and the plan.
/// `scripts/check_duckcards_vectors.sh` keeps the fixture copy identical to the
/// source; this test keeps the two readers identical to each other.
final class DuckCardsTests: XCTestCase {

    static let deckSHA256 = "4889f6e245f0d53b5b6699aca0d32f83a0b6d71f21334bace119ab50dd542dd4"

    func deck() throws -> DuckCards.Deck { try XCTUnwrap(DuckCards.Deck.bundled, "the bundled deck did not load") }

    func testTheDeckIsTheSitesByteForByte() throws {
        let url = try XCTUnwrap(DuckCards.deckURL)
        XCTAssertEqual(DuckPolicyInstall.digest(of: try Data(contentsOf: url)), Self.deckSHA256)
        let d = try deck()
        XCTAssertEqual(d.cards.count, 39)
        XCTAssertEqual(d.card(61)?.code, "kick_right")
        XCTAssertEqual(d.card(250)?.kind, "yours")
        XCTAssertNil(d.card(150))
    }

    // MARK: - the vectors

    struct Vector {
        let name: String
        let detections: [DuckCards.Detection]
        let yours: [Int: [String]]
        let expect: [String: Any]
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
                                           margin: (d["margin"] as? NSNumber)?.doubleValue ?? 0, corners: corners)
            }
            var yours: [Int: [String]] = [:]
            for (k, v) in top["yours"] as? [String: [String]] ?? [:] { yours[Int(k)!] = v }
            return Vector(name: top["name"] as? String ?? url.lastPathComponent, detections: dets, yours: yours,
                          expect: top["expect"] as? [String: Any] ?? [:])
        }
    }

    func testEveryVectorReadsAsTheDucksReaderReadIt() throws {
        let d = try deck()
        let all = try vectors()
        XCTAssertEqual(all.count, 18, "a vector went missing from the fixtures")
        for v in all {
            let r = DuckCards.reading(v.detections, deck: d, yours: v.yours)
            XCTAssertEqual(r.layout.described, v.expect["rows"] as? [[String]], v.name)
            XCTAssertEqual(r.program.kind.rawValue, v.expect["kind"] as? String, v.name)
            XCTAssertEqual(r.program.complete, v.expect["complete"] as? Bool, v.name)
            XCTAssertEqual(r.program.words, v.expect["words"] as? String, v.name)
            XCTAssertEqual(r.program.notes, v.expect["notes"] as? [String], v.name)
            XCTAssertEqual(r.program.onFall.map(\.labels), v.expect["on_fall"] as? [[String: String]], v.name)
            if let want = v.expect["plan"] as? [String: Any] {
                XCTAssertTrue(NSDictionary(dictionary: DuckCards.planJSON(r.program)).isEqual(to: want), v.name)
            } else {
                XCTAssertTrue(r.program.steps.isEmpty, v.name)
            }
        }
    }

    // MARK: - into the plan editor, and onto a duck

    func testARowOpensInThePlanEditorAndRunsAsAPlan() throws {
        let example = try XCTUnwrap(try vectors().first { $0.name == "example_row" })
        let program = DuckCards.reading(example.detections, deck: try deck()).program
        let plan = try DuckCards.intentPlan(program)
        XCTAssertEqual(plan.model, "duck-cards/0")
        XCTAssertEqual(plan.nodes.map(\.action), ["make_sound", "walk_forward", "turn_left", "kick_right"])
        XCTAssertEqual(plan.flaggedCount, 0, "a card is not a guess, so nothing is flagged")
        let robot = try RobotPlan(plan)
        XCTAssertEqual(robot.beats.count, 4)
        XCTAssertEqual(robot.skillNames, ["kick_right"])
    }

    // MARK: - watching, as cardreader's Watcher watches

    func program(_ name: String) throws -> DuckCards.Program {
        let v = try XCTUnwrap(try vectors().first { $0.name == name }, name)
        return DuckCards.reading(v.detections, deck: try deck(), yours: v.yours).program
    }

    func testACardMustHoldStillAndIsActedOnOnce() throws {
        var w = DuckCards.Watcher(need: 3, forget: 1.0)
        let card = try program("one_card"), nothing = try program("not_duck_cards")
        let shown = (0..<12).compactMap { w.feed(card, at: Double($0) * 0.25) }
        XCTAssertEqual(shown, [.card("Roll.")])
        for t in 12..<20 { _ = w.feed(nothing, at: Double(t) * 0.25) }
        let again = (20..<24).compactMap { w.feed(card, at: Double($0) * 0.25) }
        XCTAssertEqual(again, [.card("Roll.")], "gone for longer than `forget`, then shown again")
    }

    func testARowRunsWhenCompleteAndIsAskedAboutWhenNot() throws {
        var w = DuckCards.Watcher(need: 2, unfinishedAfter: 1.0)
        let half = try program("start_without_end"), whole = try program("example_row")
        XCTAssertEqual((0..<8).compactMap { w.feed(half, at: Double($0) * 0.25) }, [.unfinished("Walk forward.")])
        XCTAssertEqual((0..<4).compactMap { w.feed(whole, at: 2 + Double($0) * 0.25) },
                       [.row("Hello. Walk forward, slow. Turn left. Kick, right.")])
    }

    func testWhatTheCameraCardSays() throws {
        let d = try deck()
        let line = { (name: String) -> String in
            let v = try XCTUnwrap(try self.vectors().first { $0.name == name })
            return DuckCards.Words.sees(DuckCards.reading(v.detections, deck: d, yours: v.yours))
        }
        XCTAssertEqual(try line("example_row"), "Row: Hello. Walk forward, slow. Turn left. Kick, right.")
        XCTAssertEqual(try line("one_card"), "Card: Roll.")
        XCTAssertEqual(try line("start_without_end"), "Row so far: Walk forward.")
        XCTAssertEqual(try line("no_start"), "These cards have no Start, so there is no row to run yet.")
        XCTAssertEqual(try line("not_duck_cards"), DuckCards.Words.notACard)
    }

    // MARK: - the library

    /// A tag36h11 code AS A DUCK CARD PRINTS IT, `scale` pixels a cell, on a white page.
    ///
    /// THE CARDS PRINT EVERY CODE TURNED HALF ROUND FROM THE LIBRARY'S OWN DRAWING. The site took
    /// its codes from OpenCV's tag36h11 dictionary, which draws them rotated 180° from
    /// `apriltag_to_image`; found on 2026-10-14, when this test first drew the library's way and
    /// read the corners upside down. The ids are the same either way. What matters is that both
    /// readers — pupil_apriltags on the duck and this library here — name the corners of a code
    /// *as printed* in the same order (top right, top left, bottom left, bottom right), so this
    /// draws the code the way the card does: the library's image, turned half round.
    func page(_ id: UInt32, scale: Int = 8, margin: Int = 40) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let family = try XCTUnwrap(tag36h11_create())
        defer { tag36h11_destroy(family) }
        let tag = try XCTUnwrap(apriltag_to_image(family, id))
        defer { image_u8_destroy(tag) }
        let n = Int(tag.pointee.width), stride = Int(tag.pointee.stride)
        let side = n * scale + 2 * margin
        var bytes = [UInt8](repeating: 255, count: side * side)
        for y in 0..<(n * scale) {
            for x in 0..<(n * scale) {
                let (ty, tx) = (n - 1 - y / scale, n - 1 - x / scale)      // half a turn
                bytes[(y + margin) * side + x + margin] = tag.pointee.buf[ty * stride + tx]
            }
        }
        return (bytes, side, side)
    }

    func testTheLibraryFindsACodeAndNamesItsCornersInTheOrderTheReaderAssumes() throws {
        let (bytes, w, h) = try page(61)
        let found = DuckCards.Finder().find(grey: bytes, width: w, height: h)
        XCTAssertEqual(found.map(\.id), [61])
        let c = try XCTUnwrap(found.first).corners       // top right, top left, bottom left, bottom right
        XCTAssertGreaterThan(c[0].x, c[1].x)
        XCTAssertGreaterThan(c[2].y, c[1].y)
        XCTAssertGreaterThan(c[3].x, c[2].x)
        let reading = DuckCards.reading(found, deck: try deck())
        XCTAssertEqual(reading.program.words, "Kick, right.")
        XCTAssertEqual(reading.program.kind, .card)
    }

    func testACodeThatIsNotADuckCardIsCountedNotRead() throws {
        let (bytes, w, h) = try page(7)
        let reading = DuckCards.reading(DuckCards.Finder().find(grey: bytes, width: w, height: h), deck: try deck())
        XCTAssertEqual(reading.look.foreign, 1)
        XCTAssertTrue(reading.program.steps.isEmpty)
    }
}
