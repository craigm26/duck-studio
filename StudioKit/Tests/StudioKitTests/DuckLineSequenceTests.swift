import XCTest
@testable import StudioKit

/// A number on the frame, and the two claims it must never make.
///
/// THE MOST IMPORTANT TEST IN THIS FILE IS THE ONE ABOUT PARAMS. A sequence
/// number inside `robot.move`'s params is a fourth key in a block Pollen's
/// contract fixes at three, and what a given `robotd` does with it — refuse the
/// call, ignore the key — is a thing nobody here has tested. So the counter
/// rides beside the bytes, and `testAStampedMoveCarriesExactlyTheThreeVelocities`
/// is what keeps it there.
final class DuckLineSequenceTests: XCTestCase {

    // MARK: - stamping

    func testTheFirstFrameIsOneSoAZeroInALogIsAnUnstampedFrame() {
        var sequence = DuckLineSequence()
        XCTAssertEqual(sequence.last, 0)
        XCTAssertEqual(sequence.stamp(Data("a".utf8)).number, 1)
        XCTAssertEqual(sequence.stamp(Data("b".utf8)).number, 2)
        XCTAssertEqual(sequence.stamp(Data("c".utf8)).number, 3)
        XCTAssertEqual(sequence.last, 3)
    }

    /// The bytes handed to a transport are the bytes `DuckCall.line(id:)`
    /// produced, terminator included, untouched.
    func testStampingChangesNoBytes() throws {
        var sequence = DuckLineSequence()
        let line = try DuckCall.move(DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0)).line(id: nil)
        let stamped = sequence.stamp(line)
        XCTAssertEqual(stamped.line, line)
        XCTAssertEqual(stamped.line.last, 0x0A)
    }

    /// THE WHOLE POINT OF PUTTING IT ON THE FRAME. `robot.move`'s params are
    /// `{vx, vy, vyaw}` and stay that way: the number appears nowhere in the
    /// line, under any spelling somebody might reach for.
    func testAStampedMoveCarriesExactlyTheThreeVelocities() throws {
        var sequence = DuckLineSequence()
        let call = DuckCall.move(DuckDrive.Twist(vx: 0.3, vy: -0.1, vyaw: 1.5))
        let stamped = sequence.stamp(try call.line(id: nil))
        let top = try XCTUnwrap(
            JSONSerialization.jsonObject(with: stamped.line) as? [String: Any])
        let params = try XCTUnwrap(top["params"] as? [String: Any])
        XCTAssertEqual(Set(params.keys), ["vx", "vy", "vyaw"])
        XCTAssertEqual(Set(top.keys), ["jsonrpc", "method", "params"])
        let text = String(decoding: stamped.line, as: UTF8.self)
        for spelling in ["seq", "sequence", "frame", "counter", "n\":"] {
            XCTAssertFalse(text.contains(spelling), "\(spelling) leaked into the line: \(text)")
        }
    }

    // MARK: - reading them back

    func testAWatcherCountsWhatNeverArrived() {
        var watcher = DuckLineSequence.Watcher()
        XCTAssertEqual(watcher.saw(1), .first)
        XCTAssertEqual(watcher.saw(2), .next)
        XCTAssertEqual(watcher.saw(5), .missed(2))
        XCTAssertEqual(watcher.missed, 2)
        XCTAssertEqual(watcher.seen, 3)
        XCTAssertEqual(watcher.highest, 5)
    }

    /// A number already gone past is kept apart from a gap, because the two
    /// have different causes and collapsing them produces a summary nobody can
    /// act on.
    func testANumberAlreadyPassedIsBehindRatherThanMissed() {
        var watcher = DuckLineSequence.Watcher()
        watcher.saw(7)
        XCTAssertEqual(watcher.saw(7), .behind)
        XCTAssertEqual(watcher.saw(3), .behind)
        XCTAssertEqual(watcher.behind, 2)
        XCTAssertEqual(watcher.missed, 0)
    }

    /// THE SENTENCE REFUSES TO CALL A CLEAN RUN PROOF. Nothing missing between
    /// the first frame seen and the last says nothing about what happened before
    /// the counting started, and a sentence reading "no frames were lost" would
    /// be a claim about a period nobody was counting.
    func testACleanRunDoesNotClaimNothingWasEverLost() {
        var watcher = DuckLineSequence.Watcher()
        for n in UInt64(1)...UInt64(4) { watcher.saw(n) }
        let said = watcher.says
        XCTAssertTrue(said.contains("4 frames counted"), said)
        XCTAssertTrue(said.contains("says nothing about anything sent before"), said)
        XCTAssertFalse(said.lowercased().contains("no frames were lost"), said)
    }

    func testAWatcherWithNothingSeenSaysSoRatherThanReportingZeroLoss() {
        XCTAssertTrue(DuckLineSequence.Watcher().says.contains("nothing is known"),
                      DuckLineSequence.Watcher().says)
    }

    func testAGapIsReportedWithTheVerdictAboutOrdering() {
        var watcher = DuckLineSequence.Watcher()
        watcher.saw(1)
        watcher.saw(4)
        XCTAssertTrue(watcher.says.contains("2 never arrived"), watcher.says)
        XCTAssertTrue(watcher.says.contains(DuckLineSequence.measuresLossNotReordering),
                      watcher.says)
    }

    // MARK: - the two sentences

    /// THE VERDICT NAMES BOTH CHANNELS. A gap means loss on an ordered channel
    /// and means nothing dependable on an unordered one, and this type has no
    /// reordering window — so pointing it at an unordered channel produces a
    /// loss count made of frames that arrived a moment later.
    func testTheVerdictSaysWhatAGapProvesAndOnWhichKindOfChannel() {
        let said = DuckLineSequence.measuresLossNotReordering
        XCTAssertTrue(said.contains("in order"), said)
        XCTAssertTrue(said.contains("does not guarantee order"), said)
        XCTAssertTrue(said.contains("measures loss"), said)
        XCTAssertTrue(said.contains("no window"), said)
    }

    /// A counter looks like a guarantee and is not one. Nothing retransmits,
    /// and the thing that actually stops an undriven duck is the robot's own
    /// age-based deadman.
    func testTheCounterSaysOutLoudThatItStopsNothing() {
        let said = DuckLineSequence.thisCounterStopsNothing
        XCTAssertTrue(said.contains("Nothing is retransmitted"), said)
        XCTAssertTrue(said.contains("deadman"), said)
        XCTAssertTrue(said.contains("expires"), said)
    }
}
