import XCTest
@testable import StudioKit

/// Duck golf: a skill game because the kick itself never fails.
final class DuckGolfTests: XCTestCase {

    private let hole = DuckGolf.Hole(tee: .init(0, 0), cup: .init(1.0, 0), par: 2)

    /// Out of reach is a miss and does NOT cost a stroke — a swing you were
    /// never close enough to take is not a shot.
    func testBeingTooFarAwayIsNotAStroke() {
        var golf = DuckGolf(hole: hole)
        let far = DuckSoccer.Vec2(-1.0, 0)
        guard case .missed(let why) = golf.kick(from: far, heading: 0, power: 1) else {
            return XCTFail("a kick from a metre away should not connect")
        }
        XCTAssertTrue(why.contains("too far"), why)
        XCTAssertEqual(golf.strokes, 0)
    }

    /// The ball has to be in front of the foot, the same cone the pitch uses.
    func testTheBallHasToBeInFrontOfIt() {
        var golf = DuckGolf(hole: hole)
        // Standing next to the ball but facing away down the fairway.
        let beside = DuckSoccer.Vec2(-0.05, 0)
        guard case .missed(let why) = golf.kick(from: beside, heading: .pi, power: 1) else {
            return XCTFail("facing backwards should miss")
        }
        XCTAssertTrue(why.contains("in front"), why)
        XCTAssertEqual(golf.strokes, 0)
    }

    /// Lined up, it connects and the ball runs along the heading.
    func testALinedUpKickRunsTheBallDownTheHeading() {
        var golf = DuckGolf(hole: hole)
        guard case .struck(let distance) = golf.kick(from: .init(-0.05, 0),
                                                     heading: 0, power: 0.5) else {
            return XCTFail("a lined-up kick should connect: \(golf.summary)")
        }
        XCTAssertGreaterThan(distance, 0)
        XCTAssertEqual(golf.ball.y, 0, accuracy: 1e-12, "straight down the line")
        XCTAssertGreaterThan(golf.ball.x, 0)
        XCTAssertEqual(golf.strokes, 1)
    }

    /// Enough power in the right direction holes it, and the summary scores it
    /// against par rather than just counting.
    func testHolingItScoresAgainstPar() {
        var golf = DuckGolf(hole: hole)
        var guard_ = 0
        while !golf.holed && guard_ < 20 {
            // Stand just behind the ball, aimed at the cup, and putt.
            let aim = golf.hole.cup - golf.ball
            let stand = golf.ball - DuckSoccer.Vec2(cos(atan2(aim.y, aim.x)),
                                                    sin(atan2(aim.y, aim.x))) * 0.05
            let need = golf.toCup
            let power = min(1.0, need / (golf.capabilities.kickBallSpeed * 1.6))
            _ = golf.kick(from: stand, heading: atan2(aim.y, aim.x), power: power)
            guard_ += 1
        }
        XCTAssertTrue(golf.holed, golf.summary)
        XCTAssertTrue(golf.summary.hasPrefix("Holed in"), golf.summary)
    }

    /// A holed ball stops accepting kicks.
    func testAHoledBallIsFinishedWith() {
        var golf = DuckGolf(hole: .init(tee: .init(0, 0), cup: .init(0.2, 0),
                                        cupRadius: 0.5, par: 1))
        _ = golf.kick(from: .init(-0.05, 0), heading: 0, power: 0.5)
        XCTAssertTrue(golf.holed)
        let strokes = golf.strokes
        guard case .holed = golf.kick(from: .init(-0.05, 0), heading: 0, power: 1) else {
            return XCTFail("a finished hole should say so")
        }
        XCTAssertEqual(golf.strokes, strokes)
    }

    /// The course is playable: every hole is reachable in a sane number of
    /// kicks from the measured ball speed.
    func testEveryHoleOnTheCourseIsReachable() {
        for hole in DuckGolf.course {
            let perKick = DuckSoccer.Capabilities.measured.kickBallSpeed * 1.6
            XCTAssertLessThanOrEqual(hole.length, perKick * Double(hole.par) * 1.2,
                                     "a par \(hole.par) hole of \(hole.length) m")
            XCTAssertGreaterThan(hole.length, perKick * 0.5, "and not trivially short")
        }
    }
}
