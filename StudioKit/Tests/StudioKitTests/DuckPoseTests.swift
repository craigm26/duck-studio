import XCTest
import DuckKit
@testable import StudioKit

/// Saved poses: the file, the library, and the chat using them by name.
final class DuckPoseTests: XCTestCase {

    private func pose(_ name: String, about: String = "",
                      _ offsets: [String: Double], at when: TimeInterval = 0) -> DuckPose {
        var angles = DuckModel.homePose
        for (joint, degrees) in offsets {
            let index = DuckModel.jointIndex(of: joint)!
            angles[index] += degrees * .pi / 180
        }
        return DuckPose(name: name, about: about, angles: angles,
                        madeAt: Date(timeIntervalSince1970: when))
    }

    // MARK: - the file

    func testTheFileRoundTripsAndKeysAnglesByJointName() throws {
        let original = pose("Wing up", about: "for greetings", ["neck_pitch": 20, "left_knee": -30])
        let data = try original.encoded()
        let top = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(top["format"] as? String, "duck-pose/1")
        let angles = try XCTUnwrap(top["angles"] as? [String: Double])
        XCTAssertEqual(Set(angles.keys), Set(DuckModel.jointNames),
                       "a second reader that is not Swift needs names, not positions")
        let back = try DuckPose.decode(data)
        XCTAssertEqual(back.id, original.id)
        XCTAssertEqual(back.name, "Wing up")
        XCTAssertEqual(back.about, "for greetings")
        for (a, b) in zip(back.angles, original.angles) { XCTAssertEqual(a, b, accuracy: 1e-12) }
    }

    func testAJointTheFileLeavesOutStaysStandingAndAnUnknownOneIsRefused() throws {
        let partial = #"{"format":"duck-pose/1","name":"nod","angles":{"head_pitch":0.9}}"#
        let read = try DuckPose.decode(Data(partial.utf8))
        let head = DuckModel.jointIndex(of: "head_pitch")!
        XCTAssertEqual(read.angles[head], 0.9, accuracy: 1e-12)
        XCTAssertEqual(read.angles[0], DuckModel.homePose[0])

        let alien = #"{"format":"duck-pose/1","name":"x","angles":{"tail":0.1}}"#
        XCTAssertThrowsError(try DuckPose.decode(Data(alien.utf8))) {
            XCTAssertEqual($0 as? DuckPose.ReadError, .unknownJoint("tail"))
        }
        let future = #"{"format":"duck-pose/9","name":"x","angles":{}}"#
        XCTAssertThrowsError(try DuckPose.decode(Data(future.utf8))) {
            XCTAssertEqual($0 as? DuckPose.ReadError, .wrongFormat("duck-pose/9"))
        }
    }

    func testAnglesAreClampedIntoTheRobotsTravel() {
        let wild = DuckPose(name: "wild", angles: Array(repeating: 99, count: 15))
        for (index, value) in wild.angles.enumerated() {
            XCTAssertEqual(value, DuckModel.jointRanges[index].upper, accuracy: 1e-12)
        }
        let short = DuckPose(name: "short", angles: [0.1])
        XCTAssertEqual(short.angles.count, DuckModel.jointCount)
        XCTAssertEqual(short.angles[5], DuckModel.homePose[5])
    }

    // MARK: - making poses from poses

    func testMirrorSwapsTheLegsAndTurnsTheHeadTheOtherWay() {
        let lean = pose("lean", ["left_knee": -30, "head_yaw": 40, "neck_pitch": 10])
        let mirror = lean.mirrored()
        let leftKnee = DuckModel.jointIndex(of: "left_knee")!
        let rightKnee = DuckModel.jointIndex(of: "right_knee")!
        let yaw = DuckModel.jointIndex(of: "head_yaw")!
        let neck = DuckModel.jointIndex(of: "neck_pitch")!
        XCTAssertEqual(mirror.angles[rightKnee], -lean.angles[leftKnee], accuracy: 1e-12)
        XCTAssertEqual(mirror.angles[leftKnee], -lean.angles[rightKnee], accuracy: 1e-12)
        XCTAssertEqual(mirror.angles[yaw], -lean.angles[yaw], accuracy: 1e-12)
        XCTAssertEqual(mirror.angles[neck], lean.angles[neck], accuracy: 1e-12)
        XCTAssertEqual(DuckPose(name: "home", angles: DuckModel.homePose).mirrored().angles,
                       DuckPose(name: "home", angles: DuckModel.homePose).angles,
                       "standing is its own mirror image")
    }

