import Foundation

/// The seven answers the app's front door owes somebody, worked out here so the
/// screen only draws them.
///
/// WHY THIS TYPE EXISTS. "My Microduck" is the first thing a person sees, and
/// what it has to answer is a fixed list in a fixed order: which duck is this,
/// is it online, what is its charge, what is it doing, can I safely control it,
/// what can I launch, and is anything wrong. Every one of those is a JUDGEMENT
/// — a date compared against a tolerance, a method looked up in a routing
/// table, an error turned into the sentence its own type wrote — and a
/// judgement made inside a `View` is a judgement nothing on Linux can check.
/// Two of them have already been made twice in this app: `DriveView` computes
/// the state word from `upright` and `running` in a private property, and
/// computes what a link carries from `peer.reach` in another. A second screen
/// asking the same questions is the moment those answers start to disagree, and
/// the disagreement shows up as one screen saying "Driving" while the other
/// says "Upright" about the same duck.
///
/// EVERY SENTENCE HERE IS EITHER AN EXISTING KIT STRING OR ONE THIS FILE'S
/// TESTS PIN. That is the house rule the whole package is built on — a refusal
/// message is the product, and one you cannot test is one you find out about in
/// review — and it bites hardest here, because the front door is where an
/// honest "not yet" has to be said out loud rather than drawn as an empty card.
/// `Banner` in particular composes NOTHING: each alarm carries the message the
/// erroring type already wrote, so there is exactly one copy of every sentence
/// a person can be shown about a link that will not work.
///
/// NO CLOCK IS READ IN THIS FILE. `Presence` takes the current date as an
/// argument, which is what makes "this duck answered eleven seconds ago and is
/// therefore not live" a thing a test can assert rather than a thing that
/// depends on when the test ran.
public enum DeviceCard {

    // MARK: - 4. what is it doing

    /// The five words this app has for what a duck is doing, and the one place
    /// they are spelled.
    ///
    /// THEY ARE `DriveView.duckWord`'S OWN STRINGS, BYTE FOR BYTE. That screen
    /// wrote them into a private computed property, which was fine while it was
    /// the only screen that drove anything; the front door now shows the same
    /// word about the same duck, and two copies of "Waiting for the bench" is
    /// two copies that get edited apart. `DriveView` references these constants
    /// rather than its literals.
    ///
    /// A WORD AND NEVER A COLOUR ALONE. `StateBadge` already refuses to draw a
    /// dot without a word beside it, and the reason is in that component's own
    /// preamble: "Driving" and "Upright" are the same dot to roughly one man in
    /// twelve, and they are the difference between a duck that is walking and a
    /// duck that is standing there.
    public enum Doing {

        /// Nothing has been commanded and nothing is coming back.
        public static let notDriving = "Not driving"

        /// A command is in flight and no state block has come back yet.
        public static let waitingForTheBench = "Waiting for the bench"

        /// The state block says the trunk is not upright. A FALLEN DUCK IS
        /// STILL ACTIVE — the policy is running and the servos are moving — so
        /// this is a claim about the pose and not about the machine.
        public static let onItsSide = "On its side"

        /// Upright, and being driven.
        public static let driving = "Driving"

        /// Upright, and standing there.
        public static let upright = "Upright"

        /// The word, from the two facts that decide it.
        ///
        /// LIFTED FROM `DriveView.duckWord` WITH ITS BRANCHES INTACT, including
        /// the order: a duck that is on its side is on its side whether or not
        /// somebody is holding the stick, so the pose is tested before the
        /// driving.
        ///
        /// - Parameter upright: What the last state block said, or nil when no
        ///   state block has come back on this link at all. Nil is not `false`:
        ///   "nothing has answered" and "it is lying down" are the two facts
        ///   this screen exists to keep apart.
        /// - Parameter running: Whether this app is asking it to move.
        ///
        /// `Self.` ON THE RETURNS BECAUSE THE PARAMETER IS CALLED `upright` AND
        /// SO IS ONE OF THE CONSTANTS. Renaming either would be worse: the
        /// parameter is named after `DuckDrive.Live.upright`, which is where
        /// the value comes from, and the constant is named after the word on
        /// the glass.
        public static func word(upright: Bool?, running: Bool) -> String {
            guard let upright else {
                return running ? Self.waitingForTheBench : Self.notDriving
            }
            if !upright { return Self.onItsSide }
            return running ? Self.driving : Self.upright
        }
    }

