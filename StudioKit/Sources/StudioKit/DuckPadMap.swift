import Foundation
import DuckEvidence

/// What this phone's pad is wired to, laid over the table `padd` ships.
///
/// THE PAD STOPPED BEING A GATE AND BECAME A MAP. Before this, the Control tab
/// refused to drive until somebody picked a policy out of a list, because
/// `/health` says what a bench HOLDS and never says what it has LOADED. That
/// refusal was honest and it was also the wrong shape: a bench always has
/// something on the servos, and the thing that names it comes back on every
/// single reply — `DuckDrive.Live.policy`, "which network is driving, as the
/// bench names it". So the gate is deleted rather than replaced by a better
/// guess, and two different claims are drawn as two different sentences: what
/// the sticks AIM at is this map's business, what is DRIVING is the bench's.
/// `drivingLine(mapped:benchSaid:)` is that split, and it prefers the
/// measurement every time it has one.
///
/// A MAP NAMES A ROLE, WHICH IS WHY IT IS PORTABLE. The shipped locomotion is
/// `.slot(.walk)` — "whatever fills Walk on whatever bench I am pointed at" —
/// resolved through `DuckQuickActions.filename(filling:among:)`, the one
/// matcher in this package. The one filename-valued case, `.named`, is the
/// exception and it is checked against what the bench holds every time this tab
/// opens; a name the bench does not hold is degraded with `staleNetwork(_:)`
/// rather than posted stale.
///
/// IT IS SPARSE OVER `DuckPad.bindings` RATHER THAN A RIVAL TO IT. An entry
/// missing from `buttons` falls through to the shipped table, so the table
/// stays the thing a remap is a departure FROM — `isCustom` is exactly that
/// difference — and `onTheRobot`, padd's words for what the ROBOT does,
/// survives every remap because it was never this type's to change.
///
/// NOTHING HERE POSTS ANYTHING. `settle(against:)` degrades what a bench cannot
/// honour and returns sentences; `toPost(among:lastLoaded:)` answers "one name,
/// or nothing" and the caller decides. Both are pure, which is why the
/// connect-undoes-a-quick-action bug is finally a Linux test instead of a
/// comment in a picker's `onChange`.
public struct DuckPadMap: Equatable, Sendable {

    public static let format = "duck-padmap/1"
    public static let readableFormats: Set<String> = ["duck-padmap/1"]

    /// What the sticks drive.
    ///
    /// `Hashable` AND NOT ONLY `Equatable`, because a SwiftUI `Picker` tags its
    /// rows with the selection type and `.tag` needs a hash. Every case's
    /// payload already hashes.
    public enum Locomotion: Hashable, Sendable {
        /// Whatever fills a slot ON THIS BENCH. The shipped default, and the
        /// reason a map is portable: it names a ROLE, not a file.
        case slot(DuckOfficialPolicies.Slot)
        /// A network somebody picked by name, on some bench, once.
        case named(String)
        /// Whatever the bench already has. Nothing is ever posted for this.
        case whateverIsLoaded
    }

    /// What a control does here.
    public enum Effect: Equatable, Sendable {
        case loadSlot(DuckOfficialPolicies.Slot)
        /// A sequence, optionally followed by a slot load — the brief's
        /// "chain", as one case rather than two.
        case play(sequence: UUID, thenLoading: DuckOfficialPolicies.Slot?)
        case drive
        case stop
        case reset
        /// Named, with the reason, exactly as `DuckPad.unsupported` is.
        case notYet(String)
    }

    /// What `padButton` draws and what VoiceOver reads. NOT a `DuckPad.Binding`,
    /// because a played sequence has no `DuckPad.Effect` to be spelled as and
    /// forcing one would make `isLive` a lie.
    public struct Shown: Equatable, Sendable, Identifiable {
        public let control: DuckPad.Control
        public var id: String { control.rawValue }
        /// padd's words for what the ROBOT does. Kept even when remapped.
        public let onTheRobot: String
        /// One short phrase for the map editor's row.
        public let caption: String
        /// The accessibility hint, and the editor's second line.
        public let detail: String
        public let isLive: Bool
        /// Whether this is the person's choice rather than the shipped one.
        public let isCustom: Bool

