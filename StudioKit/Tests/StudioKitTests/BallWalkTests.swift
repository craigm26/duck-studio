import XCTest
@testable import StudioKit

/// Walk to the ball as a Tell skill, and on a real duck: what it hears, what it refuses, how a run
/// ends and how a real picture is cut.
final class BallWalkTests: XCTestCase {

    // MARK: - Tell's words

    func testTheSentencesThatAskForIt() {
        for said in ["walk to the ball", "Walk to the ball, please", "go to the ball", "go get the ball",
                     "find the ball", "duck, walk to the ball", "please go walk to the ball now",
                     "walk toward the ball", "walk towards the ball", "walk over to the ball", "walk up to the ball",
                     "go over to the ball", "go toward the ball", "get to the ball", "go and get the ball",
                     "can you walk to the ball"] {
            XCTAssertTrue(BallWalk.heard(said), said)
        }
    }

    /// A stop word in the sentence is a stop, and nothing else may read as an order to go.
    func testSentencesThatDoNotAskForIt() {
        for said in ["no, walk to the ball", "stop walking to the ball", "stop", "walk forward", "ball", "kick the ball",
                     "walk to the red mat", "don't walk to the ball", "do not walk to the ball", "halt, go to the ball", "",
                     "let me get the ball", "let me go get the ball", "let us find the ball", "do you get the ball",
                     "me and the duck go to the ball"] {
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
        XCTAssertNil(BallWalk.notReady(.init(sitting: false, homed: true)))
    }

    /// `homed` is false on every limp duck, not only mid-ramp, and only this path can stand one.
    func testALimpDuckIsStoodUpNotRefused() throws {
        let limp = DuckOrder.Readiness(sitting: false, homed: false)
        XCTAssertNil(BallWalk.notReady(limp))
        XCTAssertEqual(try DuckOrder.stand.calls(limp), [.initPose, .enable])
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
        XCTAssertEqual(across, Framing.drawnFocal / Framing.Lens.alpha.focal, accuracy: 1e-9)
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
        XCTAssertEqual(cut.target.x + (Framing.Lens.alpha.axisX - cut.source.x) * scale, 160, accuracy: 1e-9)
        // Measured from the bottom, as `target` is.
        let fromTop = (Framing.Lens.alpha.axisY - cut.source.y) * scale
        XCTAssertEqual(cut.target.y + cut.target.height - fromTop, 88, accuracy: 1e-9)
    }

    /// A quality rung with half the pixels is the same cut at half the size.
    func testASmallerRungIsTheSameCut() {
        let big = Framing.real(width: 720, height: 1280), small = Framing.real(width: 360, height: 640)
        XCTAssertEqual(small.source.height, big.source.height / 2, accuracy: 1e-9)
        XCTAssertEqual(small.source.y, big.source.y / 2, accuracy: 1e-9)
        XCTAssertEqual(small.target, big.target)
    }

    /// The beta's wide picture: the same scale and axis as the stage, a cut of it, and no bars.
    func testABetaPictureKeepsTheDrawnStagesScaleWithNoBars() {
        let cut = Framing.real(width: 1280, height: 720)
        XCTAssertEqual(cut.target.x, 0, accuracy: 1e-9)
        XCTAssertEqual(cut.target.y, 0, accuracy: 1e-9)
        XCTAssertEqual(cut.target.width, 320, accuracy: 1e-9)
        XCTAssertEqual(cut.target.height, 176, accuracy: 1e-9)
        let scale = cut.target.width / cut.source.width
        XCTAssertEqual(cut.target.height / cut.source.height, scale, accuracy: 1e-9, "a ball stays round")
        XCTAssertEqual(scale, Framing.drawnFocal / Framing.Lens.beta.focal, accuracy: 1e-9)
        // About 1048 by 576, inside the frame, around the axis.
        XCTAssertEqual(cut.source.width, 1048, accuracy: 1)
        XCTAssertEqual(cut.source.height, 576, accuracy: 1)
        XCTAssertGreaterThanOrEqual(cut.source.x, 0)
        XCTAssertLessThanOrEqual(cut.source.x + cut.source.width, 1280)
        XCTAssertGreaterThanOrEqual(cut.source.y, 0)
        XCTAssertLessThanOrEqual(cut.source.y + cut.source.height, 720)
        XCTAssertEqual(cut.source.x + cut.source.width / 2, Framing.Lens.beta.axisX, accuracy: 1e-9)
        XCTAssertEqual(cut.source.y + cut.source.height / 2, Framing.Lens.beta.axisY, accuracy: 1e-9)
    }

    func testASmallerBetaRungIsTheSameCut() {
        let big = Framing.real(width: 1280, height: 720), small = Framing.real(width: 640, height: 360)
        XCTAssertEqual(small.source.width, big.source.width / 2, accuracy: 1e-9)
        XCTAssertEqual(small.source.x, big.source.x / 2, accuracy: 1e-9)
        XCTAssertEqual(small.target, big.target)
    }

    // MARK: - the card keeps a line with its duck

    private let practiceLine = "Reached the ball in 9.5 s and stopped."

    /// A practice reach beside a real Go would read as measured, and the warnings must stay.
    func testAPracticeRunsLineDoesNotShowOnARealDuck() {
        let card = DriverCard(phase: .installed, duck: .real,
                              lastRun: .init(duck: .sim, line: practiceLine))
        XCTAssertFalse(card.lines.contains(practiceLine))
        XCTAssertTrue(card.lines.contains(BallWalk.Words.simulatorNumbersOnly))
        XCTAssertTrue(card.lines.contains(DriverCard.Words.honest(.walkToBall)))
    }

    func testARunsLineShowsOnTheDuckThatRanIt() {
        let real = BallWalk.LastRun(duck: .real, line: BallWalk.Words.stoppedItself)
        XCTAssertEqual(DriverCard(phase: .installed, duck: .real, lastRun: real).lines.first, real.line)
        XCTAssertFalse(DriverCard(phase: .installed, duck: .sim, lastRun: real).lines.contains(real.line))
        let practice = DriverCard(phase: .installed, duck: .sim, lastRun: .init(duck: .sim, line: practiceLine))
        XCTAssertEqual(practice.lines.first, practiceLine)
    }
}
