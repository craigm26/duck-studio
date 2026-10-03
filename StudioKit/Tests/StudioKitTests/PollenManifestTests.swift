import XCTest
import DuckKit
@testable import StudioKit

/// Manifests a real Microduck will load. Pollen's own `validate_manifest` accepted all seven
/// of these on 2026-10-02 (scripts/upstream_gate/manifest_gate.py re-runs that); these tests pin
/// the fields so a change has to be deliberate.
final class PollenManifestTests: XCTestCase {

    private func written(_ kind: DuckPolicyKind) throws -> [String: Any] {
        let w = PolicyManifest.forPublishing(title: "My Walk v2!", summary: "s", kind: kind, cautions: [])
        return try JSONSerialization.jsonObject(with: PolicyManifest.encode(w)) as! [String: Any]
    }

    func testThekindIsPollensNeverTheAppsFileStem() throws {
        for kind in DuckPolicyKind.allCases {
            let m = try written(kind)
            XCTAssertTrue(["episodic", "perpetual"].contains(m["kind"] as? String), "\(kind): \(m)")
            XCTAssertNotEqual(m["kind"] as? String, kind.rawValue)
        }
    }

    func testTheRobotBlockIsAMicroduck() throws {
        let robot = try written(.walk)["robot"] as! [String: Any]
        XCTAssertEqual(robot["model"] as? String, "microduck")
        XCTAssertEqual(robot["servos"] as? String, "xl330")
    }

    /// An episodic constant-command skill needs a length, or the daemon refuses it.
    func testEpisodicConstantSkillsHaveADuration() throws {
        XCTAssertEqual(try written(.kickRight)["duration_s"] as? Double, 0.5)
        XCTAssertEqual(try written(.roulade)["duration_s"] as? Double, 1.0)
        XCTAssertEqual(try written(.roulade)["chain"] as? Bool, true)
        XCTAssertNil(try written(.walk)["duration_s"])
        XCTAssertEqual(try written(.walk)["slot"] as? String, "walk")
        XCTAssertEqual((try written(.sitStand)["command"] as? [String: Any])?["encoding"] as? String,
                       "posture_flag")
    }

    func testTheNameIsABareWordRobotctlCanTake() {
        XCTAssertEqual(PolicyManifest.bareName("My Walk v2!"), "my_walk_v2")
        XCTAssertEqual(PolicyManifest.bareName("///"), "policy")
    }
}