        public init(control: DuckPad.Control, onTheRobot: String, caption: String,
                    detail: String, isLive: Bool, isCustom: Bool) {
            self.control = control
            self.onTheRobot = onTheRobot
            self.caption = caption
            self.detail = detail
            self.isLive = isLive
            self.isCustom = isCustom
        }
    }

    public var locomotion: Locomotion
    /// SPARSE ON PURPOSE — an absent control falls through to `DuckPad.bindings`,
    /// so the shipped table stays the thing a remap is a departure FROM.
    public var buttons: [DuckPad.Control: Effect]

    public init(locomotion: Locomotion, buttons: [DuckPad.Control: Effect]) {
        self.locomotion = locomotion
        self.buttons = buttons
    }

    // MARK: - defaults

    /// The shipped arrangement, as a map.
    ///
    /// THE MODE CHANGES NOTHING TODAY AND THE ARGUMENT STAYS. `robotd`'s two
    /// presets fill the same slots except `stand`, which no control is bound to,
    /// so a roller bench and a walking bench get the same fourteen entries —
    /// and `modeIsAnAssumption` is the sentence that says so out loud rather
    /// than letting somebody discover it. The parameter is here because the day
    /// `/health` grows a drive-mode field this is the door that reads it.
    public static func defaults(in mode: DuckOfficialPolicies.Mode) -> DuckPadMap {
        var buttons: [DuckPad.Control: Effect] = [:]
        for control in remappable {
            buttons[control] = shipped(for: control)
        }
        return DuckPadMap(locomotion: .slot(.walk), buttons: buttons)
    }

    /// EVERY CONTROL BUT THE TWO STICKS — fourteen. A control whose robot
    /// function has no bench wire (the head, the body pose, the mouth, the
    /// motor bus, the drive mode, the power) is still a button a person can
    /// put a sequence on: binding one asks nothing of the bench.
    public static let remappable: [DuckPad.Control] =
        DuckPad.Control.allCases.filter { $0 != .leftStick && $0 != .rightStick }

    /// The shipped table's answer for one control, in this type's vocabulary.
    ///
    /// `.unsupported` BECOMES `.notYet` AND NOTHING ELSE MOVES. The two words
    /// mean the same thing and the sentence attached to them is `padd`'s own,
    /// so the translation is a rename rather than a decision.
    public static func shipped(for control: DuckPad.Control) -> Effect {
        guard let binding = DuckPad.binding(for: control) else { return .drive }
        switch binding.here {
        case .loadSlot(let slot): return .loadSlot(slot)
        case .drive: return .drive
        case .stop: return .stop
        case .reset: return .reset
        case .unsupported(let why): return .notYet(why)
        }
    }

    // MARK: - resolving against a bench

    public func locomotionFilename(among policies: [String]) -> String? {
        switch locomotion {
        case .slot(let slot):
            return DuckQuickActions.filename(filling: slot, among: policies)
        case .named(let name):
            return policies.contains(name) ? name : nil
        case .whateverIsLoaded:
            return nil
        }
    }

    /// Why the sticks are not mapped to a file on this bench, or nil.
    ///
    /// THE SLOT CASE RETURNS `DuckQuickActions.notHeldHere` WORD FOR WORD. The
    /// front door already says this about the same missing file; a second
    /// wording would be two answers to one question, and a test pins the two
    /// strings identical rather than similar.
    public func locomotionRefusal(among policies: [String]) -> String? {
        switch locomotion {
        case .slot(let slot):
            guard DuckQuickActions.filename(filling: slot, among: policies) == nil else {
                return nil
            }
            return DuckQuickActions.notHeldHere(slot)
        case .named(let name):
            return policies.contains(name) ? nil : DuckPadMap.staleNetwork(name)
        case .whateverIsLoaded:
            return nil
        }
    }

