import XCTest
@testable import StudioKit

/// Walk to the ball as a Tell skill, and on a real duck: what it hears, what it refuses, how a run
/// ends and how a real picture is cut.
final class BallWalkTests: XCTestCase {

    // MARK: - Tell's words

    func testTheSentencesThatAskForIt() {
        for said in ["walk to the ball", "Walk to the ball, please", "go to the ball", "go get the ball",
                     "find the ball", "duck, walk to the ball", "please go walk to the ball now"] {
            XCTAssertTrue(BallWalk.heard(said), said)
        }
    }

    /// A stop word in the sentence is a stop, and nothing else may read as an order to go.
    func testSentencesThatDoNotAskForIt() {
        for said in ["no, walk to the ball", "stop walking to the ball", "stop", "walk forward", "ball", "kick the ball",
                     "walk to the red mat", "don't walk to the ball", "do not walk to the ball", "halt, go to the ball", ""] {
            XCTAssertFalse(BallWalk.heard(said), said)
        }
    }

    /// The matcher did not change: Ask the duck and Siri mean what they meant.
    func testTheMatcherStillDoesNotReadTheWalk() {
        XCTAssertNil(DuckOrderMatcher.match("walk to the ball"))
        XCTAssertEqual(DuckOrderMatcher.match("no, walk to the ball"), .stop)
    }

    // MARK: - readiness

    func testADuckThatCannotWalkYetIsToldWhatToDo() {
        XCTAssertEqual(BallWalk.notReady(.init(sitting: true)), BallWalk.Words.sitting)
        XCTAssertEqual(BallWalk.notReady(.init(sitting: false, homed: false)), BallWalk.Words.homing)
        XCTAssertNil(BallWalk.notReady(.init(sitting: false, homed: true)))
    }

    /// A duck that said nothing is stood up as Tell stands it, not refused.
    func testSilenceIsNotARefusalAndGetsTellsStandUp() throws {
        XCTAssertNil(BallWalk.notReady(.unknown))
        XCTAssertEqual(try DuckOrder.stand.calls(.unknown), [.initPose, .enable])
        XCTAssertEqual(try DuckOrder.stand.calls(.init(sitting: false, homed: true)), [.initPose, .enable])
    }

    func testTheFirstRunAsksAndANewDriverAsksAgain() {
        XCTAssertTrue(BallWalk.needsConfirming(confirmed: ""))
        XCTAssertTrue(BallWalk.needsConfirming(confirmed: "duck-driver-walk-to-ball-v5-fe94d4a"))
        XCTAssertFalse(BallWalk.needsConfirming(confirmed: DriverRelease.walkToBall.folder))
    }

    /// What the owner asked the first-run sheet to say, and what gates can read.
    func testTheFirstRunWordsSayWhatItIs() {
        let line = BallWalk.Words.confirmLine(30)
        for must in ["drawn practice stage", "wander", "miss the ball", "floor", "edges", "Stop"] {
            XCTAssertTrue(line.contains(must), must)
        }
        XCTAssertTrue(DriverCard.Words.all(.walkToBall).contains(line))
    }

    // MARK: - the ending

    private let walking = DuckDrive.Twist(vx: 0.25, vy: 0, vyaw: 0.4)

    func testTwoSecondsOfStillRowsEndARun() {
        var watch = BallWalk.Watch()
        XCTAssertEqual(BallWalk.Watch.standRows, 20)
        for _ in 0..<19 { XCTAssertNil(watch.see(row: .still, pictureAge: 0.1)) }
        XCTAssertEqual(watch.see(row: .still, pictureAge: 0.1), BallWalk.Words.stoppedItself)
    }

    func testAnyMovingRowStartsTheCountAgain() {
        var watch = BallWalk.Watch()
        for _ in 0..<19 { XCTAssertNil(watch.see(row: .still, pictureAge: 0.1)) }
        XCTAssertNil(watch.see(row: walking, pictureAge: 0.1))
        for _ in 0..<19 { XCTAssertNil(watch.see(row: .still, pictureAge: 0.1)) }
        XCTAssertNotNil(watch.see(row: .still, pictureAge: 0.1))
    }

    /// An ask between chunks is not a still row: it takes no time on the duck.
    func testAnAskDoesNotCountAsStanding() {
        var watch = BallWalk.Watch()
        for _ in 0..<100 { XCTAssertNil(watch.see(row: nil, pictureAge: 0.1)) }
        for _ in 0..<19 { XCTAssertNil(watch.see(row: .still, pictureAge: 0.1)) }
    }

    func testAnOldPictureOrNoneEndsARunAtAnyLook() {
        var watch = BallWalk.Watch()
        XCTAssertNil(watch.see(row: walking, pictureAge: BallWalk.Watch.stalePicture))
        XCTAssertEqual(watch.see(row: walking, pictureAge: BallWalk.Watch.stalePicture + 0.01), BallWalk.Words.cameraLost)
        XCTAssertEqual(watch.see(row: nil, pictureAge: 5), BallWalk.Words.cameraLost)
        XCTAssertEqual(watch.see(row: .still, pictureAge: nil), BallWalk.Words.cameraLost)
    }

