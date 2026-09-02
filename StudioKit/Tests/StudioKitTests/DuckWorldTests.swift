import XCTest
import DuckKit
@testable import StudioKit

/// Changing the world the bench stands in — and, mostly, everything it will not
/// change.
///
/// THE HALF OF THIS FEATURE WORTH TESTING IS THE REFUSALS. A scene that fits
/// the bank is a request that works; a scene that does not is the case that
/// either produces an honest note or produces a picture of a world nobody is
/// standing in. So every rule in the expressibility table gets a case here, and
/// every sentence is read letter by letter rather than eyeballed on a phone.
final class DuckWorldTests: XCTestCase {

    let bank = DuckWorld.Bank.pinned

    // MARK: - the bank, as transcribed

    func testTheBankIsTheOneInThePlant() {
        XCTAssertEqual(bank.count, 14)
        XCTAssertEqual(bank.y, 1.305, accuracy: 1e-9)
        XCTAssertEqual(bank.halfDepth, 0.17, accuracy: 1e-9)
        XCTAssertEqual(bank.halfWidth, 0.17, accuracy: 1e-9)
        XCTAssertEqual(bank.halfHeight, 0.10, accuracy: 1e-9)
        XCTAssertEqual(bank.arenaInner, 1.45, accuracy: 1e-9)
        XCTAssertEqual(bank.wallHeight, 0.25, accuracy: 1e-9)
        // Runs longer than twice the half depth stop overlapping.
        XCTAssertEqual(bank.solidRunCeiling, 0.34, accuracy: 1e-9)
    }

    /// THE 25 mm THAT IS ACTUALLY INSIDE THE WALL. `STAIR_Y` was derived as
    /// 1.5 − 0.025 − 0.17 on the belief that `wall_n` is 25 mm half-thick; it
    /// is 50 mm, so the outer edge of every tread is buried. The number stays
    /// because the bodies are compiled there and the gate has to be measured
    /// from where they are.
    func testTheTreadsOuterEdgeIsInsideTheNorthWall() {
        XCTAssertEqual(bank.treadInsideTheWall, 0.025, accuracy: 1e-9)
    }

    func testTheBanksReasonsAreSaidRatherThanImplied() {
        XCTAssertTrue(bank.yWhy.contains("1.305"))
        XCTAssertTrue(bank.yWhy.contains("recompiling"))
        XCTAssertTrue(bank.sizeWhy.contains("340"))
        XCTAssertTrue(bank.sizeWhy.contains("200"))
    }

    // MARK: - what a request cannot ask for at all

    func testFifteenStepsIsRefusedAndFourteenIsNot() {
        let fifteen = DuckScene(name: "fifteen",
                                steps: (0..<15).map {
                                    DuckScene.Step(x: -1.2 + Double($0) * 0.02, y: 0, top: 0.06)
                                })
        let refusal = DuckWorld.plan(for: fifteen, on: bank).refusals
            .first { if case .tooManySteps = $0 { return true } else { return false } }
        XCTAssertEqual(refusal, .tooManySteps(asked: 15, bank: 14))
        XCTAssertTrue(refusal!.message.contains("fifteenth"))

        let fourteen = DuckScene(name: "fourteen",
                                 steps: (0..<14).map {
                                     DuckScene.Step(x: -1.2 + Double($0) * 0.02, y: 0, top: 0.06)
                                 })
        XCTAssertTrue(DuckWorld.plan(for: fourteen, on: bank).isSendable)
    }

    /// THE ARENA IS WHAT LIMITS A REGULAR FLIGHT TO FOUR STEPS at the
    /// challenge's run. Far face = start + (n−1)·run + halfDepth: at run 0.28
    /// and start 0.12, n = 4 reaches 1.30 m and n = 5 reaches 1.58, which is
    /// 130 mm through `wall_e`.
    func testAFifthStepAtTheChallengesRunIsRefusedByName() {
        let four = DuckScene.staircase(count: 4, rise: 0.060, run: 0.28, start: 0.12)
        XCTAssertTrue(DuckWorld.plan(for: four, on: bank).isSendable,
                      "four steps fit inside the arena")

        let five = DuckScene.staircase(count: 5, rise: 0.060, run: 0.28, start: 0.12)
        let refusals = DuckWorld.plan(for: five, on: bank).refusals
        XCTAssertEqual(refusals.count, 1)
        guard case .stepCrossesTheArena(let index, let face, let wall, _) = refusals[0] else {
            return XCTFail("expected an arena refusal, got \(refusals)")
        }
        XCTAssertEqual(index, 4)
        XCTAssertEqual(face, 1.58, accuracy: 1e-9)
        XCTAssertEqual(wall, "wall_e")
        XCTAssertTrue(refusals[0].message.contains("wall_e"))
        XCTAssertTrue(refusals[0].message.contains("200 kg"))
    }

