import XCTest
import DuckKit
import DuckEvidence
@testable import StudioKit

final class PlayWorldTests: XCTestCase {

    func testEveryPlaygroundProducesASendablePlan() throws {
        let address = DuckBench.Address(host: "127.0.0.1", port: 8770)
        for playground in PlayWorld.Playground.allCases {
            let plan = playground.plan()
            XCTAssertTrue(plan.isSendable, "\(playground.rawValue) has refusals: \(plan.refusals)")
            XCTAssertNoThrow(try DuckBench.setWorld(address, plan), playground.rawValue)
            for prop in plan.props {
                XCTAssertLessThan(abs(prop.x), DuckWorld.Bank.pinned.arenaInner)
                XCTAssertLessThan(abs(prop.y), DuckWorld.Bank.pinned.arenaInner)
            }
            if let ball = plan.ball {
                XCTAssertLessThan(abs(ball.x) + DuckWorld.ballRadius, DuckWorld.Bank.pinned.arenaInner)
                XCTAssertLessThan(abs(ball.y) + DuckWorld.ballRadius, DuckWorld.Bank.pinned.arenaInner)
            }
        }
    }

    func testGoalLineDetectionMatchesCanonicalPitch() {
        let pitch = Shoot.Pitch.canon
        XCTAssertTrue(PlayWorld.isGoal(ballX: pitch.goalX, ballY: 0, pitch: pitch))
        XCTAssertTrue(PlayWorld.isGoal(ballX: pitch.goalX + 0.05, ballY: pitch.goalHalfWidth - 0.01, pitch: pitch))
        XCTAssertFalse(PlayWorld.isGoal(ballX: pitch.goalX - 0.05, ballY: 0, pitch: pitch))
        XCTAssertFalse(PlayWorld.isGoal(ballX: pitch.goalX + 0.05, ballY: pitch.goalHalfWidth + 0.05, pitch: pitch))
    }

    func testAllKidSoundsCoversEveryDuckSoundOnce() {
        XCTAssertEqual(Set(PlayWorld.kidSounds), Set(DuckSound.allCases))
        XCTAssertEqual(PlayWorld.kidSounds.count, DuckSound.allCases.count)
    }

    func testPlayWorldCopyHasNoEmDashAndNoEngineeringWords() {
        for word in PlayWorld.Words.allWords {
            XCTAssertFalse(word.isEmpty)
            XCTAssertFalse(word.contains("\u{2014}"), word)
            for jargon in ["MuJoCo", "robot.move", "deadman", "bench", "policy", "intent", "repo"] {
                XCTAssertFalse(word.lowercased().contains(jargon.lowercased()), "\(jargon) in \(word)")
            }
        }
    }
}