    // MARK: - 1. which Microduck

    /// The name at the top of the card, and — the part that matters — where
    /// that name came from.
    ///
    /// A NAME WITHOUT ITS PROVENANCE IS A NAME THIS APP IS ASKING TO BE
    /// TRUSTED FOR NO REASON. Four different things end up in this field and
    /// they are worth wildly different amounts: a string the person typed into
    /// Manage benches is worth what they meant by it; a bench's hostname is
    /// what `BenchPeer.init` falls back to precisely because `/health` answers
    /// "duck-bench" for every bench on the desk; a BLE local name is an
    /// advertisement anything can broadcast; and `system.info`'s name is the
    /// robot itself answering. Only the last of those is the duck saying who it
    /// is, and a card that printed all four in the same weight would be
    /// flattening that difference on the one screen where it decides whether
    /// somebody is looking at the duck they think they are.
    public struct Who: Equatable, Sendable {

        /// Where the name came from, most authoritative last.
        public enum Source: String, Equatable, Sendable, CaseIterable {
            /// Somebody typed it into Manage benches.
            case typedByYou
            /// The host part of the bench's address — `BenchPeer`'s fallback.
            case benchHost
            /// What a Bluetooth advertisement called itself.
            case localName
            /// `system.info` — the robot's own answer.
            case systemInfo

            /// What this name is worth, in one sentence, for the line under it.
            ///
            /// THE `localName` CASE IS THE ONE WITH A KNOWN HOLE IN IT and it
            /// says so in `DuckLink`'s own words rather than in new ones: an
            /// identifier is not an identity, and a duck whose Bluetooth
            /// address has changed comes back looking like one this app has
            /// never seen.
            public var says: String {
                switch self {
                case .typedByYou:
                    return "You named this one. It is whatever you typed in Manage benches, and "
                         + "nothing on the other end has agreed to it."
                case .benchHost:
                    return "Named after the address it answers on, because nobody typed anything "
                         + "better. A bench's /health says which SOFTWARE is running — "
                         + "\"duck-bench\" — which is the same word for every bench on the desk."
                case .localName:
                    return "This is the name a Bluetooth advertisement gave, not an answer to a "
                         + "question. " + DuckLink.identifierIsNotAnIdentity
                case .systemInfo:
                    return "The robot answered system.info with this name, so this is the duck "
                         + "saying who it is rather than this app guessing."
                }
            }
        }

        public let name: String
        public let nameCameFrom: Source
        public let colourway: DuckColourway
        public let kind: DuckIdentity.Kind

        public init(name: String, nameCameFrom: Source,
                    colourway: DuckColourway, kind: DuckIdentity.Kind) {
            self.name = name
            self.nameCameFrom = nameCameFrom
            self.colourway = colourway
            self.kind = kind
        }

