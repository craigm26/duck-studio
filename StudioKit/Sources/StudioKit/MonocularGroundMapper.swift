import Foundation
import Crypto

/// Monocular ground-plane autonomous building mapper, segmented frontier search,
/// bipedal safety interlocks, Trust Ladder, and SHA-256 dual-demo receipt export.
///
/// DESIGN & SAFETY GUARANTEES (1:1 aligned with `robot-gate/src/robot_gate/microduck_mapper.py`):
/// - Single onboard RGB camera calibrated pinhole ground-plane (`z = 0`) ray projection
///   (`projectMonocularGroundMask`) — zero extra LiDAR required.
/// - Fail-closed on `NaN`/infinite intrinsics, poses, timestamps, telemetry, or low
///   ground-segmentation confidence (`< minConfidence`).
/// - 2D segmented occupancy grid (`unknown=0`, `free=1`, `obstacle=2`, `keepout=3`, plus
///   computed `frontier=4` overlay) with doorway-aware room/zone segmentation (`zone_01..N`).
/// - Deterministic Envelope 0.2 swept-path keep-out check blocking stairwell/drop-off/no-go frontiers.
/// - Bipedal safety interlocks: IMU tilt `> 22°`, 2S LiPo battery sag `< 7.0 V`, stale camera
///   `> 1.5 s`, human proximity `< 0.65 m`, servo overtemp `>= 65.0 °C`, or E-stop -> fail-closed HOLD.
/// - Trust Ladder defaults to `L0_OBSERVE` (zero motion).
/// - Software HOLD pairs with — and NEVER replaces — a hardwired power cutoff or ISO 13850 kill switch.
public enum MonocularMappingConstants {
    public static let defaultMinBatteryV: Double = 7.0
    public static let defaultMaxTiltDeg: Double = 22.0
    public static let defaultMaxCameraAgeS: Double = 1.5
    public static let defaultMinHumanDistanceM: Double = 0.65
    public static let defaultMaxServoTempC: Double = 65.0
    public static let defaultOperatingZM: Double = 0.20
    public static let defaultMinConfidence: Double = 0.65
    public static let genesisHash: String = String(repeating: "0", count: 64)
    public static let bundleSchema: String = "graft-microduck-dual-demo-bundle/1.0"
    public static let manifestSchema: String = "graft-microduck-environment-manifest/1.0"
    public static let safetyBoundaryStatement: String =
        "Software gates, HOLD buttons, and SHA-256 receipts pair with, and NEVER replace, "
      + "a hardwired power cutoff or ISO 13850 emergency stop switch."
}

// MARK: - Core Value Types

public enum OccupancyCellState: Int, Sendable, Codable, Equatable, Hashable {
    case unknown = 0
    case free = 1
    case obstacle = 2
    case keepout = 3
    case frontier = 4
}

public enum MappingDecision: String, Sendable, Codable, Equatable, Hashable {
    case allow = "ALLOW"
    case deny = "DENY"
    case hold = "HOLD"
    case complete = "COMPLETE"
}

public enum MappingTrustTier: String, CaseIterable, Identifiable, Sendable, Codable, Equatable, Hashable {
    case observe = "L0_OBSERVE"
    case atomic = "L1_ATOMIC"
    case supervised = "L2_SUPERVISED"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .observe: return "L0 Observe"
        case .atomic: return "L1 Atomic"
        case .supervised: return "L2 Supervised"
        }
    }

    public var plainEnglishDescription: String {
        switch self {
        case .observe:
            return "Zero-motion map-only mode. Builds the segmented map and shows candidate frontiers without moving the duck."
        case .atomic:
            return "Human-approved single step. Computes one bounded frontier step and waits for your explicit Approve tap."
        case .supervised:
            return "Supervised bounded exploration. Advances across cleared frontiers inside the Envelope 0.2 keep-out boundary while you supervise."
        }
    }

    public var permitsMotion: Bool { self != .observe }
}

public enum DualDemoMode: String, CaseIterable, Identifiable, Sendable, Codable, Equatable, Hashable {
    case simulation = "simulation"
    case physicalHardware = "physical_hardware"

    public var id: String { rawValue }

    public var badgeTitle: String {
        switch self {
        case .simulation: return "DIGITAL SIM"
        case .physicalHardware: return "PHYSICAL HARDWARE"
        }
    }

    public var pickerLabel: String {
        switch self {
        case .simulation: return "Safe Sim Preview"
        case .physicalHardware: return "Physical Hardware"
        }
    }
}

public struct Pose2D: Sendable, Codable, Equatable, Hashable {
    public let x: Double
    public let y: Double
    public let theta: Double

    public init(x: Double, y: Double, theta: Double) {
        self.x = x
        self.y = y
        self.theta = theta
    }

    public var isFinite: Bool { x.isFinite && y.isFinite && theta.isFinite }
    public var array: [Double] { [x, y, theta] }
}

public struct Point2D: Sendable, Codable, Equatable, Hashable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var isFinite: Bool { x.isFinite && y.isFinite }
}

public struct GridCell: Sendable, Codable, Equatable, Hashable, Comparable {
    public let col: Int
    public let row: Int

    public init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }

    public static func < (lhs: GridCell, rhs: GridCell) -> Bool {
        lhs.col != rhs.col ? lhs.col < rhs.col : lhs.row < rhs.row
    }
}

public struct Box2D: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let name: String
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double

    public var id: String { name }

    public init(name: String, minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.name = name
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var isValid: Bool {
        minX.isFinite && minY.isFinite && maxX.isFinite && maxY.isFinite
            && minX < maxX && minY < maxY
    }

    /// Signed distance to interior of box (negative inside, positive outside).
    public func signedOutsideDistance(x: Double, y: Double) -> Double {
        let dx = max(minX - x, 0.0, x - maxX)
        let dy = max(minY - y, 0.0, y - maxY)
        if dx > 0.0 || dy > 0.0 {
            return hypot(dx, dy)
        }
        // Inside box: return negative distance to nearest edge.
        let insideMargin = min(min(x - minX, maxX - x), min(y - minY, maxY - y))
        return -insideMargin
    }

    /// Signed clearance inside workspace bounds (positive inside, negative outside).
    public func signedInsideMargin(x: Double, y: Double) -> Double {
        min(min(x - minX, maxX - x), min(y - minY, maxY - y))
    }
}

// MARK: - Calibrated Pinhole Monocular Ground Projection

public struct MonocularCameraIntrinsics: Sendable, Codable, Equatable {
    public let fx: Double
    public let fy: Double
    public let cx: Double
    public let cy: Double
    public let imageWidth: Int
    public let imageHeight: Int
    public let cameraHeightM: Double
    /// Downward pitch angle in radians (positive tilts optical axis toward the floor).
    public let cameraPitchRad: Double
    public let maxRangeM: Double
    public let minConfidence: Double

    public init(
        fx: Double = 320.0,
        fy: Double = 320.0,
        cx: Double = 320.0,
        cy: Double = 240.0,
        imageWidth: Int = 640,
        imageHeight: Int = 480,
        cameraHeightM: Double = 0.24,
        cameraPitchRad: Double = 0.38,
        maxRangeM: Double = 3.5,
        minConfidence: Double = MonocularMappingConstants.defaultMinConfidence
    ) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.cameraHeightM = cameraHeightM
        self.cameraPitchRad = cameraPitchRad
        self.maxRangeM = maxRangeM
        self.minConfidence = minConfidence
    }

    public static let microDuckDefault = MonocularCameraIntrinsics()

    public var validationError: String? {
        let scalars = [fx, fy, cx, cy, cameraHeightM, cameraPitchRad, maxRangeM, minConfidence]
        guard scalars.allSatisfy(\.isFinite) else {
            return "NON_FINITE_INTRINSICS: camera intrinsics contain NaN or infinite values"
        }
        guard imageWidth > 0, imageHeight > 0 else {
            return "INVALID_INTRINSICS: image dimensions must be positive"
        }
        guard fx > 0.0, fy > 0.0 else {
            return "INVALID_INTRINSICS: focal lengths fx/fy must be strictly positive"
        }
        guard cameraHeightM > 0.0, maxRangeM > 0.0 else {
            return "INVALID_INTRINSICS: cameraHeightM and maxRangeM must be strictly positive"
        }
        guard abs(cameraPitchRad) < (.pi / 2.0) else {
            return "INVALID_INTRINSICS: cameraPitchRad must be strictly within (-pi/2, pi/2)"
        }
        guard minConfidence > 0.0, minConfidence <= 1.0 else {
            return "INVALID_INTRINSICS: minConfidence must be within (0, 1]"
        }
        return nil
    }
}

public enum MonocularMaskClass: String, Sendable, Codable, Equatable, Hashable {
    case floor
    case obstacle
    case keepout
    case unknown
}

public struct MonocularMaskSample: Sendable, Codable, Equatable {
    public let u: Double
    public let v: Double
    public let label: MonocularMaskClass
    public let confidence: Double
    public let semanticTag: String?

    public init(
        u: Double,
        v: Double,
        label: MonocularMaskClass,
        confidence: Double,
        semanticTag: String? = nil
    ) {
        self.u = u
        self.v = v
        self.label = label
        self.confidence = confidence
        self.semanticTag = semanticTag
    }
}

public struct ProjectedGroundPoint: Sendable, Codable, Equatable {
    public let u: Double
    public let v: Double
    public let world: Point2D
    public let rangeM: Double
    public let relativeAngleRad: Double
    public let label: MonocularMaskClass
    public let confidence: Double
    public let semanticTag: String?
}