    func testBetweenIsLinearAndClampsT() {
        let a = pose("a", [:]), b = pose("b", ["neck_pitch": 30])
        let neck = DuckModel.jointIndex(of: "neck_pitch")!
        let half = DuckPose.between(a, b, t: 0.5)
        XCTAssertEqual(half.angles[neck], DuckModel.homePose[neck] + 15 * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(DuckPose.between(a, b, t: 7).angles, b.angles)
    }

    func testSummaryNamesOnlyWhatMovedInTheChatsWords() {
        XCTAssertEqual(pose("still", [:]).summary, "standing")
        XCTAssertEqual(pose("bow", ["neck_pitch": 20]).summary, "neck +20°")
    }

    // MARK: - the library

    func testNamesMatchLooselyAndStayUnique() {
        let poses = [pose("Wing up", [:]), pose("Pose", [:]), pose("Pose 2", [:])]
        XCTAssertEqual(PoseLibrary.find("wing_UP", in: poses)?.name, "Wing up")
        XCTAssertNil(PoseLibrary.find("", in: poses))
        XCTAssertEqual(PoseLibrary.closest(to: "wing", in: poses), "Wing up")
        XCTAssertEqual(PoseLibrary.uniqueName("pose", in: poses), "pose 3")
        XCTAssertEqual(PoseLibrary.uniqueName("Bow", in: poses), "Bow")
    }

    func testAnEmptyLibraryChangesNothingAboutThePrompt() {
        XCTAssertEqual(PoseLibrary.grounding([]), "")
        XCTAssertEqual(ChatDraft.instructions(for: .motion, poses: []),
                       ChatDraft.instructions(for: .motion))
        XCTAssertFalse(ChatDraft.instructions(for: .motion).contains("\"pose\""),
                       "a model shown a pose field and no poses invents pose names")
    }

    func testTheChatIsToldTheNewestPosesWithTheirDescriptions() {
        let poses = (0..<30).map { pose("p\($0)", ["neck_pitch": 10], at: TimeInterval($0)) }
            + [pose("Wing up", about: "for greetings", ["head_yaw": 30], at: 100)]
        let text = ChatDraft.instructions(for: .motion, poses: poses)
        XCTAssertTrue(text.contains("- Wing up (for greetings): head turn +30°"), text)
        XCTAssertTrue(text.contains("\"pose\""))
        XCTAssertFalse(text.contains("- p0 "), "only the newest \(PoseLibrary.offeredToTheChat) are offered")
    }

    // MARK: - poses into motions

    func testPosesStringIntoAMotionThatStartsAndEndsStanding() throws {
        let poses = [pose("up", ["neck_pitch": -20]), pose("down", ["neck_pitch": 25])]
        let draft = try PoseLibrary.motion(named: "nod twice", steps: [
            .init(pose: "up"), .init(pose: "down", holdSeconds: 0.5), .init(pose: "UP", moveSeconds: 0.05),
        ], from: poses)
        XCTAssertEqual(draft.keys.first?.pose, DuckModel.homePose)
        XCTAssertEqual(draft.keys.last?.pose, DuckModel.homePose)
        XCTAssertEqual(draft.keys.count, 6, "home, up, down, down held, up, home")
        let times = draft.keys.map(\.time)
        XCTAssertEqual(times, times.sorted())
        XCTAssertEqual(times[4] - times[3], 0.2, accuracy: 1e-9, "a jump is lengthened to 0.2 s")
        XCTAssertTrue(draft.isPlayable, "\(draft.problems)")
    }

    func testAnUnknownPoseIsRefusedWithTheNearestName() {
        let poses = [pose("Wing up", [:])]
        XCTAssertThrowsError(try PoseLibrary.motion(named: "x", steps: [.init(pose: "wing")],
                                                    from: poses)) {
            XCTAssertEqual($0 as? PoseLibrary.Refusal, .unknownPose("wing", closest: "Wing up"))
        }
        XCTAssertThrowsError(try PoseLibrary.motion(named: "x", steps: [], from: poses))
    }

    // MARK: - the chat naming poses

    func testAChatKeyNamingAPoseStartsFromItAndMovesAreOffsetsFromIt() throws {
        let wing = pose("Wing up", ["head_yaw": 30, "left_knee": -20])
        let json = #"{"name":"hello","keys":[{"atSeconds":0.8,"pose":"wing up","moves":[{"joint":"neck","degrees":10}]}]}"#
        let proposal = try ChatDraft.motion(fromJSON: json)
        XCTAssertEqual(proposal.keys.first?.pose, "wing up")
        let draft = try proposal.resolve(poses: [wing])
        let at = try XCTUnwrap(draft.keys.first { abs($0.time - 0.8) < 1e-9 })
        let yaw = DuckModel.jointIndex(of: "head_yaw")!
        let neck = DuckModel.jointIndex(of: "neck_pitch")!
        XCTAssertEqual(at.pose[yaw], wing.angles[yaw], accuracy: 1e-9)
        XCTAssertEqual(at.pose[neck], wing.angles[neck] + 10 * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(draft.keys.last?.pose, DuckModel.homePose)
    }

    func testAChatKeyNamingAPoseNobodySavedIsRefusedNotTurnedIntoStanding() {
        let proposal = MotionProposal(name: "x", keys: [.init(atSeconds: 0.5, moves: [], pose: "Wing")])
        XCTAssertThrowsError(try proposal.resolve(poses: [pose("Wing up", [:])])) {
            XCTAssertEqual($0 as? MotionProposal.Unresolvable, .unknownPose("Wing", closest: "Wing up"))
        }
        let blank = MotionProposal.Key(atSeconds: 0.5, moves: [], pose: "  ")
        XCTAssertNil(blank.pose, "a blank pose name is standing, as before poses existed")
    }

    func testTheGateCountsAnUnknownPoseAsAFailedTry() {
        var gate = DraftGate(now: { 0 })
        let proposal = MotionProposal(name: "x", keys: [.init(atSeconds: 0.5, moves: [], pose: "nope")])
        guard case .feedback(let reason) = gate.draft(proposal, poses: []) else {
            return XCTFail("expected feedback")
        }
        XCTAssertTrue(reason.contains("no saved pose called \"nope\""), reason)
    }

    func testAMotionFrameBecomesAPose() throws {
        let poses = [pose("down", ["neck_pitch": 30])]
        let draft = try PoseLibrary.motion(named: "m", steps: [.init(pose: "down", moveSeconds: 1)],
                                           from: poses)
        let frame = try XCTUnwrap(DuckPose.frame(of: draft, at: 0.5, named: "half"))
        let neck = DuckModel.jointIndex(of: "neck_pitch")!
        XCTAssertEqual(frame.angles[neck], DuckModel.homePose[neck] + 15 * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(frame.sourceSentence, "Taken from \"m\" at 0.5 s.")
    }
}

final class PoseWordsTests: XCTestCase {
    func testNoSentenceUsesAnEmDashOrIsBlank() {
        for sentence in PoseLibrary.Words.everySentence + [ControlShelf.keepItAsAPose,
                                                          ControlShelf.keptAsAPose("x")] {
            XCTAssertFalse(sentence.contains("\u{2014}"), sentence)
            XCTAssertFalse(sentence.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
