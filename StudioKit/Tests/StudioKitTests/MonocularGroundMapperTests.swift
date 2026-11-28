import XCTest
@testable import StudioKit

final class MonocularGroundMapperTests: XCTestCase {

    // MARK: - Calibrated Pinhole Ground-Plane (z=0) Projection

    func testPinholeCenterPixelProjectsToExpectedGroundDistance() {
        let pitch = 30.0 * .pi / 180.0
        let height = 0.25
        let intrinsics = MonocularCameraIntrinsics(
            fx: 320, fy: 320, cx: 320, cy: 240,
            imageWidth: 640, imageHeight: 480,
            cameraHeightM: height, cameraPitchRad: pitch,
            maxRangeM: 4.0, minConfidence: 0.65
        )
        let pose = Pose2D(x: 1.0, y: 2.0, theta: 0.0)
        let hit = MonocularGroundMapper.projectPixelToGround(
            u: 320, v: 240, pose: pose, intrinsics: intrinsics
        )
        XCTAssertNotNil(hit)
        let expectedRange = height / tan(pitch) // 0.25 / tan(30 deg) ≈ 0.4330 m
        XCTAssertEqual(hit!.world.x, 1.0 + expectedRange, accuracy: 1e-4)
        XCTAssertEqual(hit!.world.y, 2.0, accuracy: 1e-4)
        XCTAssertEqual(hit!.rangeM, expectedRange, accuracy: 1e-4)

        // Pixel to the right of principal point (u > cx) maps to negative robot-Y (right side).
        let rightHit = MonocularGroundMapper.projectPixelToGround(
            u: 400, v: 240, pose: pose, intrinsics: intrinsics
        )
        XCTAssertNotNil(rightHit)
        XCTAssertLessThan(rightHit!.world.y, 2.0)

        // Pixel well above the horizon fails closed (returns nil).
        let skyHit = MonocularGroundMapper.projectPixelToGround(
            u: 320, v: 10, pose: pose, intrinsics: intrinsics
        )
        XCTAssertNil(skyHit)
    }

    func testNaNIntrinsicsAndLowConfidenceFailClosedWithoutMutatingGrid() {
        var mapper = MonocularGroundMapper(widthM: 6.0, heightM: 6.0, resolutionM: 0.20)
        let beforeGrid = mapper.grid
        let pose = Pose2D(x: 1.0, y: 1.0, theta: 0.0)
        let goodSamples = [
            MonocularMaskSample(u: 320, v: 320, label: .floor, confidence: 0.92),
            MonocularMaskSample(u: 360, v: 320, label: .floor, confidence: 0.90),
        ]

        // 1. NaN focal length -> fail-closed HOLD, grid untouched.
        let nanIntrinsics = MonocularCameraIntrinsics(fx: .nan)
        let rNaN = mapper.projectMonocularGroundMask(
            pose: pose, intrinsics: nanIntrinsics, samples: goodSamples, timestampS: 1.0, nowS: 1.1
        )
        XCTAssertFalse(rNaN.accepted)
        XCTAssertEqual(rNaN.decision, .hold)
        XCTAssertTrue(rNaN.reason.contains("NON_FINITE_INTRINSICS"))
        XCTAssertEqual(mapper.grid, beforeGrid)

        // 2. Infinite camera height -> fail-closed HOLD, grid untouched.
        let infIntrinsics = MonocularCameraIntrinsics(cameraHeightM: .infinity)
        let rInf = mapper.projectMonocularGroundMask(
            pose: pose, intrinsics: infIntrinsics, samples: goodSamples, timestampS: 1.0, nowS: 1.1
        )
        XCTAssertFalse(rInf.accepted)
        XCTAssertEqual(rInf.decision, .hold)
        XCTAssertEqual(mapper.grid, beforeGrid)

        // 3. Low ground-segmentation confidence (< 0.65) -> fail-closed HOLD, grid untouched.
        let lowConfSamples = [
            MonocularMaskSample(u: 320, v: 320, label: .floor, confidence: 0.35),
            MonocularMaskSample(u: 350, v: 320, label: .floor, confidence: 0.42),
        ]
        let rLow = mapper.projectMonocularGroundMask(
            pose: pose, intrinsics: .microDuckDefault, samples: lowConfSamples, timestampS: 1.0, nowS: 1.1
        )
        XCTAssertFalse(rLow.accepted)
        XCTAssertEqual(rLow.decision, .hold)
        XCTAssertTrue(rLow.reason.contains("LOW_SEGMENTATION_CONFIDENCE"))
        XCTAssertEqual(mapper.grid, beforeGrid)

        // 4. Stale camera observation (> 1.5s) -> fail-closed HOLD.
        let rStale = mapper.projectMonocularGroundMask(
            pose: pose, intrinsics: .microDuckDefault, samples: goodSamples, timestampS: 1.0, nowS: 3.2
        )
        XCTAssertFalse(rStale.accepted)
        XCTAssertEqual(rStale.decision, .hold)
        XCTAssertTrue(rStale.reason.contains("STALE_CAMERA_OBSERVATION"))
        XCTAssertEqual(mapper.grid, beforeGrid)
    }