public struct MonocularProjectionResult: Sendable, Codable, Equatable {
    public let accepted: Bool
    public let decision: MappingDecision
    public let reason: String
    public let meanConfidence: Double
    public let projectedPoints: [ProjectedGroundPoint]
    public let horizonRejectedCount: Int
    public let freeCellsUpdated: Int
    public let obstacleCellsUpdated: Int
    public let keepoutCellsUpdated: Int
    public let semanticTagsAttached: Int
}

public struct DepthRayObservation: Sendable, Codable, Equatable {
    public let angleRad: Double
    public let rangeM: Double
    public let hit: Bool
    public let tag: String?
    public let confidence: Double

    public init(angleRad: Double, rangeM: Double, hit: Bool, tag: String? = nil, confidence: Double = 1.0) {
        self.angleRad = angleRad
        self.rangeM = rangeM
        self.hit = hit
        self.tag = tag
        self.confidence = confidence
    }
}

public struct SemanticTagObservation: Sendable, Codable, Equatable {
    public let tag: String
    public let xM: Double
    public let yM: Double
    public let cell: GridCell
    public let timestampS: Double
    public let confidence: Double
}

// MARK: - Bipedal Safety Interlocks (1:1 with microduck_mapper.py)

public struct BipedHealthTelemetry: Sendable, Codable, Equatable {
    public let batteryV: Double
    public let imuRollDeg: Double
    public let imuPitchDeg: Double
    public let cameraAgeS: Double
    public let humanDistanceM: Double?
    public let servoMaxTempC: Double?
    public let estopOk: Bool

    public init(
        batteryV: Double,
        imuRollDeg: Double,
        imuPitchDeg: Double,
        cameraAgeS: Double,
        humanDistanceM: Double? = nil,
        servoMaxTempC: Double? = nil,
        estopOk: Bool = true
    ) {
        self.batteryV = batteryV
        self.imuRollDeg = imuRollDeg
        self.imuPitchDeg = imuPitchDeg
        self.cameraAgeS = cameraAgeS
        self.humanDistanceM = humanDistanceM
        self.servoMaxTempC = servoMaxTempC
        self.estopOk = estopOk
    }

    public static let nominal = BipedHealthTelemetry(
        batteryV: 7.85,
        imuRollDeg: 1.4,
        imuPitchDeg: -0.9,
        cameraAgeS: 0.12,
        humanDistanceM: 2.2,
        servoMaxTempC: 36.5,
        estopOk: true
    )
}

public struct BipedHealthThresholds: Sendable, Codable, Equatable {
    public let minBatteryV: Double
    public let maxTiltDeg: Double
    public let maxCameraAgeS: Double
    public let minHumanDistanceM: Double
    public let maxServoTempC: Double

    public init(
        minBatteryV: Double = MonocularMappingConstants.defaultMinBatteryV,
        maxTiltDeg: Double = MonocularMappingConstants.defaultMaxTiltDeg,
        maxCameraAgeS: Double = MonocularMappingConstants.defaultMaxCameraAgeS,
        minHumanDistanceM: Double = MonocularMappingConstants.defaultMinHumanDistanceM,
        maxServoTempC: Double = MonocularMappingConstants.defaultMaxServoTempC
    ) {
        self.minBatteryV = minBatteryV
        self.maxTiltDeg = maxTiltDeg
        self.maxCameraAgeS = maxCameraAgeS
        self.minHumanDistanceM = minHumanDistanceM
        self.maxServoTempC = maxServoTempC
    }

    public static let microDuckDefault = BipedHealthThresholds()
}

public struct BipedHealthVerdict: Sendable, Codable, Equatable {
    public let ok: Bool
    public let decision: MappingDecision
    public let faultCodes: [String]
    public let reasons: [String]
    public let thresholds: BipedHealthThresholds
}

public func checkBipedHealth(
    _ telemetry: BipedHealthTelemetry,
    thresholds: BipedHealthThresholds = .microDuckDefault
) -> BipedHealthVerdict {
    var faults: [String] = []
    var reasons: [String] = []

    if !telemetry.estopOk {
        faults.append("HARDWARE_ESTOP_ENGAGED")
        reasons.append("Hardware E-stop / cutoff state is not clear (estopOk=false)")
    }

    let required: [(String, Double)] = [
        ("battery_v", telemetry.batteryV),
        ("imu_roll_deg", telemetry.imuRollDeg),
        ("imu_pitch_deg", telemetry.imuPitchDeg),
        ("camera_age_s", telemetry.cameraAgeS),
    ]
    for (name, val) in required where !val.isFinite {
        if !faults.contains("NON_FINITE_TELEMETRY") {
            faults.append("NON_FINITE_TELEMETRY")
        }
        reasons.append("Required telemetry '\(name)' is non-finite")
    }
    if let h = telemetry.humanDistanceM, !h.isFinite {
        if !faults.contains("NON_FINITE_TELEMETRY") {
            faults.append("NON_FINITE_TELEMETRY")
        }
        reasons.append("human_distance_m is non-finite")
    }
    if let t = telemetry.servoMaxTempC, !t.isFinite {
        if !faults.contains("NON_FINITE_TELEMETRY") {
            faults.append("NON_FINITE_TELEMETRY")
        }
        reasons.append("servo_max_temp_c is non-finite")
    }

    if telemetry.batteryV.isFinite && telemetry.batteryV < thresholds.minBatteryV {
        faults.append("LOW_BATTERY_SAG")
        reasons.append(
            String(format: "2S LiPo voltage %.2fV below fail-closed floor %.2fV",
                   telemetry.batteryV, thresholds.minBatteryV)
        )
    }

    if telemetry.imuRollDeg.isFinite && abs(telemetry.imuRollDeg) > thresholds.maxTiltDeg {
        faults.append("EXCESSIVE_IMU_TILT")
        reasons.append(
            String(format: "IMU roll %+.1f deg exceeds fall-risk limit +/-%.1f deg",
                   telemetry.imuRollDeg, thresholds.maxTiltDeg)
        )
    }

    if telemetry.imuPitchDeg.isFinite && abs(telemetry.imuPitchDeg) > thresholds.maxTiltDeg {
        if !faults.contains("EXCESSIVE_IMU_TILT") {
            faults.append("EXCESSIVE_IMU_TILT")
        }
        reasons.append(
            String(format: "IMU pitch %+.1f deg exceeds fall-risk limit +/-%.1f deg",
                   telemetry.imuPitchDeg, thresholds.maxTiltDeg)
        )
    }

    if telemetry.cameraAgeS.isFinite
        && (telemetry.cameraAgeS < 0.0 || telemetry.cameraAgeS > thresholds.maxCameraAgeS) {
        faults.append("STALE_CAMERA_FEED")
        reasons.append(
            String(format: "Camera age %.2fs violates freshness TTL [0.0, %.2f]s",
                   telemetry.cameraAgeS, thresholds.maxCameraAgeS)
        )
    }

    if let h = telemetry.humanDistanceM, h.isFinite, h < thresholds.minHumanDistanceM {
        faults.append("HUMAN_PROXIMITY_HOLD")
        reasons.append(
            String(format: "Human detected at %.2fm (< %.2fm safety radius)",
                   h, thresholds.minHumanDistanceM)
        )
    }

    if let temp = telemetry.servoMaxTempC, temp.isFinite, temp >= thresholds.maxServoTempC {
        faults.append("SERVO_OVERTEMP_HOLD")
        reasons.append(
            String(format: "Servo temperature %.1fC >= ceiling %.1fC",
                   temp, thresholds.maxServoTempC)
        )
    }

    let ok = faults.isEmpty
    return BipedHealthVerdict(
        ok: ok,
        decision: ok ? .allow : .hold,
        faultCodes: faults,
        reasons: reasons,
        thresholds: thresholds
    )
}

// MARK: - Zone Segmentation & Frontier Planning Types

public struct ZoneSegment: Sendable, Codable, Equatable, Identifiable {
    public let zoneId: String
    public let roomLabel: String
    public let freeCells: Int
    public let frontierCells: Int
    public let areaM2: Double
    public let coveragePct: Double
    public let centroid: Point2D
    public let boundsMin: Point2D
    public let boundsMax: Point2D
    public let semanticLabels: [String: Int]
    public let doorwayLinks: [String]
    public let complete: Bool

    public var id: String { zoneId }
}

public struct ZoneSegmentationResult: Sendable, Equatable {
    public let zones: [ZoneSegment]
    public let cellToZone: [GridCell: String]
    public let doorwayCells: Set<GridCell>
    public let globalCoveragePct: Double
    public let totalFreeCells: Int
    public let totalObstacleCells: Int
    public let totalKeepoutCells: Int
    public let totalFrontierCells: Int
}

public struct SweptPathVerdict: Sendable, Codable, Equatable {
    public let allowed: Bool
    public let minMarginM: Double
    public let violator: String?
    public let samplesChecked: Int
    public let kernel: String
}

public struct FrontierCandidate: Sendable, Codable, Equatable, Identifiable {
    public let clusterId: String
    public let zoneId: String
    public let inActiveZone: Bool
    public let target: Point2D
    public let informationGain: Int
    public let distanceM: Double
    public let score: Double
    public let sweptPath: [Point2D]
    public let gateAllowed: Bool
    public let gateMinMarginM: Double
    public let gateViolator: String?
    public let gateSamplesChecked: Int
    public let gateKernel: String

