import Foundation

// MARK: - the rows a brain needs before it is offered

/// n passed out of N.
public struct Tally: Equatable, Hashable, Sendable, Codable {
    public let passed: Int
    public let of: Int

    public init(_ passed: Int, of: Int) {
        self.passed = passed
        self.of = of
    }

    public var line: String { "\(passed)/\(of)" }
}

/// p50 and p95, in milliseconds.
public struct Percentiles: Equatable, Hashable, Sendable, Codable {
    public let p50: Double
    public let p95: Double
    public init(p50: Double, p95: Double) { self.p50 = p50; self.p95 = p95 }
}

/// One measured result for one brain, pinned to its exact model version and date (section 7).
///
/// A server-side model change (a new Dream-1, a moved vendor alias) makes the row stale: the
/// offer rule then hides the card or labels it "untested version" until it is run again.
public struct EvidenceRow: Equatable, Hashable, Sendable, Codable {
    public let providerId: String
    public let modelVersion: String
    /// "YYYY-MM-DD".
    public let date: String
    public let venue: BrainVenue
    /// "M1" for walk to the ball.
    public let task: String
    /// Whether the assist was on. "+ assist" on a card needs this to be true.
    public let assist: Bool
    /// Whether the gate was on. Only a gated row can put a card in front of anybody.
    public let gated: Bool
    public let training: Tally
    public let holdout: Tally
    /// Zero twist or `.done`: the floor every number is read against.
    public let doNothingHoldout: Tally
    /// The scripted expert: the ceiling.
    public let oracleHoldout: Tally?
    public let crossingsBeforeGate: Int
    /// Must be 0 for a card to show.
    public let crossingsAfterGate: Int
    /// Gate interventions by rule id.
    public let interventions: [String: Int]
    /// Planners only: closed-set accuracy on the gold prompts (PlannerCheck p002 plus decision gold).
    public let closedSetGold: Tally?
    public let decisionLatencyMs: Percentiles?
    public let actLatencyMs: Percentiles?
    public let costPerRunUSD: Double?

    public init(providerId: String, modelVersion: String, date: String, venue: BrainVenue = .practice,
                task: String = "M1", assist: Bool = false, gated: Bool = true,
                training: Tally, holdout: Tally, doNothingHoldout: Tally, oracleHoldout: Tally? = nil,
                crossingsBeforeGate: Int = 0, crossingsAfterGate: Int = 0,
                interventions: [String: Int] = [:], closedSetGold: Tally? = nil,
                decisionLatencyMs: Percentiles? = nil, actLatencyMs: Percentiles? = nil,
                costPerRunUSD: Double? = nil) {
        self.providerId = providerId
        self.modelVersion = modelVersion
        self.date = date
        self.venue = venue
        self.task = task
        self.assist = assist
        self.gated = gated
        self.training = training
        self.holdout = holdout
        self.doNothingHoldout = doNothingHoldout
        self.oracleHoldout = oracleHoldout
        self.crossingsBeforeGate = crossingsBeforeGate
        self.crossingsAfterGate = crossingsAfterGate
        self.interventions = interventions
        self.closedSetGold = closedSetGold
        self.decisionLatencyMs = decisionLatencyMs
        self.actLatencyMs = actLatencyMs
        self.costPerRunUSD = costPerRunUSD
    }

    /// "11-20" from "2026-11-20", or nil when the date is not in that form.
    public var shortDate: String? {
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return nil }
        return "\(parts[1])-\(parts[2])"
    }
}

/// What a vendor's terms say, read by a person and dated (section 7).
///
/// An answer nobody could find is `.unknown`, and an unknown answer keeps the card hidden: the
/// risk table says a provider whose terms cannot be filled in is not offered.
public struct TermsRow: Equatable, Hashable, Sendable, Codable {
    public enum Answer: String, Equatable, Hashable, Sendable, Codable {
        case allowed, forbidden, unknown, notApplicable = "not_applicable"
    }

