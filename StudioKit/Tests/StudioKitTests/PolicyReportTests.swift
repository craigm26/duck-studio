import XCTest
import DuckKit
@testable import StudioKit

/// The refusal screen is this app's single best feature, so its text is pinned
/// here rather than looked at on a phone. Each fixture in the corpus carries
/// exactly one defect, which is what makes it fair to assert that the message
/// names that defect and not some other true thing about the file.
final class PolicyReportTests: XCTestCase {

    private func report(_ file: String) throws -> PolicyReport {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: file.replacingOccurrences(of: ".onnx", with: ""),
            withExtension: "onnx", subdirectory: "Fixtures/refusals"),
            "missing fixture \(file) — run scripts/make_refusal_corpus.py")
        return PolicyReport.of(try Data(contentsOf: url), name: file)
    }

    /// The control. Without a synthesized file that LOADS, the corpus would
    /// only prove the generator emits unusable bytes.
    func testTheSyntheticControlLoads() throws {
        let r = try report("synthetic_valid.onnx")
        XCTAssertEqual(r.outcome, .runnable, "the control must load: \(r.reason)")
        XCTAssertEqual(r.reason, "", "a runnable policy has nothing to explain")
        XCTAssertNil(r.remedy)
        XCTAssertTrue(r.headline.hasSuffix("is a Microduck policy"))
    }

    // MARK: - unreadable

    func testAnEmptyFileSaysSo() throws {
        let r = try report("empty.onnx")
        XCTAssertEqual(r.outcome, .unreadable)
        XCTAssertEqual(r.reason, "The file is empty.")
        XCTAssertNil(r.remedy, "there is no advice worth giving about zero bytes")
    }

    func testATruncatedFileBlamesTheExportNotTheUser() throws {
        let r = try report("truncated.onnx")
        XCTAssertEqual(r.outcome, .unreadable)
        XCTAssertTrue(r.reason.contains("not a walkable ONNX protobuf"), r.reason)
        let remedy = try XCTUnwrap(r.remedy)
        XCTAssertTrue(remedy.contains("interrupted") || remedy.contains("cut off"), remedy)
    }

    func testGarbageIsUnreadable() throws {
        XCTAssertEqual(try report("garbage.onnx").outcome, .unreadable)
    }

    /// Walkable protobuf with no graph is its own case, and a real one: it is
    /// what a half-finished export produces.
    func testAProtobufWithNoGraphIsDistinguishedFromGarbage() throws {
        let r = try report("no_graph.onnx")
        XCTAssertEqual(r.outcome, .unreadable)
        XCTAssertTrue(r.reason.contains("no graph"), r.reason)
        XCTAssertTrue(r.reason.contains("readable protobuf"),
                      "it should say the file parsed, so the reader knows the bytes were fine")
    }

    // MARK: - wrong architecture

    /// The sentence the whole app exists for.
    func testReluIsNamedExactlyAndTheAdviceIsAboutTraining() throws {
        let r = try report("relu_instead_of_elu.onnx")
        XCTAssertEqual(r.outcome, .refused)
        XCTAssertTrue(r.reason.contains("Relu where the trained policy uses Elu"), r.reason)
        let remedy = try XCTUnwrap(r.remedy)
        XCTAssertTrue(remedy.contains("policy definition"),
                      "the fix is in the model, not the exporter flags: \(remedy)")
        // And the structure is shown beside it, so the claim is checkable.
        let ops = try XCTUnwrap(r.facts.first { $0.label == "Operations" })
        XCTAssertTrue(ops.value.contains("Relu"), ops.value)
    }

    func testAnAppendedOpIsCountedAndNamed() throws {
        let r = try report("extra_op_appended.onnx")
        XCTAssertEqual(r.outcome, .refused)
        XCTAssertTrue(r.reason.contains("1 extra operation"), r.reason)
        XCTAssertTrue(r.reason.contains("Tanh"), "say which one: \(r.reason)")
        XCTAssertTrue(try XCTUnwrap(r.remedy).contains("DuckGait"),
                      "point at where scaling actually happens")
    }

    func testAClearedTransBIsExplainedAsATransposedWeight() throws {
        let r = try report("gemm_without_transb.onnx")
        XCTAssertEqual(r.outcome, .refused)
        XCTAssertTrue(r.reason.contains("untransposed"), r.reason)
        XCTAssertTrue(r.reason.contains("[outputs, inputs]"), r.reason)
    }

    // MARK: - wrong shape

    func testAWiderObservationReportsBothNumbers() throws {
        let r = try report("observation_62_wide.onnx")
        XCTAssertEqual(r.outcome, .refused)
        XCTAssertTrue(r.reason.contains("62"), r.reason)
        XCTAssertTrue(r.reason.contains("61"), "say what it should have been: \(r.reason)")
        XCTAssertTrue(try XCTUnwrap(r.remedy).contains("13 command"),
                      "spell out the layout so the reader can find their own mistake")
    }

    func testAShorterOutputNamesTheJointCount() throws {
        let r = try report("output_13_actions.onnx")
        XCTAssertEqual(r.outcome, .refused)
        XCTAssertTrue(r.reason.contains("13 actions"), r.reason)
        XCTAssertTrue(r.reason.contains("14 actuated joints"), r.reason)
        XCTAssertTrue(try XCTUnwrap(r.remedy).contains("guessing"),
                      "refusing to guess is the point, so say it")
    }

    func testANarrowedHiddenLayerIsRefused() throws {
        let r = try report("hidden_narrowed.onnx")
        XCTAssertEqual(r.outcome, .refused)
        XCTAssertFalse(r.reason.isEmpty)
    }

    // MARK: - the table

    /// Every refusal shows the structure it objected to. A refusal screen that
    /// cannot show its evidence is asking to be believed on faith.
    func testEveryRefusalCarriesTheStructureItObjectedTo() throws {
        for file in ["relu_instead_of_elu.onnx", "extra_op_appended.onnx",
                     "gemm_without_transb.onnx", "observation_62_wide.onnx",
                     "output_13_actions.onnx", "hidden_narrowed.onnx"] {
            let r = try report(file)
            XCTAssertEqual(r.outcome, .refused, file)
            XCTAssertFalse(r.reason.isEmpty, "\(file) needs a reason")
            let labels = Set(r.facts.map(\.label))
            XCTAssertTrue(labels.contains("Operations"), "\(file) must show its ops")
            XCTAssertTrue(labels.contains("Parameters"), "\(file) must show its size")
            XCTAssertTrue(labels.contains("Layers"), "\(file) must show its widths")
        }
    }

    /// Numbers people read are grouped. 197774 is a bug report; 197,774 is a
    /// fact.
    func testParameterCountsAreGrouped() throws {
        let r = try report("synthetic_valid.onnx")
        let params = try XCTUnwrap(r.facts.first { $0.label == "Parameters" })
        XCTAssertTrue(params.value.contains(","), params.value)
    }

    /// No two fixtures produce the same sentence. If they did, the message
    /// would be describing a category rather than the file in front of you.
    func testEveryRefusalReasonIsDistinct() throws {
        var seen: [String: String] = [:]
        for file in ["empty.onnx", "truncated.onnx", "no_graph.onnx",
                     "relu_instead_of_elu.onnx", "extra_op_appended.onnx",
                     "gemm_without_transb.onnx", "observation_62_wide.onnx",
                     "output_13_actions.onnx"] {
            let reason = try report(file).reason
            if let clash = seen[reason] {
                XCTFail("\(file) and \(clash) give the same reason: \(reason)")
            }
            seen[reason] = file
        }
    }

    /// A REFUSAL HERE IS NOT A VERDICT ABOUT THE ROBOT, and the headline used
    /// to say it was. Microduck Studio's reader takes one exact architecture;
    /// robotd's `check_width` asserts only the trailing dimension of the first
    /// outlet plus a zeroed warm-up step, and looks at no layer or activation.
    /// So a file this app turns away can very well load on the robot, and the
    /// old "will not drive the robot" was a claim the app could not support.
    func testARefusalIsAboutThisAppAndNotAboutTheRobot() throws {
        let r = try report("relu_instead_of_elu.onnx")
        XCTAssertEqual(r.outcome, .refused)
        XCTAssertTrue(r.headline.hasSuffix("will not load in Microduck Studio"), r.headline)
        XCTAssertFalse(r.headline.contains("drive the robot"),
                       "a refusal must not be phrased as the robot's verdict")
    }

    func testTheCaveatNamesWhatEachReaderActuallyChecks() {
        let c = PolicyReport.refusalIsAboutThisApp
        XCTAssertTrue(c.contains("Microduck Studio's answer, not the robot's"), c)
        // The two widths are the part this app CAN check and the robot does too.
        XCTAssertTrue(c.contains("61"), c)
        XCTAssertTrue(c.contains("14"), c)
        XCTAssertTrue(c.contains("does not look at layers or activations"), c)
        XCTAssertTrue(PolicyReport.widthsTheRobotChecks.contains("refused everywhere"))
    }
}
