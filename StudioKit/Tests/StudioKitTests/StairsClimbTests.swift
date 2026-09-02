import XCTest
@testable import StudioKit

/// The `/climb` client, against the contract the bench answers to.
final class StairsClimbTests: XCTestCase {

    let address = DuckBench.Address(host: "127.0.0.1", port: 8770)

    // MARK: - what goes out

    func testClimbPostsToClimbAndTheGridIsAGet() throws {
        let call = try DuckBench.climb(address,
                                       intent: StairsChallenge.intentData(named: "ctrl_do_nothing"),
                                       rise: 0.060,
                                       cell: StairsChallenge.Grid.fallback[0])
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.url.path, "/climb")
        let grid = DuckBench.climbGrid(address)
        XCTAssertEqual(grid.method, "GET")
        XCTAssertEqual(grid.url.path, "/climb/grid")
        XCTAssertNil(grid.body)
    }

    /// THE BODY IS THE CONTRACT'S BODY, AND THE INTENT IS THE FILE. Key order
    /// included: the bench hashes what it receives.
    func testTheBodyCarriesTheIntentTheRiseTheCellAndTheTail() throws {
        let file = try StairsChallenge.intentData(named: "best_r6_ceilvaultC_60mm")
        let cell = StairsChallenge.Grid.fallback[4]      // dh 0, drop 0.130, fmul 0.7
        let call = try DuckBench.climb(address, intent: file, rise: 0.060, cell: cell)
        let body = try HarnessJSON.parse(try XCTUnwrap(call.body))

        XCTAssertEqual(body.members?.map(\.key), ["intent", "rise", "cell", "tail"])
        XCTAssertEqual(body["rise"]?.doubleValue, 0.060)
        XCTAssertEqual(body["tail"]?.stringValue, "policy")
        XCTAssertEqual(body["cell"]?.members?.map(\.key), ["dh", "drop", "fmul"])
        XCTAssertEqual(body["cell"]?["dh"]?.doubleValue, 0)
        XCTAssertEqual(body["cell"]?["drop"]?.doubleValue, 0.130)
        XCTAssertEqual(body["cell"]?["fmul"]?.doubleValue, 0.7)

        // The intent that went out is the file that came off disk.
        let intent = try XCTUnwrap(body["intent"])
        XCTAssertEqual(intent.encoded(.pretty), file)
    }

    /// A move edited in the Studio goes out as the file its own writer makes,
    /// so the hash the bench answers is the hash of what the person edited.
    func testAMoveGoesOutAsItsOwnBytes() throws {
        let move = try StairsChallenge.move(for: StairsChallenge.record)
        let call = try DuckBench.climb(address, move: move, rise: 0.060,
                                       cell: StairsChallenge.Grid.fallback[0])
        let body = try HarnessJSON.parse(try XCTUnwrap(call.body))
        XCTAssertEqual(try XCTUnwrap(body["intent"]).encoded(.pretty), move.encoded())
    }

    func testSomethingThatIsNotAnIntentIsRefusedBeforeItIsSent() {
        XCTAssertThrowsError(try DuckBench.climb(address, intent: Data("[1,2]".utf8),
                                                 rise: 0.060,
                                                 cell: StairsChallenge.Grid.fallback[0]))
        XCTAssertThrowsError(try DuckBench.climb(address, intent: Data("not json".utf8),
                                                 rise: 0.060,
                                                 cell: StairsChallenge.Grid.fallback[0]))
    }

    // MARK: - what comes back

    /// ONE ANSWER, HAND-WRITTEN TO THE CONTRACT. Every field the contract
    /// names, spelled the way it names it, read into every property.
    func testAnAnswerWrittenToTheContractReadsWhole() throws {
        let answer = Data("""
        {
          "hash": "a56d459fb6493855d635021dce569cc8b06b325b32b3c19e8593cf430ca442d1",
          "rise": 0.06,
          "cell": {"dh": -0.01, "drop": 0.12, "fmul": 1.0},
          "honest": true,
          "stable": true,
          "uprightTailTicks": 50,
          "above_mm": 116.17658662135791,
          "x_mm": 237.36029825804,
          "dy_mm": 17.621239174713033,
          "feetOnTread": 2,
          "peakAboveTread_mm": 121.71408220291646,
          "maxTq": 0.6405,
          "penetrationAtScore_mm": -0.7428401259841899,
          "minPenetrationEpisode_mm": -6.9746295824819065,
          "maxAbsDY_mm": 47.5896931638895,
          "reachedFlight": true,
          "invalid": false,
          "why": null,
          "plantName": "scene.mjb",
          "plantDigest": "3f8c9ab9b409ba74c73c30179d5f7c12b025f631693f9eec78d80dca242547be",
          "criterion": "honest: upright, inside the flight, past the riser, above the tread and both feet resting on it.",
          "seconds": 1.031
        }
        """.utf8)
        let read = try DuckBench.readClimbed(answer)
        XCTAssertEqual(read.hash,
                       "a56d459fb6493855d635021dce569cc8b06b325b32b3c19e8593cf430ca442d1")
        XCTAssertEqual(read.rise, 0.06)
        XCTAssertEqual(read.cell, DuckBench.Cell(dh: -0.01, drop: 0.12, fmul: 1.0, tier: .core))
        XCTAssertTrue(read.honest)
        XCTAssertTrue(read.stable)
        XCTAssertEqual(read.uprightTailTicks, 50)
        // Unrounded, at full digits: the parity gate compares these against
        // robust.mjs and a reader that rounded would break it.
        XCTAssertEqual(read.aboveMillimetres, 116.17658662135791)
        XCTAssertEqual(read.xMillimetres, 237.36029825804)
        XCTAssertEqual(read.dyMillimetres, 17.621239174713033)
        XCTAssertEqual(read.feetOnTread, 2)
        XCTAssertEqual(read.peakAboveTreadMillimetres, 121.71408220291646)
        XCTAssertEqual(read.maxTorque, 0.6405)
        XCTAssertEqual(read.penetrationAtScoreMillimetres, -0.7428401259841899)
        XCTAssertEqual(read.minPenetrationEpisodeMillimetres, -6.9746295824819065)
        XCTAssertEqual(read.maxAbsDYMillimetres, 47.5896931638895)
        XCTAssertTrue(read.reachedFlight)
        XCTAssertFalse(read.invalid)
        XCTAssertNil(read.why)
        XCTAssertEqual(read.plantName, "scene.mjb")
        XCTAssertEqual(read.plantDigest,
                       "3f8c9ab9b409ba74c73c30179d5f7c12b025f631693f9eec78d80dca242547be")
        XCTAssertEqual(read.seconds, 1.031)
        XCTAssertTrue(read.overBar)
    }

    /// THE ANSWER A LIVE BENCH ACTUALLY SENT, captured verbatim on 2026-09-02
    /// from the Pi bench (`duck-bench/5`, `scene.mjb` `3f8c9ab9b409…`) for the
    /// record move's first cell. Pasted rather than paraphrased: a client
    /// tested only against a contract it wrote out itself is a client tested
    /// against its own reading of the contract.
    func testTheAnswerALiveBenchSentReadsWhole() throws {
        let answer = Data(#"""
        {"hash":"a56d459fb6493855d635021dce569cc8b06b325b32b3c19e8593cf430ca442d1","move":"a56d459fb649","rise":0.06,"cell":{"dh":-0.01,"drop":0.12,"fmul":1},"tail":"policy","plantName":"scene.mjb","plantDigest":"3f8c9ab9b409ba74c73c30179d5f7c12b025f631693f9eec78d80dca242547be","criterion":"honest: at the scored instant the trunk is upright, past the riser at x > 120 mm, more than 95 mm above the tread, with at least two feet resting on a tread (past the riser, within 5 mm below to 45 mm above it, and within 3 mm of a step), and the duck never left the 340 mm-wide flight at any tick of the episode. stable: honest, and upright for at least 45 of the 50 tail ticks.","invalid":false,"why":null,"honest":true,"stable":true,"uprightTailTicks":50,"tailTicks":50,"above_mm":116.17658662135791,"x_mm":237.36029825804,"dy_mm":17.621239174713033,"feetOnTread":2,"feetOnTreadMax":2,"peakAboveTread_mm":121.71408220291646,"maxTq":0.6405,"penetrationAtScore_mm":-0.7428401259841899,"minPenetrationEpisode_mm":-6.9746295824819065,"maxAbsDY_mm":47.5896931638895,"reachedFlight":true,"seconds":0.4841549970000051}
        """#.utf8)
        let read = try DuckBench.readClimbed(answer)
        XCTAssertEqual(read.hash.prefix(12), "a56d459fb649")
        XCTAssertEqual(read.cell, DuckBench.Cell(dh: -0.01, drop: 0.12, fmul: 1, tier: .core))
        XCTAssertTrue(read.honest)
        XCTAssertTrue(read.stable)
        XCTAssertEqual(read.uprightTailTicks, 50)
        XCTAssertEqual(read.tailTicks, 50)
        XCTAssertEqual(read.feetOnTreadMax, 2)
        XCTAssertEqual(read.aboveMillimetres, 116.17658662135791)
        XCTAssertEqual(read.peakAboveTreadMillimetres, 121.71408220291646)
        XCTAssertEqual(read.minPenetrationEpisodeMillimetres, -6.9746295824819065)
        XCTAssertEqual(read.plantDigest, StairsChallenge.plantDigest)
        XCTAssertTrue(read.criterion.hasPrefix("honest: at the scored instant"))
        // Under a second of physics — the size of ceiling a /climb cell needs.
        XCTAssertLessThan(read.seconds, 2)
        // And its digits survive into a bundle unchanged.
        let cell = StairsChallenge.Submission.cellJSON(read)
        let text = try XCTUnwrap(String(data: cell.encoded(.compact), encoding: .utf8))
        XCTAssertTrue(text.contains("116.17658662135791"))
        XCTAssertTrue(text.contains("-6.9746295824819065"))
    }

    /// The tier is not on the wire in the contract's cell, so it comes from
    /// the pinned grid. A count that mixed the nine with the fourteen would be
    /// comparable with nothing.
    func testTheTierComesFromTheGridWhenTheBenchDoesNotSayIt() throws {
        func tier(_ json: String) throws -> DuckBench.Cell.Tier {
            try DuckBench.readClimbed(Data(json.utf8)).cell.tier
        }
        XCTAssertEqual(try tier(#"{"hash":"h","rise":0.06,"cell":{"dh":0,"drop":0.12,"fmul":1}}"#),
                       .core)
        XCTAssertEqual(try tier(#"{"hash":"h","rise":0.06,"cell":{"dh":0.005,"drop":0.12,"fmul":1}}"#),
                       .ext)
        XCTAssertEqual(try tier(#"{"hash":"h","rise":0.06,"cell":{"dh":0,"drop":0.14,"fmul":0.5}}"#),
                       .ext)
        // And a bench that DOES say it is believed.
        XCTAssertEqual(try tier(#"{"hash":"h","rise":0.06,"cell":{"dh":0,"drop":0.12,"fmul":1,"tier":"ext"}}"#),
                       .ext)
    }

    /// A whole number is not a `Double` through `JSONSerialization`, and a
    /// reader that assumed it was would read every rounded field as absent.
    func testAWholeNumberIsStillANumber() throws {
        let answer = Data(#"""
        {"hash":"h","rise":0,"cell":{"dh":0,"drop":0.12,"fmul":1},"above_mm":116,"maxTq":1,
         "peakAboveTread_mm":0,"seconds":2}
        """#.utf8)
        let read = try DuckBench.readClimbed(answer)
        XCTAssertEqual(read.aboveMillimetres, 116)
        XCTAssertEqual(read.maxTorque, 1)
        XCTAssertEqual(read.seconds, 2)
        XCTAssertEqual(read.peakAboveTreadMillimetres, 0)
        XCTAssertFalse(read.overBar)
    }

    /// A missing penetration is NULL, not zero. Zero is a measurement.
    func testAnUnmeasuredPenetrationIsAbsentRatherThanZero() throws {
        let read = try DuckBench.readClimbed(
            Data(#"{"hash":"h","rise":0.06,"cell":{"dh":0,"drop":0.12,"fmul":1}}"#.utf8))
        XCTAssertNil(read.penetrationAtScoreMillimetres)
        XCTAssertNil(read.minPenetrationEpisodeMillimetres)
    }

    /// A bench without `/climb` is a fact, not a failure, and it arrives in
    /// the bench's own words.
    func testABenchWithoutClimbSaysSoInItsOwnWords() {
        XCTAssertThrowsError(try DuckBench.readClimbed(Data(#"{"error":"no /climb here"}"#.utf8))) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .bench("no /climb here"))
        }
        XCTAssertThrowsError(try DuckBench.readClimbGrid(Data(#"{"error":"no /climb here"}"#.utf8))) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .bench("no /climb here"))
        }
    }

    func testRubbishIsNotAnAnswer() {
        XCTAssertThrowsError(try DuckBench.readClimbed(Data("<html>".utf8))) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .notJSON)
        }
        XCTAssertThrowsError(try DuckBench.readClimbed(Data("{}".utf8))) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .empty)
        }
    }

    /// An INVALID cell carries its reason. It is not a failed cell; it is a
    /// file that is not a result.
    func testAnInvalidCellCarriesWhy() throws {
        let read = try DuckBench.readClimbed(Data(#"""
        {"hash":"h","rise":0.06,"cell":{"dh":0,"drop":0.12,"fmul":1},
         "invalid":true,"why":"blend 2.9 is outside the declared [0.7, 2.4]"}
        """#.utf8))
        XCTAssertTrue(read.invalid)
        XCTAssertEqual(read.why, "blend 2.9 is outside the declared [0.7, 2.4]")
    }

    // MARK: - the grid endpoint

    func testTheGridReadsAsAnObjectOrAsABareArray() throws {
        let wrapped = Data(#"""
        {"cells":[{"dh":-0.01,"drop":0.12,"fmul":1,"tier":"core"},
                  {"dh":0.005,"drop":0.12,"fmul":1,"tier":"ext"}]}
        """#.utf8)
        let bare = Data(#"""
        [{"dh":-0.01,"drop":0.12,"fmul":1},{"dh":0.005,"drop":0.12,"fmul":1}]
        """#.utf8)
        let wanted = [DuckBench.Cell(dh: -0.01, drop: 0.12, fmul: 1, tier: .core),
                      DuckBench.Cell(dh: 0.005, drop: 0.12, fmul: 1, tier: .ext)]
        XCTAssertEqual(try DuckBench.readClimbGrid(wrapped).cells, wanted)
        XCTAssertEqual(try DuckBench.readClimbGrid(bare).cells, wanted)
    }

    /// A BENCH CAN ANSWER THE GRID AND STILL NOT BE ABLE TO SCORE IT. The
    /// fourteen cells are a constant; whether this plant has a step bank is
    /// not. A client that read only the cells would draw a Score button on a
    /// bench about to refuse every request.
    func testABenchThatCannotClimbSaysSoBesideTheCells() throws {
        let said = Data(#"""
        {"cells":[{"dh":0,"drop":0.12,"fmul":1,"tier":"core"}],
         "climbable":false,"why":"this scene has no step bank",
         "bar":7,"uprightTailMin":45,"criterion":"honest: …",
         "plantName":"scene.mjb","plantDigest":"3f8c9ab9b409"}
        """#.utf8)
        let grid = try DuckBench.readClimbGrid(said)
        XCTAssertFalse(grid.climbable)
        XCTAssertEqual(grid.why, "this scene has no step bank")
        XCTAssertEqual(grid.bar, 7)
        XCTAssertEqual(grid.uprightTailMinimum, 45)
        XCTAssertEqual(grid.criterion, "honest: …")
        XCTAssertEqual(grid.plantName, "scene.mjb")
    }

    /// A bench that says nothing about itself is assumed able, because that is
    /// what every bench answering the short form is.
    func testABenchThatSaysNothingAboutItselfIsTakenAsAble() throws {
        let grid = try DuckBench.readClimbGrid(
            Data(#"[{"dh":0,"drop":0.12,"fmul":1}]"#.utf8))
        XCTAssertTrue(grid.climbable)
        XCTAssertEqual(grid.bar, StairsChallenge.bar)
        XCTAssertEqual(grid.uprightTailMinimum, 45)
        XCTAssertNil(grid.criterion)
    }

    /// The live bench's own fourteen cells are the pinned fallback, in order.
    func testTheBenchesGridAndThePinnedOneAgree() throws {
        var rows: [String] = []
        for cell in StairsChallenge.Grid.fallback {
            rows.append("{\"dh\":\(cell.dh),\"drop\":\(cell.drop),\"fmul\":\(cell.fmul),"
                      + "\"tier\":\"\(cell.tier.rawValue)\"}")
        }
        let said = Data("{\"cells\":[\(rows.joined(separator: ","))]}".utf8)
        XCTAssertTrue(StairsChallenge.Grid.isPublishedGrid(
            try DuckBench.readClimbGrid(said).cells))
    }

    func testAnEmptyGridIsEmptyRatherThanAGridOfNothing() {
        XCTAssertThrowsError(try DuckBench.readClimbGrid(Data(#"{"cells":[]}"#.utf8))) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .empty)
        }
    }
}