    /// The ONE name to post, or nil. Nil when it resolves to nothing, and nil
    /// when `lastLoaded` already names it — the quick-action-undo guard lifted
    /// out of the picker's `onChange` so Linux can test it.
    public func toPost(among policies: [String], lastLoaded: String?) -> String? {
        guard let name = locomotionFilename(among: policies) else { return nil }
        guard name != lastLoaded else { return nil }
        return name
    }

    /// Degrade anything this bench cannot honour. Returns one sentence per
    /// entry it changed. POSTS NOTHING AND ASKS FOR NOTHING.
    ///
    /// A SLOT THIS BENCH DOES NOT FILL IS LEFT ALONE, which looks like a
    /// missing case and is the decision: the map still names the ROLE, the
    /// role is still the right thing to want, and the sentence for "not here"
    /// is `locomotionRefusal`'s to say beside the sticks. Rewriting it to
    /// `.whateverIsLoaded` would lose the person's choice on a bench they were
    /// only passing through.
    @discardableResult
    public mutating func settle(against policies: [String]) -> [String] {
        guard case .named(let name) = locomotion, !policies.contains(name) else { return [] }
        locomotion = .whateverIsLoaded
        return [DuckPadMap.staleNetwork(name)]
    }

    // MARK: - lookup, the single door

    /// NEVER NIL. An unmapped control lifts `DuckPad.binding(for:)!.here`
    /// unchanged, so the shipped table is the default rather than a rival.
    public func effect(for control: DuckPad.Control) -> Effect {
        buttons[control] ?? DuckPadMap.shipped(for: control)
    }

    /// The same door, with the store's knowledge of which sequences still
    /// exist.
    ///
    /// A DEAD ID CAN NEVER REACH A PRESS. A binding whose sequence has been
    /// deleted becomes `.notYet(sequenceIsGone(control))` on the way out, which
    /// is the shipped `.unsupported` idiom rather than a vanished button: the
    /// control is still there, it still says something when pressed, and what
    /// it says is what happened to it.
    public func effect(for control: DuckPad.Control,
                       naming: (UUID) -> String?) -> Effect {
        let here = effect(for: control)
        guard case .play(let id, _) = here, naming(id) == nil else { return here }
        return .notYet(DuckPadMap.sequenceIsGone(control))
    }

    public func shown(for control: DuckPad.Control,
                      naming: (UUID) -> String?) -> Shown {
        let here = effect(for: control, naming: naming)
        let robot = DuckPad.binding(for: control)?.onTheRobot ?? "—"
        var live = true
        var caption: String
        var here_: String
        switch here {
        case .loadSlot(let slot):
            caption = "Load \(slot.title.lowercased())"
            here_ = "Loads the network filling \(slot.title.lowercased()) on this bench."
        case .play(let id, let then):
            let name = naming(id) ?? ""
            if let then {
                caption = "Play \(name), then \(then.title.lowercased())"
                here_ = "Plays the sequence \(name), then loads the network filling "
                      + "\(then.title.lowercased()) on this bench."
            } else {
                caption = "Play \(name)"
                here_ = "Plays the sequence \(name)."
            }
        case .drive:
            caption = "Drive"
            here_ = "Feeds the velocity twist."
        case .stop:
            caption = "Stop"
            here_ = "Stops — zeroes the command and lets the duck settle under it."
        case .reset:
            caption = "Reset"
            here_ = "Puts the duck back on its feet."
        case .notYet(let why):
            live = false
            caption = "Nothing here"
            here_ = why
        }
        // THE ROBOT'S HALF IS APPENDED ONLY WHERE THERE IS ONE. Stop and Reset
        // are the bench's own controls and `padd` has no counterpart for them,
        // so their `onTheRobot` is an em dash; reading "On the robot: —" aloud
        // is worse than saying nothing.
        let detail = robot == "—" ? here_ : "\(here_) On the robot: \(robot)."
        return Shown(control: control, onTheRobot: robot, caption: caption,
                     detail: detail, isLive: live,
                     isCustom: here != DuckPadMap.shipped(for: control))
    }

