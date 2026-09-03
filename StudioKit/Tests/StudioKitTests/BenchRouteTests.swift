import XCTest
import DuckKit
@testable import StudioKit

/// THE ROOM THE CHALLENGE IS SCORED IN, BUILT THE WAY THE APP BUILDS IT.
///
/// `DuckScene.stairsChallenge` makes the geometry and a FRESH UUID; the screen
/// that opens a leaderboard row then stamps `challengeSceneID` onto it, which
/// is what makes opening the same row twice attach the same scene. A recogniser
/// has to be tested against the thing the app actually stores, so this helper
/// does both halves exactly as `StairsChallengeView.open(_:)` does.
enum RoomFixture {

    static func scene(rise: Double = 0.060, count: Int = 4,
                      gap: Double = 0, side: Double = 0,
                      spawn: (x: Double, y: Double)? = nil) -> DuckScene {
        var scene = DuckScene.stairsChallenge(rise: rise, count: count,
                                              gap: gap, side: side, spawn: spawn)
        scene.id = DuckScene.challengeSceneID(.stairs,
                                              riseMillimetres: Int((rise * 1000).rounded()),
                                              gap: gap, side: side, spawn: spawn,
                                              stepCount: count)
        return scene
    }

    /// A draft with a real two-keyframe track in it.
    static func draft(named name: String = "lever_up", scene: DuckScene? = nil) -> IntentDraft {
        var draft = IntentDraft.blank(named: name)
        draft.keys[1].pose[DuckModel.jointOfPolicySlot(2)] += 0.2
        draft.sceneID = scene?.id
        return draft
    }
}

/// Which bench route a draft goes down, decided once and not in a view.
final class BenchRouteTests: XCTestCase {

    func testAStairsChallengeDraftGoesToTheHarness() throws {
        let scene = RoomFixture.scene()
        let route = BenchRoute.of(draft: RoomFixture.draft(scene: scene), scene: scene)
        guard case .climb(let rise, let cell, let intent, let room) = route else {
            return XCTFail("a scored room goes to /climb, not \(route)")
        }
        XCTAssertEqual(rise, 0.060, accuracy: 1e-12)
        XCTAssertEqual(cell, StairsChallenge.Grid.nominal)
        XCTAssertEqual(room.stepCount, 4)
        XCTAssertEqual(room.spawn.x, 0.05, accuracy: 1e-9)
        XCTAssertEqual(room.spawn.y, 1.305, accuracy: 1e-9)
        // It is a harness intent, and it is this app's own.
        let move = try StairsChallenge.Move.decode(intent)
        XCTAssertEqual(move.json["authoredIn"]?.stringValue, "Microduck Studio")
        XCTAssertEqual(route.footnote, StairsChallenge.scoredWhereItIsScored)
    }

    /// PLAYABLE, NOT SCORABLE — and the button still does something.
    func testAnEditedChallengeRoomIsPlayableAndNotScorable() throws {
        var scene = RoomFixture.scene()
        scene.steps[2].x += 0.030
        let route = BenchRoute.of(draft: RoomFixture.draft(scene: scene), scene: scene)
        guard case .perform(let standing, let because) = route else {
            return XCTFail("an edited room is still played, got \(route)")
        }
        XCTAssertEqual(because, StairsChallenge.roomWasEdited)
        XCTAssertNotNil(standing?.spawn, "the duck still has to move to the bank")
    }

    func testAMoveOutsideTheDeclaredBoxIsAnExplicitNotYet() {
        let scene = RoomFixture.scene()
        let route = BenchRoute.of(draft: RoomFixture.draft(scene: scene), scene: scene,
                                  blend: 0.5)
        guard case .notYet(let blocked) = route else {
            return XCTFail("a blend under the box cannot be scored, got \(route)")
        }
        XCTAssertEqual(blocked, .blendOutsideTheScoredBox(0.5))
        XCTAssertTrue(blocked.message.contains("0.70"), blocked.message)
        XCTAssertFalse(blocked.message.contains("clamp"),
                       "a scored-room box is not the perform route's clamp: \(blocked.message)")
        XCTAssertTrue(blocked.message.contains("unscored"), blocked.message)
    }

