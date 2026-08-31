import XCTest
import DuckKit
@testable import StudioKit

/// The captions over a stage, asserted letter by letter.
///
/// EVERY ONE OF THESE WAS A FALSE STATEMENT ON A SHIPPING SCREEN. Two of them
/// were false about the world the robot was drawn in; one accused a correct
/// motion of a fault the preview had invented. None of them could be caught by
/// a test while they lived in a `Text(...)` in the app target.
final class StageCaptionTests: XCTestCase {

    // MARK: - what is in the place

    func testAnEmptyPlaceIsBareFloor() {
        XCTAssertEqual(StageCaption.contents(stepCount: 0, tallestStepMetres: 0,
                                             wallCount: 0, propCount: 0), [])
        XCTAssertEqual(StageCaption.context(stepCount: 0, tallestStepMetres: 0,
                                            wallCount: 0, propCount: 0),
                       "100 mm grid · bare floor")
    }

    /// The defect this file exists for: a room with three things in it, no
    /// steps and no walls, captioned as empty.
    func testThingsToPickUpAreNotBareFloor() {
        XCTAssertEqual(StageCaption.context(stepCount: 0, tallestStepMetres: 0,
                                            wallCount: 0, propCount: 3),
                       "100 mm grid · 3 things to pick up")
        XCTAssertEqual(StageCaption.context(stepCount: 0, tallestStepMetres: 0,
                                            wallCount: 0, propCount: 1),
                       "100 mm grid · 1 thing to pick up")
    }

    func testStepsWallsAndThingsReadInOrder() {
        XCTAssertEqual(StageCaption.context(stepCount: 4, tallestStepMetres: 0.04,
                                            wallCount: 1, propCount: 2),
                       "100 mm grid · 4 steps to 40 mm · 1 wall · 2 things to pick up")
        XCTAssertEqual(StageCaption.context(stepCount: 1, tallestStepMetres: 0.01,
                                            wallCount: 2, propCount: 0),
                       "100 mm grid · 1 step to 10 mm · 2 walls")
    }

    /// The scene row and the caption over the stage are the same sentence
    /// fragments, because they were hand-copies and both carried the same lie.
    func testTheShippedBroomSceneNoLongerSaysBareFloor() {
        let scene = DuckScene.broomCupboard()
        XCTAssertEqual(scene.props.count, 3)
        XCTAssertTrue(scene.steps.isEmpty)
        XCTAssertTrue(scene.walls.isEmpty)
        XCTAssertEqual(scene.summary, "3 things to pick up")
        XCTAssertEqual(StageCaption.context(stepCount: scene.steps.count,
                                            tallestStepMetres: 0,
                                            wallCount: scene.walls.count,
                                            propCount: scene.props.count),
                       "100 mm grid · 3 things to pick up")
        XCTAssertTrue(DuckScene.starters.contains { $0.name == scene.name },
                      "it ships on every phone, which is why the caption mattered")
    }

    func testAnActuallyBareFloorStillSaysSo() {
        XCTAssertEqual(DuckScene.bareFloor().summary, "Bare floor")
    }

    func testAStaircaseStillReadsAsItDid() {
        let scene = DuckScene.staircase()
        XCTAssertEqual(scene.summary,
                       StageCaption.contents(stepCount: scene.steps.count,
                                             tallestStepMetres: scene.steps.map(\.top).max() ?? 0,
                                             wallCount: scene.walls.count,
                                             propCount: scene.props.count)
                           .joined(separator: " · "))
    }

    // MARK: - a trunk that was never recorded

    func testThePinnedTrunkLineNamesThePin() {
        XCTAssertEqual(StageCaption.pinnedTrunk(heightMetres: DuckStance.standingHeight),
                       "Trunk pinned at 116 mm — a draft carries joints, not where the body went.")
    }

    /// The measured squat: +39.4 mm on the real meshes with the trunk pinned.
    /// The number survives; the accusation does not.
    func testAFloatingReadingUnderAPinnedTrunkIsNotAFault() {
        let text = StageCaption.pinnedGround(clearanceMetres: 0.0394)
        XCTAssertEqual(text, "39 mm above the grid. The trunk is pinned, so this is where the "
                           + "pose puts the feet — not a fault in the motion.")
        XCTAssertFalse(text.contains("floating"),
                       "the word accuses the renderer, and here the renderer did as it was told")
        XCTAssertFalse(text.contains("nothing should be"))
    }

    func testASinkingReadingUnderAPinnedTrunkReadsThePositiveWayRound() {
        XCTAssertEqual(StageCaption.pinnedGround(clearanceMetres: -0.0172),
                       "17 mm below the grid. The trunk is pinned, so this is where the "
                     + "pose puts the feet — not a fault in the motion.")
    }

    /// The home pose, which is where every draft opens: −1.5 mm, measured.
    func testTheHomePoseReadsAsOnTheGrid() {
        XCTAssertEqual(StageCaption.pinnedGround(clearanceMetres: -0.0015),
                       "-2 mm — the feet are on the grid, with the trunk pinned.")
        XCTAssertEqual(StageCaption.pinnedGround(clearanceMetres: 0.004),
                       "+4 mm — the feet are on the grid, with the trunk pinned.")
    }

