import XCTest
import DuckKit
@testable import StudioKit

/// Pollen's policy-sharing format, pinned against a REAL published file.
///
/// The fixture below is `manifest.json` from
/// `RemiFabre/microduck-flamingo-cycle`, byte for byte as Hugging Face served
/// it on 2026-08-29. A hand-written approximation would prove only that this
/// decoder agrees with itself.
final class PolicyManifestTests: XCTestCase {

    private let flamingo = #"""
{
  "schema_version": 2,
  "model_api": 1,
  "name": "flamingo-cycle",
  "kind": "perpetual",
  "obs_len": 61,
  "action_len": 14,
  "action_scale": 1.0,
  "entry_pose": "standing",
  "duration_s": null,
  "description": "Stand on one foot, either side, on command, and come back to a two-foot stand: twist = [flag, side, 0].",
  "command": {
    "twist": [
      "flag: 0 = stand on two feet (HOME), 1 = stand on one foot",
      "side: +1 = right foot down / left leg lifted, -1 = left foot down / right leg lifted; 0 allowed while flag = 0",
      "unused (0)"
    ],
    "head": "unused (zeros)",
    "body": "unused (zeros)",
    "idle": [
      0,
      0,
      0
    ]
  },
  "robot": {
    "model": "microduck",
    "hw_rev": 1,
    "servos": "xl330",
    "control_hz": 50
  },
  "training": {
    "task_id": "Mjlab-FlamingoCycleHard-Flat-MicroDuck",
    "repo": "pollen-robotics/microduck_rl",
    "commit": "0bf9897 on branch flamingo (https://github.com/pollen-robotics/microduck_rl/commit/0bf9897), not merged yet",
    "run": "pollen-robotics/flamingo-cycle-r2-hard-20260829-0245"
  },
  "eval": {
    "sim_proxy": "CPU MuJoCo with the BAM XL330 servo model, allcollisions model",
    "battery": "10/10: right and left cycles, 0.1 m/s pushes toward either side, 0.15 m/s forward, a 0.3 m/s push toward the lifted side (brief touch-down, re-lift), lowering from a static hold, 10 s hold",
    "stress_24_random_trials": {
      "held": 20,
      "recovered_stepped_down": 2,
      "fell": 2,
      "push_range_m_s": [
        0.05,
        0.25
      ]
    },
    "known_limits": "falls on backward pushes >= 0.18 m/s; pushes toward the standing-foot side above ~0.15 m/s end in a step-down; never tested on hardware",
    "transition_time_s": 1.5,
    "lifted_foot_height_m": 0.09
  }
}
"""#

    private let listing = #"""
[
  {
    "id": "RemiFabre/microduck-flamingo-cycle",
    "author": "RemiFabre",
    "lastModified": "2026-08-29T16:43:06.000Z",
    "downloads": 0,
    "likes": 0,
    "tags": [
      "onnx",
      "microduck",
      "microduck-policy",
      "mjlab",
      "robotics"
    ]
  },
  {
    "id": "fffiloni/microduck-polite-bow-b1d864",
    "author": "fffiloni",
    "lastModified": "2026-08-28T09:10:00.000Z",
    "downloads": 3,
    "likes": 1,
    "tags": [
      "onnx",
      "microduck",
      "reinforcement-learning",
      "mujoco"
    ]
  },
  {
    "id": "fffiloni/microduck-moonwalk-backward-55e6af",
    "author": "fffiloni",
    "lastModified": "2026-08-27T11:00:00.000Z",
    "downloads": 2,
    "likes": 0,
    "tags": [
      "onnx",
      "microduck",
      "robotics"
    ]
  }
]
"""#

    func testItReadsTheRealFlamingoManifest() throws {
        let m = try PolicyManifest.decode(Data(flamingo.utf8))
        XCTAssertEqual(m.schemaVersion, 2)
        XCTAssertEqual(m.modelAPI, 1)
        XCTAssertEqual(m.name, "flamingo-cycle")
        XCTAssertEqual(m.kind, "perpetual")
        XCTAssertEqual(m.observationLength, 61)
        XCTAssertEqual(m.actionLength, 14)
        XCTAssertEqual(m.actionScale, 1.0)
        XCTAssertEqual(m.entryPose, "standing")
        XCTAssertNil(m.durationSeconds, "a perpetual policy has no duration of its own")
        XCTAssertEqual(m.controlHz, 50)
    }

    /// The command block is the whole reason a manifest exists: without it,
    /// slot 0 looks like a forward velocity and is actually a flag.
    func testItCarriesWhatEachCommandSlotMeans() throws {
        let m = try PolicyManifest.decode(Data(flamingo.utf8))
        let command = try XCTUnwrap(m.command)
        XCTAssertEqual(command.twist.count, 3)
        XCTAssertTrue(command.twist[0].contains("flag"), command.twist[0])
        XCTAssertTrue(command.twist[1].contains("side"), command.twist[1])
        XCTAssertEqual(command.idle, [0, 0, 0])
        XCTAssertEqual(command.head, "unused (zeros)")
    }

    /// Three numbers decide whether this app can drive a shared network at all.
    func testItAgreesWithThisRobotsContract() throws {
        let m = try PolicyManifest.decode(Data(flamingo.utf8))
        XCTAssertTrue(m.isRunnableHere, "\(m.incompatibilities)")
        XCTAssertEqual(m.observationLength, DuckObservation.length)
        XCTAssertEqual(m.actionLength, DuckModel.policyJointCount)
        XCTAssertEqual(m.controlHz, DuckModel.tickHz)
    }

    func testAPolicyForAnotherRobotIsRefusedByName() throws {
        let other = flamingo.replacingOccurrences(of: "\"obs_len\": 61", with: "\"obs_len\": 48")
        let m = try PolicyManifest.decode(Data(other.utf8))
        XCTAssertFalse(m.isRunnableHere)
        XCTAssertEqual(m.incompatibilities, [.observationLength(48)])
        XCTAssertTrue(m.incompatibilities[0].message.contains("48"))
        XCTAssertTrue(m.incompatibilities[0].message.contains("61"))
    }

    /// Every caution is the author's own admission, not this app's invention.
    func testTheCautionsAreTheAuthorsOwnWords() throws {
        let m = try PolicyManifest.decode(Data(flamingo.utf8))
        let cautions = m.cautions
        XCTAssertTrue(cautions.contains { $0.contains("0.18") },
                      "the backward-push limit must survive: \(cautions)")
        XCTAssertTrue(cautions.contains { $0.contains("never tested on hardware") })
        XCTAssertTrue(cautions.contains { $0.contains("held 20 of 24") },
                      "the stress tally: \(cautions)")
        XCTAssertTrue(cautions.contains { $0.contains("not merged") })
        XCTAssertTrue(cautions.contains { $0.contains("Perpetual") })
        XCTAssertEqual(m.training?.isUnmerged, true)
        XCTAssertEqual(m.evaluation?.heldTrials, 20)
        XCTAssertEqual(m.evaluation?.fellTrials, 2)
        XCTAssertEqual(m.evaluation?.totalTrials, 24)
    }

    /// A schema this reader has not seen is refused, because the command
    /// block's meaning is exactly what a bump would change.
    func testAnUnknownSchemaIsRefusedRatherThanGuessed() {
        let future = flamingo.replacingOccurrences(of: "\"schema_version\": 2",
                                                   with: "\"schema_version\": 3")
        XCTAssertThrowsError(try PolicyManifest.decode(Data(future.utf8))) {
            XCTAssertEqual($0 as? PolicyManifest.ReadError, .unsupportedSchema(3))
        }
    }

    func testRubbishIsNotAManifest() {
        XCTAssertThrowsError(try PolicyManifest.decode(Data("not json".utf8))) {
            XCTAssertEqual($0 as? PolicyManifest.ReadError, .notJSON)
        }
        XCTAssertThrowsError(try PolicyManifest.decode(Data(#"{"obs_len":61}"#.utf8))) {
            XCTAssertEqual($0 as? PolicyManifest.ReadError, .missing("name"))
        }
    }

    // MARK: - discovery

    func testTheCommunityListingReadsAndSorts() throws {
        let entries = try PolicyCatalogue.parseCommunity(Data(listing.utf8))
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.first?.id, "RemiFabre/microduck-flamingo-cycle",
                       "newest first")
        XCTAssertEqual(entries.first?.name, "flamingo-cycle", "the microduck- prefix is noise")
        XCTAssertEqual(entries.first?.author, "RemiFabre")
        XCTAssertEqual(entries.first?.declaresPolicyTag, true)
        XCTAssertEqual(entries.last?.declaresPolicyTag, false,
                       "the other authors use a different toolchain and do not tag it")
        XCTAssertEqual(entries.first?.webURL, "https://huggingface.co/RemiFabre/microduck-flamingo-cycle")
    }

    /// The manifest gets its own door; the policy door still refuses anything
    /// that is not a network.
    func testTheManifestAndPolicyAddressesAreBuiltCorrectly() throws {
        let manifest = try PolicySource.huggingFaceManifest(repository: "RemiFabre/microduck-flamingo-cycle")
        XCTAssertEqual(manifest.displayURL,
            "https://huggingface.co/RemiFabre/microduck-flamingo-cycle/resolve/main/manifest.json")
        XCTAssertEqual(manifest.host, "huggingface.co")
        let policy = try PolicySource.huggingFace(repository: "RemiFabre/microduck-flamingo-cycle",
                                                  file: "policy.onnx")
        XCTAssertEqual(policy.displayURL,
            "https://huggingface.co/RemiFabre/microduck-flamingo-cycle/resolve/main/policy.onnx")
        XCTAssertThrowsError(try PolicySource.huggingFace(
            repository: "RemiFabre/microduck-flamingo-cycle", file: "manifest.json"),
            "the policy door must keep refusing non-networks")
        XCTAssertThrowsError(try PolicySource.huggingFaceManifest(repository: "nope"))
    }
}
