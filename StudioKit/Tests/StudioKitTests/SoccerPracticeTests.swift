import XCTest
@testable import StudioKit

final class SoccerPracticeTests: XCTestCase {
    typealias S = DuckSoccer
    let dt = 1.0 / 50

    /// Run one try: optionally strike on the first tick, then wait.
    private func play(_ p: inout SoccerPractice, shoot: Bool = false, pass: Bool = false,
                      maxSeconds: Double = 30) -> SoccerPractice.Outcome? {
        for i in 0..<Int(maxSeconds / dt) {
            let c = S.Control(kick: shoot && i < 5, pass: pass && i < 5)
            if let o = p.advance(dt: dt, control: c) { return o }
        }
        return nil
    }

    func testEveryDrillSetsUpYourDuckAndABall() {
        for drill in SoccerPractice.Drill.allCases {
            let p = SoccerPractice(drill)
            XCTAssertEqual(p.match.controlled, "home-3", drill.rawValue)
            XCTAssertTrue(p.match.players.contains { $0.id == "home-3" })
            XCTAssertEqual(p.match.phase, .playing)
            XCTAssertLessThanOrEqual(p.drill.blurb.split(separator: " ").count, 16)
        }
    }

    /// A straight pass from the first spot rolls into the first ring.
    func testAStraightPassLandsInTheFirstRing() {
        var p = SoccerPractice(.passing)
        XCTAssertEqual(play(&p, pass: true), .success("In the ring!"))
        XCTAssertEqual(p.successes, 1)
        XCTAssertEqual(p.attempt, 1)
    }

    /// Pick your corner: a straight shot from the middle goes in, but not in
    /// the lit half, and says so.
    func testAGoalInTheWrongHalfIsAMiss() {
        var p = SoccerPractice(.corners)
        _ = play(&p, maxSeconds: 21)   // try 1 times out (no strike)
        _ = play(&p, maxSeconds: 21)   // try 2
        XCTAssertEqual(p.attempt, 2)
        XCTAssertEqual(play(&p, shoot: true), .miss("Wrong half"))
    }

    /// A drill ends after its tries, with stars from its successes.
    func testADrillFinishesWithStars() {
        var p = SoccerPractice(.passing)
        for _ in 0..<5 { _ = play(&p, pass: true) }
        XCTAssertTrue(p.isFinished)
        XCTAssertEqual(p.results.count, 5)
        XCTAssertGreaterThanOrEqual(p.successes, 1)
        XCTAssertEqual(p.stars, p.successes >= 4 ? 3 : p.successes >= 3 ? 2 : p.successes >= 2 ? 1 : 0)
        XCTAssertNil(p.advance(dt: dt, control: S.Control()), "a finished drill does nothing")
    }

    /// The slalom lays out four gates and a finish, and times out honestly.
    func testTheSlalomHasFourGatesAndAFinish() {
        var p = SoccerPractice(.slalom)
        XCTAssertEqual(p.props.filter { $0.kind == .cone }.count, 8)
        XCTAssertEqual(p.props.filter { $0.kind == .finish }.count, 1)
        XCTAssertEqual(play(&p, maxSeconds: 160), .miss("Out of time"))
        XCTAssertTrue(p.isFinished)
        XCTAssertEqual(p.stars, 0)
    }

    /// The markings sit on the pitch, the boxes are wider than the goal and
    /// inside the touchlines, and there are three spots and four corners.
    func testThePitchMarkingsAreAProperPitch() {
        let pitch = S.Pitch.livingRoom
        let m = pitch.markings()
        for (a, b) in m.lines {
            for v in [a, b] {
                XCTAssertLessThanOrEqual(abs(v.x), pitch.halfLength + 1e-9)
                XCTAssertLessThanOrEqual(abs(v.y), pitch.halfWidth + 1e-9)
            }
        }
        XCTAssertGreaterThan(pitch.goalAreaHalfWidth, pitch.goalHalfWidth)
        XCTAssertGreaterThan(pitch.penaltyAreaHalfWidth, pitch.goalAreaHalfWidth)
        XCTAssertLessThan(pitch.penaltyAreaHalfWidth, pitch.halfWidth)
        XCTAssertEqual(m.spots.count, 3)
        XCTAssertEqual(m.corners.count, 4)
        XCTAssertEqual(pitch.penaltySpot, 11 * 2.4 / 105, accuracy: 1e-9)
    }
}
