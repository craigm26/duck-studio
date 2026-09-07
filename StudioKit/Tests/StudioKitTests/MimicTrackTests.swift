import XCTest
import DuckKit
@testable import StudioKit

/// Thirty frames a second becoming ten keyframes a second that the editor
/// will play.
final class MimicTrackTests: XCTestCase {

    private func pose(_ knee: Double) -> [Double] {
        var p = DuckModel.homePose
        p[3] = knee
        return p
    }

    func testTheFirstPoseStartsTheClockAtZero() {
        var track = MimicTrack()
        XCTAssertTrue(track.add(pose(0), at: 100))
        XCTAssertEqual(track.keys.count, 1)
        XCTAssertEqual(track.keys[0].time, 0)
        XCTAssertEqual(track.seconds, 0)
    }

    /// Frames closer than the spacing are dropped; the ones kept land at the
    /// clock's own times, not at a grid.
    func testFramesArriveAtThirtyHertzAndTenAreKept() {
        var track = MimicTrack()
        var kept = 0
        for frame in 0..<30 {
            if track.add(pose(0), at: 100 + Double(frame) / 30) { kept += 1 }
        }
        XCTAssertEqual(kept, 10)
        XCTAssertEqual(track.keyCount, 10)
        XCTAssertEqual(track.keys[1].time, 0.1, accuracy: 1e-9)
        XCTAssertEqual(track.seconds, 0.9, accuracy: 1e-9)
    }

    /// A step in the input arrives smoothed: half of it on the next keyframe.
    func testAStepIsSmoothedByHalf() {
        var track = MimicTrack()
        track.add(pose(0), at: 0)
        track.add(pose(0.2), at: 0.1)
        XCTAssertEqual(track.keys[1].pose[3], 0.1, accuracy: 1e-9)
        track.add(pose(0.2), at: 0.2)
        XCTAssertEqual(track.keys[2].pose[3], 0.15, accuracy: 1e-9)
    }

    /// A jump a model makes when it loses a joint is held under the rate the
    /// editor refuses, so the draft that comes out has no impossible line.
    func testAJumpIsSlewedUnderTheEditorsRateLimit() {
        var track = MimicTrack()
        track.add(pose(0), at: 0)
        track.add(pose(1.5), at: 0.1)
        let draft = track.draft(named: "jump", provenance: "test")!
        XCTAssertFalse(draft.problems.contains { $0.severity == .impossible },
                       draft.problems.map(\.text).joined(separator: " | "))
        XCTAssertLessThan(abs(track.keys[1].pose[3]), MimicTrack.rateCeiling * 0.1 / 1.5 + 1e-9)
    }

    func testItStopsAtTheCapAndSaysSo() {
        var track = MimicTrack()
        var t = 0.0
        while t < 40 { track.add(pose(0), at: t); t += 0.1 }
        XCTAssertTrue(track.isFull)
        XCTAssertEqual(track.seconds, MimicTrack.maxSeconds, accuracy: 1e-9)
        XCTAssertFalse(track.add(pose(0), at: 50))
        XCTAssertTrue(MimicTrack.stoppedAtTheCap.contains("30 seconds"))
        XCTAssertTrue(MimicTrack.stoppedAtTheCap.contains("one batch"))
    }

    func testAWrongWidthOrNaNIsRefused() {
        var track = MimicTrack()
        XCTAssertFalse(track.add([0, 1, 2], at: 0))
        var nan = DuckModel.homePose
        nan[0] = .nan
        XCTAssertFalse(track.add(nan, at: 0))
        XCTAssertTrue(track.isEmpty)
    }

    /// The draft is the keys, named and provenanced; a one-keyframe track is
    /// given a span so the editor has something to play.
    func testTheDraftIsPlayableAndNamesItsSource() {
        var track = MimicTrack()
        XCTAssertNil(track.draft(named: "x", provenance: "y"))
        track.add(pose(0), at: 0)
        let one = track.draft(named: "Mimic 1", provenance: MimicTrack.provenance(.camera))!
        XCTAssertEqual(one.keys.count, 2)
        XCTAssertTrue(one.isPlayable)
        XCTAssertEqual(one.provenance, "Mimicked from the camera")
        track.add(pose(0.1), at: 0.5)
        let two = track.draft(named: "Mimic 1", provenance: MimicTrack.provenance(.youtube))!
        XCTAssertEqual(two.keys.count, 2)
        XCTAssertEqual(two.keys[1].time, 0.5)
        XCTAssertEqual(two.provenance, "Mimicked from a YouTube clip")
        XCTAssertTrue(two.isPlayable)
    }

    func testClearStartsAgain() {
        var track = MimicTrack()
        track.add(pose(0), at: 5)
        track.clear()
        XCTAssertTrue(track.isEmpty)
        track.add(pose(0), at: 9)
        XCTAssertEqual(track.keys[0].time, 0)
    }

    func testNamesAndTheRecordingLine() {
        XCTAssertEqual(MimicTrack.name(.camera, ordinal: 3), "Mimic 3")
        XCTAssertEqual(MimicTrack.name(.video, ordinal: 1), "Video mimic 1")
        XCTAssertEqual(MimicTrack.recordingSaid(seconds: 2.34, keys: 24), "2.3 s · 24 keyframes")
    }
}