    func testAStepPushedThroughTheWestWallIsRefusedByItsOwnName() {
        let scene = DuckScene(name: "backwards",
                              steps: [DuckScene.Step(x: -1.40, y: 0, top: 0.06)])
        let refusals = DuckWorld.plan(for: scene, on: bank).refusals
        guard case .stepCrossesTheArena(_, _, let wall, _) = refusals.first else {
            return XCTFail("expected an arena refusal, got \(refusals)")
        }
        XCTAssertEqual(wall, "wall_w")
    }

    func testABallOutsideTheArenaIsRefused() {
        let outside = DuckScene(name: "far ball", props: [DuckScene.ball(x: 2.0, y: 0)])
        let refusals = DuckWorld.plan(for: outside, on: bank).refusals
        XCTAssertEqual(refusals.first,
                       .ballOutsideTheArena(x: 2.0, y: 0, inner: 1.45, radius: 0.05))
        XCTAssertTrue(refusals.first!.message.contains("1.45"))

        // THE FOOTPRINT, NOT THE CENTRE — the bench's own rule. A centre 20 mm
        // inside the face still puts 30 mm of the ball in the wall.
        let grazing = DuckScene(name: "grazing", props: [DuckScene.ball(x: 1.43, y: 0)])
        XCTAssertFalse(DuckWorld.plan(for: grazing, on: bank).isSendable)

        let inside = DuckScene(name: "near ball", props: [DuckScene.ball(x: 0.80, y: 0)])
        let plan = DuckWorld.plan(for: inside, on: bank)
        XCTAssertTrue(plan.isSendable)
        XCTAssertEqual(plan.ball, DuckWorld.Point(x: 0.80, y: 0))
    }

    /// A refused plan is not a request. The bench would answer 400 with the
    /// same reason, and making somebody wait for that is making them wait to
    /// be told what was already known.
    func testAPlanWithARefusalIsNeverSent() throws {
        let address = try DuckBench.address("192.168.1.20:8770")
        let five = DuckScene.staircase(count: 5, rise: 0.060, run: 0.28, start: 0.12)
        XCTAssertThrowsError(try DuckBench.setWorld(address,
                                                    DuckWorld.plan(for: five, on: bank))) {
            guard case DuckWorld.Refusal.stepCrossesTheArena = $0 else {
                return XCTFail("\($0)")
            }
        }
    }

    /// THE BENCH REFUSES A BODY THAT BOTH CLEARS AND LAYS — "say one or the
    /// other" — so the kit must never send one. A scene says what its steps
    /// are, even when the answer is none; `Plan.bareFloor` is the other
    /// spelling and it sends no `steps` key at all.
    func testAWorldRequestNeverBothClearsAndLays() throws {
        let address = try DuckBench.address("192.168.1.20:8770")

        let empty = DuckWorld.plan(for: DuckScene.bareFloor(), on: bank)
        let laid = try body(of: DuckBench.setWorld(address, empty))
        XCTAssertNil(laid["clear"])
        XCTAssertEqual((laid["steps"] as? [Any])?.count, 0)

        let parked = try body(of: DuckBench.setWorld(address, .bareFloor()))
        XCTAssertEqual(parked["clear"] as? Bool, true)
        XCTAssertNil(parked["steps"], "clear and steps together is refused by the bench")
        XCTAssertEqual(parked["name"] as? String, "Bare floor")
    }

    /// MOVING THE BALL MUST NOT PARK THE BANK. A plan built from a scene always
    /// names its steps, so a ball-only picker entry needs the third state:
    /// neither `clear` nor `steps`, which the bench reads as "leave the bank".
    func testMovingTheBallSaysNothingAboutTheBank() throws {
        let address = try DuckBench.address("192.168.1.20:8770")
        let sent = try body(of: DuckBench.setWorld(
            address, .moveTheBall(to: DuckWorld.Point(x: 0.80, y: 0))))
        XCTAssertNil(sent["steps"])
        XCTAssertNil(sent["clear"])
        XCTAssertEqual((sent["ball"] as? [String: Any])?["x"] as? Double, 0.80)

        // And it is refused on the same footprint rule as everything else.
        XCTAssertFalse(DuckWorld.Plan
            .moveTheBall(to: DuckWorld.Point(x: 1.43, y: 0)).isSendable)
    }

