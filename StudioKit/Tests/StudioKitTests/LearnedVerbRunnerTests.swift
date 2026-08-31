import XCTest
@testable import StudioKit

/// What a `learned_verbs:` block means on the other end — which is: a description, and no
/// execution. quackd's own learned-verb module says it ships no policy, no training and no
/// ONNX runtime; its docs open "this is the shape; nothing here runs yet"; and its note on
/// the runner says shipping the ONNX to robotd's policy slot is an upstream feature that
/// does not exist, because robotd's `[policy]` paths are static. A `.duck` author is
/// deciding whether to ALLOW a verb, and "allow" reads like "deploy" unless the file says
/// otherwise — so the file says otherwise, and this test pins the sentence.
final class LearnedVerbRunnerTests: XCTestCase {

    private let minimal = #"""
    {
      "schema_version": 2,
      "model_api": 1,
      "name": "moonwalk",
      "obs_len": 61,
      "action_len": 14,
      "action_scale": 1.0,
      "description": "Walk backwards on the spot.",
      "command": { "twist": [], "idle": [0, 0, 0] },
      "robot": { "control_hz": 50 }
    }
    """#

    private func spec() throws -> LearnedVerbSpec {
        try LearnedVerbSpec.export(PolicyManifest.decode(Data(minimal.utf8)),
                                   policyPath: "policies/moonwalk.onnx")
    }

    private let runnerSentence =
        "none — quackd ships no ONNX runtime, by its own learned-verb module's account, "
      + "and its note on the runner says shipping the ONNX to robotd's policy slot is an "
      + "upstream feature that does not exist yet, because robotd's policy paths are "
      + "static today. Declaring this verb describes the policy to quackd; it does not "
      + "put it on a robot."

    func testTheExportedMetadataSaysQuackdRunsNothing() throws {
        XCTAssertEqual(try spec().metadata["quackd_runner"]?.stringValue, runnerSentence)
    }

    /// The metadata is what a `.duck` actually carries, so the sentence has to survive the
    /// trip into the declaration — a claim that lives only on the Swift value is a claim
    /// the person reading the file never sees.
    func testTheSentenceSurvivesIntoTheDuckDeclaration() throws {
        let declared = try spec().duckDeclaration
        XCTAssertEqual(declared.metadata["quackd_runner"]?.stringValue, runnerSentence)
        XCTAssertEqual(declared.name, "moonwalk")
        XCTAssertEqual(declared.policy, "policies/moonwalk.onnx")
    }

    /// The two limits sit beside each other on purpose: no arguments at call time, and no
    /// runner at all. Either alone reads like a detail; together they are the whole story.
    func testTheNoArgumentsLimitStillTravelsBesideIt() throws {
        let metadata = try spec().metadata
        XCTAssertEqual(metadata["command_at_call_time"]?.stringValue,
                       "none — register_learned_verb binds NoParams, so the LLM calls this "
                     + "verb with no arguments")
        XCTAssertEqual(metadata["safety_class"]?.stringValue, "confirm")
        XCTAssertFalse(LearnedVerbSpec.acceptsCallTimeArguments)
    }
}
