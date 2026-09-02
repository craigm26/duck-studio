import Foundation
import DuckEvidence
import DuckKit

// MARK: - what a sim duck is

/// A simulated duck, described in the same keys a real one is configured with.
///
/// THE INSIGHT THIS TYPE IS BUILT ON: A REAL MICRODUCK IS A CONFIGURATION FILE.
/// `deploy/robotd.toml` in `pollen-robotics/microduck` is what makes one duck
/// behave differently from the next — a `[policy]` table whose `mode` key is
/// `"walk"` or `"roller"`, and whose remaining keys are the slots
/// (`walk`, `stand`, `sitstand`, `ground_pick`, `kick_left`, `kick_right`,
/// `roulade`) each naming the network that fills it, alongside the action scale
/// and the low-pass coefficients that shape what those networks are allowed to
/// do to the servos. Nothing else about a Microduck is configurable from a
/// file: the geometry is the geometry and the motors are the motors.
///
/// SO CUSTOMISING A SIM DUCK IS EDITING THE SAME KEYS A REAL DUCK HAS, and that
/// is the entire justification for this type existing rather than a bag of
/// simulator settings. Somebody who swaps `walk` from `alpha_walking.onnx` to a
/// network they trained themselves, and then watches their sim duck move
/// differently, has learned what that key does on a robot — because it is that
/// key, spelled the way `robotd` spells it, doing the job `robotd` gives it.
/// What they learn here is knowledge about Microducks rather than knowledge
/// about our simulator, and `robotdToml()` is the proof: it renders this value
/// AS the config excerpt, so the mapping is a thing a person can read rather
/// than a claim this comment makes.
///
/// A SIM DUCK IS A PEER AND NOT A LESSER MODE. `DuckIdentity.Kind` has exactly
/// two cases and no ranking between them; `SimDuck` conforms to `DuckPeer` the
/// same way a BLE link would. What is genuinely different is not status but
/// what can be honestly said — a simulation has no battery, renders no camera
/// frame, and produces numbers that are not hardware numbers — and every one of
/// those three lives below as a type that cannot say otherwise rather than as a
/// rule a caller is asked to remember.
///
/// THE SLOT KEYS AND THE MODE ARE `DuckOfficialPolicies`' OWN, NOT A SECOND
/// COPY. That enum was written against `robotd.toml` and `policies/README.md`
/// and already carries the wire spellings (`ground_pick`, not `groundPick`),
/// the per-release slot, and the per-release mode. A private list here would be
/// a second transcription of one table, and the day upstream renamed a slot the
/// two would disagree with nothing to notice.
public struct SimDuckConfig: Equatable, Sendable, Codable {

    /// What to call this duck. It is a name for a peer in a list, not an
    /// identifier: nothing in this app resolves a duck by name.
    public var name: String

    /// How it is drawn, so two ducks in one room are not the same duck.
    public var colourway: DuckColourway

    /// Legs or wheels — `robotd.toml`'s own one-line switch, quoted in
    /// `DuckOfficialPolicies.Mode`: "The mode changes which policies load AND
    /// the tuning defaults."
    public var mode: DuckOfficialPolicies.Mode

    /// Which network fills each slot, by filename.
    ///
    /// A SLOT WITH NO ENTRY IS A SLOT THE ROBOT WOULD LOAD NOTHING INTO, which
    /// is a real state and not a defect — `stock(mode: .roller)` leaves `stand`
    /// empty on purpose, because that is what the roller preset does. So the
    /// dictionary is sparse rather than total, and `advisories` says which
    /// gaps are worth reading about.
    ///
    /// THE VALUE IS A FILENAME AND DELIBERATELY NOT A `DuckPolicy`. Pollen's
    /// `policies/README.md` is explicit that the indirection is the point —
    /// "The names here are the *roles* … swapping which run is 'the walking
    /// policy' should not mean editing config on every robot" — so a config
    /// names a file and something else resolves it. A config that embedded the
    /// weights would be a config that could not be written down.
    public var slots: [DuckOfficialPolicies.Slot: String]

    /// How grippy the floor is, as the coefficient training randomises.
    ///
    /// THE RANGE THAT MATTERS IS `Retrieval.Drag.footFriction`, 0.7 to 1.3 —
    /// `cfg.events["foot_friction"].params["ranges"]` in the training config.
    /// A value inside it is a floor every shipped policy was trained to cope
    /// with; a value outside it is a floor no shipped policy has ever seen, and
    /// a duck that falls over on one has not necessarily found a bug. That
    /// distinction is what `advisories` exists to say out loud.
    public var floorFriction: Double

    /// What it is carrying, grams, or nil for an unladen duck.
    ///
    /// NIL AND ZERO ARE THE SAME PHYSICS AND DIFFERENT SENTENCES. Nil means
    /// nobody has put anything on this duck; zero means somebody put a
    /// weightless thing on it, which is a thing people type when they mean nil.
    /// The renderer omits the key for nil and writes `0` for zero, so a config
    /// round-trips as what was meant.
    public var payloadGrams: Double?

    /// Which scene it stands in, or nil for the bare floor.
    ///
    /// A NAME, NOT A SCENE. `DuckScene` is a whole object with obstacles in it
    /// and this is a config file; naming the scene keeps the two joinable
    /// without a config carrying a room around inside it.
    public var sceneName: String?

    public init(name: String,
                colourway: DuckColourway = .yellow,
                mode: DuckOfficialPolicies.Mode = .walk,
                slots: [DuckOfficialPolicies.Slot: String],
                floorFriction: Double = 1.0,
                payloadGrams: Double? = nil,
                sceneName: String? = nil) {
        self.name = name
        self.colourway = colourway
        self.mode = mode
        self.slots = slots
        self.floorFriction = floorFriction
        self.payloadGrams = payloadGrams
        self.sceneName = sceneName
    }

    // MARK: - the presets

    /// The friction of a floor nobody has said anything about.
    ///
    /// ONE, BECAUSE THAT IS THE MIDDLE OF THE RANGE TRAINING RANDOMISES AND
    /// NOT BECAUSE IT IS A TIDY NUMBER. Picking the bottom of the range would
    /// make every stock duck slip more than the ones Pollen demonstrate; the
    /// top would flatter every policy somebody imports.
    public static let defaultFriction = 1.0

