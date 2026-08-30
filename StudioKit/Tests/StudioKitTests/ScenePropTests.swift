import XCTest
@testable import StudioKit

final class ScenePropTests: XCTestCase {

    /// The catalogue is honest about scale: a real broom is 1.2 m of handle
    /// against a duck 0.25 m tall. A toy-sized one invented to make the demo
    /// work would be the app answering its own question.
    func testTheBroomIsARealBroom() {
        let broom = DuckScene.broom()
        XCTAssertEqual(broom.length, 1.2)
        XCTAssertEqual(broom.grams, 600)
        XCTAssertEqual(broom.graspHeightMillimetres, 150)
        XCTAssertNotNil(Retrieval.Reach.graspTime(forHeight: 0.15),
                        "the arc has to actually pass the handle")
    }

    /// Standing, it is grasped in the air and dragged. It is far past lifting
    /// and that is not a refusal.
    func testAStandingBroomIsADragJob() {
        let plan = DuckScene.broom().plan
        XCTAssertTrue(plan.isPossible, "\(plan.refusals.map(\.message))")
        XCTAssertTrue(plan.steps.contains(.dragBack(metres: 0.9)))
        guard case .tooHeavyToLift? = plan.refusals.first else {
            return XCTFail("expected the lift ceiling, got \(plan.refusals)")
        }
    }

    /// Laid down it is on the floor, and the 25 mm handle clears the 20 mm bite.
    func testABroomLaidDownStillClearsTheBite() {
        let flat = DuckScene.broom(standing: false)
        XCTAssertNil(flat.graspHeightMillimetres)
        XCTAssertTrue(flat.plan.isPossible)
    }

    /// The pencil is in the catalogue precisely because it CANNOT be picked
    /// up, and finding that out is the lesson.
    func testThePencilIsThereToBeRefused() {
        let plan = DuckScene.pencil().plan
        XCTAssertFalse(plan.isPossible)
        XCTAssertEqual(plan.refusals.first, .tooThin(millimetres: 7))
    }

    func testTheDowelIsTheOneItCanActuallyCarry() {
        let dowel = DuckScene.dowel()
        XCTAssertTrue(dowel.stick.isLiftable)
        let plan = dowel.plan
        XCTAssertTrue(plan.isPossible)
        XCTAssertTrue(plan.steps.contains(.lift))
        XCTAssertTrue(plan.refusals.isEmpty, "\(plan.refusals.map(\.message))")
    }

    /// A named prop beats the catalogue. Somebody who gave their broom 800 g
    /// means 800 g.
    func testYourPropBeatsTheGuess() {
        var heavy = DuckScene.broom()
        heavy.grams = 800
        let (reading, _) = Retrieval.plan(for: "drag the broom over here", props: [heavy])
        XCTAssertEqual(reading.stick.grams, 800)
        XCTAssertTrue(reading.assumed.isEmpty, "nothing is guessed when a prop is named")
        XCTAssertTrue(reading.understood.first!.contains("800 g"))
    }

    /// And with no matching prop it falls back to reading the sentence.
    func testAnUnknownThingStillFallsBackToTheSentence() {
        let (reading, _) = Retrieval.plan(for: "fetch the pencil", props: [DuckScene.broom()])
        XCTAssertEqual(reading.object, "pencil")
        XCTAssertFalse(reading.assumed.isEmpty)
    }

    /// The sentence can lay a standing prop down without editing the prop.
    func testTheSentenceCanLayAPropDown() {
        let (reading, _) = Retrieval.plan(for: "the broom is on the floor, drag it",
                                          props: [DuckScene.broom()])
        XCTAssertNil(reading.stick.graspHeightMillimetres)
        XCTAssertEqual(reading.stick.grams, 600, "it is still the same broom")
    }

    /// Props travel with the scene, and older scenes without them still load.
    func testScenesWithoutPropsStillDecode() throws {
        let scene = DuckScene.broomCupboard()
        XCTAssertEqual(scene.props.count, 3)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(scene)) as? [String: Any])
        json.removeValue(forKey: "props")
        let older = try JSONDecoder().decode(
            DuckScene.self, from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(older.props.isEmpty)
        XCTAssertEqual(older.name, scene.name)
    }

    func testTheStarterSceneCarriesTheBroom() {
        XCTAssertTrue(DuckScene.starters.contains { !$0.props.isEmpty })
        XCTAssertNotNil(DuckScene.broomCupboard().prop(named: "drag the broom"))
    }
}

extension ScenePropTests {

    /// The bench reports what is in its world, and a Studio prop can be checked
    /// against it. Real payload from a bench running scene_grasp.mjb.
    func testTheBenchReportsWhatItHasToPickUp() throws {
        let body = """
        {"bench":"duck-bench/2","plant":"scene_grasp.mjb — Pollen robot_allcollisions, training parameters",
         "tickHz":50,"cores":4,"policies":["BEST_alpha_stand.onnx"],
         "graspables":[{"name":"broom","mass":0.6},{"name":"dowel","mass":0.025},
                       {"name":"block_a","mass":0.03}]}
        """
        let health = try DuckBench.readHealth(Data(body.utf8))
        XCTAssertEqual(health.graspables.count, 3)
        let broom = try XCTUnwrap(health.graspables.first { $0.name == "broom" })
        XCTAssertEqual(broom.grams, 600, accuracy: 0.001)
        // And it agrees with the catalogue, which is the point of both existing.
        XCTAssertEqual(broom.grams, DuckScene.broom().grams, accuracy: 0.001)
        XCTAssertEqual(health.graspables.first { $0.name == "dowel" }?.grams,
                       DuckScene.dowel().grams)
    }

    /// The canon scene has none, and that is deliberate — every recorded clip
    /// claims to come from it, so nothing gets added to it.
    func testABareBenchReportsNothingRatherThanFailing() throws {
        let body = #"{"bench":"duck-bench/2","tickHz":50,"policies":[]}"#
        XCTAssertTrue(try DuckBench.readHealth(Data(body.utf8)).graspables.isEmpty)
    }
}