    // MARK: - a scene that is not there any more

    func testTheDeletedSceneSentenceSaysWhatIsBeingDrawnInstead() {
        XCTAssertTrue(StageCaption.sceneDeleted(.authoredAgainst).contains("has been deleted"))
        XCTAssertTrue(StageCaption.sceneDeleted(.authoredAgainst).contains("bare floor"))
        // EVERY USE SAYS WHAT REPLACED THE SCENE, not just that one is gone. A
        // person who deletes a scene is looking at a different world a moment
        // later and needs to know which one.
        for use in [StageCaption.SceneUse.authoredAgainst, .stoodIn, .playedIn] {
            let s = StageCaption.sceneDeleted(use)
            XCTAssertTrue(s.contains("has been deleted"), s)
            XCTAssertTrue(s.hasSuffix("."), s)
        }
        XCTAssertTrue(StageCaption.sceneDeleted(.stoodIn).contains("standing on a bare floor"))
        // The player does NOT fall back to a bare floor — it falls back to the
        // world the clip was recorded in, and saying "bare floor" there would
        // be a second wrong answer.
        XCTAssertTrue(StageCaption.sceneDeleted(.playedIn).contains("recorded in"))
        XCTAssertFalse(StageCaption.sceneDeleted(.playedIn).contains("bare floor"))
    }
}

/// Where a preview should look after an edit, and why a stepper stops.
final class DraftEditingTests: XCTestCase {

    private func bow() -> IntentDraft {
        var draft = IntentDraft(name: "Bow")
        draft.keys = [
            .init(time: 0.0, pose: DuckModel.homePose),
            .init(time: 0.8, pose: DuckModel.homePose),
            .init(time: 1.6, pose: DuckModel.homePose),
        ]
        return draft
    }

    func testAChangedKeyframeIsTheMomentToLookAt() {
        let before = bow()
        var after = before
        after.keys[1].pose[DuckModel.jointNames.firstIndex(of: "neck_pitch") ?? 0] = 0.5
        XCTAssertEqual(after.firstNewMoment(comparedTo: before), 0.8)
    }

    func testANewKeyframeIsTheMomentToLookAt() {
        let before = bow()
        var after = before
        after.keys.append(.init(time: 1.2, pose: DuckModel.homePose))
        XCTAssertEqual(after.firstNewMoment(comparedTo: before), 1.2)
    }

    /// A keyframe moved later: the destination is where the pose now is. The
    /// moment it left is not a place to look — nothing is there any more.
    func testAMovedKeyframeReportsWhereItLanded() {
        let before = bow()
        var after = before
        after.keys[1].time = 1.2
        XCTAssertEqual(after.firstNewMoment(comparedTo: before), 1.2)
    }

    func testARemovedKeyframeLeavesNowhereNewToLook() {
        let before = bow()
        var after = before
        after.keys.remove(at: 1)
        XCTAssertNil(after.firstNewMoment(comparedTo: before))
    }

    func testARenameLeavesNowhereNewToLook() {
        let before = bow()
        var after = before
        after.name = "A deeper bow"
        XCTAssertNil(after.firstNewMoment(comparedTo: before))
    }

    /// The old rule, spelled out so it cannot come back: the motion's earliest
    /// keyframe is the standing pose, and it is not where the edit landed.
    func testTheEarliestKeyframeIsNotTheAnswer() {
        let before = bow()
        var after = before
        after.keys[2].pose[0] = 0.3
        XCTAssertEqual(after.firstNewMoment(comparedTo: before), 1.6)
        XCTAssertNotEqual(after.firstNewMoment(comparedTo: before),
                          after.keys.map(\.time).min())
    }

    // MARK: - retiming

    func testSteppingOntoANeighbourIsRefusedInWords() {
        let draft = bow()
        let refusal = IntentDraft.retimeRefusal(draft.keys, moving: draft.keys[0].id, to: 0.8)
        XCTAssertEqual(refusal, "There is already a keyframe at 0.80 s. Move that one out of "
                              + "the way first, or step this one the other way.")
    }

    /// The default motion: two keyframes 0.5 s apart, stepped in 0.05 s. This
    /// is the stall anybody meets on their first new motion.
    func testTheBlankDraftsOwnStallIsNamed() {
        let draft = IntentDraft.blank()
        XCTAssertNotNil(IntentDraft.retimeRefusal(draft.keys, moving: draft.keys[0].id, to: 0.5))
    }

    func testAFreeMomentIsNotRefused() {
        let draft = bow()
        XCTAssertNil(IntentDraft.retimeRefusal(draft.keys, moving: draft.keys[0].id, to: 0.4))
    }

    /// A keyframe is never in its own way.
    func testAKeyframeMayStayWhereItIs() {
        let draft = bow()
        XCTAssertNil(IntentDraft.retimeRefusal(draft.keys, moving: draft.keys[1].id, to: 0.8))
    }

    /// The stepper's lower bound is zero, so a step below it is a step onto
    /// whatever sits at zero.
    func testANegativeTimeIsJudgedAtZero() {
        let draft = bow()
        XCTAssertNotNil(IntentDraft.retimeRefusal(draft.keys, moving: draft.keys[1].id, to: -1.0))
    }
}