    public let providerId: String
    /// "YYYY-MM-DD", when a person read the terms.
    public let checked: String
    /// Where the terms were read.
    public let source: String
    /// May the service be used to control a physical device?
    public let physicalControl: Answer
    /// May a person's own key be used from a third-party app such as this one?
    public let byokInThirdPartyApp: Answer
    /// How long the vendor keeps robot camera frames, in words. Nil when it cannot be stated.
    public let imageRetention: String?
    /// Whether the vendor trains on the frames. Nil when unknown.
    public let trainsOnImages: Bool?
    /// The youngest age the terms allow. Nil when unknown.
    public let minimumAge: Int?
    /// Set only for a model that runs on the person's own devices (MLX on this phone, Ollama or
    /// LM Studio on their Mac): there is no vendor, and this names the licence the weights come
    /// under ("Apache-2.0", "Gemma Terms of Use"). Nil for a vendor's service and for this app's
    /// own code. Optional so rows stored before it existed still decode.
    public let localModelLicence: String?

    public init(providerId: String, checked: String, source: String, physicalControl: Answer,
                byokInThirdPartyApp: Answer, imageRetention: String?, trainsOnImages: Bool?,
                minimumAge: Int?, localModelLicence: String? = nil) {
        self.providerId = providerId
        self.checked = checked
        self.source = source
        self.physicalControl = physicalControl
        self.byokInThirdPartyApp = byokInThirdPartyApp
        self.imageRetention = imageRetention
        self.trainsOnImages = trainsOnImages
        self.minimumAge = minimumAge
        self.localModelLicence = localModelLicence
    }

    /// Whether a vendor stands behind this brain. A local model has none.
    public var hasVendor: Bool { localModelLicence == nil && byokInThirdPartyApp != .notApplicable }

    /// The row for a model that runs on the person's own devices.
    ///
    /// NO VENDOR MEANS NO VENDOR RETENTION, AND THAT IS WRITTEN DOWN, NOT ASSUMED. Nothing is
    /// sent to a company, so retention and training are answered ("nothing kept by a vendor",
    /// false), and a key in a third-party app does not apply. What does apply is the model's own
    /// licence, which a person reads and dates like any vendor's terms: whether it permits
    /// controlling a physical device, and any age limit. Until somebody has read it, pass
    /// `.unknown` and nil, and the card stays hidden.
    public static func localModel(_ providerId: String, checked: String, licence: String, source: String,
                                  physicalControl: Answer, minimumAge: Int?) -> TermsRow {
        TermsRow(providerId: providerId, checked: checked, source: source,
                 physicalControl: physicalControl, byokInThirdPartyApp: .notApplicable,
                 imageRetention: "No vendor. Nothing is kept anywhere but your own devices.",
                 trainsOnImages: false, minimumAge: minimumAge, localModelLicence: licence)
    }

    /// The row for this app's own code running on the phone: no vendor, no key, nothing sent.
    public static func ownCode(_ providerId: String, checked: String) -> TermsRow {
        TermsRow(providerId: providerId, checked: checked, source: "this app",
                 physicalControl: .allowed, byokInThirdPartyApp: .notApplicable,
                 imageRetention: "Nothing leaves this phone.", trainsOnImages: false, minimumAge: 0)
    }

    /// Whether every question has an answer and none of them forbids what the app would do.
    public func permits(key: KeyNeed) -> Bool {
        guard physicalControl == .allowed else { return false }
        switch key {
        case .byok:
            guard byokInThirdPartyApp == .allowed else { return false }
        case .none, .onBridge:
            guard byokInThirdPartyApp != .forbidden, byokInThirdPartyApp != .unknown else { return false }
        }
        return imageRetention != nil && trainsOnImages != nil && minimumAge != nil
    }
}

