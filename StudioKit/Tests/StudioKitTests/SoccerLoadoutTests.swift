import XCTest
import DuckKit
@testable import StudioKit

final class SoccerLoadoutTests: XCTestCase {

    private func clip(seconds: Double, travel: Double, yaw: Double = 0) -> DuckIntentClip {
        let n = Int(seconds * 50)
        let frames = [[Double]](repeating: [Double](repeating: 0, count: 14), count: n)
        let q = (cos(yaw / 2), 0.0, 0.0, sin(yaw / 2))
        let roots = (0..<n).map { i -> DuckIntentClip.Root in
            let f = Double(i) / Double(max(n - 1, 1))
            return DuckIntentClip.Root(x: travel * f * cos(yaw), y: travel * f * sin(yaw), z: 0.12,
                                       quaternion: q)
        }
        return DuckIntentClip(name: "c", hz: 50, frames: frames, roots: roots, netYaw: 0, loops: false,
                              startsFrom: .standing, endsIn: .standing, policy: "p",
                              authored: true, environment: .bareFloor)
    }

    func testNoSkillsIsTheStandardGame() {
        XCTAssertEqual(SoccerLoadout.moves(from: [:]), .standard)
        XCTAssertTrue(SoccerLoadout().isStandard)
    }

    /// A shot clip's length is how long the shot holds the duck; a Special's
    /// recorded travel is how far it carries the duck.
    func testClipsDecideTheirEffect() {
        let moves = SoccerLoadout.moves(from: [.shoot: clip(seconds: 1.4, travel: 0),
                                               .special: clip(seconds: 2.0, travel: 0.5, yaw: 0.7)])
        XCTAssertEqual(moves.shootLock, 1.4, accuracy: 0.03)
        XCTAssertEqual(moves.passLock, 0.9, "an empty slot keeps the standard")
        XCTAssertEqual(moves.special?.distance ?? 0, 0.5, accuracy: 0.01,
                       "travel is measured along the clip's own starting heading")
        XCTAssertEqual(moves.special?.duration ?? 0, 2.0, accuracy: 0.03)
    }

    func testBackwardsOrRootlessTravelsNowhere() {
        XCTAssertEqual(SoccerLoadout.forwardTravel(clip(seconds: 1, travel: -0.3)), 0)
    }

    func testALoadoutRoundTrips() {
        var l = SoccerLoadout()
        l[.special] = .init(kind: "draft", key: "k", name: "Spin", digest: "sha256:1")
        XCTAssertEqual(SoccerLoadout.decoded(l.encoded()), l)
        XCTAssertEqual(SoccerLoadout.decoded("not json"), SoccerLoadout())
        XCTAssertEqual(l[.special]?.contender?.kind, .draft)
    }
}
