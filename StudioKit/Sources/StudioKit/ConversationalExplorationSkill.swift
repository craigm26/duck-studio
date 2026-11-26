import Foundation

/// Natural-language exploration skill backed by `MonocularGroundMapper`,
/// Envelope 0.2 keep-out gating, bipedal safety interlocks, and the Trust Ladder.
///
/// Every command — including *"discover the world"*, *"explore the hallway"*, *"go to lab"*,
/// and *"stop/hold"* — resolves deterministically inside `StudioKit` so Linux `swift test`
/// proves both intent routing and refusal copy before the iOS/macOS app draws a single pixel.
public enum ExplorationIntent: Sendable, Codable, Equatable {
    case hold(reason: String)
    case discoverWorld
    case exploreZone(query: String)
    case goToZone(query: String)
    case refused(reason: String)
}

public struct ExplorationGoalOutcome: Sendable, Codable, Equatable {
    public let rawCommand: String
    public let intent: ExplorationIntent
    public let decision: MappingDecision
    public let requiresHumanApproval: Bool
    public let motionPermitted: Bool
    public let targetZoneId: String?
    public let targetPoint: Point2D?
    public let sweptPath: [Point2D]
    public let gateViolator: String?
    public let summary: String
    public let frontierPlan: FrontierPlanResult?
    public let healthVerdict: BipedHealthVerdict?
}

public enum ConversationalExplorationSkill {

    /// Deterministic parser for plain-English exploration commands.
    /// Safety stop/hold commands ALWAYS take highest priority.
    public static func parse(_ raw: String) -> ExplorationIntent {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .refused(reason: "Say what to explore (for example: \"discover the world\", \"explore the hallway\", \"go to lab\", or \"stop\").")
        }
        let lower = trimmed.lowercased()

        // 1. Immediate HOLD / STOP always wins, even if mixed with other words.
        let stopTokens = ["stop", "hold", "halt", "freeze", "cancel", "e-stop", "estop", "emergency"]
        for token in stopTokens where containsWordOrPrefix(lower, token) {
            return .hold(reason: "Operator issued software HOLD command (\"\(trimmed)\").")
        }

        // 2. Global autonomous mapping ("discover the world", "map building", "explore everywhere")
        let discoverPhrases = [
            "discover the world", "discover world", "map the building", "map building",
            "explore the building", "explore everywhere", "map everything", "discover",
        ]
        if discoverPhrases.contains(where: { lower.contains($0) }) || lower == "explore" || lower == "map" {
            return .discoverWorld
        }

        // 3. Targeted navigation ("go to <place>", "visit <place>", "navigate to <place>", "walk to <place>")
        for prefix in ["go to ", "visit ", "navigate to ", "walk to ", "head to ", "move to "] {
            if let range = lower.range(of: prefix) {
                let target = cleanPlaceName(String(lower[range.upperBound...]))
                if !target.isEmpty {
                    return .goToZone(query: target)
                }
            }
        }

        // 4. Zone-scoped exploration ("explore <place>", "search <place>", "map <place>", "scan <place>")
        for prefix in ["explore ", "search ", "map ", "scan ", "check "] {
            if let range = lower.range(of: prefix) {
                let target = cleanPlaceName(String(lower[range.upperBound...]))
                if !target.isEmpty {
                    return .exploreZone(query: target)
                }
            }
        }