    // MARK: - editing

    public mutating func bind(_ effect: Effect, to control: DuckPad.Control) {
        guard control != .leftStick, control != .rightStick else { return }
        buttons[control] = effect
    }

    /// Put a control back to what the pad ships with.
    public mutating func clear(_ control: DuckPad.Control) {
        buttons[control] = DuckPadMap.shipped(for: control)
    }

    public mutating func steer(_ locomotion: Locomotion) {
        self.locomotion = locomotion
    }

    /// A binding whose sequence has been deleted becomes `.notYet(…)` on the
    /// way out of `effect(for:naming:)`, so a dead id can never reach a press.
    public static func sequenceIsGone(_ control: DuckPad.Control) -> String {
        sequenceIsGone(face: control.face)
    }

    /// The same fact where the caller holds the face rather than the control —
    /// `PadDesk.play` is handed one by `DriveView`'s press.
    ///
    /// AN EMPTY FACE IS A SEQUENCE STARTED FROM THE LIST, where there is no
    /// button to name and no binding to have lost: the sentence about opening
    /// the map and putting something on it would be about a button nobody
    /// pressed.
    public static func sequenceIsGone(face: String) -> String {
        guard !face.isEmpty else {
            return "That sequence has since been deleted, so there is nothing to play."
        }
        return "\(face) was on a sequence that has since been deleted, so nothing is bound here "
             + "now. Open the map and put something on it."
    }

    /// What the readout says when a sequence actually starts.
    ///
    /// AN EMPTY FACE IS A REAL CASE AND NOT A BUG. A sequence started from the
    /// list rather than from a button was not pressed on anything, and the
    /// merge seam passes `face: ""` for exactly that — so the sentence is built
    /// here rather than leaving a view to compose " → play x" and ship it.
    public static func pressedToPlay(face: String, named: String) -> String {
        face.isEmpty ? "Playing \(named)" : "\(face) → play \(named)"
    }

    // MARK: - the sentences

    public static func drivingLine(mapped: String?, benchSaid: String?) -> String {
        if let benchSaid {
            return "driving \(benchSaid) — the bench's own word for what is on the servos"
        }
        if let mapped {
            return "sticks mapped to \(mapped); the bench has not answered yet, so nothing "
                 + "here is confirmed"
        }
        return "sticks mapped to whatever this bench already has loaded; it says what that "
             + "is on the first reply"
    }

    public static func staleNetwork(_ name: String) -> String {
        "\(name) is not on this bench. The mapping is remembered on this phone and a bench holds "
      + "whatever it holds, so the sticks have been put back to whatever this bench already has "
      + "loaded rather than sending a name nothing here would recognise."
    }

    public static let sticksAreAlwaysMapped =
        "The sticks are mapped, so Drive works without picking anything first. By default they "
      + "drive whichever network fills the Walk slot on this bench; if it fills none, they drive "
      + "whatever it already has loaded and the readout prints the bench's own name for it. Every "
      + "button below is remapped the same way."

    public static let modeIsAnAssumption =
        "These defaults assume legs. /health lists what a bench holds and does not say which drive "
      + "mode it is in, so this app cannot read it — a duck on wheels gets the walking map, and any "
      + "entry it has no network for says so when you press it rather than failing quietly. When "
      + "/health grows the field, this reads it."

    public static let motionOnAButtonIsNotYet =
        "A motion on a button is not built yet. A motion is keyframes, and the only way this app can "
      + "play one is POST /perform on a bench: a batch call that runs whole rollouts, takes minutes "
      + "and answers with a verdict rather than a picture. Nothing in the robot vocabulary carries "
      + "keyframes at all, so a button that played one while you steer would be a control with no "
      + "wire behind it. Slots and sequences go on the buttons today; a motion is run from Studio."