    /// The window knows when the camera last delivered, and an empty window has no such time.
    func testTheWindowSaysWhenTheCameraLastDelivered() {
        var window = DreamFrameWindow()
        XCTAssertNil(window.lastTick)
        window.add("a", at: 10)
        window.add("b", at: 10.05)     // not kept: too soon. The camera still delivered.
        XCTAssertEqual(window.lastTick, 10.05)
        XCTAssertEqual(window.frames, ["a"])
        window.clear()
        XCTAssertNil(window.lastTick)
    }

    /// At the rate a run asks, every picture is kept and the driver's two are one place apart from
    /// `DriverTrial.cameraPeriod` twice: its 0.4 s, as in training.
    func testAtTheDriversRateTheWindowMatchesTraining() {
        var window = DreamFrameWindow()
        for i in 0..<7 { window.add("\(i)", at: Double(i) * DriverTrial.cameraPeriod) }
        XCTAssertEqual(window.frames.count, BallWalk.Pictures.first)
        XCTAssertEqual(DriverPrep.places(offsets: [0, -4], count: 7), [6, 4])
    }

    // MARK: - the line after a run

    func testNoLineClaimsTheBall() {
        for line in BallWalk.Words.all where !line.hasPrefix("Get it first") {
            for claim in ["reached the ball", "got to the ball", "at the ball", "found the ball"] {
                XCTAssertFalse(line.lowercased().contains(claim), "\(claim): \(line)")
            }
        }
    }

    func testTheRunLineSaysHowItEnded() {
        func line(_ said: String?, capped: Bool = false, p50: Int? = nil) -> String {
            BallWalk.line(pilotSaid: said, capped: capped, capSeconds: 30, p50: p50)
        }
        XCTAssertEqual(line(BallWalk.Words.stoppedItself), BallWalk.Words.stoppedItself)
        XCTAssertEqual(line(DuckDream.Words.stopped, capped: true), BallWalk.Words.timeLimit(30))
        XCTAssertEqual(line(DuckDream.Words.timeUp), BallWalk.Words.timeLimit(30))
        XCTAssertEqual(line(DuckDream.Words.stopped), DuckDream.Words.stopped)
        XCTAssertEqual(line(DuckDream.Words.tooHot), DuckDream.Words.tooHot)
        XCTAssertEqual(line(BallWalk.Words.cameraLost, p50: 12),
                       BallWalk.Words.cameraLost + " " + BallRunWatch.Words.answered(12))
    }

    // MARK: - the real picture

    private typealias Framing = BallWalk.Framing

    /// The alpha's upright picture: nothing stretched, and a degree the same size as on the stage.
    func testAPortraitPictureKeepsTheDrawnStagesScale() {
        let cut = Framing.real(width: 720, height: 1280)
        let across = cut.target.width / cut.source.width, down = cut.target.height / cut.source.height
        XCTAssertEqual(across, down, accuracy: 1e-9, "a ball stays round")
        XCTAssertEqual(across, Framing.drawnFocal / Framing.focal, accuracy: 1e-9)
        XCTAssertEqual(across, 0.2, accuracy: 0.001)
        // All of the width, the drawn 176 pixels tall, and inside both pictures.
        XCTAssertEqual(cut.source.x, 0)
        XCTAssertEqual(cut.source.width, 720)
        XCTAssertEqual(cut.target.height, 176, accuracy: 1e-6)
        XCTAssertEqual(cut.target.y, 0, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(cut.source.y, 0)
        XCTAssertLessThanOrEqual(cut.source.y + cut.source.height, 1280)
        XCTAssertGreaterThanOrEqual(cut.target.x, 0)
        XCTAssertLessThanOrEqual(cut.target.x + cut.target.width, 320)
    }

    /// The optical axis lands on the middle of the drawn picture, wherever it is in the real one.
    func testTheRealOpticalAxisIsTheMiddleOfTheCut() {
        let cut = Framing.real(width: 720, height: 1280)
        let scale = cut.target.width / cut.source.width
        XCTAssertEqual(cut.target.x + (Framing.axisX - cut.source.x) * scale, 160, accuracy: 1e-9)
        // Measured from the bottom, as `target` is.
        let fromTop = (Framing.axisY - cut.source.y) * scale
        XCTAssertEqual(cut.target.y + cut.target.height - fromTop, 88, accuracy: 1e-9)
    }

    /// A quality rung with half the pixels is the same cut at half the size.
    func testASmallerRungIsTheSameCut() {
        let big = Framing.real(width: 720, height: 1280), small = Framing.real(width: 360, height: 640)
        XCTAssertEqual(small.source.height, big.source.height / 2, accuracy: 1e-9)
        XCTAssertEqual(small.source.y, big.source.y / 2, accuracy: 1e-9)
        XCTAssertEqual(small.target, big.target)
    }

    /// A landscape picture has no published angle to match, so it is fitted whole.
    func testALandscapePictureIsFittedWhole() {
        let cut = Framing.real(width: 1280, height: 720)
        XCTAssertEqual(cut.source, .init(x: 0, y: 0, width: 1280, height: 720))
        XCTAssertEqual(cut.target, .init(x: 0, y: 0, width: 320, height: 176))
    }
}
