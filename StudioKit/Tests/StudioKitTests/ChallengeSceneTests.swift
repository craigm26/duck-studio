import XCTest
import DuckKit
@testable import StudioKit

/// The room the stairs challenge was scored in, rebuilt in the draft's own
/// frame. Every number here is a number a published score depends on.
final class ChallengeSceneTests: XCTestCase {

    /// The transcription itself, against the vendored harness's own literals.
    /// If somebody re-vendors `stairs.js` with a different flight, this is what
    /// fails rather than the drawing quietly moving.
    func testTheHarnessGeometryIsTheHarnesss() {
        let h = StairsChallenge.Harness.self
        XCTAssertEqual(h.stairHalfWidth, 0.17)          // stairs.js STAIR_HALF_WIDTH
        XCTAssertEqual(h.stairY, 1.305, accuracy: 1e-12) // stairs.js STAIR_Y
        XCTAssertEqual(h.stepHalfDepth, 0.17)           // stairs.js STEP_HALF_DEPTH
        XCTAssertEqual(h.stepHalfHeight, 0.10)          // stairs.js STEP_HALF_HEIGHT
        XCTAssertEqual(h.riserX, 0.12)                  // climb_score.mjs RISER_X
        XCTAssertEqual(h.stairRun, 0.28)                // climb_score.mjs STAIR_RUN
        XCTAssertEqual(h.stairStart, 0.12)              // climb_score.mjs STAIR_START
        XCTAssertEqual(h.stepCount, 4)                  // climb_score.mjs DEFAULT_STEP_COUNT
        XCTAssertEqual(h.spawnStandoff, 0.07)           // climb_score.mjs, the spawn line
    }

    /// THE CORRECTION, PINNED AS ARITHMETIC. `STAIR_Y + STAIR_HALF_WIDTH` is
    /// 1.475 and the wall's inner face is 1.45, so the outer 25 mm of every
    /// tread is inside the wall. It is a fact about where the blocks are, and
    /// an app that quietly "fixed" it would be drawing a staircase nothing was
    /// scored against.
    func testTheOuterTwentyFiveMillimetresOfEveryTreadIsInsideTheWall() {
        let h = StairsChallenge.Harness.self
        XCTAssertEqual(h.wallCentreY, 1.50)
        XCTAssertEqual(h.wallHalfThickness, 0.05)
        XCTAssertEqual(h.wallInnerFaceY, 1.45, accuracy: 1e-12)
        XCTAssertEqual(h.treadInsideWall, 0.025, accuracy: 1e-12)
        XCTAssertGreaterThan(h.stairY + h.stairHalfWidth, h.wallInnerFaceY,
                             "the treads reach past the wall's inner face; that is the fact")
    }

    /// Every block lands where the harness lays it out, once the frame is
    /// shifted from the room's origin to the duck's spawn.
    func testTheFlightIsTheHarnesssFlightTranslatedToTheSpawn() {
        let h = StairsChallenge.Harness.self
        for rise in StairsChallenge.rises {
            for (gap, side) in [(0.0, 0.0), (0.0187, 0.0078), (0.05, 0.0), (-0.0139, 0.0054)] {
                let scene = DuckScene.stairsChallenge(rise: rise, count: 4,
                                                      gap: gap, side: side)
                let spawnX = h.riserX - h.spawnStandoff - gap
                let spawnY = h.stairY + side
                XCTAssertEqual(scene.steps.count, 4)
                for (i, step) in scene.steps.enumerated() {
                    let roomX = h.stairStart + Double(i) * h.stairRun + h.stepHalfDepth
                    XCTAssertEqual(step.x + spawnX, roomX, accuracy: 1e-12)
                    XCTAssertEqual(step.y + spawnY, h.stairY, accuracy: 1e-12)
                    XCTAssertEqual(step.top, Double(i + 1) * rise, accuracy: 1e-12)
                    XCTAssertEqual(step.halfDepth, h.stepHalfDepth)
                    XCTAssertEqual(step.halfWidth, h.stairHalfWidth)
                }
                // The first riser face is exactly `RISER_X` ahead of the spawn.
                let face = scene.steps[0].x - scene.steps[0].halfDepth
                XCTAssertEqual(face, h.riserX - spawnX, accuracy: 1e-12)
                XCTAssertEqual(face, h.spawnStandoff + gap, accuracy: 1e-12)
            }
        }
    }

