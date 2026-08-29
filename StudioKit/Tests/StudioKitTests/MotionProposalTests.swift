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

    // MARK: - what a small model actually emits

    /// The refusal that shipped: the model called the beak "mouthOpen" and
    /// was told the nearest joint was "left hip".
    func testTheBeakIsAJointByAnyOfItsNames() throws {
        for word in ["beak", "mouth", "mouthOpen", "jaw", "Mouth Open"] {
            let draft = try MotionProposal(name: "quack", keys: [
                .init(atSeconds: 0.4, moves: [.init(joint: word, degrees: 30)]),
                .init(atSeconds: 0.9, moves: []),
            ]).resolve()
            XCTAssertEqual(draft.pose(at: 0.4)[DuckModel.mouthIndex], DuckModel.mouthOpen,
                           accuracy: 1e-9, word)
        }
    }

    /// Wire names, hyphens, case, newlines and the travel annotation the
    /// grounding itself teaches all resolve.
    func testWireNamesAndSloppyFormattingResolve() throws {
        for word in ["left_hip", "left-hip", "LEFT HIP", "head nod\n", "neck (-110° to 40°)",
                     "head yaw", "head_pitch", "right hip roll"] {
            XCTAssertNoThrow(try MotionProposal(name: "x", keys: [
                .init(atSeconds: 0.4, moves: [.init(joint: word, degrees: 5)]),
            ]).resolve(), word)
        }
    }

    /// A blank joint is a no-op, not a refusal with a nonsense hint.
    func testABlankJointIsSkipped() throws {
        let draft = try MotionProposal(name: "x", keys: [
            .init(atSeconds: 0.4, moves: [.init(joint: "", degrees: 0),
                                          .init(joint: "neck", degrees: 10)]),
        ]).resolve()
        XCTAssertTrue(draft.isPlayable)
    }

    /// "both knees 20°" bends both knees the same way — mirrored signs, because
    /// the right leg's home is the left's negated.
    func testGroupWordsMirrorAcrossTheBody() throws {
        let draft = try MotionProposal(name: "crouch", keys: [
            .init(atSeconds: 0.5, moves: [.init(joint: "both knees", degrees: 20)]),
        ]).resolve()
        let pose = draft.pose(at: 0.5)
        let l = DuckModel.jointIndex(of: "left_knee")!, r = DuckModel.jointIndex(of: "right_knee")!
        XCTAssertEqual(pose[l] - DuckModel.homePose[l], 20 * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(pose[r] - DuckModel.homePose[r], -20 * .pi / 180, accuracy: 1e-9)
    }

    /// The hint is thresholded: a near miss gets its neighbour, nonsense gets
    /// the list, and "head" alone gets a head word.
    func testHintsAreNearOrAbsent() {
        XCTAssertEqual(MotionProposal.closest(to: "left kne"), "left knee")
        XCTAssertEqual(MotionProposal.closest(to: "knee"), "left knee")
        XCTAssertNil(MotionProposal.closest(to: "propeller"))
        XCTAssertTrue(MotionProposal.closest(to: "head")?.hasPrefix("head") == true)
        XCTAssertThrowsError(try MotionProposal(name: "x", keys: [
            .init(atSeconds: 0.4, moves: [.init(joint: "propeller", degrees: 5)]),
        ]).resolve()) { error in
            let message = (error as! MotionProposal.Unresolvable).message
            XCTAssertTrue(message.contains("The joints are:"), message)
            XCTAssertFalse(message.contains("nearest"), message)
        }
    }

    /// A draft that never opens the beak leaves it at home: no phantom tail,
    /// no mouth caution.
    func testAShutBeakStaysAtHomeAndAddsNoTail() throws {
        let draft = try MotionProposal(name: "nod", keys: [
            .init(atSeconds: 0.5, moves: [.init(joint: "head nod", degrees: 15)]),
            .init(atSeconds: 1.0, moves: []),
        ]).resolve()
        XCTAssertEqual(draft.pose(at: 0.5)[DuckModel.mouthIndex],
                       DuckModel.homePose[DuckModel.mouthIndex], accuracy: 1e-12)
        XCTAssertEqual(draft.keys.count, 3, "start, nod, back — no extra return-home tail")
        XCTAssertFalse(draft.problems.contains { $0.severity == .caution },
                       "\(draft.problems)")
    }

    /// The offered list is what a constrained decoder may emit: every joint
    /// word and every pair word, each of which resolves.
    func testEveryOfferedWordResolves() throws {
        for word in MotionProposal.offeredWords {
            XCTAssertNoThrow(try MotionProposal(name: "x", keys: [
                .init(atSeconds: 0.4, moves: [.init(joint: word, degrees: 5)]),
            ]).resolve(), word)
            XCTAssertTrue(MotionProposal.grounding().contains(word), "\(word) not in the grounding")
        }
    }

    func testOutOfOrderKeysResolveToAPlayableDraft() throws {
        let draft = try MotionProposal(name: "x", keys: [
            .init(atSeconds: 0.8, moves: [.init(joint: "neck", degrees: 20)]),
            .init(atSeconds: 0.0, moves: []),
        ]).resolve()
        XCTAssertTrue(draft.isPlayable, "\(draft.problems)")
        let times = draft.keys.map(\.time)
        XCTAssertEqual(times, times.sorted())
        XCTAssertEqual(Set(times).count, times.count, "no duplicate times")
    }

    func testASmallMouthOpenStillOpensTheBeak() throws {
        let draft = try MotionProposal(name: "x", keys: [
            .init(atSeconds: 0.4, moves: [], mouthOpen: 0.1),
            .init(atSeconds: 0.9, moves: []),
        ]).resolve()
        XCTAssertEqual(draft.pose(at: 0.4)[DuckModel.mouthIndex], 3 * .pi / 180, accuracy: 1e-9)
    }

    func testASinglePoseBecomesAPlayableMoment() throws {
        let draft = try MotionProposal(name: "still", keys: [.init(atSeconds: 0, moves: [])]).resolve()
        XCTAssertTrue(draft.isPlayable, "\(draft.problems)")
        XCTAssertGreaterThanOrEqual(draft.keys.count, 2)
    }

    func testAPressedShutBeakCountsAsHome() throws {
        let draft = try MotionProposal(name: "quack", keys: [
            .init(atSeconds: 0.5, moves: [.init(joint: "beak", degrees: 30)]),
            .init(atSeconds: 1.0, moves: [.init(joint: "beak", degrees: -5)]),
        ]).resolve()
        XCTAssertEqual(draft.keys.count, 3, "start, open, shut — no tail: \(draft.keys.map(\.time))")
    }

    func testTheGroundingStatesTheBeakAndSignConventions() {
        let g = MotionProposal.grounding()
        XCTAssertTrue(g.contains("beak (0° resting to 30° wide open)"))
        XCTAssertTrue(g.contains("duck's own left"))
        XCTAssertFalse(g.contains("beak (-5°"))
    }

    func testALeadingParenthesisIsRefusedNotDropped() {
        XCTAssertThrowsError(try MotionProposal(name: "x", keys: [
            .init(atSeconds: 0.4, moves: [.init(joint: "(left) knee", degrees: 5)]),
        ]).resolve())
    }
}