        /// Build the card's identity block from whatever this app actually has.
        ///
        /// THE ORDER OF AUTHORITY IS THE WHOLE FUNCTION, and it is: the robot's
        /// own answer, then the person's own word, then whatever the identity
        /// arrived carrying. `system.info` first because it is the only source
        /// here that came from the duck; the typed name second because a person
        /// who has named their bench "Kitchen" is telling this app something
        /// true that no host lookup knows; and the identity's own name last,
        /// labelled by kind — a `.sim` name is the bench host `BenchPeer` fell
        /// back to, and a `.real` one arrived in an advertisement.
        ///
        /// THE KIND AND THE COLOURWAY ARE NEVER OVERRIDDEN, whatever else is
        /// handed in. `DuckIdentity.Kind` is a claim about whether something in
        /// a room can fall over, and `system.info` does not carry it — a
        /// factory that promoted a duck to `.real` because a name arrived would
        /// be the exact defect `DuckIdentity`'s preamble was written against.
        ///
        /// - Parameter typed: What somebody typed for this connection, if
        ///   anything. Whitespace-only counts as nothing, because an accidental
        ///   space is not a name.
        public static func of(_ identity: DuckIdentity,
                              typed: String? = nil,
                              systemInfo: DuckLink.SystemInfo? = nil) -> Who {
            if let systemInfo, !systemInfo.name.trimmingCharacters(in: .whitespaces).isEmpty {
                return Who(name: systemInfo.name, nameCameFrom: .systemInfo,
                           colourway: identity.colourway, kind: identity.kind)
            }
            if let typed, !typed.trimmingCharacters(in: .whitespaces).isEmpty {
                return Who(name: typed, nameCameFrom: .typedByYou,
                           colourway: identity.colourway, kind: identity.kind)
            }
            return Who(name: identity.name,
                       nameCameFrom: identity.kind == .sim ? .benchHost : .localName,
                       colourway: identity.colourway, kind: identity.kind)
        }

        /// The one word beside the name that says whether anything can break.
        /// `DuckIdentity.Kind.label` lowercased is "robot" or "simulated"; the
        /// card wants the shorter pair the design asks for.
        public var kindWord: String {
            switch kind {
            case .real: return "real"
            case .sim: return "sim"
            }
        }
    }

    // MARK: - 2. is it online

    /// Whether anything has come back lately, and the sentence for each answer.
    ///
    /// A DATE AND A TOLERANCE, NOT A BOOLEAN SOMEBODY SETS. "Connected" is not
    /// a state any of this app's transports actually has: the bench is HTTP,
    /// which has no connection to be in, and its world only advances inside a
    /// request — `BenchPeer.theWorldOnlyMovesWhenAsked` is that paragraph. So
    /// the only honest thing to say is when something last answered, and to be
    /// explicit about the fact that silence here is ambiguous.
    ///
    /// THE THIRD SENTENCE IS THE HONEST ONE AND IT COSTS A LINE. A screen that
    /// showed a grey dot after ten seconds would be telling somebody their duck
    /// had gone away, when in fact this screen only asks on appear and on pull
    /// to refresh. So the stale sentence says both halves: nothing has come
    /// back, AND nothing has been asked.
    public struct Presence: Equatable, Sendable {

        /// When the last reply came back on this link, or nil if none ever has.
        public let lastReplyAt: Date?

        /// Which link that was, so the sentence can name it.
        public let transport: DuckTransportKind

        public init(lastReplyAt: Date?, transport: DuckTransportKind) {
            self.lastReplyAt = lastReplyAt
            self.transport = transport
        }

        /// How recent a reply has to be for this screen to call the duck live.
        ///
        /// TEN SECONDS, AND THE NUMBER IS A JUDGEMENT ABOUT A PERSON RATHER
        /// THAN ABOUT A NETWORK. A bench on the same desk answers `/health` in
        /// single-digit milliseconds, so any tolerance at all is generous by
        /// the network's standards; what it is really sized for is the reading
        /// time of the card. Somebody who has just pulled to refresh should see
        /// "answering" for as long as it takes to read the rest of the screen,
        /// and a card left open while the bench is killed on the other computer
        /// should stop claiming to be live before they walk back to it.
        public static let answeringWithin: TimeInterval = 10