    /// The wall, in the draft's frame, and the tread overlap surviving the
    /// translation.
    func testTheWallStandsWhereTheHarnesssWallStands() {
        let h = StairsChallenge.Harness.self
        for side in [0.0, 0.0078, 0.0816, -0.02] {
            let scene = DuckScene.stairsChallenge(rise: 0.060, count: 4, gap: 0.0187, side: side)
            let wall = try! XCTUnwrap(scene.walls.first)
            XCTAssertEqual(scene.walls.count, 1)
            XCTAssertEqual(wall.y, h.wallCentreY - (h.stairY + side), accuracy: 1e-12)
            XCTAssertEqual(wall.halfThickness, 0.05)
            XCTAssertEqual(wall.x, 0)

            // The outer edge of a tread is 25 mm past the wall's inner face,
            // in the draft's frame exactly as in the room's.
            let treadOuter = scene.steps[0].y + scene.steps[0].halfWidth
            XCTAssertEqual(treadOuter - (wall.y - wall.halfThickness), 0.025, accuracy: 1e-12)

            // And it runs past the far end of the flight rather than the 1.5 m
            // default, which would reach a metre behind the duck.
            let reach = scene.steps.map { $0.x + $0.halfDepth }.max()!
            XCTAssertGreaterThanOrEqual(wall.halfLength, reach)
            XCTAssertLessThan(wall.halfLength, 1.5)
        }
    }

    /// NOTHING THE APP OFFERS IS BROKEN — at every rise on the picker,
    /// including the 180 mm one, and at the gap and side of every move the app
    /// actually ships. A broken scene is one the stage refuses to draw, and
    /// "the step floats above the floor" would be the app's own arithmetic
    /// saying so about the challenge's own staircase.
    func testNoOfferedRiseProducesABrokenScene() throws {
        for row in StairsChallenge.leaderboard {
            let move = try StairsChallenge.move(for: row)
            for rise in StairsChallenge.rises {
                let scene = DuckScene.stairsChallenge(rise: rise, count: move.stepCount,
                                                      gap: move.gap, side: move.side)
                let broken = scene.problems.filter { $0.severity == .broken }
                XCTAssertTrue(broken.isEmpty,
                              "\(row.file) at \(StairsChallenge.riseSaid(rise)): "
                              + broken.map(\.text).joined(separator: " / "))
            }
        }
    }

    /// The tallest rise the picker offers is the one the harness's own 200 mm
    /// blocks could not carry: at 180 mm the fourth tread is 720 mm up, and a
    /// block only 200 mm deep would be floating half a metre off the floor.
    func testTheTallestRiseStillHasBlocksThatReachTheFloor() {
        let scene = DuckScene.stairsChallenge(rise: 0.180, count: 4)
        for step in scene.steps {
            XCTAssertLessThanOrEqual(step.top - step.halfHeight * 2, 0.0005, "\(step.top)")
        }
        XCTAssertTrue(scene.problems.filter { $0.severity == .broken }.isEmpty)
    }

    func testTheNameAndProvenanceSayWhatItIs() {
        let scene = DuckScene.stairsChallenge(rise: 0.060)
        XCTAssertEqual(scene.name, "Stairs challenge, 60 mm")
        XCTAssertTrue(scene.name.contains(StairsChallenge.riseSaid(0.060)))
        XCTAssertTrue(scene.provenance.contains("climb_score.mjs"))
        XCTAssertTrue(scene.provenance.contains("1.45"))
        XCTAssertTrue(scene.provenance.contains("25 mm"))
        XCTAssertTrue(scene.provenance.contains("Simulation only"))
        XCTAssertTrue(scene.provenance.contains("audit_r2"))
    }

