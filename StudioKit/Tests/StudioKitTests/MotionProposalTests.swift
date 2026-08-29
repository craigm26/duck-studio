import XCTest
import DuckKit
@testable import StudioKit

/// The words-to-motion resolver, proved before any model speaks.
final class MotionProposalTests: XCTestCase {

    /// The happy path: a bow in plain words becomes a playable, previewable
    /// draft that starts and ends at home.
    func testABowInPlainWordsBecomesAPlayableDraft() throws {
        let proposal = MotionProposal(name: "little bow", keys: [
            .init(atSeconds: 0.7, moves: [
                .init(joint: "neck", degrees: 30),
                .init(joint: "head nod", degrees: 25),
            ]),
            .init(atSeconds: 1.6, moves: []),
        ])
        let draft = try proposal.resolve()
        XCTAssertTrue(draft.isPlayable, "\(draft.problems)")
        XCTAssertEqual(draft.keys.first?.pose, DuckModel.homePose,
                       "it starts from standing even though the words never said so")
        XCTAssertEqual(draft.keys.last?.pose, DuckModel.homePose,
                       "and returns home at the end")
        let neck = DuckModel.jointIndex(of: "neck_pitch")!
        let mid = draft.pose(at: 0.7)
        XCTAssertEqual(mid[neck], DuckModel.homePose[neck] + 30 * .pi / 180,
                       accuracy: 1e-9)
    }

    /// A 200° nod gets the joint's actual limit — the robot's answer to an
    /// impossible request is its travel stop, not a crash and not obedience.
    func testImpossibleAnglesClampToTheRealTravel() throws {
        let proposal = MotionProposal(name: "owl", keys: [
            .init(atSeconds: 0.5, moves: [.init(joint: "head turn", degrees: 400)]),
        ])
        let draft = try proposal.resolve()
        let yaw = DuckModel.jointIndex(of: "head_yaw")!
        let peak = draft.keys.map { $0.pose[yaw] }.max()!
        XCTAssertEqual(peak, DuckModel.jointRanges[yaw].upper, accuracy: 1e-9)
        XCTAssertTrue(draft.isPlayable)
    }

    /// A joint the robot does not have is refused BY NAME with the nearest
    /// real one — the refusal is the lesson.
    func testAWingIsRefusedWithTheNearestRealJoint() {
        let proposal = MotionProposal(name: "flap", keys: [
            .init(atSeconds: 0.5, moves: [.init(joint: "left wing", degrees: 40)]),
        ])
        XCTAssertThrowsError(try proposal.resolve()) { error in
            guard case MotionProposal.Unresolvable.unknownJoint(let word, let closest) = error
            else { return XCTFail("wrong error") }
            XCTAssertEqual(word, "left wing")
            XCTAssertNotNil(closest)
            XCTAssertTrue((error as! MotionProposal.Unresolvable).message
                .contains("not a joint this robot has"))
        }
    }

    /// "head" alone suggests a head word, not an ankle.
    func testTheSuggestionIsActuallyNear() {
        XCTAssertTrue(MotionProposal.closest(to: "head")?.contains("head") == true)
        XCTAssertTrue(MotionProposal.closest(to: "kne")?.contains("knee") == true)
    }

    /// The robot's own names work too — someone who knows them should not be
    /// punished for precision.
    func testTheRobotsOwnJointNamesResolve() throws {
        let proposal = MotionProposal(name: "x", keys: [
            .init(atSeconds: 0.4, moves: [.init(joint: "left_knee", degrees: -10)]),
        ])
        XCTAssertNoThrow(try proposal.resolve())
    }

    /// The mouth channel rides through, and the standard draft machinery
    /// flags it as the thing no policy can do.
    func testTheMouthChannelArrivesWithItsCaution() throws {
        let proposal = MotionProposal(name: "quack", keys: [
            .init(atSeconds: 0.4, moves: [], mouthOpen: 1.0),
            .init(atSeconds: 0.9, moves: [], mouthOpen: 0),
        ])
        let draft = try proposal.resolve()
        XCTAssertEqual(draft.pose(at: 0.4)[DuckModel.mouthIndex],
                       DuckModel.mouthOpen, accuracy: 1e-9)
        XCTAssertTrue(draft.problems.contains { $0.severity == .caution },
                      "driving the mouth carries the no-policy-can caution")
    }

    /// No keyframes is refused before anything else looks at it.
    func testAnEmptyDraftIsRefused() {
        XCTAssertThrowsError(try MotionProposal(name: "x", keys: []).resolve()) {
            XCTAssertEqual($0 as? MotionProposal.Unresolvable, .noKeyframes)
        }
    }

    /// The grounding is generated FROM the vocabulary, so the words the model
    /// is offered and the words that resolve are one list.
    func testTheGroundingNamesEveryVocabularyWordWithItsTravel() {
        let grounding = MotionProposal.grounding()
        for entry in MotionProposal.jointVocabulary {
            XCTAssertTrue(grounding.contains(entry.word),
                          "\(entry.word) missing from the grounding")
        }
        XCTAssertTrue(grounding.contains("finish with everything back at 0"))
        XCTAssertFalse(grounding.contains("head_yaw"),
                       "the model gets plain words, not the wire names")
    }

    /// Resolved drafts survive the whole existing pipeline: export through the
    /// format's single door and back.
    func testAResolvedDraftExportsLikeAnyOther() throws {
        let draft = try MotionProposal(name: "wave hello", keys: [
            .init(atSeconds: 0.5, moves: [.init(joint: "head tilt", degrees: 15)],
                  mouthOpen: 0.5),
            .init(atSeconds: 1.2, moves: []),
        ]).resolve()
        let contents = try DuckMoveFile.decode(try draft.exported())
        XCTAssertEqual(contents.name, "wave hello")
        XCTAssertTrue(contents.provenance?.contains("on-device model") == true)
    }
}