        /// Live means "answered inside the tolerance", and nothing else.
        ///
        /// `now` IS AN ARGUMENT BECAUSE THIS PACKAGE DOES NOT READ CLOCKS. A
        /// `Date()` in here would make every one of the three sentences below
        /// assertable only by a test that ran fast enough, which is the kind of
        /// test that passes on a laptop and fails on a busy machine at three in
        /// the morning.
        ///
        /// A REPLY DATED IN THE FUTURE IS STILL A REPLY. Clocks move, and a
        /// negative interval here would otherwise fail the comparison and
        /// report a duck that answered a moment ago as gone.
        public func isLive(now: Date) -> Bool {
            guard let lastReplyAt else { return false }
            return now.timeIntervalSince(lastReplyAt) <= Self.answeringWithin
        }

        /// Which of the three things is true.
        public enum Standing: Equatable, Sendable {
            /// Something answered, inside the tolerance.
            case answering
            /// Something answered once, and not lately.
            case waiting
            /// Nothing has ever answered on this link.
            case neverAnswered
        }

        public func standing(now: Date) -> Standing {
            guard lastReplyAt != nil else { return .neverAnswered }
            return isLive(now: now) ? .answering : .waiting
        }

        /// The sentence under the name.
        public func says(now: Date) -> String {
            let link = transport.label
            switch standing(now: now) {
            case .answering:
                return "Answering. The last reply came back over \(link) within the "
                     + "last \(Self.seconds) seconds."
            case .waiting:
                return "Asked, and nothing since. The last reply over \(link) is more "
                     + "than \(Self.seconds) seconds old — which can equally mean the duck has "
                     + "gone away or that nothing has been asked, because this screen only asks "
                     + "when it opens and when you pull to refresh."
            case .neverAnswered:
                return "Nothing has ever come back over \(link) on this connection. Pull to "
                     + "refresh to ask."
            }
        }

        /// The tolerance as it is written into the sentences. An `Int` because
        /// "10.0 seconds" in a sentence is a number pretending to be measured.
        static var seconds: Int { Int(answeringWithin) }
    }

    // MARK: - 3. battery

    /// What to put in the charge row, in words.
    ///
    /// TWO CASES, AND NEITHER OF THEM IS A NUMBER. `DuckBattery` already
    /// refuses to exist for a duck that is not `.real`, and its own preamble
    /// says why a dash is not good enough either: "—" in a battery row reads as
    /// a reading that failed to arrive, which invites somebody to reconnect and
    /// try again, and there is nothing to reconnect to. The second case is the
    /// gap that type does not cover: a REAL duck, on a link that carries no
    /// call which answers with a charge. `DuckMethod` has no such call — the
    /// whole vocabulary is hello, the driving surface, state, the pairing PIN
    /// and the updater — so this app has never read a cell and must not draw a
    /// bar as though it had.
    ///
    /// WHEN A BATTERY CALL ARRIVES, A THIRD CASE ARRIVES WITH IT. It is not
    /// modelled today because there is nothing behind it: a `case charged(Int)`
    /// sitting here unfilled is an invitation for a screen to fill it with a
    /// plausible number.
    public enum Charge: Equatable, Sendable {

        /// Physics on another machine. Carries `DuckBattery.noneToRead`.
        case noneToRead(String)

        /// Hardware, on a link with no call that answers with a charge.
        case notReported(String)

        /// The sentence, whichever case this is.
        public var says: String {
            switch self {
            case .noneToRead(let sentence), .notReported(let sentence): return sentence
            }
        }

        /// What a link that carries no charge has to say for itself.
        ///
        /// A NEW SENTENCE RATHER THAN A REUSE, because the two absences have
        /// different causes and a person can act on exactly one of them.
        /// `DuckBattery.noneToRead` is about the duck — there is no cell. This
        /// is about the link — there is a cell and nothing in this vocabulary
        /// asks it anything.
        public static let linkCarriesNoCharge =
            "No charge reading. This link carries hello, the driving calls and a state read, and "
          + "none of them answers with a battery — so a percentage here would be this app "
          + "putting a number on a cell it has never asked about."