    // MARK: - Stairwell Keep-Out Envelope 0.2 DENY

    func testStairwellKeepoutDeniesFrontierCrossingDropoff() {
        var mapper = MonocularGroundMapper(widthM: 6.0, heightM: 6.0, resolutionM: 0.20, minZoneCells: 2)
        // Register stairwell drop-off keep-out directly between robot (1.0, 3.0) and frontier (4.0, 3.0).
        let stairs = Box2D(name: "stairwell_dropoff", minX: 2.0, minY: 2.0, maxX: 3.0, maxY: 4.0)
        let marked = mapper.markKeepoutZone(stairs)
        XCTAssertGreaterThan(marked, 0)

        // Direct swept path across stairwell MUST be DENIED with violator stairwell_dropoff.
        let blocked = mapper.checkSweptPath2D(
            waypoints: [Point2D(x: 1.0, y: 3.0), Point2D(x: 4.0, y: 3.0)]
        )
        XCTAssertFalse(blocked.allowed)
        XCTAssertEqual(blocked.violator, "stairwell_dropoff")
        XCTAssertLessThanOrEqual(blocked.minMarginM, 0.0)

        // Path staying well clear of stairwell MUST be ALLOWED.
        let clear = mapper.checkSweptPath2D(
            waypoints: [Point2D(x: 1.0, y: 1.0), Point2D(x: 4.0, y: 1.0)]
        )
        XCTAssertTrue(clear.allowed)
        XCTAssertNil(clear.violator)
        XCTAssertGreaterThan(clear.minMarginM, 0.5)

        // Frontier placed behind stairwell (only reachable through stairwell) -> planNextFrontier DENY.
        let pose = Pose2D(x: 1.2, y: 3.0, theta: 0.0)
        // Paint only a small pocket on the far side of the stairwell as FREE adjacent to UNKNOWN.
        for r in 14...16 {
            for c in 18...19 {
                mapper.setCell(GridCell(col: c, row: r), state: .free)
            }
        }
        let plan = mapper.planNextFrontier(pose: pose, health: .nominal)
        XCTAssertEqual(plan.decision, .deny)
        XCTAssertNil(plan.selectedFrontier)
        XCTAssertFalse(plan.rejectedCandidates.isEmpty)
        XCTAssertEqual(plan.rejectedCandidates.first?.gateViolator, "stairwell_dropoff")
    }

    // MARK: - Bipedal Safety Interlocks (IMU Tilt, Battery Sag, Stale Camera, E-Stop)