    public var id: String { clusterId }
}

public struct FrontierPlanResult: Sendable, Codable, Equatable {
    public let decision: MappingDecision
    public let reason: String
    public let activeZoneId: String?
    public let selectedFrontier: FrontierCandidate?
    public let rejectedCandidates: [FrontierCandidate]
    public let allCandidatesConsidered: Int
    public let healthVerdict: BipedHealthVerdict?
    public let kernel: String
}

// MARK: - Dual Provenance Environment Manifest & SHA-256 Receipt Chain

public struct EnvironmentFactorManifest: Sendable, Codable, Equatable {
    public let schema: String
    public let mode: DualDemoMode
    public let robotId: String
    public let simulator: String?
    public let cameraModel: String
    public let knownFactors: [String: String]
    public let unknownFactors: [String: String]
    public let safetyBoundaryStatement: String

    public static func forSimulation(
        robotId: String = "pollen-open-duck-mini",
        simulator: String = "DuckStudio Safe Sim Preview (Monocular Pinhole)",
        cameraModel: String = "virtual_pinhole_rgb_640x480_no_lidar"
    ) -> EnvironmentFactorManifest {
        EnvironmentFactorManifest(
            schema: MonocularMappingConstants.manifestSchema,
            mode: .simulation,
            robotId: robotId,
            simulator: simulator,
            cameraModel: cameraModel,
            knownFactors: [
                "provenance_mode": "simulation",
                "sensor_modality": "single_monocular_rgb_ground_segmentation_no_extra_lidar",
                "grid_resolution_m": "0.10",
                "workspace_and_stairwell_keepout_boxes": "exact_known_2d_envelope_0_2",
                "imu_roll_pitch_limit_deg": "22.0",
                "battery_voltage_floor_v": "7.0",
                "sensor_freshness_ttl_s": "1.5",
            ],
            unknownFactors: [
                "real_floor_friction_and_carpet_pile": "unmodeled_flat_plane_proxy",
                "ambient_lighting_glare_and_rolling_shutter_blur": "not_simulated",
                "feetech_servo_gear_backlash_and_thermal_drift": "idealized_motion_step",
                "monocular_segmentation_false_positives_on_mirrors": "synthetic_mask_only",
                "unmapped_dynamic_humans_pets_and_cables": "excluded_unless_injected",
            ],
            safetyBoundaryStatement: MonocularMappingConstants.safetyBoundaryStatement
        )
    }

    public static func forPhysicalHardware(
        robotId: String = "pollen-open-duck-mini",
        cameraModel: String = "pi_csi_or_uvc_onboard_rgb_camera"
    ) -> EnvironmentFactorManifest {
        EnvironmentFactorManifest(
            schema: MonocularMappingConstants.manifestSchema,
            mode: .physicalHardware,
            robotId: robotId,
            simulator: nil,
            cameraModel: cameraModel,
            knownFactors: [
                "provenance_mode": "physical_hardware",
                "sensor_modality": "single_monocular_rgb_ground_segmentation_no_extra_lidar",
                "grid_resolution_m": "0.10",
                "workspace_and_stairwell_keepout_boxes": "tape_measured_envelope_0_2",
                "imu_roll_pitch_limit_deg": "22.0",
                "battery_voltage_floor_v": "7.0",
                "sensor_freshness_ttl_s": "1.5",
                "hardwired_cutoff_switch": "operator_confirmed_iso13850_physical_cutoff",
            ],
            unknownFactors: [
                "unmeasured_floor_irregularities_and_rug_edges": "live_physical_environment",
                "ambient_window_glare_and_low_light_motion_blur": "live_camera_noise",
                "odometry_slip_on_hardwood_or_tile": "uncalibrated_foot_slip_drift",
                "dynamic_household_obstacles_pets_and_humans": "uncontrolled_world",
                "transient_2s_lipo_current_spikes_and_servo_backlash": "real_electro_mechanical_wear",
            ],
            safetyBoundaryStatement: MonocularMappingConstants.safetyBoundaryStatement
        )
    }

    public func canonicalSHA256() -> String {
        MonocularGroundMapper.canonicalSHA256(self)
    }
}

public struct MappingHudOverlay: Sendable, Codable, Equatable {
    public let modeBadge: String
    public let mode: DualDemoMode
    public let trustTier: MappingTrustTier
    public let decision: MappingDecision
    public let activeZone: String
    public let coveragePct: Double
    public let poseXYTheta: [Double]
    public let batteryV: Double?
    public let imuRollDeg: Double?
    public let imuPitchDeg: Double?
    public let gateViolator: String?
}

public struct MappingReceiptBody: Sendable, Codable, Equatable {
    public let seq: Int
    public let timestampISO: String
    public let sessionId: String
    public let mode: DualDemoMode
    public let event: String
    public let decision: MappingDecision
    public let hudOverlay: MappingHudOverlay
    public let details: [String: String]
    public let prevHash: String
}

public struct MappingReceiptRecord: Sendable, Codable, Equatable, Identifiable {
    public let body: MappingReceiptBody
    public let hash: String

    public var id: Int { body.seq }
    public var hashPrefix: String { String(hash.prefix(12)) }
}

public struct MappingSessionBundle: Sendable, Codable, Equatable {
    public let schema: String
    public let sessionId: String
    public let mode: DualDemoMode
    public let isPhysicalHardware: Bool
    public let manifest: EnvironmentFactorManifest
    public let manifestSHA256: String
    public let safetyBoundaryStatement: String
    public let recordCount: Int
    public let chainHeadHash: String
    public let chainVerified: Bool
    public let records: [MappingReceiptRecord]
    public let bundleSHA256: String
}

public struct MappingReceiptChain: Sendable, Equatable {
    public let sessionId: String
    public let manifest: EnvironmentFactorManifest
    public private(set) var records: [MappingReceiptRecord] = []
    public private(set) var headHash: String = MonocularMappingConstants.genesisHash

    public init(sessionId: String, manifest: EnvironmentFactorManifest) {
        self.sessionId = sessionId
        self.manifest = manifest
    }

    @discardableResult
    public mutating func append(
        event: String,
        decision: MappingDecision,
        pose: Pose2D,
        trustTier: MappingTrustTier,
        activeZoneId: String?,
        coveragePct: Double,
        telemetry: BipedHealthTelemetry?,
        gateViolator: String?,
        details: [String: String] = [:],
        timestampISO: String = "2026-11-26T00:00:00Z"
    ) -> MappingReceiptRecord {
        let nextSeq = records.count + 1
        let hud = MappingHudOverlay(
            modeBadge: manifest.mode.badgeTitle,
            mode: manifest.mode,
            trustTier: trustTier,
            decision: decision,
            activeZone: activeZoneId ?? "none",
            coveragePct: (coveragePct * 100.0).rounded() / 100.0,
            poseXYTheta: pose.isFinite
                ? [
                    (pose.x * 10_000.0).rounded() / 10_000.0,
                    (pose.y * 10_000.0).rounded() / 10_000.0,
                    (pose.theta * 10_000.0).rounded() / 10_000.0,
                ]
                : [0.0, 0.0, 0.0],
            batteryV: telemetry.flatMap { $0.batteryV.isFinite ? ($0.batteryV * 100.0).rounded() / 100.0 : nil },
            imuRollDeg: telemetry.flatMap { $0.imuRollDeg.isFinite ? ($0.imuRollDeg * 100.0).rounded() / 100.0 : nil },
            imuPitchDeg: telemetry.flatMap { $0.imuPitchDeg.isFinite ? ($0.imuPitchDeg * 100.0).rounded() / 100.0 : nil },
            gateViolator: gateViolator
        )
        let body = MappingReceiptBody(
            seq: nextSeq,
            timestampISO: timestampISO,
            sessionId: sessionId,
            mode: manifest.mode,
            event: event,
            decision: decision,
            hudOverlay: hud,
            details: details,
            prevHash: headHash
        )
        let digest = MonocularGroundMapper.canonicalSHA256(body)
        let rec = MappingReceiptRecord(body: body, hash: digest)
        records.append(rec)
        headHash = digest
        return rec
    }

    public func verifyChain() -> Bool {
        var expectedPrev = MonocularMappingConstants.genesisHash
        for (idx, rec) in records.enumerated() {
            if rec.body.seq != idx + 1 { return false }
            if rec.body.mode != manifest.mode { return false }
            if rec.body.hudOverlay.mode != manifest.mode { return false }
            if rec.body.prevHash != expectedPrev { return false }
            let computed = MonocularGroundMapper.canonicalSHA256(rec.body)
            if rec.hash != computed { return false }
            expectedPrev = computed
        }
        return expectedPrev == headHash
    }

