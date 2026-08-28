import XCTest
import DuckKit
import DuckEvidence
@testable import StudioKit

/// A probe, not a test: runs a policy from OUTSIDE this project through the
/// whole pipeline and prints what each stage says. The first real third-party
/// artifact the provenance design has met.
final class ThirdPartyProbe: XCTestCase {
    func testProbeThirdPartyPolicy() throws {
        let path = "/tmp/claude-1000/-home-craigm26-projects/0319e4f7-7237-4a68-86d3-7a005c2c7514/scratchpad/third/headspin.onnx"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path))
        let data = try Data(contentsOf: URL(fileURLWithPath: path))

        let report = PolicyReport.of(data, name: "headspin_iter_00548.onnx")
        print("PROBE outcome   : \(report.outcome)")
        print("PROBE headline  : \(report.headline)")
        print("PROBE reason    : \(report.reason)")
        for fact in report.facts { print("PROBE fact      : \(fact.label) = \(fact.value)") }

        if let policy = try? DuckPolicy.load(from: data) {
            print("PROBE fingerprint: \(policy.fingerprint)")
            let standing = DuckOfficialPolicies.standing(of: policy)
            print("PROBE standing   : \(standing)")
            print("PROBE summary    : \(DuckOfficialPolicies.summary(for: standing))")
            let entry = PolicyLibrary.entry(for: data, name: "headspin.onnx", origin: .imported)
            print("PROBE identity   : \(entry.identity.isNetworkIdentity ? "parameters" : "file-only") \(entry.shortIdentity)")
        }
    }
}