    /// A duck configured the way one arrives: every slot filled by the network
    /// `DuckOfficialPolicies` records for it.
    ///
    /// BUILT FROM THE RELEASE TABLE RATHER THAN FROM A LIST TYPED HERE, so a
    /// policy Pollen re-release under a new filename changes this preset by
    /// changing the table, in one place, where the fingerprints live.
    ///
    /// THE ROLLER PRESET IS THIS APP'S, AND THE DIFFERENCE IS WORTH KNOWING.
    /// `DuckOfficialPolicies.Mode` quotes what upstream's roller preset does:
    /// it "puts `roller.onnx` in the locomotion slot and the crouch on the
    /// ground-pick trigger — and deliberately leaves the standing network out,
    /// 'standing transitions being skipped on wheels'." That is three facts —
    /// two substitutions and one omission — and it is everything this app has
    /// read about that preset. So those three are applied here and the
    /// remaining slots are left holding what the walking preset put in them,
    /// which is an assumption rather than a transcription. If somebody reads
    /// the real `[policy]` table for roller mode and finds the kicks are absent
    /// too, this function is where that gets corrected, and the correction is
    /// one line rather than an archaeology.
    ///
    /// A ROLLER RELEASE WITH NO PLACEMENT IS SAID OUT LOUD RATHER THAN SKIPPED.
    /// See `rollerPlacements`.
    public static func stock(mode: DuckOfficialPolicies.Mode = .walk) -> SimDuckConfig {
        var slots: [DuckOfficialPolicies.Slot: String] = [:]
        for release in DuckOfficialPolicies.releases {
            // The walking preset is every release that names a slot. The roller
            // releases name none — `slot` is nil for both — which is precisely
            // why they need placing by hand below.
            guard release.mode == .walk, let slot = release.slot else { continue }
            slots[slot] = release.filename
        }
        if mode == .roller {
            // THE FOUR SLOTS NOT TOUCHED BELOW ARE CARRIED OVER ON PURPOSE, and
            // that is a transcription rather than an assumption. `robotd.toml`
            // describes its own roller preset: "roller.onnx as the locomotion
            // policy, the crouch on the ground-pick trigger (3.0 s, 0.8),
            // action_scale 0.8 — and everything else as walking has it:
            // sit/stand, kicks, roulade, the trained low-pass. Only the
            // standing network stays out." So sitstand, kick_left, kick_right
            // and roulade keep their walking entries because the robot keeps
            // them, and `stand` is removed two lines below because the robot
            // removes it — "standing transitions being skipped on wheels".
            //
            // NOT CARRIED: that preset's `action_scale = 0.8`. This config has
            // no action-scale field, so `robotdToml()` renders a roller table
            // without one and a reader would take the daemon's default. See
            // `advisories`, which says so rather than leaving it to be noticed.
            for release in DuckOfficialPolicies.releases where release.mode == .roller {
                // A release this table has no placement for is left where it
                // is — nowhere — and `advisories` names it. It is not dropped
                // silently here, which is the only thing that would be worse
                // than not knowing where it goes.
                guard let slot = rollerPlacements[release.filename] else { continue }
                slots[slot] = release.filename
            }
            slots[.stand] = nil
        }
        return SimDuckConfig(name: "Duck", mode: mode, slots: slots,
                             floorFriction: defaultFriction)
    }

    /// Where each roller-mode release goes, for the ones this app has read a
    /// placement for.
    ///
    /// A TABLE AND NOT A `switch`, BECAUSE THE THING THAT CHANGES HERE IS DATA.
    /// A `switch` over `release.filename` with a `default:` was what stood here
    /// before, and it did the thing `DuckPeer`'s exhaustive-switch discipline
    /// exists to prevent: a tenth release in `DuckOfficialPolicies.releases`
    /// would have gone nowhere and said nothing, leaving a roller duck holding
    /// the walking preset's file in that slot and looking correct. No shape of
    /// Swift `switch` can fix that, because the new roller policy is a new row
    /// in another package's array rather than a new case in an enum, and a
    /// compiler cannot be made to notice a row. What CAN be made to notice one
    /// is this app: everything under `mode == .roller` that is not a key here
    /// is reported by `unplacedRollerPolicies` and said in `advisories`, so the
    /// preset admits the gap to the person reading it in the same breath as it
    /// shows them the duck.
    ///
    /// THE TWO KEYS ARE UPSTREAM'S SHIPPED FILENAMES, quoted by
    /// `DuckOfficialPolicies.Mode` — `roller.onnx` in the locomotion slot,
    /// `roller_crouch.onnx` on the ground-pick trigger. Matching by filename is
    /// what this app has to match on: `Release.slot` is nil for both, which is
    /// precisely the fact that makes them need placing by hand.
    static let rollerPlacements: [String: DuckOfficialPolicies.Slot] = [
        "roller.onnx": .walk,
        "roller_crouch.onnx": .groundPick,
    ]

    /// Roller-mode releases this build has nowhere to put, by filename.
    ///
    /// Normally empty. It stops being empty the day upstream ships a third
    /// roller policy, and on that day `advisories` starts saying so on every
    /// roller duck — which is the difference between a preset that is one fact
    /// short and a preset that is one fact short and quiet about it.
    public static var unplacedRollerPolicies: [String] {
        DuckOfficialPolicies.releases
            .filter { $0.mode == .roller && rollerPlacements[$0.filename] == nil }
            .map(\.filename)
    }

    /// What to tell somebody whose roller preset is short a policy, or nil when
    /// it is not.
    ///
    /// IT TAKES THE LIST RATHER THAN READING IT, so the branch that only fires
    /// on a day that has not come yet can be read on a day that has. The
    /// sentence nobody can produce is the sentence nobody can check, and this
    /// one exists precisely for a release table this build has never seen.
    static func unplacedRollerSentence(_ unplaced: [String], placed: Int) -> String? {
        guard !unplaced.isEmpty else { return nil }
        let names = unplaced.joined(separator: ", ")
        let isOne = unplaced.count == 1
        return "This app has read where \(placed) of the roller policies go, and \(names) "
             + (isOne ? "is not one of them" : "are not among them")
             + ". So the roller preset has left \(isOne ? "that network" : "those networks") "
             + "out rather than guess at a slot, and any slot it did not fill is still holding "
             + "the walking preset's file. Read robotd.toml's [policy] table for roller mode "
             + "before comparing this duck with anybody else's."
    }

    // MARK: - what is worth saying about this config