    public static let mapLivesOnThisPhone =
        "This map lives on this phone, not on the bench. Every entry names a role or one of your "
      + "own sequences rather than a file, so it means the same thing on any bench; the one "
      + "exception is a network you picked by name, which is checked against what the bench holds "
      + "every time this tab opens."

    /// The heading and the two captions the map editor draws, here for the same
    /// reason every other sentence is.
    public static let sticksRowTitle = "Sticks"
    public static let putThePadBack = "Put the pad back"
    public static let putThePadBackDetail =
        "Restores every button and the sticks to the arrangement this app ships with. Your "
      + "sequences are not touched — only what is bound to what."

    /// The three choices in the locomotion picker, in words rather than cases.
    public static let steerBySlot = "the network filling Walk on this bench"
    public static let steerByWhateverIsLoaded = "whatever this bench already has loaded"
    public static let pickANetwork = "Pick a network"

    /// The bind sheet's footnote, where somebody is about to change what a
    /// button does.
    ///
    /// IT IS HERE AND NOT IN THE SHEET because it makes a claim — that
    /// remapping a control on this phone does not change what that button does
    /// on a robot — and a claim composed in a view is a claim nothing on Linux
    /// ever reads.
    public static func onTheRobotSurvivesARemap(_ onTheRobot: String) -> String {
        guard onTheRobot != "—" else { return mapLivesOnThisPhone }
        return "On the robot this button is: \(onTheRobot). That does not change when you remap "
             + "it here."
    }

    /// The two ways a sequence goes onto a button.
    public static let playIt = "Play it"
    public static func playThenLoad(_ slot: DuckOfficialPolicies.Slot) -> String {
        "Play it, then load \(slot.title.lowercased())"
    }

    // MARK: - the file

    public func encoded() throws -> Data {
        var object: [String: Any] = ["format": DuckPadMap.format]
        switch locomotion {
        case .slot(let slot):
            object["locomotion"] = ["kind": "slot", "slot": slot.rawValue]
        case .named(let name):
            object["locomotion"] = ["kind": "named", "name": name]
        case .whateverIsLoaded:
            object["locomotion"] = ["kind": "loaded"]
        }
        var wired: [String: Any] = [:]
        for (control, effect) in buttons {
            wired[control.rawValue] = DuckPadMap.wire(effect)
        }
        object["buttons"] = wired
        return try JSONSerialization.data(withJSONObject: object,
                                          options: [.prettyPrinted, .sortedKeys])
    }

    /// One effect as the file spells it.
    ///
    /// HAND-BUILT AND NOT `Codable`, and the dictionary is the reason. A
    /// `[DuckPad.Control: Effect]` under synthesised `Codable` encodes as an
    /// unkeyed alternating array unless the key conforms to
    /// `CodingKeyRepresentable` — a file nobody can read by eye, and a
    /// forward-compatibility story that breaks the first time a control is
    /// added. `IntentExport` and `DuckPlanFile` are hand-built for the same
    /// reason and this follows them.
    private static func wire(_ effect: Effect) -> [String: Any] {
        switch effect {
        case .loadSlot(let slot): return ["effect": "loadSlot", "slot": slot.rawValue]
        case .play(let id, let then):
            var body: [String: Any] = ["effect": "play", "sequence": id.uuidString]
            if let then { body["thenLoading"] = then.rawValue }
            return body
        case .drive: return ["effect": "drive"]
        case .stop: return ["effect": "stop"]
        case .reset: return ["effect": "reset"]
        case .notYet(let why): return ["effect": "notYet", "why": why]
        }
    }