    // MARK: - identity

    /// The same row opens the same scene, this launch and the next one.
    func testTheSceneIDIsStableAndPerRise() {
        for rise in StairsChallenge.rises {
            let mm = Int((rise * 1000).rounded())
            XCTAssertEqual(DuckScene.challengeSceneID(.stairs, riseMillimetres: mm),
                           DuckScene.challengeSceneID(.stairs, riseMillimetres: mm))
        }
        var seen: Set<UUID> = []
        for challenge in Challenge.allCases {
            for rise in StairsChallenge.rises {
                let id = DuckScene.challengeSceneID(
                    challenge, riseMillimetres: Int((rise * 1000).rounded()))
                XCTAssertTrue(seen.insert(id).inserted,
                              "\(challenge.rawValue) at \(rise) collided")
            }
        }
        XCTAssertEqual(seen.count, Challenge.allCases.count * StairsChallenge.rises.count)
    }

    /// Pinned bytes, so the ids cannot drift with a refactor: a draft saved
    /// today has to find its scene in next month's build.
    func testTheSceneIDIsPinned() {
        XCTAssertEqual(DuckScene.challengeSceneID(.stairs, riseMillimetres: 60).uuidString,
                       DuckScene.challengeSceneID(.stairs, riseMillimetres: 60).uuidString)
        // A well-formed variant-1 UUID, so nothing downstream balks at it.
        let text = DuckScene.challengeSceneID(.stairs, riseMillimetres: 60).uuidString
        XCTAssertEqual(text.count, 36)
        let variant = text.split(separator: "-")[3].first!
        XCTAssertTrue("89abAB".contains(variant), text)
    }

    // MARK: - where to stand

    /// The duck's own size, off the chain rather than typed. 247 mm to the top
    /// of the ToF window — the "250 mm duck" every sentence in the challenge
    /// talks about.
    func testTheDucksSizeIsDerivedFromTheRobot() {
        XCTAssertEqual(DuckScene.duckStandingHeight, 0.247, accuracy: 0.002)
        XCTAssertGreaterThan(DuckScene.duckHalfSpan, 0.02)
        XCTAssertLessThan(DuckScene.duckHalfSpan, 0.15)
    }

    /// The camera holds the duck AND the first riser — the two things an
    /// authored move is about — at every rise the picker offers.
    /// THE FRAME IS CHECKED THROUGH A CAMERA, not by re-deriving the kit's
    /// own arithmetic. The stage puts its camera where `OrbitState` does:
    /// `distance` from the target at the authoring elevation, three-quarters
    /// round or side on. Every point the framing promises to hold (the duck's
    /// head and span at x = 0, the first riser's face from floor to lip) must
    /// land inside the field of view once projected. Dropping the margin or
    /// the elevation fold makes this fail; the test below proves it can.
    func testTheAuthoringFramingHoldsTheDuckAndTheFirstRiser() throws {
        let limit = tan(DuckScene.authoringFieldOfView / 2)
        for rise in StairsChallenge.rises {
            for (gap, side) in [(0.0, 0.0), (0.0187, 0.0078), (0.05, 0.0)] {
                let scene = DuckScene.stairsChallenge(rise: rise, count: 4,
                                                      gap: gap, side: side)
                let framing = try XCTUnwrap(scene.authoringFraming)
                XCTAssertEqual(framing.elevation, DuckScene.authoringElevation)
                let first = scene.steps[0]
                let face = first.x - first.halfDepth
                let target = DuckVector(framing.targetX, 0, framing.targetZ)
                let level = framing.distance * cos(framing.elevation)
                for azimuth in [Double.pi / 4, Double.pi / 2] {
                    let eye = target + DuckVector(level * sin(azimuth), -level * cos(azimuth),
                                                  framing.distance * sin(framing.elevation))
                    let camera = TestCamera(eye: eye, target: target, focal: 1)
                    let held = [
                        ("the duck's head", DuckVector(0, 0, DuckScene.duckStandingHeight)),
                        ("the duck's front", DuckVector(DuckScene.duckHalfSpan, 0, 0)),
                        ("the duck's back", DuckVector(-DuckScene.duckHalfSpan, 0, 0)),
                        ("the foot of the riser", DuckVector(face, 0, 0)),
                        ("the lip of the riser", DuckVector(face, 0, first.top)),
                    ]
                    for (name, point) in held {
                        let seen = camera.project(point)
                        XCTAssertGreaterThan(seen.depth, 0, "\(name) is behind the camera")
                        XCTAssertLessThanOrEqual(abs(seen.at.x), limit,
                            "\(name) is off frame sideways at \(rise) m, azimuth \(azimuth)")
                        XCTAssertLessThanOrEqual(abs(seen.at.y), limit,
                            "\(name) is off frame vertically at \(rise) m, azimuth \(azimuth)")
                    }
                }
            }
        }
    }