        return .refused(
            reason: "I didn't recognize \"\(trimmed)\". Try \"discover the world\", \"explore the hallway\", \"go to lab\", or \"stop\"."
        )
    }

    /// Route a natural-language command through HOLD latch, bipedal health interlocks,
    /// Envelope 0.2 keep-out swept-path checking, and the Trust Ladder.
    public static func evaluate(
        command: String,
        mapper: MonocularGroundMapper,
        pose: Pose2D,
        trustTier: MappingTrustTier,
        softwareHoldEngaged: Bool,
        health: BipedHealthTelemetry,
        nowS: Double? = nil,
        humanApprovedAtomicStep: Bool = false
    ) -> ExplorationGoalOutcome {
        let intent = parse(command)

        // 1. HOLD commands always execute immediately with zero motion.
        if case .hold(let reason) = intent {
            return ExplorationGoalOutcome(
                rawCommand: command,
                intent: intent,
                decision: .hold,
                requiresHumanApproval: false,
                motionPermitted: false,
                targetZoneId: nil,
                targetPoint: nil,
                sweptPath: [],
                gateViolator: nil,
                summary: "\(reason) Software HOLD pairs with — never replaces — your physical power/ISO 13850 kill switch.",
                frontierPlan: nil,
                healthVerdict: nil
            )
        }

        if case .refused(let reason) = intent {
            return ExplorationGoalOutcome(
                rawCommand: command,
                intent: intent,
                decision: .hold,
                requiresHumanApproval: false,
                motionPermitted: false,
                targetZoneId: nil,
                targetPoint: nil,
                sweptPath: [],
                gateViolator: nil,
                summary: reason,
                frontierPlan: nil,
                healthVerdict: nil
            )
        }

        // 2. Fail-closed if software HOLD latch is active.
        if softwareHoldEngaged {
            return ExplorationGoalOutcome(
                rawCommand: command,
                intent: intent,
                decision: .hold,
                requiresHumanApproval: false,
                motionPermitted: false,
                targetZoneId: nil,
                targetPoint: nil,
                sweptPath: [],
                gateViolator: "SOFTWARE_HOLD_LATCHED",
                summary: "Software HOLD is latched. Release HOLD only after verifying the physical area is clear.",
                frontierPlan: nil,
                healthVerdict: nil
            )
        }

        // 3. Bipedal safety interlocks (IMU tilt > 22°, battery < 7.0V, stale camera > 1.5s, human < 0.65m, E-stop).
        let healthVerdict = checkBipedHealth(health)
        if !healthVerdict.ok {
            return ExplorationGoalOutcome(
                rawCommand: command,
                intent: intent,
                decision: .hold,
                requiresHumanApproval: false,
                motionPermitted: false,
                targetZoneId: nil,
                targetPoint: nil,
                sweptPath: [],
                gateViolator: healthVerdict.faultCodes.first,
                summary: "Bipedal safety HOLD: \(healthVerdict.reasons.joined(separator: "; "))",
                frontierPlan: nil,
                healthVerdict: healthVerdict
            )
        }

        let seg = mapper.segmentZones()

        switch intent {
        case .discoverWorld:
            let plan = mapper.planNextFrontier(pose: pose, health: health, nowS: nowS)
            return applyTrustLadder(
                command: command,
                intent: intent,
                plan: plan,
                trustTier: trustTier,
                humanApprovedAtomicStep: humanApprovedAtomicStep,
                healthVerdict: healthVerdict
            )

        case .exploreZone(let query):
            if let keepoutHit = matchingKeepout(query: query, keepouts: mapper.keepoutZones) {
                let target = Point2D(
                    x: (keepoutHit.minX + keepoutHit.maxX) * 0.5,
                    y: (keepoutHit.minY + keepoutHit.maxY) * 0.5
                )
                let path = [Point2D(x: pose.x, y: pose.y), target]
                let gate = mapper.checkSweptPath2D(waypoints: path)
                return ExplorationGoalOutcome(
                    rawCommand: command,
                    intent: intent,
                    decision: .deny,
                    requiresHumanApproval: false,
                    motionPermitted: false,
                    targetZoneId: nil,
                    targetPoint: target,
                    sweptPath: path,
                    gateViolator: gate.violator ?? keepoutHit.name,
                    summary: "DENY: \"\(query)\" enters Envelope 0.2 keep-out \"\(keepoutHit.name)\" (stairwell/drop-off protection).",
                    frontierPlan: nil,
                    healthVerdict: healthVerdict
                )
            }
            let matchedZone = resolveZone(query: query, zones: seg.zones)
            let plan = mapper.planNextFrontier(
                pose: pose,
                health: health,
                nowS: nowS,
                preferredZoneId: matchedZone?.zoneId
            )
            return applyTrustLadder(
                command: command,
                intent: intent,
                plan: plan,
                trustTier: trustTier,
                humanApprovedAtomicStep: humanApprovedAtomicStep,
                healthVerdict: healthVerdict
            )

        case .goToZone(let query):
            // Check keep-out names explicitly so "go to stairwell" produces a deterministic Envelope 0.2 DENY.
            if let keepoutHit = matchingKeepout(query: query, keepouts: mapper.keepoutZones) {
                let target = Point2D(
                    x: (keepoutHit.minX + keepoutHit.maxX) * 0.5,
                    y: (keepoutHit.minY + keepoutHit.maxY) * 0.5
                )
                let path = [Point2D(x: pose.x, y: pose.y), target]
                let gate = mapper.checkSweptPath2D(waypoints: path)
                return ExplorationGoalOutcome(
                    rawCommand: command,
                    intent: intent,
                    decision: .deny,
                    requiresHumanApproval: false,
                    motionPermitted: false,
                    targetZoneId: nil,
                    targetPoint: target,
                    sweptPath: path,
                    gateViolator: gate.violator ?? keepoutHit.name,
                    summary: "DENY: Swept path to \"\(query)\" violates Envelope 0.2 keep-out \"\(keepoutHit.name)\".",
                    frontierPlan: nil,
                    healthVerdict: healthVerdict
                )
            }

            guard let targetZone = resolveZone(query: query, zones: seg.zones) else {
                let known = seg.zones.map { "\($0.roomLabel) (\($0.zoneId))" }.joined(separator: ", ")
                return ExplorationGoalOutcome(
                    rawCommand: command,
                    intent: intent,
                    decision: .hold,
                    requiresHumanApproval: false,
                    motionPermitted: false,
                    targetZoneId: nil,
                    targetPoint: nil,
                    sweptPath: [],
                    gateViolator: "UNKNOWN_ZONE",
                    summary: "No mapped zone matches \"\(query)\". Known zones: \(known.isEmpty ? "none mapped yet" : known).",
                    frontierPlan: nil,
                    healthVerdict: healthVerdict
                )
            }

            let path = [Point2D(x: pose.x, y: pose.y), targetZone.centroid]
            let gate = mapper.checkSweptPath2D(waypoints: path)
            if !gate.allowed {
                return ExplorationGoalOutcome(
                    rawCommand: command,
                    intent: intent,
                    decision: .deny,
                    requiresHumanApproval: false,
                    motionPermitted: false,
                    targetZoneId: targetZone.zoneId,
                    targetPoint: targetZone.centroid,
                    sweptPath: path,
                    gateViolator: gate.violator,
                    summary: "DENY: Swept path to \(targetZone.roomLabel) crosses keep-out \"\(gate.violator ?? "boundary")\".",
                    frontierPlan: nil,
                    healthVerdict: healthVerdict
                )
            }

            return gateMotionByTrustTier(
                command: command,
                intent: intent,
                targetZoneId: targetZone.zoneId,
                targetLabel: targetZone.roomLabel,
                targetPoint: targetZone.centroid,
                sweptPath: path,
                trustTier: trustTier,
                humanApprovedAtomicStep: humanApprovedAtomicStep,
                frontierPlan: nil,
                healthVerdict: healthVerdict
            )

        case .hold, .refused:
            // Handled above.
            return ExplorationGoalOutcome(
                rawCommand: command, intent: intent, decision: .hold,
                requiresHumanApproval: false, motionPermitted: false,
                targetZoneId: nil, targetPoint: nil, sweptPath: [], gateViolator: nil,
                summary: "Held.", frontierPlan: nil, healthVerdict: healthVerdict
            )
        }
    }

    // MARK: Trust Ladder Gating

    private static func applyTrustLadder(
        command: String,
        intent: ExplorationIntent,
        plan: FrontierPlanResult,
        trustTier: MappingTrustTier,
        humanApprovedAtomicStep: Bool,
        healthVerdict: BipedHealthVerdict
    ) -> ExplorationGoalOutcome {
        switch plan.decision {
        case .hold:
            return ExplorationGoalOutcome(
                rawCommand: command, intent: intent, decision: .hold,
                requiresHumanApproval: false, motionPermitted: false,
                targetZoneId: plan.activeZoneId, targetPoint: nil, sweptPath: [],
                gateViolator: plan.healthVerdict?.faultCodes.first,
                summary: plan.reason, frontierPlan: plan, healthVerdict: healthVerdict
            )
        case .deny:
            let violator = plan.rejectedCandidates.first?.gateViolator
            let rejectedPath = plan.rejectedCandidates.first?.sweptPath ?? []
            return ExplorationGoalOutcome(
                rawCommand: command, intent: intent, decision: .deny,
                requiresHumanApproval: false, motionPermitted: false,
                targetZoneId: plan.activeZoneId,
                targetPoint: plan.rejectedCandidates.first?.target,
                sweptPath: rejectedPath,
                gateViolator: violator,
                summary: plan.reason, frontierPlan: plan, healthVerdict: healthVerdict
            )
        case .complete:
            return ExplorationGoalOutcome(
                rawCommand: command, intent: intent, decision: .complete,
                requiresHumanApproval: false, motionPermitted: false,
                targetZoneId: plan.activeZoneId, targetPoint: nil, sweptPath: [],
                gateViolator: nil, summary: plan.reason, frontierPlan: plan, healthVerdict: healthVerdict
            )
        case .allow:
            guard let frontier = plan.selectedFrontier else {
                return ExplorationGoalOutcome(
                    rawCommand: command, intent: intent, decision: .hold,
                    requiresHumanApproval: false, motionPermitted: false,
                    targetZoneId: plan.activeZoneId, targetPoint: nil, sweptPath: [],
                    gateViolator: nil, summary: "No frontier selected.", frontierPlan: plan, healthVerdict: healthVerdict
                )
            }
            return gateMotionByTrustTier(
                command: command,
                intent: intent,
                targetZoneId: frontier.zoneId,
                targetLabel: "\(frontier.clusterId) in \(frontier.zoneId)",
                targetPoint: frontier.target,
                sweptPath: frontier.sweptPath,
                trustTier: trustTier,
                humanApprovedAtomicStep: humanApprovedAtomicStep,
                frontierPlan: plan,
                healthVerdict: healthVerdict
            )
        }
    }

    private static func gateMotionByTrustTier(
        command: String,
        intent: ExplorationIntent,
        targetZoneId: String,
        targetLabel: String,
        targetPoint: Point2D,
        sweptPath: [Point2D],
        trustTier: MappingTrustTier,
        humanApprovedAtomicStep: Bool,
        frontierPlan: FrontierPlanResult?,
        healthVerdict: BipedHealthVerdict
    ) -> ExplorationGoalOutcome {
        switch trustTier {
        case .observe:
            return ExplorationGoalOutcome(
                rawCommand: command,
                intent: intent,
                decision: .hold,
                requiresHumanApproval: true,
                motionPermitted: false,
                targetZoneId: targetZoneId,
                targetPoint: targetPoint,
                sweptPath: sweptPath,
                gateViolator: "TRUST_TIER_L0_OBSERVE",
                summary: "L0_OBSERVE (zero motion): planned \(targetLabel) cleared Envelope 0.2. Switch to L1_ATOMIC to approve one step.",
                frontierPlan: frontierPlan,
                healthVerdict: healthVerdict
            )
        case .atomic:
            if !humanApprovedAtomicStep {
                return ExplorationGoalOutcome(
                    rawCommand: command,
                    intent: intent,
                    decision: .hold,
                    requiresHumanApproval: true,
                    motionPermitted: false,
                    targetZoneId: targetZoneId,
                    targetPoint: targetPoint,
                    sweptPath: sweptPath,
                    gateViolator: "AWAITING_L1_HUMAN_APPROVAL",
                    summary: "L1_ATOMIC: Envelope 0.2 cleared \(targetLabel). Tap Approve Step to move one bounded step.",
                    frontierPlan: frontierPlan,
                    healthVerdict: healthVerdict
                )
            }
            return ExplorationGoalOutcome(
                rawCommand: command,
                intent: intent,
                decision: .allow,
                requiresHumanApproval: false,
                motionPermitted: true,
                targetZoneId: targetZoneId,
                targetPoint: targetPoint,
                sweptPath: sweptPath,
                gateViolator: nil,
                summary: "L1_ATOMIC ALLOW (human-approved): moving bounded step toward \(targetLabel).",
                frontierPlan: frontierPlan,
                healthVerdict: healthVerdict
            )
        case .supervised:
            return ExplorationGoalOutcome(
                rawCommand: command,
                intent: intent,
                decision: .allow,
                requiresHumanApproval: false,
                motionPermitted: true,
                targetZoneId: targetZoneId,
                targetPoint: targetPoint,
                sweptPath: sweptPath,
                gateViolator: nil,
                summary: "L2_SUPERVISED ALLOW: advancing toward \(targetLabel) inside Envelope 0.2.",
                frontierPlan: frontierPlan,
                healthVerdict: healthVerdict
            )
        }
    }

    // MARK: Zone & Keep-Out Matching Helpers

    private static func cleanPlaceName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        for article in ["the ", "a ", "an ", "my "] where s.hasPrefix(article) {
            s = String(s.dropFirst(article.count))
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsWordOrPrefix(_ text: String, _ token: String) -> Bool {
        if text == token { return true }
        let parts = text.split { !$0.isLetter && !$0.isNumber && $0 != "-" }
        return parts.contains { String($0) == token }
    }

    private static func matchingKeepout(query: String, keepouts: [Box2D]) -> Box2D? {
        let q = query.lowercased()
        let hazardWords = ["stair", "stairs", "stairwell", "dropoff", "drop-off", "cliff", "ledge", "keepout", "no-go"]
        if hazardWords.contains(where: { q.contains($0) }) {
            return keepouts.first
        }
        return keepouts.first {
            let n = $0.name.lowercased().replacingOccurrences(of: "_", with: " ")
            return n.contains(q) || q.contains(n)
        }
    }

    private static func resolveZone(query: String, zones: [ZoneSegment]) -> ZoneSegment? {
        let q = query.lowercased()
        if let exact = zones.first(where: {
            $0.roomLabel.lowercased() == q || $0.zoneId.lowercased() == q
        }) {
            return exact
        }
        if let normalized = zones.first(where: {
            $0.roomLabel.lowercased().contains(q)
                || q.contains($0.roomLabel.lowercased())
                || $0.zoneId.replacingOccurrences(of: "_0", with: " ").contains(q)
                || $0.zoneId.replacingOccurrences(of: "_", with: " ").contains(q)
        }) {
            return normalized
        }
        // Match by semantic tag inside the zone (e.g. "workbench").
        return zones.first { zone in
            zone.semanticLabels.keys.contains { $0.lowercased().contains(q) || q.contains($0.lowercased()) }
        }
    }
}