    public static func decode(_ data: Data) throws -> DuckPadMap {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        guard let format = top["format"] as? String else { throw ReadError.missing("a format") }
        guard readableFormats.contains(format) else { throw ReadError.wrongFormat(format) }
        guard let steering = top["locomotion"] as? [String: Any] else {
            throw ReadError.missing("what the sticks drive")
        }
        let locomotion: Locomotion
        switch steering["kind"] as? String {
        case "slot":
            guard let raw = steering["slot"] as? String,
                  let slot = DuckOfficialPolicies.Slot(rawValue: raw) else {
                throw ReadError.missing("the slot the sticks drive")
            }
            locomotion = .slot(slot)
        case "named":
            guard let name = steering["name"] as? String else {
                throw ReadError.missing("the network the sticks drive")
            }
            locomotion = .named(name)
        case "loaded":
            locomotion = .whateverIsLoaded
        default:
            throw ReadError.missing("what the sticks drive")
        }
        // AN UNKNOWN CONTROL KEY IS DROPPED RATHER THAN FATAL. A map written by
        // a build that had a control this one does not is still a map about
        // fourteen buttons this one has; refusing the file to keep the reader
        // tidy would lose every other entry in it.
        var buttons: [DuckPad.Control: Effect] = [:]
        for (key, value) in (top["buttons"] as? [String: Any] ?? [:]) {
            guard let control = DuckPad.Control(rawValue: key),
                  let body = value as? [String: Any],
                  let effect = read(effect: body) else { continue }
            buttons[control] = effect
        }
        return DuckPadMap(locomotion: locomotion, buttons: buttons)
    }

    private static func read(effect body: [String: Any]) -> Effect? {
        switch body["effect"] as? String {
        case "loadSlot":
            guard let raw = body["slot"] as? String,
                  let slot = DuckOfficialPolicies.Slot(rawValue: raw) else { return nil }
            return .loadSlot(slot)
        case "play":
            guard let raw = body["sequence"] as? String, let id = UUID(uuidString: raw) else {
                return nil
            }
            let then = (body["thenLoading"] as? String)
                .flatMap { DuckOfficialPolicies.Slot(rawValue: $0) }
            return .play(sequence: id, thenLoading: then)
        case "drive": return .drive
        case "stop": return .stop
        case "reset": return .reset
        case "notYet":
            guard let why = body["why"] as? String else { return nil }
            return .notYet(why)
        default: return nil
        }
    }

    public enum ReadError: Error, Equatable {
        case notJSON, wrongFormat(String), missing(String)

        public var message: String {
            switch self {
            case .notJSON:
                return "That file is not a pad map this app wrote — it is not even JSON."
            case .wrongFormat(let found):
                return "That pad map is in format \"\(found)\", which this version does not read. "
                     + "It reads \(DuckPadMap.readableFormats.sorted().joined(separator: ", "))."
            case .missing(let field):
                return "That pad map is missing \(field), so it cannot be read. It may have been "
                     + "written by a newer version."
            }
        }
    }

    /// Every sentence this type ships, for the word test and the script that
    /// backs it up.
    public static let allSentences: [String] = [
        sticksAreAlwaysMapped, modeIsAnAssumption, motionOnAButtonIsNotYet,
        mapLivesOnThisPhone, sticksRowTitle, putThePadBack, putThePadBackDetail,
        steerBySlot, steerByWhateverIsLoaded, pickANetwork, playIt,
        playThenLoad(.walk),
        onTheRobotSurvivesARemap("Ground pick"),
        onTheRobotSurvivesARemap("—"),
        staleNetwork("a.onnx"),
        sequenceIsGone(.a), sequenceIsGone(face: ""),
        pressedToPlay(face: "A", named: "a take"),
        pressedToPlay(face: "", named: "a take"),
        drivingLine(mapped: nil, benchSaid: nil),
        drivingLine(mapped: "a.onnx", benchSaid: nil),
        drivingLine(mapped: nil, benchSaid: "a.onnx"),
        ReadError.notJSON.message,
        ReadError.wrongFormat("duck-padmap/9").message,
        ReadError.missing("a format").message,
    ]
}
