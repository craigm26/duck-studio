import XCTest
import DuckKit
@testable import StudioKit

/// `policy.install` on the wire: the bridge's verb, carried by the bridge
/// alone, with the digest of the bytes it carries.
final class DuckPolicyInstallTests: XCTestCase {

    private let bytes = Data("not really onnx".utf8)

    func testTheLineIsARequestWithTheBytesTheirDigestAndAnOptionalSlot() throws {
        let install = DuckPolicyInstall(name: "walk_two", bytes: bytes, slot: "walk")
        let line = try DuckCall.installPolicy(install).line(id: 4)
        let top = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        XCTAssertEqual(top["method"] as? String, "policy.install")
        XCTAssertEqual(top["id"] as? Int, 4)
        let params = try XCTUnwrap(top["params"] as? [String: Any])
        XCTAssertEqual(params["name"] as? String, "walk_two")
        XCTAssertEqual(params["slot"] as? String, "walk")
        XCTAssertEqual(params["bytes"] as? String, bytes.base64EncodedString())
        XCTAssertEqual(params["sha256"] as? String,
                       "6d0c3a0a64e0b3e0fd3d4b14b60d2c7b0fb4d3a2c0a7c1a3bd5ba6a2f0f8a6b0".count == 64
                           ? DuckPolicyInstall.digest(of: bytes) : "")
        XCTAssertEqual(params["sha256"] as? String, DuckPolicyInstall.digest(of: bytes))
        XCTAssertEqual((params["sha256"] as? String)?.count, 64)
        XCTAssertNil(try XCTUnwrap(JSONSerialization.jsonObject(
            with: try DuckCall.installPolicy(DuckPolicyInstall(name: "x", bytes: bytes)).line(id: 1))
            as? [String: Any])["params"].flatMap { ($0 as? [String: Any])?["slot"] })
        // A request, so it needs an id.
        XCTAssertThrowsError(try DuckCall.installPolicy(install).line(id: nil))
    }

    func testOnlyTheBridgeCarriesIt() {
        for transport in DuckTransportKind.allCases {
            let carried = DuckMethod.reach(for: transport).contains(.installPolicy)
            XCTAssertEqual(carried, transport == .bridge, "\(transport.label)")
        }
        XCTAssertFalse(DuckMethod.installPolicy.mutatesTheRecoveryPath)
        XCTAssertTrue(DuckCall.allShapes.contains { $0.method == .installPolicy })
    }

    func testATitleBecomesAFilenameTheBridgeAccepts() {
        XCTAssertEqual(DuckPolicyInstall.fileName(for: "alpha_walking, searched 09-06 07:39"),
                       "alpha_walking-searched-09-06-07-39")
        XCTAssertEqual(DuckPolicyInstall.fileName(for: "Walk Two.onnx"), "walk-two")
        XCTAssertEqual(DuckPolicyInstall.fileName(for: "../../etc"), "etc")
        XCTAssertEqual(DuckPolicyInstall.fileName(for: "***"), "policy")
        XCTAssertEqual(DuckPolicyInstall.fileName(for: String(repeating: "a", count: 90)).count, 64)
        let rule = try! NSRegularExpression(pattern: "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
        for title in ["a", "Ünïcode duck", ".start", "-lead", "x.y-z_w"] {
            let name = DuckPolicyInstall.fileName(for: title)
            XCTAssertEqual(rule.numberOfMatches(in: name, range: NSRange(name.startIndex..., in: name)),
                           1, "\(title) -> \(name)")
        }
    }

    func testTheAnswerIsReadBackAndNeverStopsAtInstalled() throws {
        let answered = Data("""
        {"jsonrpc":"2.0","id":4,"result":{"installed":"/opt/policies/walk_two.onnx",
        "sha256":"abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789","bytes":15,
        "takes_effect":"when robotd next starts; this bridge does not restart it",
        "slot":{"asked":"walk","applied":true,"backup":"/etc/robotd.toml.bak-1"}}}
        """.utf8)
        let outcome = try DuckPolicyInstall.read(try DuckReply.decode(answered))
        XCTAssertEqual(outcome.installed, "/opt/policies/walk_two.onnx")
        XCTAssertEqual(outcome.bytes, 15)
        XCTAssertEqual(outcome.slot?.applied, true)
        XCTAssertTrue(outcome.said.contains("Installed as /opt/policies/walk_two.onnx"))
        XCTAssertTrue(outcome.said.contains("walk key now names it"), outcome.said)
        XCTAssertTrue(outcome.said.contains("takes effect when robotd next starts"), outcome.said)

        let notApplied = Data("""
        {"jsonrpc":"2.0","id":5,"result":{"installed":"/p/x.onnx","sha256":"ab","bytes":1,
        "takes_effect":"when robotd next starts; this bridge does not restart it",
        "slot":{"asked":"roulade","applied":false,"why":"robotd.toml has no `roulade` key"}}}
        """.utf8)
        let held = try DuckPolicyInstall.read(try DuckReply.decode(notApplied))
        XCTAssertTrue(held.said.contains("roulade slot was not changed: robotd.toml has no"), held.said)

        let refused = Data(#"{"jsonrpc":"2.0","id":6,"error":{"code":-32602,"message":"nothing was written"}}"#.utf8)
        XCTAssertThrowsError(try DuckPolicyInstall.read(try DuckReply.decode(refused))) { error in
            XCTAssertEqual(error as? DuckPolicyInstall.ReadError, .refused("nothing was written"))
        }
        let wrongShape = Data(#"{"jsonrpc":"2.0","id":7,"result":true}"#.utf8)
        XCTAssertThrowsError(try DuckPolicyInstall.read(try DuckReply.decode(wrongShape)))
    }

    func testTheGreetingSaysWhetherInstallIsOn() throws {
        let on = try BridgeHandshake.read(Data(#"{"microduck":"v1","bridge":"b","deadman_ms":400,"policy_install":true}"#.utf8))
        XCTAssertTrue(on.installsPolicies)
        let older = try BridgeHandshake.read(Data(#"{"microduck":"v1","bridge":"b","deadman_ms":400}"#.utf8))
        XCTAssertFalse(older.installsPolicies)
        XCTAssertNil(older.policyInstall)
        for line in [DuckPolicyInstall.whatInstallDoes, DuckPolicyInstall.bridgeCannotInstall,
                     DuckPolicyInstall.neverRunOnHardware] {
            XCTAssertFalse(line.contains("probably"))
        }
        XCTAssertTrue(DuckPolicyInstall.whatInstallDoes.contains("not on its servos"))
    }
}