    public func exportBundle() -> MappingSessionBundle {
        let verified = verifyChain()
        let manifestSha = manifest.canonicalSHA256()
        struct UnsignedBundle: Codable {
            let schema: String
            let sessionId: String
            let mode: DualDemoMode
            let isPhysicalHardware: Bool
            let manifest: EnvironmentFactorManifest
            let manifestSHA256: String
            let safetyBoundaryStatement: String
            let recordCount: Int
            let chainHeadHash: String
            let chainVerified: Bool
            let records: [MappingReceiptRecord]
        }
        let unsigned = UnsignedBundle(
            schema: MonocularMappingConstants.bundleSchema,
            sessionId: sessionId,
            mode: manifest.mode,
            isPhysicalHardware: manifest.mode == .physicalHardware,
            manifest: manifest,
            manifestSHA256: manifestSha,
            safetyBoundaryStatement: MonocularMappingConstants.safetyBoundaryStatement,
            recordCount: records.count,
            chainHeadHash: headHash,
            chainVerified: verified,
            records: records
        )
        let bundleHash = "sha256:" + MonocularGroundMapper.canonicalSHA256(unsigned)
        return MappingSessionBundle(
            schema: unsigned.schema,
            sessionId: unsigned.sessionId,
            mode: unsigned.mode,
            isPhysicalHardware: unsigned.isPhysicalHardware,
            manifest: unsigned.manifest,
            manifestSHA256: unsigned.manifestSHA256,
            safetyBoundaryStatement: unsigned.safetyBoundaryStatement,
            recordCount: unsigned.recordCount,
            chainHeadHash: unsigned.chainHeadHash,
            chainVerified: unsigned.chainVerified,
            records: unsigned.records,
            bundleSHA256: bundleHash
        )
    }