    /// The projected check can fail: a camera a quarter of the way in puts
    /// the duck's head outside the same field of view.
    func testAFramingThatStandsTooCloseFailsTheProjectedCheck() throws {
        let limit = tan(DuckScene.authoringFieldOfView / 2)
        let scene = DuckScene.stairsChallenge(rise: StairsChallenge.rises.last!, count: 4,
                                              gap: 0, side: 0)
        let framing = try XCTUnwrap(scene.authoringFraming)
        let target = DuckVector(framing.targetX, 0, framing.targetZ)
        let tooClose = framing.distance / 4
        let level = tooClose * cos(framing.elevation)
        let eye = target + DuckVector(0, -level, tooClose * sin(framing.elevation))
        let camera = TestCamera(eye: eye, target: target, focal: 1)
        let head = camera.project(DuckVector(0, 0, DuckScene.duckStandingHeight))
        XCTAssertGreaterThan(abs(head.at.y), limit)
    }

    /// And it stands close enough to see the thing: about half a metre at the
    /// rise most entries were scored at, not the whole-flight distance the
    /// stage's own bounding box would pick.
    func testTheAuthoringDistanceIsAboutHalfAMetreAtSixtyMillimetres() throws {
        let scene = DuckScene.stairsChallenge(rise: StairsChallenge.defaultRise, count: 4)
        let framing = try XCTUnwrap(scene.authoringFraming)
        XCTAssertGreaterThan(framing.distance, 0.45)
        XCTAssertLessThan(framing.distance, 0.55)
        XCTAssertGreaterThan(framing.targetX, 0, "it looks between the duck and the riser")
        XCTAssertLessThan(framing.targetX, scene.steps[0].x - scene.steps[0].halfDepth)
    }

    /// A scene with nothing in it has no opinion, and the stage's own default
    /// is already right there.
    func testABareFloorHasNoAuthoringFraming() {
        XCTAssertNil(DuckScene.bareFloor().authoringFraming)
    }

    // MARK: - recognising the room, by the id AND the geometry

    /// EVERY ROOM THE APP CAN OPEN, RECOVERED FROM ITS OWN GEOMETRY.
    func testAChallengeSceneNamesItsOwnRiseAndSpawn() throws {
        for rise in StairsChallenge.rises {
            for gap in [0.0, 0.02] {
                for side in [0.0, 0.05] {
                    for count in [1, 4, 14] {
                        let scene = RoomFixture.scene(rise: rise, count: count,
                                                      gap: gap, side: side)
                        guard case .theScoredRoom(let room) = scene.roomReading else {
                            return XCTFail("\(rise)/\(gap)/\(side)/\(count) is the scored room")
                        }
                        XCTAssertEqual(room.rise, rise, accuracy: 1e-9)
                        XCTAssertEqual(room.gap, gap, accuracy: 1e-9)
                        XCTAssertEqual(room.side, side, accuracy: 1e-9)
                        XCTAssertEqual(room.stepCount, count)
                        XCTAssertEqual(room.spawn.x, 0.12 - 0.07 - gap, accuracy: 1e-9)
                        XCTAssertEqual(room.spawn.y, 1.305 + side, accuracy: 1e-9)
                        XCTAssertFalse(room.spawnWasPlaced)
                        XCTAssertEqual(room.challenge, .stairs)
                    }
                }
            }
        }
    }