    func testBipedHealthInterlocksFailClosed() {
        XCTAssertTrue(checkBipedHealth(.nominal).ok)
        XCTAssertEqual(checkBipedHealth(.nominal).decision, .allow)

        // IMU tilt > 22 deg -> HOLD
        let tilted = BipedHealthTelemetry(batteryV: 7.8, imuRollDeg: 24.5, imuPitchDeg: 2.0, cameraAgeS: 0.1)
        let vTilt = checkBipedHealth(tilted)
        XCTAssertFalse(vTilt.ok)
        XCTAssertEqual(vTilt.decision, .hold)
        XCTAssertTrue(vTilt.faultCodes.contains("EXCESSIVE_IMU_TILT"))

        // 2S LiPo battery sag < 7.0 V -> HOLD
        let lowBatt = BipedHealthTelemetry(batteryV: 6.75, imuRollDeg: 1.0, imuPitchDeg: 1.0, cameraAgeS: 0.1)
        let vBatt = checkBipedHealth(lowBatt)
        XCTAssertFalse(vBatt.ok)
        XCTAssertEqual(vBatt.decision, .hold)
        XCTAssertTrue(vBatt.faultCodes.contains("LOW_BATTERY_SAG"))

        // Stale camera > 1.5 s -> HOLD
        let stale = BipedHealthTelemetry(batteryV: 7.8, imuRollDeg: 1.0, imuPitchDeg: 1.0, cameraAgeS: 1.85)
        let vStale = checkBipedHealth(stale)
        XCTAssertFalse(vStale.ok)
        XCTAssertEqual(vStale.decision, .hold)
        XCTAssertTrue(vStale.faultCodes.contains("STALE_CAMERA_FEED"))

        // Human proximity < 0.65 m -> HOLD
        let human = BipedHealthTelemetry(batteryV: 7.8, imuRollDeg: 1.0, imuPitchDeg: 1.0, cameraAgeS: 0.1, humanDistanceM: 0.40)
        let vHuman = checkBipedHealth(human)
        XCTAssertFalse(vHuman.ok)
        XCTAssertTrue(vHuman.faultCodes.contains("HUMAN_PROXIMITY_HOLD"))

        // Hardware E-stop engaged -> HOLD
        let estop = BipedHealthTelemetry(batteryV: 7.8, imuRollDeg: 1.0, imuPitchDeg: 1.0, cameraAgeS: 0.1, estopOk: false)
        let vEstop = checkBipedHealth(estop)
        XCTAssertFalse(vEstop.ok)
        XCTAssertTrue(vEstop.faultCodes.contains("HARDWARE_ESTOP_ENGAGED"))

        // NaN reading -> HOLD
        let nanTel = BipedHealthTelemetry(batteryV: .nan, imuRollDeg: 1.0, imuPitchDeg: 1.0, cameraAgeS: 0.1)
        let vNaN = checkBipedHealth(nanTel)
        XCTAssertFalse(vNaN.ok)
        XCTAssertTrue(vNaN.faultCodes.contains("NON_FINITE_TELEMETRY"))
    }

    // MARK: - Doorway-Aware Room / Zone Segmentation

    func testDoorwaySplitsTwoRoomsIntoDistinctZones() {
        var mapper = MonocularGroundMapper(widthM: 6.0, heightM: 4.0, resolutionM: 0.20, minZoneCells: 4)
        // Paint two free rooms: x in [0.4, 2.4] and x in [3.2, 5.2], connected by a doorway at x=2.8, y=2.0.
        for r in 4...15 {
            for c in 2...12 { mapper.setCell(GridCell(col: c, row: r), state: .free) }
            for c in 16...26 { mapper.setCell(GridCell(col: c, row: r), state: .free) }
            // Dividing wall at col 14 with doorway gap at rows 9..10
            if r < 9 || r > 10 {
                mapper.setCell(GridCell(col: 14, row: r), state: .obstacle)
            } else {
                mapper.setCell(GridCell(col: 13, row: r), state: .free)
                mapper.setCell(GridCell(col: 14, row: r), state: .free)
                mapper.setCell(GridCell(col: 15, row: r), state: .free)
            }
        }
        mapper.attachSemanticTag("doorway", at: mapper.cellToWorld(GridCell(col: 14, row: 9)), timestampS: 1.0)
        mapper.registerZoneAlias(zoneId: "zone_01", name: "Hallway")
        mapper.registerZoneAlias(zoneId: "zone_02", name: "Lab")

        let seg = mapper.segmentZones()
        XCTAssertEqual(seg.zones.count, 2)
        XCTAssertEqual(seg.zones[0].zoneId, "zone_01")
        XCTAssertEqual(seg.zones[0].roomLabel, "Hallway")
        XCTAssertEqual(seg.zones[1].zoneId, "zone_02")
        XCTAssertEqual(seg.zones[1].roomLabel, "Lab")
        XCTAssertTrue(seg.zones[0].doorwayLinks.contains("zone_02"))
        XCTAssertGreaterThan(seg.globalCoveragePct, 0.0)
    }