    /// Sentences about this configuration that a person should read before
    /// believing what their sim duck does.
    ///
    /// NOT ERRORS AND NOT A VALIDATOR. Every config in this type is renderable
    /// and every one of them is a duck somebody may genuinely want; what these
    /// say is where a result stops being comparable to Pollen's, which is a
    /// different question from whether the file is well formed. They are
    /// ordered most-surprising first, because a person reads the first one.
    public var advisories: [String] {
        var said: [String] = []

        if !floorFriction.isFinite {
            said.append("The floor friction is not a number. TOML can write that and physics "
                      + "cannot use it, so this duck would not stand up anywhere.")
        } else if !Retrieval.Drag.footFriction.contains(floorFriction) {
            let range = "\(Self.number(Retrieval.Drag.footFriction.lowerBound))"
                      + "–\(Self.number(Retrieval.Drag.footFriction.upperBound))"
            said.append("A floor at \(Self.number(floorFriction)) is outside the \(range) that "
                      + "training randomised the feet over, so no shipped policy has ever met "
                      + "one. A duck that falls over here has not necessarily found a fault.")
        }

        if mode == .roller,
           let unplaced = Self.unplacedRollerSentence(Self.unplacedRollerPolicies,
                                                      placed: Self.rollerPlacements.count) {
            said.append(unplaced)
        }

        // THE ONE FIELD THIS TYPE CANNOT RENDER. robotd.toml's roller preset
        // sets `action_scale = 0.8`; a `SimDuckConfig` has no action scale, so
        // the table this renders leaves it out and a reader takes the daemon's
        // default of 0.9 — a 12% difference at every joint, in the direction of
        // asking for more than the preset does.
        if mode == .roller {
            said.append("This roller table has no action_scale. The robot's own roller preset "
                      + "sets 0.8; leaving it out means the daemon's default, which is more "
                      + "movement per action than the preset asks for.")
        }

        // A payload that is not a number gets the same treatment friction does:
        // TOML will write it and physics cannot use it.
        if let payload = payloadGrams, !payload.isFinite {
            said.append("The payload is not a number of grams. TOML can write that and the "
                      + "mouth cannot carry it.")
        } else if let payload = payloadGrams, payload < 0 {
            said.append("A payload of \(Self.number(payload)) g is a negative mass. Nothing in "
                      + "the physics rejects it and nothing in it means anything either.")
        }

        for slot in DuckOfficialPolicies.Slot.allCases where slots[slot] == nil {
            // The one empty slot that is a decision rather than an omission.
            if mode == .roller, slot == .stand { continue }
            said.append("Nothing fills \(slot.rawValue). The robot loads no network into that "
                      + "slot, so whatever it does is what it does with the slot empty.")
        }

        if let payloadGrams {
            let duckGrams = Retrieval.Drag.duckMass * 1000
            if payloadGrams > duckGrams {
                said.append("A \(Self.number(payloadGrams)) g payload is heavier than the duck, "
                          + "which weighs \(Self.number((duckGrams * 10).rounded() / 10)) g by "
                          + "its own MJCF. Nothing in this app has measured a duck carrying "
                          + "anything, let alone more than itself.")
            }
        }

        return said
    }

    // MARK: - rendering it as the robot's own file

    /// This configuration written as the `robotd.toml` excerpt it corresponds to.
    ///
    /// THIS FUNCTION IS THE POINT OF THE WHOLE TYPE. Everything above claims
    /// that customising a sim duck is editing a real duck's config; this is
    /// where that stops being a claim. The `[policy]` section it renders is
    /// `deploy/robotd.toml`'s section, spelled with `robotd`'s keys and
    /// `policies/`' filenames, and a person who reads it has read what their
    /// sim duck would be if it were a robot on a desk.
    ///
    /// THE FILE IS SPLIT AND THE SPLIT IS LOAD-BEARING. Everything under
    /// `[policy]` is a key the robot really has. Everything under `[studio]` is
    /// ours — a floor coefficient, a payload, a scene — and a robot would
    /// ignore all of it, which the header comment says in the output rather
    /// than only here, because the output is the part somebody pastes
    /// somewhere. Mixing the two into one section would produce a file that
    /// looks copyable onto a robot and quietly is not.
    ///
    /// WHAT IS DELIBERATELY MISSING: `action_scale` and the low-pass
    /// coefficients. They are real `[policy]` keys and this app holds no value
    /// for either, so writing one would be inventing a robot's tuning and
    /// dressing it as a transcription. A comment in the output says they were
    /// left out and why.
    public func robotdToml() -> String {
        var lines: [String] = []
        lines.append("# \(Self.tomlComment(name)) — a sim duck, written as the robot's own config.")
        lines.append("#")
        lines.append("# Every key under [policy] is a key deploy/robotd.toml really has, so what")
        lines.append("# you tune here is what a Microduck owner tunes. [studio] is this app's own")
        lines.append("# and a robot would ignore it.")
        lines.append("")
        lines.append("[policy]")
        lines.append("mode = \(Self.tomlString(mode.rawValue))")
        // Slot order is `Slot.allCases`, which is declaration order, which is
        // the order the keys appear in upstream's own table. A dictionary's
        // order is nobody's, and a config file that reordered itself between
        // renders could not be diffed.
        for slot in DuckOfficialPolicies.Slot.allCases {
            guard let filename = slots[slot] else { continue }
            lines.append("\(slot.rawValue) = \(Self.tomlString(filename))")
        }
        lines.append("# action_scale and the low-pass coefficients belong here too. This app has")
        lines.append("# no value for them, and a default written here would be inventing the")
        lines.append("# robot's tuning rather than recording it.")
        lines.append("")
        lines.append("[studio]")
        lines.append("# Not robotd's. A robot has a floor already.")
        lines.append("floor_friction = \(Self.number(floorFriction))")
        if let payloadGrams {
            lines.append("payload_grams = \(Self.number(payloadGrams))")
        }
        if let sceneName {
            lines.append("scene = \(Self.tomlString(sceneName))")
        }
        lines.append("colourway = \(Self.tomlString(colourway.rawValue))")
        return lines.joined(separator: "\n") + "\n"
    }