        /// Which of the two absences this duck has.
        ///
        /// IT TAKES THE IDENTITY RATHER THAN A BOOL, for `DuckBattery.init?`'s
        /// own stated reason: a `isReal: Bool` parameter is a thing a caller
        /// passes `true` to by accident, while an identity is a value that came
        /// from a peer saying who it is.
        public static func of(_ identity: DuckIdentity) -> Charge {
            switch identity.kind {
            case .sim: return .noneToRead(DuckBattery.noneToRead)
            case .real: return .notReported(linkCarriesNoCharge)
            }
        }
    }

    // MARK: - 5. can I safely control it

    /// Whether a control may be drawn at all, and — when it may not — which
    /// call is missing and on which link.
    ///
    /// THE RULE THIS TYPE EXISTS FOR: A CONTROL IS NEVER PRESENT AND INERT. A
    /// Drive button that is drawn and does nothing is worse than no button,
    /// because pressing it teaches somebody that this app is broken rather than
    /// that this link does not carry `robot.move`. So the affordance is
    /// conditioned on `state == .live`, and `.absent` carries the reason as a
    /// sentence the screen prints in its place.
    ///
    /// BOTH HALVES OF THE ANSWER COME FROM SOMEWHERE ELSE. The routing table
    /// says what a transport carries — `DuckMethod.reach(for:)`, which is the
    /// single copy of that decision — and `BenchPeer.refusal(for:)` says what
    /// this particular kind of peer cannot do even inside its reach. A type
    /// that listed either of them again would be a table that agrees on the day
    /// it is written and drifts afterwards, and the symptom of the drift is a
    /// dead control with a sentence beside it that is no longer true.
    public struct Control: Equatable, Sendable {

        public enum State: Equatable, Sendable {
            /// Draw the control.
            case live
            /// Do not draw the control. Print this instead.
            case absent(reason: String)
        }

        public let method: DuckMethod
        public let state: State

        public init(method: DuckMethod, state: State) {
            self.method = method
            self.state = state
        }

        public var isLive: Bool { state == .live }

        /// The reason, when there is one.
        public var reason: String? {
            if case .absent(let reason) = state { return reason }
            return nil
        }

        /// Work out whether a control may be drawn for this method on this
        /// link.
        ///
        /// THE ORDER OF THE TWO CHECKS IS `BenchPeer.call`'S ORDER, and for the
        /// same reason turned around. There, the named refusal goes first
        /// because a person who has pressed something wants to know what the
        /// bench is missing rather than that a table said no. Here the routing
        /// table goes first, because a method that is not carried at all is not
        /// a fact about a bench: on Bluetooth there is no bench to have a
        /// refusal, and `BenchPeer.refusal(for:)`'s sentences would be
        /// describing a simulator that is not on the other end.
        ///
        /// - Parameter reach: What the link carries. Passed in rather than
        ///   derived from `transport` so a peer that has NARROWED its reach — a
        ///   robot on an older API version, which `DuckPeer` explicitly allows
        ///   — is answered on what it actually carries.
        public static func of(_ method: DuckMethod,
                              over transport: DuckTransportKind,
                              reach: Set<DuckMethod>) -> Control {
            guard reach.contains(method) else {
                return Control(method: method,
                               state: .absent(reason: DuckCall.Misuse
                                   .outOfReach(method, transport).message))
            }
            if transport == .bench, let call = benchCall(for: method),
               let refusal = BenchPeer.refusal(for: call) {
                return Control(method: method, state: .absent(reason: refusal.message))
            }
            return Control(method: method, state: .live)
        }

        /// The call shape to ask `BenchPeer.refusal(for:)` about.
        ///
        /// ONLY THE TWO METHODS THE FRONT DOOR ASKS ABOUT — `robot.move` and
        /// `robot.stop` — because those are the two whose controls this card
        /// decides. A method with no shape here is answered by the routing
        /// table alone, which is the honest outcome: this returns nil rather
        /// than inventing a `DuckHead` of zeroes to ask a question about.
        private static func benchCall(for method: DuckMethod) -> DuckCall? {
            switch method {
            case .move: return .move(.still)
            case .stop: return .stop
            default: return nil
            }
        }
    }

