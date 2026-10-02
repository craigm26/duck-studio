import XCTest
@testable import StudioKit

final class HubTrainingTests: XCTestCase {

    private let when = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-21 14:13 UTC

    func testTheBatchIDIsReadableAndUnique() {
        let id = HubTraining.Recipe(name: "Walk slowly, please!").batchID(at: when)
        XCTAssertEqual(id, "app-walk-slowly-please-20260921-1413")
        XCTAssertEqual(HubTraining.Recipe(name: "!!").batchID(at: when), "app-run-20260921-1413")
    }

    /// THE PASS LINES ARE IN THE MENU BEFORE IT RUNS, so a result cannot move them.
    func testTheMenuCarriesItsPassLinesAndTheRecipe() {
        let recipe = HubTraining.Recipe(name: "Pilot", iterations: 100, linearProgressWeight: 1.5,
                                        angularProgressWeight: 0.5)
        let menu = recipe.menuYAML(batchID: "app-pilot-x")
        XCTAssertTrue(menu.contains("cmd 0.10 m/s -> >= 0.05 m/s"), menu)
        XCTAssertTrue(menu.contains("falls/min <= 0.71"), menu)
        XCTAssertTrue(menu.contains("A PILOT"), menu)
        XCTAssertTrue(menu.contains("VelStand's curriculum, 25% of envs"), "say the real standing share: \(menu)")
        XCTAssertTrue(menu.contains("batch_id: app-pilot-x"), menu)
        XCTAssertTrue(menu.contains("iterations: 100"), menu)
        XCTAssertTrue(menu.contains("func: duckbatch.rewards.command_progress_linear\n      weight: 1.5"), menu)
        XCTAssertTrue(menu.contains("func: duckbatch.rewards.command_progress_angular\n      weight: 0.5"), menu)
        XCTAssertTrue(menu.contains("coef_fallen: 1.0"), "the teacher anchor stays: \(menu)")
        XCTAssertFalse(menu.contains("track_linear_velocity"), "b003's narrowed widths stay out")
        XCTAssertFalse(HubTraining.Recipe(name: "Full", iterations: 1500).menuYAML(batchID: "b")
            .contains("A PILOT"))
    }

    func testRefusalsBeforeAnyMoneyIsSpent() {
        XCTAssertNil(HubTraining.Recipe(name: "ok").refusal)
        XCTAssertNotNil(HubTraining.Recipe(name: "x", iterations: 5).refusal)
        XCTAssertNotNil(HubTraining.Recipe(name: "x", linearProgressWeight: 9).refusal)
        let b003 = HubTraining.Recipe(name: "x", linearProgressWeight: 0, angularProgressWeight: 0)
        XCTAssertTrue(b003.refusal?.contains("b003 again") == true)
    }

    /// The body `HfApi.run_job` would send, with duckbatch's bootstrap fetched at the pin.
    func testTheRequestRunsDuckbatchsOwnBootstrapAtThePin() throws {
        let body = HubTraining.requestBody(recipe: .init(name: "p"), batchID: "app-p",
                                           dataset: "me/records", token: "hf_secret")
        XCTAssertEqual(body["dockerImage"] as? String, HubTraining.image)
        XCTAssertEqual(body["flavor"] as? String, "l4x1")
        XCTAssertEqual(body["timeoutSeconds"] as? Int, 3600)
        let command = try XCTUnwrap(body["command"] as? [String])
        XCTAssertEqual(command.first, "bash")
        XCTAssertTrue(command[2].contains(
            "raw.githubusercontent.com/craigm26/duckbatch/\(HubTraining.duckbatchCommit)/scripts/hf_job_bootstrap.sh"))
        let env = try XCTUnwrap(body["environment"] as? [String: String])
        XCTAssertEqual(env["RUN"], "finetune")
        XCTAssertEqual(env["COMMIT"], HubTraining.duckbatchCommit)
        XCTAssertTrue(env["MENU_YAML"]?.contains("batch_id: app-p") == true)
        XCTAssertNil(env["HF_TOKEN"], "the token is a secret, never an environment variable")
        XCTAssertEqual((body["secrets"] as? [String: String])?["HF_TOKEN"], "hf_secret")
        XCTAssertEqual(HubTraining.duckbatchCommit.count, 40, "pin a full SHA")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(body))
    }

    func testReadingAJobsState() {
        let json = #"{"id":"6abd","status":{"stage":"RUNNING","message":null},"flavor":"l4x1"}"#
        let state = HubTraining.jobState(from: Data(json.utf8))
        XCTAssertEqual(state, .init(id: "6abd", stage: .running, message: nil))
        XCTAssertFalse(state!.stage.isFinal)
        XCTAssertTrue(HubTraining.Stage.completed.isFinal)
        XCTAssertNil(HubTraining.jobState(from: Data("{}".utf8)))
    }

    func testWhereTheResultLands() {
        XCTAssertEqual(HubTraining.fileURL(dataset: "me/r", jobID: "j1", batchID: "b1",
                                           path: HubTraining.policyPath)?.absoluteString,
                       "https://huggingface.co/datasets/me/r/resolve/main/jobs/j1/b1/policies/finetuned/policy.onnx")
    }
}