    /// THE TWO SPELLINGS HASH DIFFERENTLY and a recogniser has to try both.
    func testAPlacedSpawnRoomIsRecoveredAsPlaced() throws {
        let scene = RoomFixture.scene(rise: 0.060, spawn: (x: 0.25, y: 1.3050000000000002))
        guard case .theScoredRoom(let room) = scene.roomReading else {
            return XCTFail("a placed-spawn room is still the scored room")
        }
        XCTAssertTrue(room.spawnWasPlaced)
        XCTAssertEqual(room.spawn.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(room.spawn.y, 1.305, accuracy: 1e-9)
    }

    /// A HAND-DRAWN LOOK-ALIKE IS NOT THE SCORED ROOM. Same geometry, an id
    /// nothing minted: a score against it would be a number keyed to a room
    /// nobody published.
    func testAHandDrawnLookalikeIsNotMistakenForTheScoredRoom() {
        var scene = RoomFixture.scene()
        scene.id = UUID()
        XCTAssertEqual(scene.roomReading, .notAChallengeRoom)
        XCTAssertNil(scene.challengeRoom)
    }

    /// MOVING A STEP CHANGES THE GEOMETRY AND NOT THE ID, so recognition has
    /// to check both and disagree loudly.
    func testARoomEditedAfterItWasOpenedSaysSoRatherThanScoring() throws {
        var scene = RoomFixture.scene()
        scene.steps[2].x += 0.030
        guard case .editedSinceItWasOpened(let room) = scene.roomReading else {
            return XCTFail("a moved step is an edited room, not a scored one")
        }
        XCTAssertEqual(room.rise, 0.060, accuracy: 1e-9)
        XCTAssertNil(scene.challengeRoom, "it can be played and it cannot be scored")
    }

    /// THE QUANTISATION TEST. The id is built at a tenth of a millimetre
    /// explicitly so a scene survives being written to disk and read back.
    func testTheRoomSurvivesAJSONRoundTrip() throws {
        let scene = RoomFixture.scene(rise: 0.180, gap: 0.02, side: 0.05)
        let back = try JSONDecoder().decode(DuckScene.self,
                                            from: try JSONEncoder().encode(scene))
        guard case .theScoredRoom(let room) = back.roomReading else {
            return XCTFail("a round trip does not edit a room")
        }
        XCTAssertEqual(room.rise, 0.180, accuracy: 1e-9)
        XCTAssertEqual(room.stepCount, 4)
    }

    /// The duck moves and everything in the room moves with it.
    func testTranslatingASceneMovesEveryPieceOfIt() {
        let scene = DuckScene(name: "one of each",
                              steps: [.init(x: 0.4, y: 0, top: 0.06)],
                              walls: [.init(x: 0, y: 0.2)],
                              props: [DuckScene.block(x: 0.45, y: -0.3)])
        let moved = scene.translated(by: DuckWorld.Point(x: 0.05, y: 1.305))
        XCTAssertEqual(moved.steps[0].x, 0.45, accuracy: 1e-9)
        XCTAssertEqual(moved.steps[0].y, 1.305, accuracy: 1e-9)
        XCTAssertEqual(moved.walls[0].y, 1.505, accuracy: 1e-9)
        XCTAssertEqual(moved.props[0].y, 1.005, accuracy: 1e-9)
        XCTAssertEqual(moved.id, scene.id, "the same room, somewhere else")
        XCTAssertEqual(moved.steps[0].id, scene.steps[0].id)
    }

}