    /// A TOML basic string, quoted and escaped.
    ///
    /// ESCAPED RATHER THAN TRUSTED because a scene is named by a person and a
    /// person may well name one `He said "duck"`. TOML 1.0's basic strings take
    /// the same escapes JSON does, and the two that actually occur in a name
    /// typed on a phone are the backslash and the quote; the control characters
    /// are escaped as well because a name pasted from somewhere else can carry
    /// a tab or a newline and an unescaped newline ends the value mid-word.
    static func tomlString(_ text: String) -> String {
        var out = "\""
        for character in text.unicodeScalars {
            switch character {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if character.value < 0x20 || character.value == 0x7F {
                    out += String(format: "\\u%04X", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        return out + "\""
    }

    /// The same text, safe to put after a `#`.
    ///
    /// A COMMENT CANNOT BE ESCAPED, ONLY ENDED. TOML gives a comment no escape
    /// syntax at all: it runs to the end of the line, so a name with a newline
    /// in it would put the rest of the name on a line of its own where it would
    /// be read as a key. Folding the line breaks into spaces is the only honest
    /// fix, and it changes nothing a person sees.
    static func tomlComment(_ text: String) -> String {
        text.unicodeScalars.map { $0.value < 0x20 || $0.value == 0x7F ? " " : String($0) }
            .joined()
    }

    /// A number written the way TOML writes one.
    ///
    /// NON-FINITE VALUES ARE RENDERED, NOT SUPPRESSED. TOML 1.0 has `nan`,
    /// `inf` and `-inf` as float literals, so a friction of NaN produces a
    /// valid file that says something absurd — which is better than a file that
    /// silently drops the key and reads as if the friction were the default.
    /// `advisories` is what tells the person; this only refuses to lie.
    ///
    /// A WHOLE NUMBER IS WRITTEN AS AN INTEGER because `payload_grams = 40` is
    /// what somebody typed and `40.0000` is what a formatter does to it.
    static func number(_ value: Double) -> String {
        guard value.isFinite else {
            if value.isNaN { return "nan" }
            return value > 0 ? "inf" : "-inf"
        }
        // A NEGATIVE THAT ROUNDS TO ZERO IS NOT "-0", AND A NON-ZERO IS NOT "0".
        // `%.4f` renders -0.00001 as "-0" and 0.00001 as "0" — the first is a
        // minus sign on nothing, and the second writes a value the config did
        // not have into a file this type exists to render truthfully. The same
        // failure `Choreography.ms` had, in the same package, for the same
        // reason: a formatter deciding a sign.
        if value != 0, abs(value) < 0.00005 {
            return value > 0 ? "0.0001" : "-0.0001"
        }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    // MARK: - persistence

    /// The keys as a saved config spells them.
    ///
    /// SNAKE CASE, MATCHING THE TOML THIS TYPE RENDERS. A person who opens the
    /// saved JSON after reading `robotdToml()` should see the same words; two
    /// spellings of one field is how a format grows a translation layer.
    private enum Key: String, CodingKey {
        case name, colourway, mode, slots
        case floorFriction = "floor_friction"
        case payloadGrams = "payload_grams"
        case sceneName = "scene"
    }

    /// Written and read by hand rather than synthesised, for one reason:
    /// `slots` is keyed by `DuckOfficialPolicies.Slot`, which belongs to
    /// `DuckEvidence` and is not `Codable`.
    ///
    /// THE ALTERNATIVE WAS A RETROACTIVE CONFORMANCE ON SOMEBODY ELSE'S TYPE,
    /// and this file does not get to bolt a serialisation format onto a type
    /// another package owns — the day `DuckEvidence` adds its own `Codable` the
    /// two would collide, and the collision would be at link time in a build
    /// nobody here is running. Encoding the raw values by hand also fixes the
    /// shape of the saved file at something legible: `{"walk": "alpha_walking.onnx"}`
    /// rather than the alternating key/value array Swift emits for a dictionary
    /// whose key it cannot use as a string.
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: Key.self)
        try box.encode(name, forKey: .name)
        try box.encode(colourway.rawValue, forKey: .colourway)
        try box.encode(mode.rawValue, forKey: .mode)
        var raw: [String: String] = [:]
        for (slot, filename) in slots { raw[slot.rawValue] = filename }
        try box.encode(raw, forKey: .slots)
        try box.encode(floorFriction, forKey: .floorFriction)
        try box.encodeIfPresent(payloadGrams, forKey: .payloadGrams)
        try box.encodeIfPresent(sceneName, forKey: .sceneName)
    }

    /// A SLOT THIS BUILD DOES NOT KNOW IS DROPPED, NOT REFUSED. A config
    /// written by a newer build — one that knows a slot upstream added after
    /// this app shipped — must still open, and the honest thing to do with a
    /// slot this build cannot render, fill or explain is to leave it out rather
    /// than to pretend the file is corrupt. The cost is real and worth stating:
    /// re-saving such a config here loses that key.
    ///
    /// Everything except the name has a default, so a config saved before a
    /// field existed still opens.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: Key.self)
        name = try box.decode(String.self, forKey: .name)
        colourway = DuckColourway(
            rawValue: try box.decodeIfPresent(String.self, forKey: .colourway) ?? "") ?? .yellow
        mode = DuckOfficialPolicies.Mode(
            rawValue: try box.decodeIfPresent(String.self, forKey: .mode) ?? "") ?? .walk
        let raw = try box.decodeIfPresent([String: String].self, forKey: .slots) ?? [:]
        var decoded: [DuckOfficialPolicies.Slot: String] = [:]
        for (key, filename) in raw {
            guard let slot = DuckOfficialPolicies.Slot(rawValue: key) else { continue }
            decoded[slot] = filename
        }
        slots = decoded
        floorFriction = try box.decodeIfPresent(Double.self, forKey: .floorFriction)
                     ?? Self.defaultFriction
        payloadGrams = try box.decodeIfPresent(Double.self, forKey: .payloadGrams)
        sceneName = try box.decodeIfPresent(String.self, forKey: .sceneName)
    }
}

// MARK: - the battery a sim duck does not have

/// How much charge is left in a duck, when the duck has a battery in it.
///
/// THE INITIALISER IS FAILABLE AND IT FAILS FOR EVERY SIMULATED DUCK, WHICH IS
/// THE WHOLE TYPE. A percentage is a measurement of a physical cell; a
/// simulation contains no cell, so any number shown next to a battery glyph for
/// a sim duck is invented — not approximate, not stale, INVENTED. The way to
/// make that unsayable is not a rule in a review checklist and not an optional
/// somebody is trusted to leave nil: it is a type that refuses to exist unless
/// the duck it describes is `.real`. A caller who is determined to fake one
/// gets nil back and has nothing to draw.
///
/// THE RANGE IS CHECKED FOR THE SAME REASON. 104% is as invented as a
/// simulator's battery; a reading outside 0…100 came from arithmetic rather
/// than from a cell, so it is refused here rather than clamped, because
/// clamping turns a wrong number into a plausible one.
public struct DuckBattery: Equatable, Sendable {

    /// Percent of charge, 0 through 100.
    public let percent: Int

    /// Nil unless `identity` is a real robot and `percent` is a percentage.
    ///
    /// TAKING THE IDENTITY RATHER THAN A BOOL is deliberate: a `isReal: Bool`
    /// parameter is a thing a caller passes `true` to by accident, while an
    /// identity is a value that came from a peer saying who it is.
    public init?(percent: Int, of identity: DuckIdentity) {
        guard identity.kind == .real else { return nil }
        guard (0...100).contains(percent) else { return nil }
        self.percent = percent
    }

    /// What to put under the glyph.
    public var says: String { "\(percent)% charged" }

    /// What to say instead, for a duck that has no battery to read.
    ///
    /// A SENTENCE RATHER THAN A DASH. "—" in a battery row reads as a reading
    /// that failed to arrive, which invites somebody to reconnect and try
    /// again; there is nothing to reconnect to and nothing coming.
    public static let noneToRead =
        "No battery. This duck is physics on another machine, and a percentage here "
      + "would be a number this app made up."
}

// MARK: - the camera a sim duck does not render

/// What this build can show from a duck's head camera.
///
/// A ONE-CASE ENUM, ON PURPOSE, AND THE SINGLE CASE IS "NO IMAGE". The bench
/// this app talks to (`sim/duckbench.mjs`) answers with state blocks and
/// recorded clips; nothing anywhere in this app or in DuckKit renders a frame,
/// which `DuckSceneMJCF` says of itself in its own words — "the kit never sees
/// a camera frame". So there is no case here that means "here is a picture",
/// and a screen therefore cannot be handed one by mistake: the absence is in
/// the type rather than in a nil somebody could later fill.
///
/// THE MODEL KNOWS WHERE THE LENS WOULD BE, WHICH IS NOT THE SAME THING.
/// `DuckKinematics` carries a `head_camera` site at (0.01175, 0, −0.0735) in
/// the head frame, so the POSE of a camera is computable from a sim duck right
/// now. Knowing where a lens would be is not having taken a photograph, and a
/// preview drawn from a known pose would be a rendering of this app's guess
/// about a room presented as a robot's view of one.
///
/// WHEN A RENDERER ARRIVES, adding a case here breaks every `switch` that was
/// written while there was only one — which is exactly the review that change
/// deserves, and exactly what a `Bool` named `hasCamera` would not have caused.
public enum SimVision: String, CaseIterable, Equatable, Sendable {

    /// There is no frame, and there is no other case.
    case noImage

    public var says: String {
        switch self {
        case .noImage:
            return "No camera view. The simulation computes where the duck is, not what it "
                 + "would see; there is no frame to show and none is being waited for."
        }
    }
}

// MARK: - a number, and where it came from

/// One measured number about a duck, carrying which duck it came off.
///
/// THE PROVENANCE IS NOT A FIELD SOMEBODY REMEMBERS TO SET — IT IS THE ONLY WAY
/// TO BUILD ONE. The memberwise initialiser is private and the two public ways
/// in are `simulated(_:_:in:under:)` and `hardware(_:_:in:onboard:)`, so there
/// is no path to a number that has not said which world it is from. Neither of
/// them takes the provenance as a word, either: the simulated one takes the
/// configuration that produced the number, and the hardware one takes a
/// `Robot`, which is a value that cannot be made out of anything but a real
/// duck's identity. This is the
/// smallest version of a discipline the rest of the package already keeps —
/// `RunMetrics.provenance`, `DuckScene.provenance`, `IntentExport`'s
/// provenance sentence — pushed down to the individual number, because a number
/// lifted out of a panel and pasted into a message arrives without the panel's
/// sentence.
///
/// AND TWO OF THEM CANNOT BE SUBTRACTED. There is no `-` here and no
/// `Comparable`; the only way to relate two measurements is `compare(_:_:)`,
/// which refuses across sources and says why. A simulator's 0.681 m and a
/// robot's 0.681 m are not the same fact — the bench is a rigid-body
/// approximation with a position servo standing in for the friction-and-lag
/// motor model, as `ClipNote` already says — and a difference computed between
/// them is a number about nothing.
public struct DuckMeasurement: Equatable, Sendable {

    /// The units this app measures ducks in.
    ///
    /// SHORT AND CLOSED. A free-form unit string compares equal only when two
    /// people spell it the same way, and "m/s" against "ms^-1" would refuse a
    /// perfectly good comparison. These are the units that actually appear on
    /// this app's screens; adding one is a deliberate act.
    public enum Unit: String, Equatable, Sendable, CaseIterable {
        case metres = "m"
        case metresPerSecond = "m/s"
        case radiansPerSecond = "rad/s"
        case seconds = "s"
        case grams = "g"
        /// A rate, 0…1 — a success rate, a fraction of trials.
        case fraction = ""

        public var suffix: String { rawValue.isEmpty ? "" : " \(rawValue)" }
    }

    /// A robot a number was read off, and the proof that there was one.
    ///
    /// THE ONLY WAY TO MAKE ONE IS TO SHOW A REAL DUCK'S IDENTITY, WHICH IS THE
    /// WHOLE TYPE — the same enforcement `DuckBattery` does from the other end,
    /// pointed at the other half of the same lie. `hardware(...)` used to take
    /// the robot's name as a `String`, and a string is a thing anybody can
    /// type: a view with a bench figure in hand, or a test fixture, could hand
    /// one over and get back a number that renders as "Measured on Pip, a real
    /// Microduck". Nothing about that number was measured on a robot, and
    /// nothing downstream could tell — `compare` would refuse it against a
    /// simulated number for being hardware, which is the strongest possible
    /// endorsement of a fabrication.
    ///
    /// TAKING THE IDENTITY RATHER THAN A BOOL OR A NAME, for `DuckBattery`'s
    /// stated reason: an identity is a value that came from a peer saying who
    /// it is, and `SimDuck` and `BenchPeer` both hard-code theirs to `.sim`
    /// with no initialiser parameter that could say otherwise. So the only
    /// identities in this app that answer `.real` are ones a robot's own link
    /// produced.
    ///
    /// A SEPARATE TYPE RATHER THAN A CHECK INSIDE `hardware(...)`, because the
    /// `Source` case is public and its payload is what carries the claim: with
    /// a `String` in there, `Source.hardware(robot: "Pip").provenance` is a
    /// sentence about a real Microduck that anybody can write. With this in
    /// there, the check cannot be gone round, only passed.
    public struct Robot: Equatable, Sendable {

        /// What the duck calls itself, so a number can be found again — the
        /// name off the identity, never a second name typed beside it.
        public let name: String

        /// Nil unless `identity` is a real robot.
        public init?(_ identity: DuckIdentity) {
            guard identity.kind == .real else { return nil }
            self.name = identity.name
        }
    }

    /// Where a number came from, in the only two kinds there are.
    public enum Source: Equatable, Sendable {
        /// Physics on a machine somewhere, under this configuration. The whole
        /// config travels rather than its name, because the friction and the
        /// filled slots are exactly what somebody would need to reproduce the
        /// number, and a name is a pointer to something that may since have
        /// been edited.
        case simulated(SimDuckConfig)
        /// A reading off a robot, named so it can be found again. See `Robot`
        /// for why the payload is not the name.
        case hardware(Robot)

        /// The sentence that goes with any number from this source.
        public var provenance: String {
            switch self {
            case .simulated(let config):
                var said = "Measured in simulation, not on a robot — \(config.name), "
                         + "\(config.mode.rawValue) mode, floor friction "
                         + "\(SimDuckConfig.number(config.floorFriction))"
                if let scene = config.sceneName { said += ", in \(scene)" }
                return said + ". Physics on another machine is not a robot on a floor."
            case .hardware(let robot):
                return "Measured on \(robot.name), a real Microduck."
            }
        }

        /// Whether two numbers describe the same kind of world. Two sim numbers
        /// count even when the configs differ — the configs are then the
        /// interesting part of the comparison, and `compare` says so.
        var kindMatches: (Source) -> Bool {
            switch self {
            case .simulated:
                return { if case .simulated = $0 { return true } else { return false } }
            case .hardware:
                return { if case .hardware = $0 { return true } else { return false } }
            }
        }
    }

    /// What was measured, in words — "distance walked in six seconds".
    public let name: String
    public let value: Double
    public let unit: Unit
    public let source: Source

    private init(name: String, value: Double, unit: Unit, source: Source) {
        self.name = name
        self.value = value
        self.unit = unit
        self.source = source
    }

    /// A number a simulation produced.
    public static func simulated(_ name: String, _ value: Double, in unit: Unit,
                                 under config: SimDuckConfig) -> DuckMeasurement {
        DuckMeasurement(name: name, value: value, unit: unit, source: .simulated(config))
    }

    /// A number a robot produced, or nil when the duck it names is not one.
    ///
    /// NOTHING IN THIS APP CAN CALL THIS YET, and it exists anyway: a `Source`
    /// with one case would not have forced the comparison rules below to be
    /// written, and those rules are the thing that has to be right before the
    /// first hardware number ever arrives.
    ///
    /// IT IS FAILABLE FOR EXACTLY THE REASON `DuckBattery.init?` IS. The
    /// identity of the duck the number came off is the evidence that there was
    /// a duck; a caller holding a simulated identity — every peer this app can
    /// build today holds one — gets nil and has no hardware number to show.
    /// Returning an optional rather than trapping is the same choice made
    /// there: a screen that cannot draw a number draws the sentence instead,
    /// and a fixture that expected one finds out at the call site.
    public static func hardware(_ name: String, _ value: Double, in unit: Unit,
                                onboard identity: DuckIdentity) -> DuckMeasurement? {
        guard let robot = Robot(identity) else { return nil }
        return DuckMeasurement(name: name, value: value, unit: unit, source: .hardware(robot))
    }

    /// The sentence this number must never be shown without.
    public var provenance: String { source.provenance }

    /// The number and its sentence, for anywhere one line is all there is.
    public var says: String {
        "\(name): \(SimDuckConfig.number(value))\(unit.suffix) — \(provenance)"
    }

    /// What came of putting two measurements side by side.
    public enum Comparison: Equatable, Sendable {
        /// They can be compared, and this is `later − earlier` in their shared
        /// unit, with the sentence to print beside it.
        case difference(Double, says: String)
        /// They cannot, and this says why in a sentence somebody can act on.
        case notComparable(String)
    }

    /// Compare two measurements, or refuse to.
    ///
    /// THREE REFUSALS, AND THE FIRST IS THE ONE THIS FILE EXISTS FOR. A
    /// simulated number against a hardware number is the comparison somebody
    /// most wants to make and the one that means least: it would read as "the
    /// robot is 9 cm worse than the simulator" when what it measures is the gap
    /// between a rigid-body approximation and a floor. The other two — a
    /// different unit, a different quantity — are the ordinary mistakes, and
    /// they are refused in the same voice so that no refusal here looks like a
    /// special case.
    public static func compare(_ earlier: DuckMeasurement,
                               _ later: DuckMeasurement) -> Comparison {
        guard earlier.source.kindMatches(later.source) else {
            return .notComparable(
                "One of these was measured in simulation and the other on a robot. The "
              + "difference between them is not a fact about either duck — it is the gap "
              + "between physics on a machine and a duck on a floor, which nothing here has "
              + "measured.")
        }
        guard earlier.unit == later.unit else {
            return .notComparable(
                "\(earlier.name) is in \(earlier.unit.rawValue.isEmpty ? "a fraction" : earlier.unit.rawValue) "
              + "and \(later.name) is in "
              + "\(later.unit.rawValue.isEmpty ? "a fraction" : later.unit.rawValue). "
              + "Subtracting one from the other would produce a number with no units at all.")
        }
        guard earlier.name == later.name else {
            return .notComparable(
                "\(earlier.name) and \(later.name) are different quantities. They share a "
              + "unit, which is not the same as measuring the same thing.")
        }
        let delta = later.value - earlier.value
        var said = "\(SimDuckConfig.number(abs(delta)))\(later.unit.suffix) "
                 + (delta < 0 ? "less" : "more") + " than before."
        if case .simulated(let a) = earlier.source, case .simulated(let b) = later.source,
           a != b {
            said += " Both in simulation, but not under the same configuration — the "
                  + "difference includes whatever changed between them."
        }
        return .difference(delta, says: said)
    }
}

// MARK: - the peer

/// A simulated duck this app can drive, as a peer like any other.
///
/// IT IMPLEMENTS THE VOCABULARY AND OWNS NONE OF THE BYTES. `DuckPeer` is where
/// the rules live — which methods this link carries, which direction each goes
/// — and this type enforces them through `vet` and then hands one NDJSON line
/// to a closure the caller supplied. That split is what lets every path in here
/// be driven by `swift test` on Linux with nothing listening, which is the same
/// argument `CameraAvailability` makes for taking three facts as parameters
/// rather than importing ARKit.
///
/// IT SPEAKS LINES, AND THE BENCH IS NOT A LINE — WHICH IS WHY `.bench` IS NOT
/// SOMETHING THIS TYPE CAN BE HANDED. Everything that leaves here is
/// `DuckCall.line(id:)`: one NDJSON JSON-RPC object, newline-terminated, in
/// `framing.rs`' framing. `sim/duckbench.mjs` does not speak that. It takes
/// `POST /intent {vx, vy, vyaw, hold}`, and a JSON-RPC line posted at it parses
/// as a body with no `vx`, no `vy` and no `vyaw` in it — a ZERO TWIST. A duck
/// that stands perfectly still while the app reports it walking, with no error
/// anywhere, is the worst failure this package can produce, and this type
/// defaulted to it: `transport` was a `DuckTransportKind` whose default was
/// `.bench`. So the parameter's TYPE is now `LineTransport`, which has no bench
/// case to pass, and the default is gone: a caller names the link their closure
/// speaks or does not get a peer. `LineTransport` is also where the one other
/// exclusion is argued — Bluetooth carries these lines and carries them to a
/// robot somebody has bonded with.
///
/// THE BENCH ADAPTER ALREADY EXISTS AND IT IS `BenchPeer`. It is the same
/// `DuckPeer` vocabulary with `DuckDrive` underneath it, turning `.move` into
/// the POST the bench actually answers and `hello` into `/health`, and it
/// names the four things a bench cannot do rather than posting them into a
/// void. Anything that wants to drive `duckbench.mjs` wants that type. The
/// alternative — teaching this one to emit a bench body when its transport was
/// `.bench` — would have put two wire formats behind one closure typed
/// `(Data) async throws -> Data?`, where the caller's closure cannot tell which
/// of the two it has been handed, and it would have made a second copy of
/// `DuckDrive`'s bench knowledge for the two to disagree about later.
///
/// AN ACTOR BECAUSE THE ID COUNTER IS STATE AND `DuckPeer` IS `Sendable`. There
/// is exactly one piece of mutable state in this type and it is the JSON-RPC id
/// to use next; two tasks driving one duck must not both get id 7, because the
/// reply to one would be read as the reply to the other. An `@unchecked
/// Sendable` class with a lock would do the same job while asking the reader to
/// take the locking on trust.
///
/// ONE WRITER PER DUCK IS STILL NOT ENFORCED HERE, and `DuckPeer` says why:
/// `intents.rs` is last-writer-wins on a single slot, so two clients at 50 Hz
/// "interleave into one slot, producing a robot that obeys neither". Serialising
/// this peer's own writes does not help with that; the fix is a token the duck
/// hands out, which lives a layer above.
public actor SimDuck: DuckPeer {

    /// A transport a `SimDuck` can honestly be put on.
    ///
    /// TWO QUESTIONS, AND A TRANSPORT HAS TO ANSWER BOTH. Does a line of
    /// `duck-ipc-proto` go down this link as it stands, and can a simulation be
    /// the thing on the far end of it? WebRTC and a bridge answer yes twice —
    /// the contract says the continuous intents will travel over WebRTC, and a
    /// bridge is another copy of this app relaying this same vocabulary to a
    /// duck of either kind. The other two each fail one of the questions, and
    /// `whyNot(_:)` carries the sentence for each.
    ///
    /// THIS IS A SEPARATE ENUM RATHER THAN A CHECK IN THE INITIALISER, so
    /// wiring a bench to this peer is a line the compiler refuses to compile
    /// rather than a refusal somebody meets at runtime while holding a phone. A
    /// thrown error would have been the second-best answer and it is a long way
    /// second: the call site that is wrong is the one being written, not the
    /// one being run.
    public enum LineTransport: String, CaseIterable, Sendable {
        case webRTC
        case bridge

        /// Which link this is, for `reach` and for `vet`.
        public var kind: DuckTransportKind {
            switch self {
            case .webRTC: return .webRTC
            case .bridge: return .bridge
            }
        }

        /// The same question asked of a transport, answered for every one of
        /// them.
        ///
        /// EXHAUSTIVE OVER `DuckTransportKind` WITH NO `default`, copying
        /// `DuckMethod.reach(for:)`'s discipline and for its stated reason: a
        /// transport added to that enum stops this file compiling until
        /// somebody says whether a sim duck belongs on it. A `default: return
        /// nil` would answer no for every future transport silently, and the
        /// first symptom would be a peer nobody could construct for a link that
        /// would have worked.
        public init?(_ kind: DuckTransportKind) {
            switch kind {
            case .webRTC: self = .webRTC
            case .bridge: self = .bridge
            case .bench, .ble: return nil
            }
        }

        /// Why a transport is not one of these, or nil for the two that are.
        ///
        /// A SENTENCE PER REFUSAL, FOR THE REASON `BenchPeer.refusal(for:)`
        /// GIVES: a screen that cannot offer a link has to say what is missing
        /// on the other end, and a refusal with no reason reads as this app
        /// being broken.
        public static func whyNot(_ kind: DuckTransportKind) -> String? {
            switch kind {
            case .webRTC, .bridge: return nil
            case .bench: return benchIsNotALine
            case .ble: return bluetoothIsABondWithSomethingPhysical
            }
        }

        /// The bench speaks a different wire, and this is the failure that
        /// wire mismatch produces.
        public static let benchIsNotALine =
            "A bench is not one of these. sim/duckbench.mjs answers HTTP posts — /intent takes "
          + "vx, vy, vyaw and a hold — and never a JSON-RPC line, so a line posted at it reads "
          + "as a body with no velocities in it: a zero twist, a duck standing still, and no "
          + "error to see. BenchPeer is the type that speaks to a bench, and it already says "
          + "what a bench cannot do."

        /// Bluetooth carries the line and cannot carry a simulation.
        ///
        /// THE REACH TABLE IS THE ARGUMENT. `DuckMethod.reach(for: .ble)` is
        /// `hello` plus the recovery path — the pairing PIN and the updater —
        /// because BLE is how somebody standing next to a robot gets back into
        /// it. A simulated duck there would advertise a PIN it does not have
        /// and firmware it cannot be given, while being able to say exactly one
        /// word of the vocabulary. Nothing in this app has ever put physics
        /// behind a GATT characteristic, and a peer that let somebody try would
        /// be offering a recovery path for a thing that cannot be lost.
        public static let bluetoothIsABondWithSomethingPhysical =
            "Bluetooth is not one of these. It carries these lines — DuckLink writes them over "
          + "a characteristic — but what it carries them to is a robot somebody has bonded with "
          + "and is standing next to: reach over BLE is hello plus the pairing PIN and the "
          + "updater, which are the way back into a duck that has stopped answering. A "
          + "simulation has no PIN, no firmware, and nothing to be locked out of, so a sim duck "
          + "here would offer a recovery path for something that cannot be lost."
    }

    /// One line out, and the line that came back — nil when nothing did.
    ///
    /// `Data` IN AND `Data` OUT RATHER THAN A `DuckCall`, so the closure is a
    /// transport and not a second place where the vocabulary is interpreted.
    /// Everything about what a call means has already happened by the time this
    /// is invoked.
    public typealias Wire = @Sendable (Data) async throws -> Data?

    /// What this duck is configured as. It travels with every measurement this
    /// peer produces, which is why it is public.
    public nonisolated let config: SimDuckConfig

    /// KIND IS HARD-CODED `.sim` AND IS NOT AN INITIALISER PARAMETER. A
    /// `SimDuck` that could be introduced as a robot would make every screen's
    /// "Simulated" badge a suggestion. There is no way to construct this type
    /// with any other kind, which is the same enforcement `DuckBattery` uses
    /// from the other end.
    public nonisolated let identity: DuckIdentity

    /// Which link the caller's closure actually speaks.
    ///
    /// THERE IS NO DEFAULT, AND THAT IS THE SECOND HALF OF THE FIX. The type
    /// already makes a bench impossible to name; a default would make one of
    /// the three remaining links the one people got without deciding, and this
    /// peer has never actually been on any of them — `BenchPeer` is what has
    /// reached a simulator. A default here would be a claim about a link this
    /// app has not written, chosen for the convenience of not typing it.
    public nonisolated let transport: LineTransport

    /// Exactly `DuckMethod.reach(for:)` for this transport — never wider, as
    /// `DuckPeer` requires. A sim duck does not get extra reach for being ours.
    /// Derived from the link rather than stored beside it, so it cannot come
    /// to name a transport whose reach set this peer is not using.
    public nonisolated var transportKind: DuckTransportKind { transport.kind }
    public nonisolated let reach: Set<DuckMethod>

    private let wire: Wire

    /// The next JSON-RPC id. Starts at 1 rather than 0 so that a zero in a log
    /// is a bug rather than the first call.
    private var nextID = 1

    public init(config: SimDuckConfig,
                over transport: LineTransport,
                wire: @escaping Wire) {
        self.config = config
        self.identity = DuckIdentity(name: config.name, colourway: config.colourway, kind: .sim)
        self.transport = transport
        self.reach = DuckMethod.reach(for: transport.kind)
        self.wire = wire
    }

    // MARK: - the three things it will not claim

    /// Always nil, and nil for a reason a future edit cannot remove.
    ///
    /// THIS DELIBERATELY ASKS FOR THE BEST POSSIBLE READING AND GETS NOTHING.
    /// A plain `{ nil }` would be a body somebody could later replace with a
    /// number while the doc comment above it still said there was no battery.
    /// Asking `DuckBattery` for 100% and being refused puts the rule in the
    /// type: as long as this peer's identity is `.sim` — and it cannot be
    /// anything else — there is no percentage to be had.
    public nonisolated var battery: DuckBattery? { DuckBattery(percent: 100, of: identity) }

    /// What this duck's camera shows: nothing, because nothing renders it.
    /// See `SimVision`, which has no case that means otherwise.
    public nonisolated var vision: SimVision { .noImage }

    /// A number this duck produced, stamped with the configuration that
    /// produced it. The only way to get a `DuckMeasurement` out of a sim duck,
    /// and it cannot produce an unstamped one.
    public nonisolated func measured(_ name: String, _ value: Double,
                                     in unit: DuckMeasurement.Unit) -> DuckMeasurement {
        .simulated(name, value, in: unit, under: config)
    }

    // MARK: - saying the vocabulary

    /// Ask, and wait.
    public func call(_ c: DuckCall) async throws -> DuckReply {
        try vet(c, asNotification: false)
        let id = nextID
        nextID += 1
        guard let answer = try await wire(try c.line(id: id)) else {
            throw DuckLink.LinkError.unexpected(
                "\(c.method.rawValue) was asked and nothing came back. It is a call that is "
              + "answered, so silence is the link failing rather than the duck declining.")
        }
        let reply = try DuckReply.decode(answer)
        // AN ID THAT DOES NOT MATCH IS WORSE THAN NO REPLY, because it is a
        // reply to somebody else's question being read as the answer to this
        // one. A reply carrying no id at all is let through, and that is
        // JSON-RPC 2.0's own case rather than a leniency invented here: a
        // response to a request the far end could not parse carries `"id":
        // null`, which is exactly the reply somebody most needs to see, and
        // refusing it would replace the duck's own refusal with a sentence
        // accusing two clients of talking at once.
        if let answered = reply.id, answered != id {
            throw DuckLink.LinkError.unexpected(
                "Asked \(c.method.rawValue) as \(id) and got the answer to \(answered). Two "
              + "things are talking to this duck at once, and neither can trust what comes back.")
        }
        return reply
    }

    /// Say, and do not wait.
    ///
    /// A REPLY TO A NOTIFICATION IS DROPPED RATHER THAN REFUSED. What the
    /// contract forbids is the id — a continuous intent is never answered, so
    /// it must not carry one — and `DuckCall.line(id:)` already enforces that.
    /// Whether bytes come back is the transport's business, and the same
    /// closure carries both directions for every call this peer makes: a
    /// carrier that answers each write, or a relay that acknowledges one, hands
    /// back something here. It cannot be the answer to anything, because no id
    /// went out for it to answer, so discarding it is the only honest thing to
    /// do with it. Throwing instead would refuse a link over a byte that meant
    /// nothing.
    public func notify(_ c: DuckCall) async throws {
        try vet(c, asNotification: true)
        _ = try await wire(try c.line(id: nil))
    }

    // MARK: - what this duck says without being asked

    private nonisolated let fan = DuckStateFanOut()

    /// Every state this duck reports — which, on this peer, is every state a
    /// test has fed it and nothing else.
    ///
    /// THIS PEER HAS NO INBOUND STREAM AND CANNOT ACQUIRE ONE. `Wire` is
    /// `(Data) -> Data?`: one line out, at most one line back, which is a
    /// request/response shape with nowhere for telemetry to arrive. A real
    /// `robotd` pushes `robot.state` unbidden at the loop rate, so a peer that
    /// wanted to carry those needs a stream that exists whether or not anybody
    /// asked anything — and that peer is `LinePeer`, which takes exactly that.
    ///
    /// SO WHY IMPLEMENT IT AT ALL RATHER THAN FINISHING THE STREAM EMPTY?
    /// Because a screen written against `DuckPeer.states()` has to be drivable
    /// without a robot, a bench or a socket, and this is the peer every test in
    /// this package already builds. `feed(_:)` is how a test says "now the duck
    /// falls over" and watches what a card does about it. It is not a
    /// simulation of telemetry — nothing here generates a state — it is a hand
    /// on the other end of the stream, which is the honest thing for a type
    /// whose whole job is standing in for a duck.
    public nonisolated func states() -> AsyncStream<DuckState> { fan.states() }

    /// Hand one canned state to every reader.
    ///
    /// NOTHING IN THE APP TARGET CALLS THIS AND NOTHING SHOULD. A view that fed
    /// a state it composed itself would be a view inventing telemetry, which is
    /// the one thing `DuckState`'s all-optional design exists to make
    /// impossible from the decoding side; there is no reason to reintroduce it
    /// from the publishing side. `scripts/check_no_studio_math.sh` will not
    /// catch that, so it is said here.
    public func feed(_ state: DuckState) {
        fan.publish(state)
    }

    /// End every reader's stream, the way a dropped link would.
    public func stopFeeding() {
        fan.finish()
    }
}