/// Whether a brain may run on a real duck. A separate row from the practice number, off by
/// default, and on only after a tester's run (manifest `enabled_on_robot`).
public struct RealDuckRow: Equatable, Hashable, Sendable, Codable {
    public let enabledOnRobot: Bool
    /// "YYYY-MM-DD" of the tester's run on a real duck. Nil until there is one.
    public let testerRunDate: String?
    /// Envelope crossings after the gate on that run. Must be 0.
    public let crossingsAfterGate: Int?

    public init(enabledOnRobot: Bool, testerRunDate: String?, crossingsAfterGate: Int?) {
        self.enabledOnRobot = enabledOnRobot
        self.testerRunDate = testerRunDate
        self.crossingsAfterGate = crossingsAfterGate
    }

    public static let off = RealDuckRow(enabledOnRobot: false, testerRunDate: nil, crossingsAfterGate: nil)

    public var isOn: Bool { enabledOnRobot && testerRunDate != nil && crossingsAfterGate == 0 }
}

// MARK: - the offer rule

/// Whether a brain's card shows, in which mode, and what it says (section 7). A kit table, so
/// every branch is a Linux test and the app only draws the answer.
public enum OfferRule {

    // THE BARS ARE THE PLAN'S PROPOSAL, NOT A DECISION YET. Section 11, question 4 asks Craig
    // whether 4/10 for Tell and 6/10 for Auto are right. Until he answers, they live here as
    // named numbers so changing them is one line and one test run.
    /// Tell: beat do-nothing on the holdout by at least this many out of 10.
    public static let tellMarginOutOf10 = 4
    /// Auto: beat do-nothing on the holdout by at least this many out of 10.
    public static let autoMarginOutOf10 = 6
    /// Whether Craig has confirmed the two bars above.
    public static let barsConfirmedByCraig = false
    /// A planner under this closed-set gold accuracy is Tell with a Go every time, never Auto.
    public static let goldPercentForAuto = 80
    /// The fewest holdout seeds a number can stand on (M1's fresh 10-seed holdout).
    public static let minimumHoldout = 10

    /// How a person confirms what an offered brain decided.
    public enum Confirmation: String, Equatable, Sendable {
        /// Tell's card with its countdown and Cancel.
        case countdown
        /// A Go tap for every decision.
        case goEveryTime
        /// Auto: a Go the first time a kind, skill or source is used, then within the envelope.
        case newKindsOnly
    }

    public struct Card: Equatable, Sendable {
        public let label: String
        /// "6/10 on the practice duck, 11-20"
        public let number: String
        public let confirmation: Confirmation
    }

    public enum Hidden: Equatable, Sendable {
        case noEvidence
        case noTerms
        case termsDoNotPermit
        case rowsForAnotherProvider
        case notAPracticeDuckRow
        case ungatedRow
        case undated
        case labelClaimsAssist
        case realDuckOff
        /// A local model whose version names no checkpoint (an Ollama tag, a repository with
        /// no commit). A tag moves when somebody pulls again, so no number can be pinned to it.
        case unpinnedLocalModel
        case holdoutTooSmall(Int)
        case crossingsAfterGate(Int)
        case belowBar(mode: BrainMode)
        case goldBelowAutoBar
    }

    public enum Offer: Equatable, Sendable {
        case offered(Card)
        /// Shown, labelled, and not runnable until the new version is measured.
        case untestedVersion(label: String, line: String)
        case hidden(Hidden)

        public var canRun: Bool { if case .offered = self { return true } else { return false } }
    }

