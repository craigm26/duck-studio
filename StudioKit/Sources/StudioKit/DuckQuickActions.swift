import Foundation
import DuckEvidence

/// The four things a person can launch from the front door, and what happens
/// when they cannot.
///
/// WHY THIS IS A TYPE AND NOT A LIST IN A VIEW. "What can I launch" is the
/// sixth question the front door answers, and answering it is an intersection
/// of three facts that live in three different places: the seven roles a
/// Microduck's `robotd.toml` names, the files this particular bench happens to
/// hold, and whether the link in front of us has any way to load a policy at
/// all. `DriveView` already does two-thirds of that arithmetic in a private
/// `policy(filling:)` — matching a slot to a filename, with the
/// without-extension fallback a real bench needs — and a second screen writing
/// that match again is two matchers that disagree the first time somebody's
/// bench lists `alpha_walking` rather than `alpha_walking.onnx`. So the match
/// is here, once, and `filename(filling:among:)` is that function lifted
/// unchanged.
///
/// THE INTERESTING OUTPUT IS THE ONES THAT WILL NOT RUN. A quick-action grid
/// that silently omits everything unavailable is a grid that is empty on a
/// fresh install with no explanation, which is the exact "empty card" the house
/// rule forbids. So `Effect` has three cases and two of them are refusals with
/// sentences attached: a slot this bench does not fill, and a link that cannot
/// load a policy at all. A chip drawn from either says why when it is pressed
/// rather than doing nothing.
///
/// THE SLOTS ARE DUCKKIT'S AND THE ORDER IS DUCKKIT'S. `DuckOfficialPolicies.
/// Slot.allCases` is walk, stand, sitstand, ground_pick, kick_left, kick_right,
/// roulade — the order they are declared in, which is roughly the order of how
/// often somebody wants them — and taking the first four of that is a rule
/// anybody can predict. Sorting by anything else (most recently used, say)
/// would move controls around under a thumb between visits.
public enum DuckQuickActions {

    /// One chip.
    public struct Action: Equatable, Sendable, Identifiable {

        /// The role this fills on the robot. `robotd.toml`'s own key.
        public let slot: DuckOfficialPolicies.Slot

        /// What to call it. `Slot.title` — duckkit's word, not a second one.
        public let title: String

        /// The file this bench would actually load, when there is one. Nil for
        /// both refusals: a filename on an action that cannot run is a string
        /// somebody will eventually send.
        public let policyFilename: String?

        public let effect: Effect

        public var id: String { slot.rawValue }

        public init(slot: DuckOfficialPolicies.Slot, title: String,
                    policyFilename: String?, effect: Effect) {
            self.slot = slot
            self.title = title
            self.policyFilename = policyFilename
            self.effect = effect
        }

        /// Whether pressing this sends anything.
        public var runs: Bool {
            if case .loadsOnABench = effect { return true }
            return false
        }

        /// What to say when it does not. Nil when it does.
        public var reason: String? {
            switch effect {
            case .loadsOnABench: return nil
            case .notOnThisBench(let reason), .notCarried(let reason): return reason
            }
        }
    }

    /// What pressing a chip does.
    public enum Effect: Equatable, Sendable {

        /// `POST /policy` with this filename, and the bench swaps which network
        /// is driving without restarting the world.
        case loadsOnABench(filename: String)

        /// The link could load a policy; this bench does not hold one for this
        /// slot.
        case notOnThisBench(reason: String)

        /// The link has no way to load a policy at all.
        case notCarried(reason: String)
    }

    // MARK: - which slots exist in which mode

    /// The slots a robot in this drive mode actually has filled.
    ///
    /// ROLLER LEAVES STANDING OUT, AND THAT IS UPSTREAM'S DECISION RATHER THAN
    /// THIS FILE'S. `robotd.toml`'s roller preset puts `roller.onnx` in the
    /// locomotion slot and the crouch on the ground-pick trigger, and
    /// deliberately omits the standing network — duckkit records the reason in
    /// its own words: "standing transitions being skipped on wheels". A chip
    /// offering Stand on a duck with wheels on would be offering a network that
    /// is not loaded, and the refusal would come back from the bench looking
    /// like a fault.
    ///
    /// EVERYTHING ELSE SURVIVES THE MODE. The kicks, the roll and the sit are
    /// slots in both presets; what changes underneath is which file fills the
    /// two that roller replaces, and that is `filename(filling:among:)`'s
    /// problem rather than this one's.
    public static func slots(in mode: DuckOfficialPolicies.Mode)
        -> [DuckOfficialPolicies.Slot] {
        switch mode {
        case .walk: return DuckOfficialPolicies.Slot.allCases
        case .roller: return DuckOfficialPolicies.Slot.allCases.filter { $0 != .stand }
        }
    }

