import XCTest
@testable import StudioKit

/// What a community card says about a distilled student, from the manifest
/// craigm26/duckbatch actually published for
/// `craigm26/microduck-duckbatch-b002-128x128` (the numbers below are copied
/// from that file, held-out seeds 2001–2003).
final class PolicyComparisonTests: XCTestCase {

    private let published = """
    {"schema_version": 2, "model_api": 1, "obs_len": 61, "action_len": 14,
     "robot": {"model": "microduck", "control_hz": 50},
     "name": "duckbatch-128-128", "kind": "perpetual", "slot": "walk",
     "description": "A 26,254-parameter walking gait (61-128-128-14) distilled from Pollen's default walker (197,774 params) in simulation. Sim only: never run on hardware.",
     "command": {"encoding": "constant", "idle": [0, 0, 0],
                 "twist": ["vx (m/s)", "vy (m/s)", "wz (rad/s)"],
                 "head": "neck/head pose", "body": "unused (zeros)"},
     "training": {"repo": "craigm26/duckbatch", "method": "population DAgger distillation",
                  "run": "b002-student-size-longer/a02",
                  "teacher": "pollen-robotics/microduck-policies@1b56c39/velstand.onnx"},
     "eval": {"where": "mjlab Mjlab-VelStand-Flat-MicroDuck, domain randomization and pushes on",
              "student": {"falls_per_min": 0.4561, "down_frac": 0.0112, "lin_err": 0.1819,
                          "ang_err": 0.4072, "recovered_frac": 0.9708, "t_up_s": 0.5619},
              "teacher_same_eval": {"falls_per_min": 0.1365, "down_frac": 0.0043, "lin_err": 0.1736,
                                    "ang_err": 0.3678, "recovered_frac": 0.9688, "t_up_s": 0.5621}},
     "verdict": {"model": "jev-latest", "gap": 1.74,
                 "levels": ["None", "Small", "Material", "Severe"]}}
    """

    private func manifest(_ json: String) throws -> PolicyManifest {
        try PolicyManifest.decode(Data(json.utf8))
    }

    func testTheStudentAndTeacherNumbersAreReadSideBySide() throws {
        let c = try XCTUnwrap(try manifest(published).comparison)
        XCTAssertEqual(c.teacher, "pollen-robotics/microduck-policies@1b56c39/velstand.onnx")
        XCTAssertEqual(c.method, "population DAgger distillation")
        XCTAssertEqual(c.metrics["falls_per_min"], .init(student: 0.4561, teacher: 0.1365))
        XCTAssertEqual(c.metrics.count, 6, "every metric both sides report, and only those")
    }

    func testTheCardSaysTheGapBeforeTheGoodNews() throws {
        let c = try XCTUnwrap(try manifest(published).comparison)
        XCTAssertEqual(PolicyComparisonSummary.lines(c), [
            "Falls 3.3× as often as its teacher (0.46 vs 0.14 a minute in sim)",
            "Tracks velocity within 5% (planar) and 11% (turning) of its teacher",
            "Gets up from a fall 97% of the time (teacher 97%)",
        ])
    }

    func testTheJudgeIsNamedAsAJudgeNotAMeasurement() throws {
        let v = try XCTUnwrap(try manifest(published).verdict)
        XCTAssertEqual(PolicyComparisonSummary.verdictLine(v),
                       "Jev judges: material gap to the teacher (1.7 of 3)")
    }

    /// A metric the student reports and the teacher does not is not a
    /// comparison, and a verdict outside 0…3 is not a gap level.
    func testHalfAComparisonAndAnOutOfRangeVerdictAreDropped() throws {
        let m = try manifest("""
        {"name": "x", "obs_len": 61, "action_len": 14,
         "eval": {"student": {"falls_per_min": 1.0, "lin_err": 0.2}, "teacher_same_eval": {"lin_err": 0.2}},
         "verdict": {"model": "jev-latest", "gap": 7}}
        """)
        XCTAssertEqual(m.comparison?.metrics.keys.sorted(), ["lin_err"])
        XCTAssertNil(m.verdict)
    }

    func testAPollenStyleManifestIsNotAComparison() throws {
        let m = try manifest("""
        {"name": "x", "obs_len": 61, "action_len": 14,
         "eval": {"sim_proxy": "mjlab", "known_limits": "backwards pushes"}}
        """)
        XCTAssertNil(m.comparison)
        XCTAssertEqual(m.evaluation?.knownLimits, "backwards pushes", "the old block still reads")
    }

    /// Pollen's own publisher writes `twist` as one string; reading only lists
    /// turned it into nothing.
    func testATwistWrittenAsOneStringIsKept() throws {
        let m = try manifest("""
        {"name": "x", "obs_len": 61, "action_len": 14,
         "command": {"encoding": "constant", "idle": [0, 0, 0], "twist": "unused (zeros)"}}
        """)
        XCTAssertEqual(m.command?.twist, ["unused (zeros)"])
    }
}