    /// A staircase goes on the wire as `{x, top}` and nothing else — the two
    /// numbers a slide joint can be written with.
    func testAStaircaseGoesOnTheWireAsTheTwoNumbersASlideCanHold() throws {
        let address = try DuckBench.address("192.168.1.20:8770")
        let scene = DuckScene.staircase(count: 4, rise: 0.060, run: 0.28, start: 0.12)
        let sent = try body(of: DuckBench.setWorld(address,
                                                   DuckWorld.plan(for: scene, on: bank)))
        let steps = try XCTUnwrap(sent["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.count, 4)
        // FULL PRECISION ON THE WIRE, ROUNDED IN THE ANSWER. The generator's
        // x is 0.29000000000000015 and the bench reads back 0.29 — it rounds
        // its readback to four places — so nothing here may compare the two
        // exactly.
        for (i, x) in [0.29, 0.57, 0.85, 1.13].enumerated() {
            XCTAssertEqual(steps[i]["x"] as? Double ?? .nan, x, accuracy: 1e-9)
        }
        for (i, top) in [0.06, 0.12, 0.18, 0.24].enumerated() {
            XCTAssertEqual(steps[i]["top"] as? Double ?? .nan, top, accuracy: 1e-9)
        }
        XCTAssertEqual(Set(steps[0].keys), ["x", "top"])
        XCTAssertNil(sent["ball"], "a scene that drew no ball does not move it")
    }

    private func body(of call: DuckBench.Call) throws -> [String: Any] {
        let data = try XCTUnwrap(call.body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - what it says instead of refusing

    func testAStepAtYZeroComesBackAt1305AndSaysSo() throws {
        let scene = DuckScene(name: "one", steps: [DuckScene.Step(x: 0.29, y: 0, top: 0.06)])
        let note = try XCTUnwrap(DuckWorld.plan(for: scene, on: bank).predicted
            .first { $0.field == "y" })
        XCTAssertEqual(note.asked, "0.000 m")
        XCTAssertEqual(note.got, "1.305 m")
        XCTAssertTrue(note.says.hasPrefix("Step 1's y: asked for 0.000 m, got 1.305 m."))
    }

    func testATallerBlockComesBackAtTheBanksHeight() {
        let scene = DuckScene(name: "chunky",
                              steps: [DuckScene.Step(x: 0.29, y: 1.305, top: 0.25,
                                                     halfHeight: 0.25)])
        let note = DuckWorld.plan(for: scene, on: bank).predicted
            .first { $0.field == "halfHeight" }
        XCTAssertEqual(note?.asked, "250 mm")
        XCTAssertEqual(note?.got, "100 mm")
    }

    func testABlockOfAnotherSizeComesBackTheBanksSize() {
        let scene = DuckScene(name: "narrow",
                              steps: [DuckScene.Step(x: 0.29, y: 1.305, top: 0.06,
                                                     halfDepth: 0.10, halfWidth: 0.10)])
        let note = DuckWorld.plan(for: scene, on: bank).predicted
            .first { $0.field == "size" }
        XCTAssertEqual(note?.asked, "200 × 200 mm")
        XCTAssertEqual(note?.got, "340 × 340 mm")
    }

    /// A RUN OVER 0.34 IS LAID, NOT REFUSED. The blocks go exactly where they
    /// were asked for; they stop overlapping, so a foot can go between them.
    ///
    /// ONE NOTE PER GAP, IN THE BENCH'S OWN WORDS AND ITS OWN SHAPE, so a
    /// prediction and the readback that follows it can be read side by side.
    func testARunOverTheOverlapCeilingIsNotASolidFlight() {
        let gappy = DuckScene.staircase(count: 3, rise: 0.060, run: 0.40, start: 0.12)
        let plan = DuckWorld.plan(for: gappy, on: bank)
        XCTAssertTrue(plan.isSendable)
        let gaps = plan.predicted.filter { $0.what == "gap between steps" }
        XCTAssertEqual(gaps.count, 2)
        XCTAssertEqual(gaps.map(\.index), [1, 2])
        XCTAssertEqual(gaps[0].asked, "0.400 m")
        XCTAssertEqual(gaps[0].got, "0.060 m")   // the daylight, not a substituted run
        XCTAssertTrue(gaps[0].why.contains("60 mm of daylight"))
        XCTAssertTrue(gaps[0].why.contains("not a solid flight"))

        let solid = DuckScene.staircase(count: 3, rise: 0.060, run: 0.28, start: 0.12)
        XCTAssertNil(DuckWorld.plan(for: solid, on: bank).predicted
            .first { $0.what == "gap between steps" })
    }

    func testAWallThatIsNotTheArenasIsNotBuilt() {
        let scene = DuckScene(name: "wall", walls: [DuckScene.Wall(x: 0, y: 1.5)])
        let plan = DuckWorld.plan(for: scene, on: bank)
        let note = plan.predicted.first { $0.what == "wall" }
        XCTAssertNotNil(note)
        XCTAssertTrue(note!.why.contains("wall_n"))
        XCTAssertTrue(note!.why.contains("no joints"))
        // IT IS SENT TO BE REFUSED, so the row lands in the READBACK the
        // screen draws rather than only in this prediction.
        XCTAssertEqual(plan.walls, ["a wall at (0.00, 1.50) m"])
    }

    /// THE BALL CANNOT BE TAKEN OUT, so a scene that drew no ball still gets
    /// one and the person is told where it came from.
    func testASceneWithNoBallIsToldItStillHasOne() {
        let scene = DuckScene.staircase(count: 4, rise: 0.060, run: 0.28, start: 0.12)
        let note = DuckWorld.plan(for: scene, on: bank).predicted.first { $0.what == "ball" }
        XCTAssertNotNil(note)
        XCTAssertTrue(note!.why.contains("permanent body"))
        XCTAssertEqual(note!.says, "Ball: still where it was. " + note!.why)
    }

    // MARK: - seating a prop on a body that exists

    let plant: [DuckBench.Health.Graspable] = [
        .init(name: "block_a", kilograms: 0.030),
        .init(name: "block_b", kilograms: 0.025),
        .init(name: "block_c", kilograms: 0.018),
        .init(name: "cone_a", kilograms: 0.020),
        .init(name: "cone_b", kilograms: 0.020),
    ]

    func testABlockSeatsOnTheFirstBlockAndABroomSeatsOnNothing() {
        XCTAssertEqual(DuckWorld.seat(DuckScene.block(), among: plant), "block_a")
        XCTAssertNil(DuckWorld.seat(DuckScene.broom(), among: plant))
        XCTAssertNil(DuckWorld.seat(DuckScene.dowel(), among: plant))
        // Case is the scene's, not the model's.
        XCTAssertEqual(DuckWorld.seat(DuckScene.Prop(name: "BLOCK", x: 0, y: 0, grams: 1,
                                                     thicknessMillimetres: 1, length: 1),
                                      among: plant), "block_a")
        XCTAssertNil(DuckWorld.seat(DuckScene.Prop(name: "  ", x: 0, y: 0, grams: 1,
                                                   thicknessMillimetres: 1, length: 1),
                                    among: plant))
    }

    func testAPropThePlantLacksIsNamedWithTheBodiesItHas() throws {
        let scene = DuckScene(name: "cupboard", props: [DuckScene.broom(), DuckScene.block()])
        let plan = DuckWorld.plan(for: scene, on: bank, graspables: plant)
        // THE BROOM IS STILL SENT, under the name the scene gave it, so the
        // bench answers with the five bodies it does have. Dropping it here
        // would make it vanish silently.
        XCTAssertEqual(plan.props, [DuckWorld.Requested(name: "Broom", x: 0.9, y: 0),
                                    DuckWorld.Requested(name: "block_a", x: 0.30, y: 0.40)])
        let note = try XCTUnwrap(plan.predicted.first { $0.what == "prop" })
        XCTAssertEqual(note.asked, "Broom")
        XCTAssertTrue(note.why.contains("block_a, block_b, block_c, cone_a, cone_b"))
    }

    /// AN EMPTY GRASPABLE LIST MEANS "NOT KNOWN", NOT "NONE". Telling somebody
    /// their broom will not fit in a world nobody has asked about is inventing
    /// a fact.
    func testWithNoHealthReadNothingIsPredictedAboutProps() {
        let scene = DuckScene(name: "cupboard", props: [DuckScene.broom()])
        let plan = DuckWorld.plan(for: scene, on: bank)
        XCTAssertEqual(plan.props, [DuckWorld.Requested(name: "Broom", x: 0.9, y: 0)])
        XCTAssertNil(plan.predicted.first { $0.what == "prop" })
    }

    // MARK: - the readback is what gets drawn

    func testTheStageDrawsTheReadbackAndNotTheRequest() {
        let world = DuckWorld(
            isSet: true, name: "4 steps at 60 mm",
            steps: [.init(x: 0.29, y: 1.305, top: 0.06,
                          halfDepth: 0.17, halfWidth: 0.17, halfHeight: 0.10)],
            ball: DuckWorld.Point(x: 0.55, y: 0.1, z: 0.05),
            props: [DuckWorld.Seated(name: "block_a", x: 0.3, y: 0.4, kilograms: 0.03)])
        let environment = world.asEnvironment
        XCTAssertEqual(environment.steps.count, 1)
        XCTAssertEqual(environment.steps[0].y, 1.305, accuracy: 1e-9)
        XCTAssertEqual(environment.steps[0].halfHeight, 0.10, accuracy: 1e-9)
        // THE ARENA IS NOT DRAWN, and the reason is in a sentence rather than
        // in four bars across the room in the wrong two places.
        XCTAssertTrue(environment.walls.isEmpty)

        let props = world.asProps
        XCTAssertEqual(props.map(\.name), ["Ball", "block_a"])
        XCTAssertEqual(props[0].shape, .ball)
        XCTAssertEqual(props[1].shape, .block)
        XCTAssertEqual(props[1].grams, 30, accuracy: 1e-9)
    }

    func testAWorldWithNoBallDrawsNoBall() {
        let world = DuckWorld(isSet: true, name: "no ball", steps: [], ball: nil)
        XCTAssertTrue(world.asProps.isEmpty)
    }

    // MARK: - reading a bench's answer

    /// `Fixtures/bench/world.json` IS THE BENCH'S OWN ANSWER, CAPTURED, not a
    /// body written to match this reader.
    ///
    /// WHY THAT DISTINCTION IS THE WHOLE VALUE OF THE FILE. A fixture written
    /// beside the parser it feeds agrees with the parser by construction, which
    /// is exactly the evidence that let a placeholder ship once already. These
    /// bytes came out of `sim/world_parity.mjs` phase 2: `POST /world` with the
    /// stairs challenge at 60 mm — four steps, run 0.28, start 0.12, centres at
    /// 0.29, 0.57, 0.85 and 1.13, the last reaching 1.30 m and stopping 150 mm
    /// short of `wall_e` — read back through `GET /world`.
    ///
    /// IT ALSO CORRECTED THIS READER RATHER THAN THE OTHER WAY AROUND. The
    /// design said `unexpressed[].what` would be one word and `props[].at` an
    /// object; the bench sends "step y" and "step size" as two-word subjects,
    /// `at` as `[x, y, z]`, and `asked`/`got` as bare numbers and as LISTS of
    /// body names. All four are what the reader now handles.
    private func capturedWorld() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/bench/world",
                                                  withExtension: "json"),
                                "the world fixture is missing")
        return try Data(contentsOf: url)
    }

    func testItReadsAWorldTheBenchIsStandingIn() throws {
        let world = try DuckBench.readWorld(capturedWorld())
        XCTAssertTrue(world.isSet)
        XCTAssertEqual(world.name, "Stairs challenge, 60 mm")
        XCTAssertEqual(world.steps.map(\.x), [0.29, 0.57, 0.85, 1.13])
        XCTAssertEqual(world.steps.map(\.top), [0.06, 0.12, 0.18, 0.24])
        for step in world.steps {
            XCTAssertEqual(step.y, 1.305, accuracy: 1e-9)
            XCTAssertEqual(step.halfHeight, 0.10, accuracy: 1e-9)
        }
        XCTAssertEqual(world.ball, DuckWorld.Point(x: 0.8, y: 0, z: 0.05))
        XCTAssertEqual(world.ballRadius, 0.05)
        XCTAssertEqual(world.props.map(\.name),
                       ["block_a", "block_b", "block_c", "cone_a", "cone_b"])
        XCTAssertEqual(world.props[0].kilograms, 0.030)
        // `at` ARRIVES AS `[x, y, z]`, and the world has moved block_a away
        // from where the plant compiled it (0.30, 0.40).
        XCTAssertEqual(world.props[0].x, 0.45, accuracy: 1e-9)
        XCTAssertEqual(world.props[0].y, -0.30, accuracy: 1e-9)
        XCTAssertEqual(world.bank, DuckWorld.Bank.pinned)
        XCTAssertEqual(world.arena.walls.map(\.name).sorted(),
                       ["wall_e", "wall_n", "wall_s", "wall_w"])
        XCTAssertEqual(world.arena.innerX, 1.45, accuracy: 1e-9)
        // NINE NOTES, AND THE TWO THAT MATTER ARE THE LISTS. A scene asking
        // for a broom and a partition is told, by name, what this plant has
        // instead — and `got` is an array on the wire, which is why the reader
        // renders a list rather than dropping the row.
        XCTAssertEqual(world.unexpressed.count, 9)
        XCTAssertEqual(Set(world.unexpressed.map(\.what)),
                       ["step y", "step size", "prop", "wall"])
        let flattenedY = try XCTUnwrap(world.unexpressed.first { $0.what == "step y" })
        XCTAssertEqual(flattenedY.asked, "0")
        XCTAssertEqual(flattenedY.got, "1.305")
        XCTAssertEqual(flattenedY.says,
                       "Step 1 y: asked for 0, got 1.305. "
                     + "the block has an x and a z slide and no y joint")
        let broom = try XCTUnwrap(world.unexpressed.first { $0.what == "prop" })
        XCTAssertEqual(broom.asked, "broom")
        XCTAssertEqual(broom.got, "block_a, block_b, block_c, cone_a, cone_b")
        XCTAssertTrue(broom.says.hasPrefix("Prop 2's name: asked for broom, got block_a,"))
        let partition = try XCTUnwrap(world.unexpressed.first { $0.what == "wall" })
        XCTAssertEqual(partition.got, "wall_e, wall_n, wall_s, wall_w")
        XCTAssertEqual(world.plantName, "scene.mjb")
        XCTAssertEqual(world.plantDigest?.prefix(12), "3f8c9ab9b409")
        // The stage draws exactly this and no walls.
        XCTAssertEqual(world.asEnvironment.steps.count, 4)
        XCTAssertTrue(world.asEnvironment.walls.isEmpty)
        XCTAssertEqual(world.asProps.count, 6)
    }

    /// A BENCH WITHOUT THE ROUTE IS A FACT, NOT A FAULT. Every shell in this
    /// family answers an unknown path with its own words, and the screen prints
    /// `noWorldRoute` beside a disabled picker rather than a failure.
    func testAnOlderBenchComesBackAsTheBenchsOwnWords() {
        let body = Data(#"{"error":"no /world here"}"#.utf8)
        XCTAssertThrowsError(try DuckBench.readWorld(body)) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .bench("no /world here"))
        }
        XCTAssertThrowsError(try DuckBench.readWorld(Data("not json".utf8))) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .notJSON)
        }
    }

    /// A bench that answers only the world, with no bank and no arena, is
    /// answered from the transcription — those numbers are compiled into the
    /// plant, and a bench that does not repeat them has not changed them.
    func testABareAnswerFallsBackToTheTranscribedBank() throws {
        let body = Data(#"{"world":{"set":false,"name":null},"steps":[],"ball":null}"#.utf8)
        let world = try DuckBench.readWorld(body)
        XCTAssertFalse(world.isSet)
        XCTAssertNil(world.name)
        XCTAssertNil(world.ball)
        XCTAssertEqual(world.bank, DuckWorld.Bank.pinned)
        XCTAssertEqual(world.arena, DuckWorld.Arena.pinned)
    }

    // MARK: - the ball moves while you drive

    /// `/state` CARRIES THE BALL AS `[x, y, z]`, and a world with no ball
    /// carries a null there. Both have to read, and neither may become a ball
    /// at the origin.
    func testTheLiveReadPicksUpTheBallAndSurvivesItsAbsence() throws {
        let joints = Array(repeating: 0.0, count: DuckModel.policyJointCount)
        func state(_ ball: String) -> Data {
            Data("""
            {"t":1.0,"position":[0,0,0.12],"quaternion":[1,0,0,0],
             "joints":\(joints),"height":0.12,"upright":true,
             "policy":"alpha_walking.onnx","command":{"vx":0,"vy":0,"vyaw":0},
             "ball":\(ball)}
            """.utf8)
        }
        let rolling = try DuckDrive.readLive(state("[0.8,0.0,0.05]"))
        XCTAssertEqual(rolling.ball, DuckWorld.Point(x: 0.8, y: 0, z: 0.05))
        XCTAssertNil(try DuckDrive.readLive(state("null")).ball)
        // An older bench does not send the field at all.
        let older = Data("""
        {"t":1.0,"position":[0,0,0.12],"quaternion":[1,0,0,0],
         "joints":\(joints),"height":0.12,"upright":true,
         "command":{"vx":0,"vy":0,"vyaw":0}}
        """.utf8)
        XCTAssertNil(try DuckDrive.readLive(older).ball)
    }

    // MARK: - the sentences

    func testEverySentenceSaysTheThingItIsFor() {
        XCTAssertTrue(DuckWorld.benchOwnWorld.contains("exactly as it booted"))
        XCTAssertTrue(DuckWorld.benchOwnWorld.contains("comparable"))

        // THE ONE THIS WHOLE FEATURE OWES SOMEBODY.
        XCTAssertTrue(DuckWorld.bareFloorIsAChange.contains("never been parked"))
        XCTAssertTrue(DuckWorld.bareFloorIsAChange.contains("fourteen"))
        XCTAssertTrue(DuckWorld.bareFloorIsAChange.contains("Nothing published moves"))

        XCTAssertTrue(DuckWorld.noWorldRoute.contains("/world"))
        XCTAssertTrue(DuckWorld.arenaIsNotDrawn.contains("1.45"))
        XCTAssertTrue(DuckWorld.arenaIsNotDrawn.contains("not in the picture"))
        XCTAssertTrue(DuckWorld.resetKeepsTheWorld.contains("lays your steps"))
        // NOTHING CAN GIVE THE BOOTED WORLD BACK, and the sentence no longer
        // pretends a row can.
        XCTAssertFalse(DuckWorld.resetKeepsTheWorld.contains("give it back"))
        XCTAssertTrue(DuckWorld.oneWayUntilRestart.contains("one-way until the bench restarts"))
        XCTAssertTrue(DuckWorld.ballNeedsAWorld.contains("Pick a floor or a flight first"))
        XCTAssertTrue(DuckWorld.floorIsNotAReadback.contains("not a readback"))
    }

    func testTheUnexpressedHeadingCountsAndDisappears() {
        XCTAssertNil(DuckWorld.couldNotExpress([]))
        let one = DuckWorld.Unexpressed(what: "step", why: "because")
        XCTAssertEqual(DuckWorld.couldNotExpress([one]),
                       "One thing in that scene this world cannot say:")
        XCTAssertEqual(DuckWorld.couldNotExpress([one, one]),
                       "2 things in that scene this world cannot say:")
    }

    /// Every shape of note has to read as a sentence, including the ones with
    /// half their fields missing.
    func testAnUnexpressedNoteReadsAsASentenceInEveryShape() {
        XCTAssertEqual(DuckWorld.Unexpressed(what: "wall", why: "no fifth wall.").says,
                       "Wall. no fifth wall.")
        XCTAssertEqual(DuckWorld.Unexpressed(what: "step", index: 2, field: "y",
                                             asked: "0.000 m", got: "1.305 m",
                                             why: "compiled.").says,
                       "Step 3's y: asked for 0.000 m, got 1.305 m. compiled.")
        XCTAssertEqual(DuckWorld.Unexpressed(what: "prop", asked: "Broom", why: "absent.").says,
                       "Prop: asked for Broom. absent.")
        XCTAssertEqual(DuckWorld.Unexpressed(what: "", why: "").says, "Something.")
        // THE BENCH'S OWN TWO-WORD SPELLING. It has already named the part, so
        // the field is not said twice.
        XCTAssertEqual(DuckWorld.Unexpressed(what: "step size", index: 1, field: "halfHeight",
                                             asked: "0.12", got: "0.1",
                                             why: "one bank.").says,
                       "Step 2 size: asked for 0.12, got 0.1. one bank.")
    }

    // MARK: - Control's scene can be deleted too

    func testADeletedSceneOnControlDoesNotClaimABareFloor() {
        let said = StageCaption.sceneDeleted(.drivenIn)
        XCTAssertFalse(said.contains("bare floor"),
                       "the bench is standing in whatever was last built there")
        XCTAssertTrue(said.contains("bench's own world"))
    }

    // MARK: - where you are driving it

    func testTheThreeVenuesAreLabelledAndOnlyOneIsANotYet() {
        XCTAssertEqual(DriveVenue.allCases.map(\.label), ["Sim", "Your floor", "Robot"])
        XCTAssertNil(DriveVenue.sim.notYet)
        XCTAssertNil(DriveVenue.ar.notYet)
        XCTAssertEqual(DriveVenue.real.notYet, DriveVenue.robotIsNotDrivenYet)
        XCTAssertTrue(DriveVenue.ar.oneLine.contains("does not move house"))
    }

    /// AR IS COERCED BACK WHEN THE CAMERA IS SHUT, and the robot venue is not:
    /// it is worth opening, and what it must not draw is a stick.
    func testAShutCameraCoercesOnlyTheARVenue() {
        let shut = CameraAvailability(usageDescriptionIsDeclared: true,
                                      permission: .denied,
                                      deviceSupportsWorldTracking: true)
        XCTAssertEqual(DriveVenue.coerce(.ar, camera: shut), .sim)
        XCTAssertEqual(DriveVenue.coerce(.real, camera: shut), .real)
        XCTAssertEqual(DriveVenue.coerce(.sim, camera: shut), .sim)

        let open = CameraAvailability(usageDescriptionIsDeclared: true,
                                      permission: .authorized,
                                      deviceSupportsWorldTracking: true)
        XCTAssertEqual(DriveVenue.coerce(.ar, camera: open), .ar)
        XCTAssertTrue(DriveVenue.ar.canBeEntered(camera: open))
        XCTAssertFalse(DriveVenue.ar.canBeEntered(camera: shut))
    }

    func testARSaysWhatIsMeasuredAndWhatIsDrawn() {
        XCTAssertTrue(DriveVenue.arIsReal.contains("where your phone is"))
        XCTAssertTrue(DriveVenue.arIsReal.contains("floor"))
        XCTAssertTrue(DriveVenue.arIsNot.contains("walk through your sofa"))
        XCTAssertTrue(DriveVenue.arIsNot.contains("2.9 m"))
    }

    /// THE UNMEASURED ARRANGEMENT IS NAMED, NOT REFUSED, and only when it is
    /// actually the arrangement.
    func testTwoEnginesOnOnePhoneIsSaidOnlyWhenTheBenchIsThePhone() throws {
        XCTAssertNil(DriveVenue.twoEnginesOnOnePhone(benchIsThisPhone: false))
        let said = try XCTUnwrap(DriveVenue.twoEnginesOnOnePhone(benchIsThisPhone: true))
        XCTAssertTrue(said.contains("Nobody has measured"))
        XCTAssertTrue(said.contains("not refused"))
    }

    /// The robot venue names the transport rather than apologising, and says
    /// what is already written toward it.
    func testTheRobotVenueNamesTheTransportAndTheGap() {
        XCTAssertTrue(DriveVenue.robotIsNotDrivenYet.contains("Bluetooth"))
        XCTAssertTrue(DriveVenue.robotIsNotDrivenYet.contains("move, stop"))
        XCTAssertTrue(DriveVenue.robotIsNotDrivenYet.contains("pair"))

        XCTAssertTrue(DriveVenue.whatTheKitHasTowardIt.contains("DuckPeer"))
        XCTAssertTrue(DriveVenue.whatTheKitHasTowardIt.contains("DuckLineSequence"))
        XCTAssertTrue(DriveVenue.whatTheKitHasTowardIt.contains("nothing conforms to it"))

        XCTAssertTrue(DriveVenue.whatABridgeWouldTake.contains("/run/robotd.sock"))
        XCTAssertTrue(DriveVenue.whatABridgeWouldTake.contains("deadman"))
        XCTAssertTrue(DriveVenue.whatABridgeWouldTake.contains("has not been built"))
    }

    /// A set world with standing steps frames like a challenge scene, close.
    func testASetWorldWithStandingStepsFramesClose() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "world", withExtension: "json",
                                                  subdirectory: "Fixtures/bench"))
        let world = try DuckBench.readWorld(try Data(contentsOf: url))
        XCTAssertTrue(world.isSet)
        XCTAssertEqual(world.steps.count, 4)
        let framing = try XCTUnwrap(world.framing)
        XCTAssertGreaterThan(framing.distance, 0.2)
        XCTAssertLessThan(framing.distance, 2.0)
    }

    /// THE BENCH'S OWN WORLD HAS NO FRAMING. This is the Pi bench's readback
    /// on 2026-09-02, shortened: nobody set a world, and the fourteen blocks
    /// have fallen through each other from far below the floor to above the
    /// duck's head. Framing them put the camera nineteen metres away and the
    /// Control tab went black; the answer is no framing at all.
    func testTheBenchsOwnScatteredBlocksHaveNoFraming() throws {
        let readback = """
        {"world": {"set": false, "name": null},
         "steps": [{"x": 0, "y": 1.305, "top": -11.715, "halfDepth": 0.17, "halfWidth": 0.17, "halfHeight": 0.1},
                   {"x": 0, "y": 1.305, "top": -5.2, "halfDepth": 0.17, "halfWidth": 0.17, "halfHeight": 0.1},
                   {"x": 0, "y": 1.305, "top": 1.618, "halfDepth": 0.17, "halfWidth": 0.17, "halfHeight": 0.1}],
         "ball": {"x": 0.55, "y": 0.1, "z": 0.0499}, "props": [], "unexpressed": []}
        """
        let world = try DuckBench.readWorld(Data(readback.utf8))
        XCTAssertFalse(world.isSet)
        XCTAssertEqual(world.steps.count, 3, "the readback is still drawn whole")
        XCTAssertNil(world.framing)
    }

    /// A set world frames only the steps standing above the floor: a block
    /// the bench parked under it is not a riser.
    func testASetWorldFramesOnlyStepsAboveTheFloor() throws {
        let readback = """
        {"world": {"set": true, "name": "One step"},
         "steps": [{"x": 0.29, "y": 1.305, "top": 0.06, "halfDepth": 0.17, "halfWidth": 0.17, "halfHeight": 0.1},
                   {"x": 1.5, "y": 1.305, "top": -5.0, "halfDepth": 0.17, "halfWidth": 0.17, "halfHeight": 0.1}],
         "ball": null, "props": [], "unexpressed": []}
        """
        let world = try DuckBench.readWorld(Data(readback.utf8))
        let framing = try XCTUnwrap(world.framing)
        XCTAssertLessThan(framing.distance, 2.0)
        XCTAssertLessThan(abs(framing.targetZ), 0.2, "the target is near the floor, not five metres under it")
    }

    /// The gesture words are the kit's, so the AR stage draws no literal.
    func testTheARGestureSentencesAreTheKits() {
        XCTAssertEqual(DriveVenue.pointAtTheFloor, "Point the camera at the floor and tap to put the duck down.")
        XCTAssertEqual(DriveVenue.noFloorThere, "No floor there yet — move the phone and tap again.")
        XCTAssertEqual(DriveVenue.placedSaid, "Placed. Tap the floor again to move it.")
        XCTAssertEqual(DriveVenue.arWhatIsRealTitle, "What is real here")
    }

    /// Footnotes share a line when they share a reason, and a note with
    /// numbers keeps its own.
    func testUnexpressedNotesAreGroupedByReason() {
        let bank = "The bank has fourteen blocks and the flight asked for more."
        let notes = [
            DuckWorld.Unexpressed(what: "step", index: 14, why: bank),
            DuckWorld.Unexpressed(what: "step y", index: 2, asked: "0.020 m", got: "0.000 m",
                                  why: "The wire carries no y."),
            DuckWorld.Unexpressed(what: "step", index: 15, why: bank),
            DuckWorld.Unexpressed(what: "step", index: 16, why: bank),
            DuckWorld.Unexpressed(what: "wall", why: "This world has no walls."),
        ]
        let lines = DuckWorld.groupedSayings(notes)
        XCTAssertEqual(lines, [
            "Step 3 y: asked for 0.020 m, got 0.000 m. The wire carries no y.",
            "Step 15, step 16 and step 17. " + bank,
            "Wall. This world has no walls.",
        ])
        XCTAssertEqual(DuckWorld.groupedSayings([]), [])
        XCTAssertEqual(DuckWorld.groupedSayings([notes[0]]), [notes[0].says])
    }
}