    // MARK: - 7. is anything wrong

    /// One thing that is wrong, in the words of whichever type found it.
    ///
    /// THE SENTENCE IS NEVER WRITTEN HERE. Every constructor below takes an
    /// error this package already defines and lifts that error's own `message`,
    /// `reason` or `says`. This is `DriveView.report`'s funnel argument stated
    /// as a type: every refusal this app can suffer is a paragraph somebody
    /// wrote in the kit, and the only way one of them reaches a person is for
    /// the code that receives it to ask its own type. Anything that composed a
    /// new sentence here would be a second, untested copy of a message that
    /// already exists — which is how "The operation couldn't be completed" ends
    /// up on a screen.
    public struct Alarm: Equatable, Sendable, Identifiable {

        /// How loud. `critical` is drawn in the refusal colour and `warning` in
        /// the warning one; `Theme` owns which those are.
        ///
        /// THE LINE BETWEEN THEM IS WHETHER THE LINK WORKS AT ALL. A bench that
        /// is not there, a body that is not a bench, a radio that is off: those
        /// are critical, because nothing on this screen below the banner is
        /// true while one of them holds. A call that was refused on a link that
        /// is otherwise answering is a warning: the duck is there, and one
        /// thing you asked for is not available.
        public enum Severity: Int, Comparable, Sendable, CaseIterable {
            case critical = 0
            case warning = 1

            public static func < (a: Severity, b: Severity) -> Bool {
                a.rawValue < b.rawValue
            }
        }

        /// Which type wrote the sentence. FOR THE READER OF THE CODE AND FOR
        /// THE TESTS, not for the screen: a person does not need to be told
        /// that a sentence came from `BenchSetup`, and a maintainer chasing a
        /// wrong sentence needs to know exactly which file to open.
        public enum Source: String, Equatable, Sendable, CaseIterable {
            case benchSetup
            case pairingSpike
            case benchRead
            case benchRefusal
            case duckRefusal
        }

        public let severity: Severity
        public let sentence: String
        public let source: Source

        public var id: String { "\(source.rawValue)·\(sentence)" }

        public init(severity: Severity, sentence: String, source: Source) {
            self.severity = severity
            self.sentence = sentence
            self.source = source
        }

        /// A setup diagnosis, unless it is the one that is not a problem.
        ///
        /// `.connected` RETURNS NIL RATHER THAN A CHEERFUL ALARM. Its message
        /// is "Connected. 9 policies available to run." — true, useful on the
        /// setup screen, and on the front door it would be a red bar saying
        /// everything is fine. The banner's whole contract is that it is
        /// present only when something is wrong.
        public static func of(_ diagnosis: BenchSetup.Diagnosis) -> Alarm? {
            guard !diagnosis.isConnected else { return nil }
            return Alarm(severity: .critical, sentence: diagnosis.message, source: .benchSetup)
        }

        /// The phone's own radio. CRITICAL, AND IT IS NOT ABOUT THE DUCK —
        /// which is the first thing every one of `RadioProblem`'s sentences
        /// says, in its own words.
        public static func of(_ problem: PairingSpike.RadioProblem) -> Alarm {
            Alarm(severity: .critical, sentence: problem.reason, source: .pairingSpike)
        }

        /// A read that did not come back as a bench.
        public static func of(_ error: DuckBench.ReadError) -> Alarm {
            Alarm(severity: .critical, sentence: error.message, source: .benchRead)
        }

        /// A call this bench cannot carry. A WARNING, because a peer that can
        /// refuse by name is a peer that is answering.
        public static func of(_ refusal: BenchPeer.Refusal) -> Alarm {
            Alarm(severity: .warning, sentence: refusal.message, source: .benchRefusal)
        }