    // MARK: - Conversational Goal Routing & Trust Ladder

    func testConversationalGoalRoutingAndTrustLadder() {
        var sim = MonocularMappingSimPreset()
        // Populate both Hallway and Lab so "go to lab" has a mapped centroid.
        for r in 5...14 {
            for c in 16...24 {
                sim.mapper.setCell(GridCell(col: c, row: r), state: .free)
            }
        }

        // 1. Parse intents deterministically.
        XCTAssertEqual(ConversationalExplorationSkill.parse("discover the world"), .discoverWorld)
        XCTAssertEqual(ConversationalExplorationSkill.parse("explore the hallway"), .exploreZone(query: "hallway"))
        XCTAssertEqual(ConversationalExplorationSkill.parse("go to lab"), .goToZone(query: "lab"))
        if case .hold = ConversationalExplorationSkill.parse("stop now") {} else {
            XCTFail("Expected .hold for stop command")
        }

        // 2. Default L0_OBSERVE permits ZERO motion even when path clears Envelope 0.2.
        let l0 = ConversationalExplorationSkill.evaluate(
            command: "discover the world",
            mapper: sim.mapper,
            pose: sim.pose,
            trustTier: .observe,
            softwareHoldEngaged: false,
            health: .nominal
        )
        XCTAssertEqual(l0.decision, .hold)
        XCTAssertFalse(l0.motionPermitted)
        XCTAssertTrue(l0.requiresHumanApproval)
        XCTAssertEqual(l0.gateViolator, "TRUST_TIER_L0_OBSERVE")

        // 3. L1_ATOMIC holds until explicit human approval, then allows 1 bounded step.
        let l1Pending = ConversationalExplorationSkill.evaluate(
            command: "explore the hallway",
            mapper: sim.mapper,
            pose: sim.pose,
            trustTier: .atomic,
            softwareHoldEngaged: false,
            health: .nominal,
            humanApprovedAtomicStep: false
        )
        XCTAssertEqual(l1Pending.decision, .hold)
        XCTAssertFalse(l1Pending.motionPermitted)
        XCTAssertTrue(l1Pending.requiresHumanApproval)

        let l1Approved = ConversationalExplorationSkill.evaluate(
            command: "explore the hallway",
            mapper: sim.mapper,
            pose: sim.pose,
            trustTier: .atomic,
            softwareHoldEngaged: false,
            health: .nominal,
            humanApprovedAtomicStep: true
        )
        XCTAssertEqual(l1Approved.decision, .allow)
        XCTAssertTrue(l1Approved.motionPermitted)
        XCTAssertNotNil(l1Approved.targetPoint)

        // 4. "go to lab" routes to zone_02 centroid at L2_SUPERVISED.
        let goLab = ConversationalExplorationSkill.evaluate(
            command: "go to lab",
            mapper: sim.mapper,
            pose: sim.pose,
            trustTier: .supervised,
            softwareHoldEngaged: false,
            health: .nominal
        )
        XCTAssertEqual(goLab.decision, .allow)
        XCTAssertEqual(goLab.targetZoneId, "zone_02")
        XCTAssertTrue(goLab.motionPermitted)

        // 5. "go to stairwell" MUST be DENIED by Envelope 0.2 keep-out gate even at L2_SUPERVISED.
        let goStairs = ConversationalExplorationSkill.evaluate(
            command: "go to stairwell",
            mapper: sim.mapper,
            pose: sim.pose,
            trustTier: .supervised,
            softwareHoldEngaged: false,
            health: .nominal
        )
        XCTAssertEqual(goStairs.decision, .deny)
        XCTAssertFalse(goStairs.motionPermitted)
        XCTAssertEqual(goStairs.gateViolator, "stairwell_dropoff")

        // 6. "stop" ALWAYS returns HOLD with zero motion and cites physical kill switch boundary.
        let stopOut = ConversationalExplorationSkill.evaluate(
            command: "stop",
            mapper: sim.mapper,
            pose: sim.pose,
            trustTier: .supervised,
            softwareHoldEngaged: false,
            health: .nominal
        )
        XCTAssertEqual(stopOut.decision, .hold)
        XCTAssertFalse(stopOut.motionPermitted)
        XCTAssertTrue(stopOut.summary.contains("ISO 13850"))
    }