    // MARK: - can this link load a policy at all

    /// Whether a policy can be loaded over this link.
    ///
    /// THE ANSWER IS "ONLY A BENCH", AND THE REASON IS THAT LOADING A POLICY IS
    /// NOT IN THE VOCABULARY. `DuckMethod` is the complete list of what this
    /// app can say to a duck — hello, the driving surface, a state read, the
    /// pairing PIN, the updater — and none of them swaps a network. What does
    /// is `POST /policy`, which is duckbench's own endpoint and which
    /// `DriveView` is explicit about keeping bench-shaped: "three things do
    /// not [go through the peer], because no duck has them". So a link that is
    /// not a bench cannot load one, and saying otherwise on a chip would be
    /// promising a call that has no wire spelling.
    ///
    /// THE REACH IS STILL CONSULTED, AND NOT AS A FORMALITY. A bench peer that
    /// has narrowed its reach — which `DuckPeer` explicitly permits — is a
    /// bench this app cannot even read the outcome of a load from: the answer
    /// to `POST /policy` is a state block, and a peer that does not carry
    /// `studio.state` is one that has told us it has no state to give. Offering
    /// a swap whose result is unreadable is offering a control whose effect
    /// nobody can see.
    public static func carriesAPolicyLoad(transport: DuckTransportKind,
                                          reach: Set<DuckMethod>) -> Bool {
        guard transport == .bench else { return false }
        return reach.contains(.state)
    }

    /// What to say on a chip whose link cannot load anything.
    ///
    /// IT NAMES THE LINK, because "this does not work" is a sentence about the
    /// app and "Bluetooth does not carry a policy load" is a sentence about the
    /// world, and only the second one tells somebody what to change.
    public static func cannotLoadHere(_ transport: DuckTransportKind) -> String {
        "\(transport.label) cannot load a policy. Swapping which network drives the duck is "
      + "POST /policy on a bench, and it is not in the robot vocabulary this app speaks at all "
      + "— no transport carries a method for it. Connect a bench under Bench below, or drive "
      + "whatever is already loaded."
    }

    /// What to say on a chip whose slot this bench does not fill.
    ///
    /// NOT AN ACCUSATION, WHICH IS THE SAME NOTE `DuckOfficialPolicies.Standing`
    /// strikes about an unrecognised policy: a bench carrying somebody's own
    /// networks fills none of the official slots, and that is a legitimate
    /// bench rather than a broken one.
    public static func notHeldHere(_ slot: DuckOfficialPolicies.Slot) -> String {
        "This bench holds no policy for \(slot.title.lowercased()). That is not a fault — a "
      + "bench carrying networks somebody trained themselves fills none of the official slots, "
      + "and loading the wrong file would be worse than saying so. Copy the release into the "
      + "bench's policies folder and ask again — pull to refresh on My Microduck, or reopen "
      + "Control."
    }

    /// What to say where the chips would be, when there are none.
    ///
    /// THE "NOT YET" FOR THE WHOLE GRID, and it is a kit string for the reason
    /// every one of them is: a sentence composed in a view is a sentence
    /// nothing on Linux ever reads.
    public static let noneInstalled =
        "No quick actions yet. These are the official networks — walking, standing, the kicks, "
      + "the roll — and they appear here once a bench that holds them is connected. Nothing is "
      + "wrong; there is simply nothing yet to launch."

    // MARK: - the match