    /// A blend above one is a different refusal with a different reason:
    /// `/perform` would CLAMP it and report the number it did not run.
    func testABlendAboveOneOnAPerformRouteIsANotYet() {
        let scene = DuckScene.staircase(count: 3, rise: 0.04)
        let route = BenchRoute.of(draft: RoomFixture.draft(scene: scene), scene: scene,
                                  blend: 1.5)
        guard case .notYet(let blocked) = route else {
            return XCTFail("/perform clamps a blend above one, got \(route)")
        }
        XCTAssertEqual(blocked, .blendOutsideTheBox(1.5))
        XCTAssertTrue(blocked.message.contains("1.5000"), blocked.message)
        XCTAssertTrue(blocked.message.contains("clamp"), blocked.message)
    }

    func testASavedSceneWithABlockGoesToPerformWithAWorldAndASpawn() throws {
        var scene = DuckScene(name: "A step and a block",
                              steps: [.init(x: 0.40, y: 0, top: 0.06)],
                              props: [DuckScene.block(x: 0.45, y: -0.30)])
        scene.id = UUID()
        let route = BenchRoute.of(draft: RoomFixture.draft(scene: scene), scene: scene)
        guard case .perform(let standing, let because) = route else {
            return XCTFail("a drawn scene is performed, got \(route)")
        }
        XCTAssertNil(because)
        let plan = try XCTUnwrap(standing?.plan)
        XCTAssertEqual(plan.steps?.count, 1)
        // THE DUCK MOVED TO THE BANK, so the step is at the bank's row and the
        // block travelled with it.
        XCTAssertEqual(standing?.spawn?.y, 1.305)
        XCTAssertEqual(plan.props.first?.y ?? 0, 1.005, accuracy: 1e-9)
    }

    func testASceneThatDrawsNothingGoesToPerformWithNoWorldAtAll() {
        let route = BenchRoute.of(draft: RoomFixture.draft(), scene: DuckScene.bareFloor())
        guard case .perform(let standing, let because) = route else {
            return XCTFail("nothing drawn is nothing sent, got \(route)")
        }
        XCTAssertNil(standing, "a scene that draws nothing must send no world at all")
        XCTAssertNil(because)
        XCTAssertEqual(route.footnote, Pipeline.eightRolloutsSaid)
    }

    /// A draft with one usable keyframe has no track, and says so rather than
    /// being sent as one.
    func testADraftWithNoTrackIsANotYetRatherThanARequest() {
        var draft = IntentDraft.blank()
        draft.keys = [draft.keys[0]]
        guard case .notYet(let blocked) = BenchRoute.of(draft: draft, scene: nil) else {
            return XCTFail("one keyframe is not a track")
        }
        XCTAssertEqual(blocked, .tooFewKeyframes(1))
    }

    func testEveryBlockedCaseHasItsOwnMessage() {
        let cases: [BenchRoute.Blocked] = [
            .roomWasEdited,
            .blendOutsideTheBox(1.5),
            .blendOutsideTheScoredBox(0.5),
            .sideOutsideTheBox(0.5),
            .planRefused(.tooManySteps(asked: 15, bank: 14), movedToTheBank: true),
            .tooFewKeyframes(1),
        ]
        let said = cases.map(\.message)
        for line in said { XCTAssertFalse(line.isEmpty) }
        XCTAssertEqual(Set(said).count, said.count, "each blocked case says its own thing")
        // A refusal that only exists because the scene moved says so; the same
        // refusal on a scene that was already illegal does not.
        XCTAssertTrue(said[4].hasPrefix("Moving the duck to the step bank"))
        XCTAssertFalse(
            BenchRoute.Blocked.planRefused(.tooManySteps(asked: 15, bank: 14),
                                           movedToTheBank: false)
                .message.contains("Moving the duck"))
    }
}