    /// The offer for one brain, in one mode, at one venue.
    ///
    /// - `liveModelVersion` is what the device or vendor reports now. When it differs from the
    ///   row's, the card is "untested version" and cannot run.
    public static func offer(for brain: some BrainCard, mode: BrainMode, venue: BrainVenue,
                             liveModelVersion: String? = nil) -> Offer {
        guard let row = brain.evidence else { return .hidden(.noEvidence) }
        guard let terms = brain.terms else { return .hidden(.noTerms) }
        guard row.providerId == brain.id, terms.providerId == brain.id else {
            return .hidden(.rowsForAnotherProvider)
        }
        guard terms.permits(key: brain.key) else { return .hidden(.termsDoNotPermit) }
        // A LOCAL MODEL'S ROW IS PER CHECKPOINT. Its EvidenceRow is per model id plus the weights
        // it ran (digest or commit, which pins the quantisation), so a bare name cannot carry one.
        if terms.localModelLicence != nil,
           !LocalModelVersion.isPinned(brain.modelVersion) || !LocalModelVersion.isPinned(row.modelVersion) {
            return .hidden(.unpinnedLocalModel)
        }
        guard row.venue == .practice else { return .hidden(.notAPracticeDuckRow) }
        guard row.gated else { return .hidden(.ungatedRow) }
        guard let day = row.shortDate else { return .hidden(.undated) }
        if brain.label.contains("+ assist") && !row.assist { return .hidden(.labelClaimsAssist) }
        if venue == .real && !brain.realDuck.isOn { return .hidden(.realDuckOff) }
        guard row.crossingsAfterGate == 0 else { return .hidden(.crossingsAfterGate(row.crossingsAfterGate)) }
        guard row.holdout.of >= minimumHoldout, row.doNothingHoldout.of >= minimumHoldout else {
            return .hidden(.holdoutTooSmall(min(row.holdout.of, row.doNothingHoldout.of)))
        }

        let number = Words.number(row.holdout, day: day)
        let live = liveModelVersion ?? brain.modelVersion
        guard row.modelVersion == brain.modelVersion, live == brain.modelVersion else {
            return .untestedVersion(label: brain.label, line: Words.untested(row.holdout, day: day))
        }

        let bar = mode == .tell ? tellMarginOutOf10 : autoMarginOutOf10
        guard beats(row.holdout, row.doNothingHoldout, byOutOf10: bar) else {
            return .hidden(.belowBar(mode: mode))
        }

        var confirmation: Confirmation = mode == .tell ? .countdown : .newKindsOnly
        if isPlanner(brain), !goldPassesAutoBar(row.closedSetGold) {
            if mode == .auto { return .hidden(.goldBelowAutoBar) }
            confirmation = .goEveryTime
        }
        return .offered(Card(label: brain.label, number: number, confirmation: confirmation))
    }

    /// Whether `got` beats `floor` by at least `margin` out of 10, in exact integer arithmetic:
    /// got/Ng - floor/Nf >= margin/10.
    public static func beats(_ got: Tally, _ floor: Tally, byOutOf10 margin: Int) -> Bool {
        guard got.of > 0, floor.of > 0 else { return false }
        return 10 * (got.passed * floor.of - floor.passed * got.of) >= margin * got.of * floor.of
    }

    /// Whether a planner's gold accuracy reaches the Auto bar. A planner with no gold row has
    /// not shown it, so it does not.
    public static func goldPassesAutoBar(_ gold: Tally?) -> Bool {
        guard let gold, gold.of > 0 else { return false }
        return gold.passed * 100 >= goldPercentForAuto * gold.of
    }

    static func isPlanner(_ brain: some BrainCard) -> Bool { brain is PlannerInfo }

    /// The card's words. No arm or Robocurve number appears in any of them (section 7, copy).
    public enum Words {
        public static func number(_ t: Tally, day: String) -> String {
            "\(t.line) on the practice duck, \(day)"
        }

        public static func untested(_ t: Tally, day: String) -> String {
            "Untested version. \(t.line) on the practice duck, \(day), was for an earlier version."
        }

        public static let notYetOnARealDuck =
            "Not on a real duck yet. It needs a tester's run first."

        public static var all: [String] {
            [number(Tally(6, of: 10), day: "11-20"), untested(Tally(6, of: 10), day: "11-20"),
             notYetOnARealDuck]
        }
    }
}