    /// Which of this bench's policies fills a slot.
    ///
    /// LIFTED VERBATIM FROM `DriveView.policy(filling:)`, INCLUDING THE
    /// FALLBACK, which is the part that earns its keep. Matched on the role
    /// name, which this app and the robot now share — the rename to Pollen's
    /// role names is what makes a bench's `alpha_sitstand` findable from
    /// `Slot.sitstand` at all. A bench often lists its policies without the
    /// `.onnx`, so an exact match is tried first and the stem second; a bench
    /// carrying somebody's own networks may fill none of them, and saying so
    /// beats loading the wrong one.
    public static func filename(filling slot: DuckOfficialPolicies.Slot,
                                among policies: [String]) -> String? {
        let wanted = DuckOfficialPolicies.releases.first { $0.slot == slot }?.filename
        if let wanted, let exact = policies.first(where: { $0 == wanted }) { return exact }
        // A bench often lists them without the extension.
        let stem = wanted.map { $0.replacingOccurrences(of: ".onnx", with: "") }
        return stem.flatMap { name in policies.first { $0 == name } }
    }

    /// One chip's worth of decision, for any slot.
    ///
    /// PUBLIC BECAUSE THE UNFILLED CASE HAS TO BE REACHABLE. `installed(...)`
    /// deliberately returns only the chips that will run, so `.notOnThisBench`
    /// would otherwise be a case in the type that nothing can produce — which
    /// is the same defect as a sentence nothing tests. A screen that wants to
    /// show a named slot whether or not the bench has it asks here.
    public static func action(filling slot: DuckOfficialPolicies.Slot,
                              among policies: [String],
                              reach: Set<DuckMethod>,
                              transport: DuckTransportKind) -> Action {
        guard carriesAPolicyLoad(transport: transport, reach: reach) else {
            return Action(slot: slot, title: slot.title, policyFilename: nil,
                          effect: .notCarried(reason: cannotLoadHere(transport)))
        }
        guard let file = filename(filling: slot, among: policies) else {
            return Action(slot: slot, title: slot.title, policyFilename: nil,
                          effect: .notOnThisBench(reason: notHeldHere(slot)))
        }
        return Action(slot: slot, title: slot.title, policyFilename: file,
                      effect: .loadsOnABench(filename: file))
    }

    /// The chips the front door draws, at most `limit` of them.
    ///
    /// TWO SHAPES OF ANSWER, AND THE DIFFERENCE IS DELIBERATE.
    ///
    /// On a link that CAN load a policy, this is the intersection: the slots
    /// this mode has, filtered to the ones this bench actually fills, first
    /// `limit` in slot order. A slot the bench does not hold produces no chip,
    /// because there is nothing to launch and a grid of dead chips is not a
    /// menu. When the intersection is empty the caller draws `noneInstalled`,
    /// which is the "not yet" for the whole surface.
    ///
    /// On a link that CANNOT, the chips are drawn anyway — first `limit` slots
    /// of the mode, every one of them `.notCarried`. That looks like the
    /// opposite decision and it is the same one: the question the grid answers
    /// is "what can I launch", and on a Bluetooth link the honest answer is
    /// "these four things, and not from here", which is information. Silence
    /// would leave somebody holding a paired robot wondering whether this app
    /// has quick actions at all. Nothing about these chips is inert: pressing
    /// one prints `cannotLoadHere`, which names the link and says what to
    /// change.
    ///
    /// A NON-POSITIVE `limit` IS AN EMPTY GRID, NOT A CRASH. `prefix` already
    /// answers that way; it is written down because a caller computing the
    /// limit from a screen width could reach zero.
    public static func installed(policies: [String],
                                 mode: DuckOfficialPolicies.Mode,
                                 reach: Set<DuckMethod>,
                                 transport: DuckTransportKind,
                                 limit: Int = 4) -> [Action] {
        guard limit > 0 else { return [] }
        let wanted = slots(in: mode)
        guard carriesAPolicyLoad(transport: transport, reach: reach) else {
            return wanted.prefix(limit).map { slot in
                action(filling: slot, among: policies, reach: reach, transport: transport)
            }
        }
        return wanted
            .compactMap { slot -> Action? in
                let one = action(filling: slot, among: policies,
                                 reach: reach, transport: transport)
                return one.runs ? one : nil
            }
            .prefix(limit)
            .map { $0 }
    }
}