        /// The duck itself saying no, in `DuckReply.Failure.says` — which
        /// carries the code alongside the message, because a refusal by number
        /// is what somebody quotes in a bug report.
        public static func of(_ failure: DuckReply.Failure) -> Alarm {
            Alarm(severity: .warning, sentence: failure.says, source: .duckRefusal)
        }
    }

    /// Everything wrong at once, worst first — or nothing at all.
    ///
    /// AN ORDERED LIST RATHER THAN THE FIRST PROBLEM, because the problems
    /// arrive from different places and hiding the second one behind the first
    /// is how somebody fixes their bench address and then discovers their
    /// Bluetooth was off as well. Worst first because the screen puts this
    /// above everything, and a person reading downwards should meet the thing
    /// that invalidates the rest of the card before they read the rest of it.
    ///
    /// EMPTY IS A REAL AND COMMON ANSWER, AND IT MUST DRAW NOTHING. The design
    /// says "a banner above everything, or nothing at all" — not a green bar
    /// saying all is well, which is a row of pixels that is right 99% of the
    /// time and therefore stops being read.
    public struct Banner: Equatable, Sendable {

        public let alarms: [Alarm]

        public var isEmpty: Bool { alarms.isEmpty }

        /// The one to read first, when there is one.
        public var worst: Alarm? { alarms.first }

        /// Sort by severity, keeping the caller's order inside each severity.
        ///
        /// STABLE BY HAND, BECAUSE `sorted(by:)` IS NOT. Swift's sort makes no
        /// stability guarantee, so two criticals could swap places between
        /// runs — which on this screen is a banner whose top line changes when
        /// nothing about the duck did. Decorating with the original index and
        /// comparing it as the tiebreak is the usual fix and is cheap at these
        /// sizes.
        public static func of(_ alarms: [Alarm]) -> Banner {
            let ordered = alarms.enumerated()
                .sorted { a, b in
                    a.element.severity == b.element.severity
                        ? a.offset < b.offset
                        : a.element.severity < b.element.severity
                }
                .map(\.element)
            return Banner(alarms: ordered)
        }

        /// Nothing is wrong.
        public static let nothingWrong = Banner(alarms: [])

        public init(alarms: [Alarm]) {
            self.alarms = alarms
        }
    }

    // MARK: - below the fold

    /// Why there is no camera preview, in words, on a screen whose design asks
    /// for one.
    ///
    /// THE DESIGN ASKS FOR A CAMERA PREVIEW AND THIS BUILD CANNOT DRAW ONE, SO
    /// IT SAYS SO. The house rule is that a blocked surface ships as an
    /// explicit "not yet" rather than as an empty card or a spinner that never
    /// resolves — an empty card is indistinguishable from a bug, and a person
    /// who cannot tell those apart files the wrong one.
    ///
    /// THE FACT IT RESTS ON IS `DuckLink.whatThisCanDo`, WHICH IS QUOTED
    /// RATHER THAN SUMMARISED. Bluetooth carries provisioning, status, update
    /// trigger and progress, and Pollen's own architecture note says outright
    /// that it is "too slow and too constrained for the full surface", with
    /// payloads never crossing it — a video frame being the largest payload
    /// anybody could ask for. The network transports that would carry one do
    /// not exist in this app yet. `SimDuck`'s camera type says the other half:
    /// its single case means "no image", so nothing in this app or in DuckKit
    /// has ever rendered a frame.
    public static let noCameraYet =
        "No camera preview yet, and this is a gap rather than a failure. The only link toward a "
      + "duck this app has code for is Bluetooth — none of it yet run against a robot — and it "
      + "carries provisioning, status and the "
      + "update trigger — Pollen's own note calls it \"too slow and too constrained for the full "
      + "surface\", with payloads never crossing it, and a video frame is the largest payload "
      + "there is. The bench on the other side of the network answers with state blocks and "
      + "recorded clips and has never rendered a frame either. When a transport arrives that "
      + "carries video, the preview arrives with it."
}