    public func exportBundleJSON() -> String {
        let bundle = exportBundle()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(bundle),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

// MARK: - MonocularGroundMapper Core Engine

public struct MonocularGroundMapper: Sendable {
    public let widthM: Double
    public let heightM: Double
    public let resolutionM: Double
    public let origin: Point2D
    public let cols: Int
    public let rows: Int
    public let maxRangeM: Double
    public let sensorTTLS: Double
    public let minZoneCells: Int

    public private(set) var grid: [OccupancyCellState]
    public private(set) var keepoutZones: [Box2D] = []
    public private(set) var semanticObservations: [SemanticTagObservation] = []
    private var cellTags: [GridCell: Set<String>] = [:]
    public private(set) var zoneAliases: [String: String] = [:]
    public private(set) var lastObservationTimestampS: Double?
    public private(set) var lastPose: Pose2D?
    public private(set) var nearestHumanDistanceM: Double?
    public private(set) var observationCount: Int = 0

    public init(
        widthM: Double = 8.0,
        heightM: Double = 6.0,
        resolutionM: Double = 0.20,
        origin: Point2D = Point2D(x: 0.0, y: 0.0),
        maxRangeM: Double = 3.5,
        sensorTTLS: Double = MonocularMappingConstants.defaultMaxCameraAgeS,
        minZoneCells: Int = 3
    ) {
        let safeW = (widthM.isFinite && widthM > 0.0) ? widthM : 8.0
        let safeH = (heightM.isFinite && heightM > 0.0) ? heightM : 6.0
        let safeRes = (resolutionM.isFinite && resolutionM > 0.0) ? resolutionM : 0.20
        self.widthM = safeW
        self.heightM = safeH
        self.resolutionM = safeRes
        self.origin = origin.isFinite ? origin : Point2D(x: 0.0, y: 0.0)
        self.maxRangeM = (maxRangeM.isFinite && maxRangeM > 0.0) ? maxRangeM : 3.5
        self.sensorTTLS = (sensorTTLS.isFinite && sensorTTLS > 0.0) ? sensorTTLS : 1.5
        self.minZoneCells = max(1, minZoneCells)
        self.cols = max(1, Int(ceil(safeW / safeRes)))
        self.rows = max(1, Int(ceil(safeH / safeRes)))
        self.grid = Array(repeating: .unknown, count: self.cols * self.rows)
    }

    public var workspaceBounds: Box2D {
        Box2D(
            name: "workspace",
            minX: origin.x,
            minY: origin.y,
            maxX: origin.x + Double(cols) * resolutionM,
            maxY: origin.y + Double(rows) * resolutionM
        )
    }

    // MARK: Canonical SHA-256

    public static func canonicalSHA256<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else {
            return MonocularMappingConstants.genesisHash
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Grid Coordinates

    public func worldToCell(_ point: Point2D) -> GridCell {
        let col = Int(floor((point.x - origin.x) / resolutionM))
        let row = Int(floor((point.y - origin.y) / resolutionM))
        return GridCell(col: col, row: row)
    }

    public func cellToWorld(_ cell: GridCell) -> Point2D {
        Point2D(
            x: origin.x + (Double(cell.col) + 0.5) * resolutionM,
            y: origin.y + (Double(cell.row) + 0.5) * resolutionM
        )
    }

    public func inBounds(_ cell: GridCell) -> Bool {
        cell.col >= 0 && cell.col < cols && cell.row >= 0 && cell.row < rows
    }

    public func cellState(_ cell: GridCell) -> OccupancyCellState {
        guard inBounds(cell) else { return .obstacle }
        return grid[cell.row * cols + cell.col]
    }

    @discardableResult
    public mutating func setCell(
        _ cell: GridCell,
        state: OccupancyCellState,
        forceKeepoutOverride: Bool = false
    ) -> Bool {
        guard inBounds(cell) else { return false }
        let idx = cell.row * cols + cell.col
        if grid[idx] == .keepout && state != .keepout && !forceKeepoutOverride {
            return false
        }
        grid[idx] = state
        return true
    }

    @discardableResult
    public mutating func markKeepoutZone(_ zone: Box2D) -> Int {
        guard zone.isValid else { return 0 }
        if !keepoutZones.contains(where: { $0.name == zone.name }) {
            keepoutZones.append(zone)
        }
        let c0 = worldToCell(Point2D(x: zone.minX, y: zone.minY))
        let c1 = worldToCell(Point2D(x: zone.maxX - 1e-9, y: zone.maxY - 1e-9))
        var marked = 0
        let rLo = max(0, c0.row)
        let rHi = min(rows - 1, c1.row)
        let cLo = max(0, c0.col)
        let cHi = min(cols - 1, c1.col)
        if rLo <= rHi && cLo <= cHi {
            for r in rLo...rHi {
                for c in cLo...cHi {
                    if setCell(GridCell(col: c, row: r), state: .keepout, forceKeepoutOverride: true) {
                        marked += 1
                    }
                }
            }
        }
        return marked
    }

    public mutating func registerZoneAlias(zoneId: String, name: String) {
        zoneAliases[zoneId] = name
    }

    public mutating func attachSemanticTag(_ tag: String, at point: Point2D, timestampS: Double, confidence: Double = 1.0) {
        guard point.isFinite, timestampS.isFinite, confidence.isFinite else { return }
        let cell = worldToCell(point)
        let obs = SemanticTagObservation(
            tag: tag,
            xM: point.x,
            yM: point.y,
            cell: cell,
            timestampS: timestampS,
            confidence: confidence
        )
        semanticObservations.append(obs)
        if inBounds(cell) {
            cellTags[cell, default: []].insert(tag)
        }
    }

    // MARK: Pure Swift Calibrated Pinhole Ground-Plane (z=0) Ray Projection

    /// Project a single calibrated pinhole pixel `(u, v)` onto the floor plane `z = 0`.
    /// Returns `nil` for non-finite inputs, rays at/above the horizon (`rz >= -1e-4`), or ranges
    /// outside `(0.02, intrinsics.maxRangeM]`.
    public static func projectPixelToGround(
        u: Double,
        v: Double,
        pose: Pose2D,
        intrinsics: MonocularCameraIntrinsics
    ) -> (world: Point2D, rangeM: Double, relativeAngleRad: Double)? {
        guard intrinsics.validationError == nil,
              pose.isFinite,
              u.isFinite, v.isFinite,
              u >= 0.0, u <= Double(intrinsics.imageWidth),
              v >= 0.0, v <= Double(intrinsics.imageHeight) else {
            return nil
        }
        // Normalized camera optical ray: +X right, +Y down, +Z forward.
        let xn = (u - intrinsics.cx) / intrinsics.fx
        let yn = (v - intrinsics.cy) / intrinsics.fy
        // Robot body frame (+X forward, +Y left, +Z up), pitched down by `cameraPitchRad`.
        let cp = cos(intrinsics.cameraPitchRad)
        let sp = sin(intrinsics.cameraPitchRad)
        let rx = cp - yn * sp
        let ry = -xn
        let rz = -sp - yn * cp

        // Ray must point strictly downward to hit the floor plane z = 0 ahead of the camera.
        guard rz < -1e-4, rx > 1e-4 else { return nil }
        let t = -intrinsics.cameraHeightM / rz
        let gx = t * rx
        let gy = t * ry
        let range = hypot(gx, gy)
        guard range.isFinite, range > 0.02, range <= intrinsics.maxRangeM else { return nil }

        let ct = cos(pose.theta)
        let st = sin(pose.theta)
        let wx = pose.x + gx * ct - gy * st
        let wy = pose.y + gx * st + gy * ct
        guard wx.isFinite, wy.isFinite else { return nil }

        let relAngle = atan2(gy, gx)
        return (Point2D(x: wx, y: wy), range, relAngle)
    }

    /// Project a monocular ground-plane segmentation mask onto `z = 0` and fuse it into the
    /// 2D occupancy grid via deterministic Bresenham raycasting (zero extra LiDAR required).
    ///
    /// Fail-closed: rejects `NaN`/infinite intrinsics, poses, samples, stale frames, or
    /// low segmentation confidence (`< intrinsics.minConfidence`) before mutating any cell.
    @discardableResult
    public mutating func projectMonocularGroundMask(
        pose: Pose2D,
        intrinsics: MonocularCameraIntrinsics,
        samples: [MonocularMaskSample],
        timestampS: Double,
        nowS: Double? = nil
    ) -> MonocularProjectionResult {
        if let err = intrinsics.validationError {
            return MonocularProjectionResult(
                accepted: false, decision: .hold, reason: err,
                meanConfidence: 0.0, projectedPoints: [], horizonRejectedCount: 0,
                freeCellsUpdated: 0, obstacleCellsUpdated: 0, keepoutCellsUpdated: 0, semanticTagsAttached: 0
            )
        }
        guard pose.isFinite else {
            return MonocularProjectionResult(
                accepted: false, decision: .hold,
                reason: "NON_FINITE_POSE: pose contains NaN or infinite values",
                meanConfidence: 0.0, projectedPoints: [], horizonRejectedCount: 0,
                freeCellsUpdated: 0, obstacleCellsUpdated: 0, keepoutCellsUpdated: 0, semanticTagsAttached: 0
            )
        }
        guard timestampS.isFinite, timestampS >= 0.0 else {
            return MonocularProjectionResult(
                accepted: false, decision: .hold,
                reason: "NON_FINITE_TIMESTAMP: invalid timestampS",
                meanConfidence: 0.0, projectedPoints: [], horizonRejectedCount: 0,
                freeCellsUpdated: 0, obstacleCellsUpdated: 0, keepoutCellsUpdated: 0, semanticTagsAttached: 0
            )
        }
        if let now = nowS {
            guard now.isFinite else {
                return MonocularProjectionResult(
                    accepted: false, decision: .hold,
                    reason: "NON_FINITE_CLOCK: invalid nowS",
                    meanConfidence: 0.0, projectedPoints: [], horizonRejectedCount: 0,
                    freeCellsUpdated: 0, obstacleCellsUpdated: 0, keepoutCellsUpdated: 0, semanticTagsAttached: 0
                )
            }
            let age = now - timestampS
            if age < -0.05 || age > sensorTTLS {
                return MonocularProjectionResult(
                    accepted: false, decision: .hold,
                    reason: String(format: "STALE_CAMERA_OBSERVATION: age %.2fs exceeds TTL %.2fs", age, sensorTTLS),
                    meanConfidence: 0.0, projectedPoints: [], horizonRejectedCount: 0,
                    freeCellsUpdated: 0, obstacleCellsUpdated: 0, keepoutCellsUpdated: 0, semanticTagsAttached: 0
                )
            }
        }
        guard !samples.isEmpty else {
            return MonocularProjectionResult(
                accepted: false, decision: .hold,
                reason: "EMPTY_GROUND_MASK: no monocular segmentation samples provided",
                meanConfidence: 0.0, projectedPoints: [], horizonRejectedCount: 0,
                freeCellsUpdated: 0, obstacleCellsUpdated: 0, keepoutCellsUpdated: 0, semanticTagsAttached: 0
            )
        }

        // Atomic pre-validation before any grid mutation.
        var confSum = 0.0
        for sample in samples {
            guard sample.u.isFinite, sample.v.isFinite, sample.confidence.isFinite,
                  sample.confidence >= 0.0, sample.confidence <= 1.0 else {
                return MonocularProjectionResult(
                    accepted: false, decision: .hold,
                    reason: "NON_FINITE_MASK_SAMPLE: sample contains NaN/Inf or out-of-range confidence",
                    meanConfidence: 0.0, projectedPoints: [], horizonRejectedCount: 0,
                    freeCellsUpdated: 0, obstacleCellsUpdated: 0, keepoutCellsUpdated: 0, semanticTagsAttached: 0
                )
            }
            confSum += sample.confidence
        }
        let meanConf = confSum / Double(samples.count)
        guard meanConf >= intrinsics.minConfidence else {
            return MonocularProjectionResult(
                accepted: false, decision: .hold,
                reason: String(
                    format: "LOW_SEGMENTATION_CONFIDENCE: mean confidence %.2f < floor %.2f",
                    meanConf, intrinsics.minConfidence
                ),
                meanConfidence: meanConf, projectedPoints: [], horizonRejectedCount: 0,
                freeCellsUpdated: 0, obstacleCellsUpdated: 0, keepoutCellsUpdated: 0, semanticTagsAttached: 0
            )
        }

        var projected: [ProjectedGroundPoint] = []
        var horizonRejected = 0
        for sample in samples {
            guard sample.confidence >= intrinsics.minConfidence, sample.label != .unknown else {
                continue
            }
            guard let hit = Self.projectPixelToGround(u: sample.u, v: sample.v, pose: pose, intrinsics: intrinsics) else {
                horizonRejected += 1
                continue
            }
            projected.append(ProjectedGroundPoint(
                u: sample.u,
                v: sample.v,
                world: hit.world,
                rangeM: hit.rangeM,
                relativeAngleRad: hit.relativeAngleRad,
                label: sample.label,
                confidence: sample.confidence,
                semanticTag: sample.semanticTag
            ))
        }

        guard !projected.isEmpty else {
            return MonocularProjectionResult(
                accepted: false, decision: .hold,
                reason: "NO_VALID_GROUND_PROJECTIONS: all mask samples were low-confidence or above horizon",
                meanConfidence: meanConf, projectedPoints: [], horizonRejectedCount: horizonRejected,
                freeCellsUpdated: 0, obstacleCellsUpdated: 0, keepoutCellsUpdated: 0, semanticTagsAttached: 0
            )
        }

        // Commit validated ground projections to 2D occupancy grid.
        let startCell = worldToCell(Point2D(x: pose.x, y: pose.y))
        var freeUpdated = 0
        var obsUpdated = 0
        var keepoutUpdated = 0
        var tagsAttached = 0

        if inBounds(startCell), cellState(startCell) != .keepout, cellState(startCell) != .free {
            if setCell(startCell, state: .free) { freeUpdated += 1 }
        }

        var nearestHuman: Double? = nil
        for pt in projected {
            let endCell = worldToCell(pt.world)
            let line = Self.bresenham(from: startCell, to: endCell)
            switch pt.label {
            case .floor:
                for c in line {
                    if !inBounds(c) { break }
                    let cur = cellState(c)
                    if cur == .keepout { break }
                    if cur != .free, setCell(c, state: .free) {
                        freeUpdated += 1
                    }
                }
            case .obstacle:
                for c in line.dropLast() {
                    if !inBounds(c) { break }
                    let cur = cellState(c)
                    if cur == .keepout { break }
                    if cur != .free, setCell(c, state: .free) {
                        freeUpdated += 1
                    }
                }
                if inBounds(endCell), cellState(endCell) != .keepout, cellState(endCell) != .obstacle {
                    if setCell(endCell, state: .obstacle) { obsUpdated += 1 }
                }
            case .keepout:
                if inBounds(endCell), cellState(endCell) != .keepout {
                    if setCell(endCell, state: .keepout, forceKeepoutOverride: true) { keepoutUpdated += 1 }
                }
                attachSemanticTag(pt.semanticTag ?? "stairs_hazard", at: pt.world, timestampS: timestampS, confidence: pt.confidence)
                tagsAttached += 1
            case .unknown:
                break
            }

            if let tag = pt.semanticTag, pt.label != .keepout {
                attachSemanticTag(tag, at: pt.world, timestampS: timestampS, confidence: pt.confidence)
                tagsAttached += 1
                if tag == "human" {
                    let dist = hypot(pt.world.x - pose.x, pt.world.y - pose.y)
                    nearestHuman = nearestHuman.map { min($0, dist) } ?? dist
                }
            }
        }

        lastObservationTimestampS = timestampS
        lastPose = pose
        nearestHumanDistanceM = nearestHuman
        observationCount += 1

        return MonocularProjectionResult(
            accepted: true,
            decision: .allow,
            reason: "ok",
            meanConfidence: meanConf,
            projectedPoints: projected,
            horizonRejectedCount: horizonRejected,
            freeCellsUpdated: freeUpdated,
            obstacleCellsUpdated: obsUpdated,
            keepoutCellsUpdated: keepoutUpdated,
            semanticTagsAttached: tagsAttached
        )
    }

    /// Direct 2D ray ingestion matching `microduck_mapper.py` `ingest_camera_observation`.
    @discardableResult
    public mutating func ingestDepthRays(
        pose: Pose2D,
        rays: [DepthRayObservation],
        timestampS: Double,
        nowS: Double? = nil
    ) -> MappingDecision {
        guard pose.isFinite, timestampS.isFinite, timestampS >= 0.0 else { return .hold }
        if let now = nowS {
            guard now.isFinite else { return .hold }
            let age = now - timestampS
            if age < -0.05 || age > sensorTTLS { return .hold }
        }
        for ray in rays {
            guard ray.angleRad.isFinite, ray.rangeM.isFinite, ray.rangeM > 0.0, ray.confidence.isFinite else {
                return .hold
            }
        }
        let startCell = worldToCell(Point2D(x: pose.x, y: pose.y))
        if inBounds(startCell), cellState(startCell) != .keepout {
            setCell(startCell, state: .free)
        }
        for ray in rays {
            let clampedR = min(ray.rangeM, maxRangeM)
            let ex = pose.x + clampedR * cos(pose.theta + ray.angleRad)
            let ey = pose.y + clampedR * sin(pose.theta + ray.angleRad)
            let endCell = worldToCell(Point2D(x: ex, y: ey))
            let line = Self.bresenham(from: startCell, to: endCell)
            let freeSeg = ray.hit ? Array(line.dropLast()) : line
            for c in freeSeg {
                if !inBounds(c) { break }
                if cellState(c) == .keepout { break }
                setCell(c, state: .free)
            }
            if ray.hit, inBounds(endCell), cellState(endCell) != .keepout {
                setCell(endCell, state: .obstacle)
            }
            if let tag = ray.tag {
                attachSemanticTag(tag, at: Point2D(x: ex, y: ey), timestampS: timestampS, confidence: ray.confidence)
            }
        }
        lastObservationTimestampS = timestampS
        lastPose = pose
        observationCount += 1
        return .allow
    }

    // MARK: Bresenham Line

    public static func bresenham(from start: GridCell, to end: GridCell) -> [GridCell] {
        var points: [GridCell] = []
        let dc = abs(end.col - start.col)
        let dr = abs(end.row - start.row)
        let sc = start.col < end.col ? 1 : -1
        let sr = start.row < end.row ? 1 : -1
        var err = dc - dr
        var c = start.col
        var r = start.row
        while true {
            points.append(GridCell(col: c, row: r))
            if c == end.col && r == end.row { break }
            let e2 = 2 * err
            if e2 > -dr {
                err -= dr
                c += sc
            }
            if e2 < dc {
                err += dc
                r += sr
            }
        }
        return points
    }

    // MARK: Doorway-Aware Room / Zone Segmentation

    public func isFrontierCell(_ cell: GridCell) -> Bool {
        guard cellState(cell) == .free else { return false }
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        for (dc, dr) in dirs {
            let n = GridCell(col: cell.col + dc, row: cell.row + dr)
            if inBounds(n), cellState(n) == .unknown {
                return true
            }
        }
        return false
    }

    private func collectDoorwayBarrierCells() -> Set<GridCell> {
        let seeds = cellTags.compactMap { (cell, tags) -> GridCell? in
            (tags.contains("doorway") && inBounds(cell)) ? cell : nil
        }
        var barrier = Set(seeds)
        for seed in seeds {
            var horiz = [seed]
            for step in [-1, 1] {
                for k in 1...4 {
                    let nc = GridCell(col: seed.col + step * k, row: seed.row)
                    if !inBounds(nc) || cellState(nc) == .obstacle || cellState(nc) == .keepout {
                        break
                    }
                    horiz.append(nc)
                }
            }
            var vert = [seed]
            for step in [-1, 1] {
                for k in 1...4 {
                    let nr = GridCell(col: seed.col, row: seed.row + step * k)
                    if !inBounds(nr) || cellState(nr) == .obstacle || cellState(nr) == .keepout {
                        break
                    }
                    vert.append(nr)
                }
            }
            let throat = horiz.count <= vert.count ? horiz : vert
            barrier.formUnion(throat)
        }
        return barrier
    }

    public func segmentZones() -> ZoneSegmentationResult {
        let doorwayBarrier = collectDoorwayBarrierCells()
        var visited = Set<GridCell>()
        var rawComponents: [[GridCell]] = []

        for r in 0..<rows {
            for c in 0..<cols {
                let start = GridCell(col: c, row: r)
                if visited.contains(start) || doorwayBarrier.contains(start) || cellState(start) != .free {
                    continue
                }
                var comp: [GridCell] = []
                var queue: [GridCell] = [start]
                var qIdx = 0
                visited.insert(start)
                while qIdx < queue.count {
                    let cur = queue[qIdx]
                    qIdx += 1
                    comp.append(cur)
                    for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nxt = GridCell(col: cur.col + dc, row: cur.row + dr)
                        if inBounds(nxt), !visited.contains(nxt), !doorwayBarrier.contains(nxt),
                           cellState(nxt) == .free {
                            visited.insert(nxt)
                            queue.append(nxt)
                        }
                    }
                }
                rawComponents.append(comp)
            }
        }

        var major = rawComponents.filter { $0.count >= minZoneCells }
        var minor = rawComponents.filter { $0.count < minZoneCells }
        if major.isEmpty && !minor.isEmpty {
            major = minor
            minor = []
        }

        // Deterministic sort by centroid (x, y) then size descending.
        func compCentroid(_ cells: [GridCell]) -> (Double, Double) {
            let pts = cells.map { cellToWorld($0) }
            let cx = pts.reduce(0.0) { $0 + $1.x } / Double(pts.count)
            let cy = pts.reduce(0.0) { $0 + $1.y } / Double(pts.count)
            return ((cx * 1000.0).rounded() / 1000.0, (cy * 1000.0).rounded() / 1000.0)
        }
        major.sort { a, b in
            let ca = compCentroid(a), cb = compCentroid(b)
            if ca.0 != cb.0 { return ca.0 < cb.0 }
            if ca.1 != cb.1 { return ca.1 < cb.1 }
            return a.count > b.count
        }

        var cellToZone: [GridCell: String] = [:]
        var zoneCells: [String: [GridCell]] = [:]
        for (idx, comp) in major.enumerated() {
            let zid = String(format: "zone_%02d", idx + 1)
            zoneCells[zid] = comp
            for cell in comp { cellToZone[cell] = zid }
        }

        if !minor.isEmpty && !zoneCells.isEmpty {
            let centroids: [String: (Double, Double)] = zoneCells.mapValues { compCentroid($0) }
            for frag in minor {
                let fc = compCentroid(frag)
                if let nearest = centroids.min(by: {
                    hypot($0.value.0 - fc.0, $0.value.1 - fc.1) < hypot($1.value.0 - fc.0, $1.value.1 - fc.1)
                })?.key {
                    for cell in frag {
                        cellToZone[cell] = nearest
                        zoneCells[nearest, default: []].append(cell)
                    }
                }
            }
        }

        var doorwayLinks: [String: Set<String>] = [:]
        for zid in zoneCells.keys { doorwayLinks[zid] = [] }
        for dcCell in doorwayBarrier {
            var adj = Set<String>()
            for dx in -2...2 {
                for dy in -2...2 {
                    if let nz = cellToZone[GridCell(col: dcCell.col + dx, row: dcCell.row + dy)] {
                        adj.insert(nz)
                    }
                }
            }
            for z1 in adj {
                for z2 in adj where z1 != z2 {
                    doorwayLinks[z1, default: []].insert(z2)
                }
            }
        }

        var zones: [ZoneSegment] = []
        var totalFrontiers = 0
        let cellArea = resolutionM * resolutionM

        for (idx, zid) in zoneCells.keys.sorted().enumerated() {
            let cells = zoneCells[zid] ?? []
            let cellSet = Set(cells)
            let pts = cells.map { cellToWorld($0) }
            let cx = pts.reduce(0.0) { $0 + $1.x } / Double(max(1, pts.count))
            let cy = pts.reduce(0.0) { $0 + $1.y } / Double(max(1, pts.count))
            let minX = pts.map(\.x).min() ?? 0.0
            let maxX = pts.map(\.x).max() ?? 0.0
            let minY = pts.map(\.y).min() ?? 0.0
            let maxY = pts.map(\.y).max() ?? 0.0

            let frontiers = cells.filter { isFrontierCell($0) }.count
            totalFrontiers += frontiers

            let minC = cells.map(\.col).min() ?? 0
            let maxC = cells.map(\.col).max() ?? 0
            let minR = cells.map(\.row).min() ?? 0
            let maxR = cells.map(\.row).max() ?? 0
            var bboxUnknown = 0
            for rr in max(0, minR - 1)...min(rows - 1, maxR + 1) {
                for cc in max(0, minC - 1)...min(cols - 1, maxC + 1) {
                    if cellState(GridCell(col: cc, row: rr)) == .unknown {
                        bboxUnknown += 1
                    }
                }
            }
            let covPct: Double
            if frontiers == 0 {
                covPct = 100.0
            } else {
                let denom = max(1, cells.count + max(frontiers, bboxUnknown))
                covPct = min(99.5, (Double(cells.count) / Double(denom)) * 100.0)
            }

            var labelCounts: [String: Int] = [:]
            for obs in semanticObservations {
                if cellSet.contains(obs.cell) {
                    labelCounts[obs.tag, default: 0] += 1
                    continue
                }
                var adjacent = false
                outer: for dx in -2...2 {
                    for dy in -2...2 {
                        if cellSet.contains(GridCell(col: obs.cell.col + dx, row: obs.cell.row + dy)) {
                            adjacent = true
                            break outer
                        }
                    }
                }
                if adjacent {
                    labelCounts[obs.tag, default: 0] += 1
                }
            }

            let roomLabel = zoneAliases[zid] ?? "Zone \(idx + 1)"
            zones.append(ZoneSegment(
                zoneId: zid,
                roomLabel: roomLabel,
                freeCells: cells.count,
                frontierCells: frontiers,
                areaM2: Double(cells.count) * cellArea,
                coveragePct: covPct,
                centroid: Point2D(x: cx, y: cy),
                boundsMin: Point2D(x: minX, y: minY),
                boundsMax: Point2D(x: maxX, y: maxY),
                semanticLabels: labelCounts,
                doorwayLinks: Array(doorwayLinks[zid] ?? []).sorted(),
                complete: frontiers == 0
            ))
        }

        let freeCount = grid.filter { $0 == .free }.count
        let obsCount = grid.filter { $0 == .obstacle }.count
        let keepCount = grid.filter { $0 == .keepout }.count
        let explorable = max(1, grid.count - keepCount)
        let globalCov = min(100.0, (Double(freeCount + obsCount) / Double(explorable)) * 100.0)

        return ZoneSegmentationResult(
            zones: zones,
            cellToZone: cellToZone,
            doorwayCells: doorwayBarrier,
            globalCoveragePct: globalCov,
            totalFreeCells: freeCount,
            totalObstacleCells: obsCount,
            totalKeepoutCells: keepCount,
            totalFrontierCells: totalFrontiers
        )
    }

    // MARK: Envelope 0.2 Deterministic Swept-Path Keep-Out Check

    public func checkSweptPath2D(
        waypoints: [Point2D],
        workspace: Box2D? = nil,
        extraKeepouts: [Box2D] = [],
        samplesPerSegment: Int = 12
    ) -> SweptPathVerdict {
        let ws = workspace ?? workspaceBounds
        guard ws.isValid else {
            return SweptPathVerdict(
                allowed: false, minMarginM: -1.0,
                violator: "INVALID_WORKSPACE_BOUNDS", samplesChecked: 0,
                kernel: "swift:envelope_0_2"
            )
        }
        guard !waypoints.isEmpty, waypoints.allSatisfy(\.isFinite) else {
            return SweptPathVerdict(
                allowed: false, minMarginM: -1.0,
                violator: "NON_FINITE_WAYPOINT", samplesChecked: 0,
                kernel: "swift:envelope_0_2"
            )
        }
        var allKeepouts = keepoutZones
        for kz in extraKeepouts where !allKeepouts.contains(where: { $0.name == kz.name }) {
            guard kz.isValid else {
                return SweptPathVerdict(
                    allowed: false, minMarginM: -1.0,
                    violator: "INVALID_KEEPOUT_ZONE", samplesChecked: 0,
                    kernel: "swift:envelope_0_2"
                )
            }
            allKeepouts.append(kz)
        }

        let steps = max(2, samplesPerSegment)
        var minMargin = Double.greatestFiniteMagnitude
        var firstViolator: String? = nil
        var checked = 0

        func inspectPoint(_ p: Point2D) {
            checked += 1
            let wsMargin = ws.signedInsideMargin(x: p.x, y: p.y)
            if wsMargin < minMargin {
                minMargin = wsMargin
            }
            if wsMargin < 0.0 && firstViolator == nil {
                firstViolator = "workspace_boundary"
            }
            for kz in allKeepouts {
                let d = kz.signedOutsideDistance(x: p.x, y: p.y)
                if d < minMargin {
                    minMargin = d
                }
                if d <= 0.0 && firstViolator == nil {
                    firstViolator = kz.name
                }
            }
        }

        if waypoints.count == 1 {
            inspectPoint(waypoints[0])
        } else {
            for segIdx in 0..<(waypoints.count - 1) {
                let a = waypoints[segIdx]
                let b = waypoints[segIdx + 1]
                for s in 0...steps {
                    let frac = Double(s) / Double(steps)
                    let p = Point2D(
                        x: a.x + (b.x - a.x) * frac,
                        y: a.y + (b.y - a.y) * frac
                    )
                    inspectPoint(p)
                }
            }
        }

        let allowed = firstViolator == nil && minMargin >= 0.0
        return SweptPathVerdict(
            allowed: allowed,
            minMarginM: minMargin.isFinite ? minMargin : -1.0,
            violator: firstViolator,
            samplesChecked: checked,
            kernel: "swift:envelope_0_2"
        )
    }

    // MARK: Frontier Clustering & Segmented Search Planning

    private func clusterFrontiers(
        seg: ZoneSegmentationResult,
        workspace: Box2D
    ) -> [(zoneId: String, cells: [GridCell])] {
        var frontierSet = Set<GridCell>()
        for r in 0..<rows {
            for c in 0..<cols {
                let cell = GridCell(col: c, row: r)
                if isFrontierCell(cell) {
                    let w = cellToWorld(cell)
                    if w.x >= workspace.minX && w.x <= workspace.maxX
                        && w.y >= workspace.minY && w.y <= workspace.maxY {
                        frontierSet.insert(cell)
                    }
                }
            }
        }
        var visited = Set<GridCell>()
        var clusters: [(String, [GridCell])] = []
        for cell in frontierSet.sorted() {
            if visited.contains(cell) { continue }
            let zid = seg.cellToZone[cell] ?? "zone_unassigned"
            var cluster: [GridCell] = []
            var queue = [cell]
            var qIdx = 0
            visited.insert(cell)
            while qIdx < queue.count {
                let cur = queue[qIdx]
                qIdx += 1
                cluster.append(cur)
                for dc in -1...1 {
                    for dr in -1...1 {
                        if dc == 0 && dr == 0 { continue }
                        let n = GridCell(col: cur.col + dc, row: cur.row + dr)
                        if frontierSet.contains(n), !visited.contains(n),
                           (seg.cellToZone[n] ?? "zone_unassigned") == zid {
                            visited.insert(n)
                            queue.append(n)
                        }
                    }
                }
            }
            clusters.append((zid, cluster))
        }
        return clusters
    }

    public func planNextFrontier(
        pose: Pose2D,
        workspace: Box2D? = nil,
        extraKeepouts: [Box2D] = [],
        health: BipedHealthTelemetry? = nil,
        nowS: Double? = nil,
        preferredZoneId: String? = nil,
        samplesPerSegment: Int = 12
    ) -> FrontierPlanResult {
        let kernel = "swift:envelope_0_2"
        guard pose.isFinite else {
            return FrontierPlanResult(
                decision: .hold,
                reason: "NON_FINITE_POSE: robot pose contains NaN or infinite values",
                activeZoneId: nil, selectedFrontier: nil, rejectedCandidates: [],
                allCandidatesConsidered: 0, healthVerdict: nil, kernel: kernel
            )
        }
        let ws = workspace ?? workspaceBounds
        guard ws.isValid else {
            return FrontierPlanResult(
                decision: .hold,
                reason: "INVALID_WORKSPACE_BOUNDS: workspace min must be less than max",
                activeZoneId: nil, selectedFrontier: nil, rejectedCandidates: [],
                allCandidatesConsidered: 0, healthVerdict: nil, kernel: kernel
            )
        }

        var healthVerdict: BipedHealthVerdict? = nil
        if let h = health {
            let v = checkBipedHealth(h)
            healthVerdict = v
            if !v.ok {
                return FrontierPlanResult(
                    decision: .hold,
                    reason: "BIPED_HEALTH_HOLD: \(v.reasons.joined(separator: "; "))",
                    activeZoneId: nil, selectedFrontier: nil, rejectedCandidates: [],
                    allCandidatesConsidered: 0, healthVerdict: v, kernel: kernel
                )
            }
        }

        if let now = nowS {
            guard now.isFinite else {
                return FrontierPlanResult(
                    decision: .hold, reason: "NON_FINITE_CLOCK: invalid nowS",
                    activeZoneId: nil, selectedFrontier: nil, rejectedCandidates: [],
                    allCandidatesConsidered: 0, healthVerdict: healthVerdict, kernel: kernel
                )
            }
            guard let lastTs = lastObservationTimestampS else {
                return FrontierPlanResult(
                    decision: .hold, reason: "STALE_CAMERA_FEED: no camera observation ingested yet",
                    activeZoneId: nil, selectedFrontier: nil, rejectedCandidates: [],
                    allCandidatesConsidered: 0, healthVerdict: healthVerdict, kernel: kernel
                )
            }
            let age = now - lastTs
            if age < -0.05 || age > sensorTTLS {
                return FrontierPlanResult(
                    decision: .hold,
                    reason: String(format: "STALE_CAMERA_FEED: last observation age %.2fs > TTL %.2fs", age, sensorTTLS),
                    activeZoneId: nil, selectedFrontier: nil, rejectedCandidates: [],
                    allCandidatesConsidered: 0, healthVerdict: healthVerdict, kernel: kernel
                )
            }
        }

        let seg = segmentZones()
        let poseCell = worldToCell(Point2D(x: pose.x, y: pose.y))
        var activeZone = preferredZoneId ?? seg.cellToZone[poseCell]
        if activeZone == nil, let nearest = seg.zones.min(by: {
            hypot($0.centroid.x - pose.x, $0.centroid.y - pose.y)
                < hypot($1.centroid.x - pose.x, $1.centroid.y - pose.y)
        }) {
            activeZone = nearest.zoneId
        }

        let rawClusters = clusterFrontiers(seg: seg, workspace: ws)
        if rawClusters.isEmpty {
            return FrontierPlanResult(
                decision: .complete,
                reason: "No remaining frontier cells within workspace bounds",
                activeZoneId: activeZone, selectedFrontier: nil, rejectedCandidates: [],
                allCandidatesConsidered: 0, healthVerdict: healthVerdict, kernel: kernel
            )
        }

        struct ScoredRaw {
            let inActiveZone: Bool
            let score: Double
            let zoneId: String
            let target: Point2D
            let gain: Int
            let dist: Double
        }

        var scored: [ScoredRaw] = rawClusters.map { (zid, cells) in
            let pts = cells.map { cellToWorld($0) }
            let tx = pts.reduce(0.0) { $0 + $1.x } / Double(pts.count)
            let ty = pts.reduce(0.0) { $0 + $1.y } / Double(pts.count)
            let dist = hypot(tx - pose.x, ty - pose.y)
            let gain = cells.count
            let score = Double(gain) / max(dist, 0.20)
            let inActive = (activeZone != nil && zid == activeZone)
            return ScoredRaw(
                inActiveZone: inActive,
                score: score,
                zoneId: zid,
                target: Point2D(x: tx, y: ty),
                gain: gain,
                dist: dist
            )
        }

        scored.sort { a, b in
            if a.inActiveZone != b.inActiveZone { return a.inActiveZone && !b.inActiveZone }
            if a.score != b.score { return a.score > b.score }
            return a.dist < b.dist
        }

        var selected: FrontierCandidate? = nil
        var rejected: [FrontierCandidate] = []

        for (idx, item) in scored.enumerated() {
            let path = [Point2D(x: pose.x, y: pose.y), item.target]
            let gate = checkSweptPath2D(
                waypoints: path,
                workspace: ws,
                extraKeepouts: extraKeepouts,
                samplesPerSegment: samplesPerSegment
            )
            let cand = FrontierCandidate(
                clusterId: String(format: "frontier_%02d", idx + 1),
                zoneId: item.zoneId,
                inActiveZone: item.inActiveZone,
                target: item.target,
                informationGain: item.gain,
                distanceM: item.dist,
                score: item.score,
                sweptPath: path,
                gateAllowed: gate.allowed,
                gateMinMarginM: gate.minMarginM,
                gateViolator: gate.violator,
                gateSamplesChecked: gate.samplesChecked,
                gateKernel: gate.kernel
            )
            if gate.allowed && selected == nil {
                selected = cand
            } else if !gate.allowed {
                rejected.append(cand)
            }
        }

        guard let winner = selected else {
            let violators = Array(Set(rejected.compactMap(\.gateViolator))).sorted()
            return FrontierPlanResult(
                decision: .deny,
                reason: "All \(scored.count) frontier candidate(s) denied by Envelope 0.2 keep-out gate (violators=\(violators))",
                activeZoneId: activeZone,
                selectedFrontier: nil,
                rejectedCandidates: rejected,
                allCandidatesConsidered: scored.count,
                healthVerdict: healthVerdict,
                kernel: kernel
            )
        }

        return FrontierPlanResult(
            decision: .allow,
            reason: String(
                format: "Selected %@ in %@ (gain=%d, dist=%.2fm, margin=%+.2fm)",
                winner.clusterId, winner.zoneId, winner.informationGain, winner.distanceM, winner.gateMinMarginM
            ),
            activeZoneId: activeZone,
            selectedFrontier: winner,
            rejectedCandidates: rejected,
            allCandidatesConsidered: scored.count,
            healthVerdict: healthVerdict,
            kernel: winner.gateKernel
        )
    }

    // MARK: Render Snapshot (UI-free presentation data for SwiftUI Canvas)

    public func displayCells() -> [OccupancyCellState] {
        var out = grid
        for r in 0..<rows {
            for c in 0..<cols {
                let cell = GridCell(col: c, row: r)
                if isFrontierCell(cell) {
                    out[r * cols + c] = .frontier
                }
            }
        }
        return out
    }
}

// MARK: - Built-in Safe Sim Preview Engine (for Xcode Preview / iOS Simulator / Mac app)

public struct MonocularSimCameraOverlayPatch: Sendable, Equatable, Identifiable {
    public let id: String
    /// Normalized camera viewport rectangle `[0, 1] x [0, 1]`.
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double
    public let label: MonocularMaskClass
    public let caption: String
    public let confidence: Double
}

public struct MonocularMappingSimPreset: Sendable {
    public var mapper: MonocularGroundMapper
    public private(set) var pose: Pose2D
    public private(set) var simClockS: Double = 0.0
    public private(set) var stepIndex: Int = 0
    public let intrinsics: MonocularCameraIntrinsics
    public let stairwellKeepout: Box2D

    public init() {
        var m = MonocularGroundMapper(
            widthM: 8.0,
            heightM: 6.0,
            resolutionM: 0.20,
            origin: Point2D(x: 0.0, y: 0.0),
            maxRangeM: 3.5,
            sensorTTLS: MonocularMappingConstants.defaultMaxCameraAgeS,
            minZoneCells: 4
        )
        let stairs = Box2D(name: "stairwell_dropoff", minX: 3.2, minY: 4.1, maxX: 5.0, maxY: 5.8)
        m.markKeepoutZone(stairs)

        // Seed building walls separating Hallway (left), Lab (center-bottom), and Lounge (right),
        // with doorways that split them into distinct semantic zones.
        for r in 0..<m.rows {
            // Outer boundary walls
            m.setCell(GridCell(col: 0, row: r), state: .obstacle)
            m.setCell(GridCell(col: m.cols - 1, row: r), state: .obstacle)
        }
        for c in 0..<m.cols {
            m.setCell(GridCell(col: c, row: 0), state: .obstacle)
            m.setCell(GridCell(col: c, row: m.rows - 1), state: .obstacle)
        }
        // Interior partition between Hallway (x < 2.8) and Lab (x > 2.8), leaving doorway at y = 2.0..2.8
        let wallCol = m.worldToCell(Point2D(x: 2.8, y: 0.0)).col
        for r in 1..<(m.rows - 1) {
            let wy = m.cellToWorld(GridCell(col: wallCol, row: r)).y
            if wy < 2.0 || wy > 2.8 {
                m.setCell(GridCell(col: wallCol, row: r), state: .obstacle)
            }
        }
        m.attachSemanticTag("doorway", at: Point2D(x: 2.8, y: 2.4), timestampS: 0.0)
        m.attachSemanticTag("workbench", at: Point2D(x: 5.4, y: 1.6), timestampS: 0.0)
        m.attachSemanticTag("stairs_hazard", at: Point2D(x: 4.1, y: 4.2), timestampS: 0.0)

        m.registerZoneAlias(zoneId: "zone_01", name: "Hallway")
        m.registerZoneAlias(zoneId: "zone_02", name: "Lab")
        m.registerZoneAlias(zoneId: "zone_03", name: "Lounge")

        self.mapper = m
        self.pose = Pose2D(x: 1.3, y: 1.5, theta: 0.35)
        self.intrinsics = .microDuckDefault
        self.stairwellKeepout = stairs
        self.ingestSyntheticCameraFrame()
    }

    /// Generates a calibrated monocular RGB ground-segmentation mask sample fan from the current pose.
    public func syntheticMaskSamples() -> [MonocularMaskSample] {
        var samples: [MonocularMaskSample] = []
        let uCols: [Double] = [140, 210, 280, 320, 360, 430, 500]
        let vRows: [Double] = [275, 315, 360, 415]
        for v in vRows {
            for u in uCols {
                guard let hit = MonocularGroundMapper.projectPixelToGround(
                    u: u, v: v, pose: pose, intrinsics: intrinsics
                ) else { continue }
                let cell = mapper.worldToCell(hit.world)
                let label: MonocularMaskClass
                let tag: String?
                if stairwellKeepout.signedOutsideDistance(x: hit.world.x, y: hit.world.y) <= 0.15 {
                    label = .keepout
                    tag = "stairs_hazard"
                } else if mapper.cellState(cell) == .obstacle {
                    label = .obstacle
                    tag = nil
                } else {
                    label = .floor
                    tag = nil
                }
                samples.append(MonocularMaskSample(
                    u: u, v: v, label: label, confidence: 0.91, semanticTag: tag
                ))
            }
        }
        return samples
    }

    @discardableResult
    public mutating func ingestSyntheticCameraFrame() -> MonocularProjectionResult {
        simClockS += 0.25
        let samples = syntheticMaskSamples()
        return mapper.projectMonocularGroundMask(
            pose: pose,
            intrinsics: intrinsics,
            samples: samples,
            timestampS: simClockS,
            nowS: simClockS + 0.05
        )
    }

    /// Moves the simulated MicroDuck one bounded step (`<= 0.55 m`) toward a target point
    /// and captures a fresh monocular ground-plane frame.
    @discardableResult
    public mutating func stepToward(_ target: Point2D, maxStepM: Double = 0.55) -> MonocularProjectionResult {
        let dx = target.x - pose.x
        let dy = target.y - pose.y
        let dist = hypot(dx, dy)
        let heading = dist > 1e-4 ? atan2(dy, dx) : pose.theta
        let move = min(dist, maxStepM)
        let nx = pose.x + move * cos(heading)
        let ny = pose.y + move * sin(heading)
        pose = Pose2D(x: nx, y: ny, theta: heading)
        stepIndex += 1
        return ingestSyntheticCameraFrame()
    }

    /// Computes normalized camera-view ground-segmentation mask patches for the UI overlay.
    public func cameraOverlayPatches(plan: FrontierPlanResult?) -> [MonocularSimCameraOverlayPatch] {
        let nearKeepout = stairwellKeepout.signedOutsideDistance(x: pose.x, y: pose.y) < 2.2
        var patches: [MonocularSimCameraOverlayPatch] = [
            MonocularSimCameraOverlayPatch(
                id: "floor-primary",
                minX: 0.08, minY: 0.52, width: 0.84, height: 0.42,
                label: .floor, caption: "Ground plane z=0 (0.91)", confidence: 0.91
            )
        ]
        if let f = plan?.selectedFrontier {
            patches.append(MonocularSimCameraOverlayPatch(
                id: "frontier-band",
                minX: 0.22, minY: 0.42, width: 0.56, height: 0.12,
                label: .unknown, caption: "Frontier \(f.clusterId) · \(f.zoneId)", confidence: 0.88
            ))
        }
        if nearKeepout || !(plan?.rejectedCandidates.isEmpty ?? true) {
            patches.append(MonocularSimCameraOverlayPatch(
                id: "keepout-stairs",
                minX: 0.62, minY: 0.34, width: 0.30, height: 0.22,
                label: .keepout, caption: "KEEPOUT: stairwell_dropoff", confidence: 0.97
            ))
        }
        return patches
    }
}