// MARK: - Tested Plain-English UI Copy (StudioKit presentation truth)

public enum AutonomousMappingWords {
    public static let screenTitle = "Autonomous Mapping"
    public static let studioRowTitle = "Autonomous mapping"
    public static let studioRowLine = "Monocular floor mapping, frontier search and keep-outs."
    public static let studioRowSymbol = "map.fill"

    public static let cameraBadge = "MONOCULAR GROUND-SEG · NO EXTRA LIDAR"
    public static let holdButtonTitle = "SOFTWARE HOLD"
    public static let holdReleaseTitle = "Release Software HOLD"
    public static let holdSafetyNotice =
        "Software HOLD stops commands in app and bridge. It pairs with — and NEVER replaces — "
      + "your hardwired power switch or ISO 13850 emergency stop."

    public static let goalPlaceholder = "Ask MicroDuck: \"discover the world\", \"explore the hallway\", \"go to lab\""
    public static let exampleCommands: [String] = [
        "Discover the world",
        "Explore the hallway",
        "Go to lab",
        "Go to stairwell",
        "Stop / Hold",
    ]

    public static let infoSheetTitle = "How Autonomous Mapping Works"
    public static let infoSections: [(title: String, body: String)] = [
        (
            "Single Camera, Zero Extra LiDAR",
            "MicroDuck projects segmented floor pixels from its onboard RGB camera onto the flat ground plane (z = 0) using calibrated pinhole geometry. Low-confidence or non-finite frames fail closed into HOLD."
        ),
        (
            "Segmented Rooms & Frontier Search",
            "Cleared floor cells are split at doorways into Zone 1..N. Frontier targets sit where known floor meets unknown space, prioritizing the robot's current room first."
        ),
        (
            "Envelope 0.2 Keep-Out Gate",
            "Every candidate swept path is checked deterministically against workspace walls and stairwell or drop-off keep-out boxes before motion is allowed. Any path entering a keep-out is denied."
        ),
        (
            "Trust Ladder & Bipedal Safety Interlocks",
            "Starts in L0_OBSERVE (zero motion). L1_ATOMIC requires your explicit Approve tap for each bounded step. IMU tilt over 22 deg, 2S LiPo sag under 7.0 V, or camera age over 1.5 s trigger fail-closed HOLD."
        ),
        (
            "Physical Kill Switch Boundary",
            "Software HOLD and SHA-256 receipts are audit and control layers. They pair with — and never replace — a hardwired battery cutoff or ISO 13850 emergency stop."
        ),
    ]
}