    // MARK: - Dual Provenance SHA-256 Receipt Chain & Export

    func testDeterministicSHA256ReceiptChainAndProvenance() {
        let simManifest = EnvironmentFactorManifest.forSimulation()
        let hwManifest = EnvironmentFactorManifest.forPhysicalHardware()
        XCTAssertEqual(simManifest.mode, .simulation)
        XCTAssertEqual(hwManifest.mode, .physicalHardware)
        XCTAssertNotNil(simManifest.simulator)
        XCTAssertNil(hwManifest.simulator)
        XCTAssertFalse(simManifest.knownFactors.isEmpty)
        XCTAssertFalse(simManifest.unknownFactors.isEmpty)
        XCTAssertNotEqual(simManifest.canonicalSHA256(), hwManifest.canonicalSHA256())

        var chainA = MappingReceiptChain(sessionId: "sess-test-01", manifest: simManifest)
        var chainB = MappingReceiptChain(sessionId: "sess-test-01", manifest: simManifest)

        let rA1 = chainA.append(
            event: "monocular_ground_ingest",
            decision: .allow,
            pose: Pose2D(x: 1.3, y: 1.5, theta: 0.35),
            trustTier: .observe,
            activeZoneId: "zone_01",
            coveragePct: 14.5,
            telemetry: .nominal,
            gateViolator: nil,
            timestampISO: "2026-11-26T12:00:00Z"
        )
        let rB1 = chainB.append(
            event: "monocular_ground_ingest",
            decision: .allow,
            pose: Pose2D(x: 1.3, y: 1.5, theta: 0.35),
            trustTier: .observe,
            activeZoneId: "zone_01",
            coveragePct: 14.5,
            telemetry: .nominal,
            gateViolator: nil,
            timestampISO: "2026-11-26T12:00:00Z"
        )
        // Deterministic SHA-256 hash matches byte-for-byte across identical runs.
        XCTAssertEqual(rA1.hash, rB1.hash)
        XCTAssertEqual(rA1.hash.count, 64)

        _ = chainA.append(
            event: "stairwell_keepout_check",
            decision: .deny,
            pose: Pose2D(x: 2.1, y: 2.4, theta: 0.5),
            trustTier: .atomic,
            activeZoneId: "zone_01",
            coveragePct: 22.0,
            telemetry: .nominal,
            gateViolator: "stairwell_dropoff",
            timestampISO: "2026-11-26T12:00:05Z"
        )
        XCTAssertTrue(chainA.verifyChain())

        let bundle = chainA.exportBundle()
        XCTAssertEqual(bundle.schema, MonocularMappingConstants.bundleSchema)
        XCTAssertEqual(bundle.mode, .simulation)
        XCTAssertFalse(bundle.isPhysicalHardware)
        XCTAssertTrue(bundle.chainVerified)
        XCTAssertEqual(bundle.recordCount, 2)
        XCTAssertTrue(bundle.bundleSHA256.hasPrefix("sha256:"))
        XCTAssertTrue(bundle.safetyBoundaryStatement.contains("ISO 13850"))
    }

    // MARK: - Copy & Safe Sim Preset Checks

    func testSafeSimPresetAndCopyConventions() {
        var sim = MonocularMappingSimPreset()
        let seg1 = sim.mapper.segmentZones()
        XCTAssertGreaterThan(seg1.totalFreeCells, 0)
        XCTAssertGreaterThan(seg1.totalKeepoutCells, 0)

        let plan = sim.mapper.planNextFrontier(pose: sim.pose, health: .nominal)
        XCTAssertEqual(plan.decision, .allow)
        if let target = plan.selectedFrontier?.target {
            let proj = sim.stepToward(target)
            XCTAssertTrue(proj.accepted)
            XCTAssertEqual(sim.stepIndex, 1)
        }

        XCTAssertLessThanOrEqual(AutonomousMappingWords.studioRowLine.count, 60)
        XCTAssertTrue(AutonomousMappingWords.studioRowLine.hasSuffix("."))
        XCTAssertTrue(AutonomousMappingWords.holdSafetyNotice.contains("ISO 13850"))
        XCTAssertFalse(AutonomousMappingWords.infoSections.isEmpty)
    }
}
