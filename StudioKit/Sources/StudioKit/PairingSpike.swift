import Foundation

/// The phone spike Pollen's own roadmap names as the blocker on their app.
///
/// THIS IS NOT A FEATURE. It is one falsifiable question, on somebody else's
/// critical path, that only a person holding an iPhone and a duck can answer.
/// `docs/project/roadmap.md` M6 "Ship readiness" says it outright: "**The app.**
/// #107 designs it and builds nothing. The blocker is a phone spike — scan,
/// connect, `hello`, authenticate, `system.info` with `--require-pairing` on, on
/// a real iPhone and a real Android — because §5.5 is currently a fact about
/// CoreBluetooth on a laptop."
///
/// §5.5 of `docs/design/app-path-design.md` is the fact in question: "`encrypt_read`
/// on the characteristic makes the read **hang** on macOS: CoreBluetooth issues the
/// Read Request, BlueZ refuses it for insufficient encryption, and nothing resolves
/// it — no prompt, no error, no retry. The client waits out its timeout against a
/// working robot." Everything downstream of that sentence is stuck: "**The default
/// is insecure, on purpose, for now.** The flag is `--require-pairing` and it is
/// **off**", which means "**every robot running this has wifi credentials and a PIN
/// readable by a bystander**", and "this must be closed — the flag flipped, and
/// defaulted on — before anything is handed to anyone."
///
/// iOS has a pairing-prompt flow macOS often does not, so the macOS observation
/// does not settle the iOS case. BOTH ANSWERS ARE WORTH THE TRIP:
/// - iOS prompts and the read completes → the flag can default on, blocker clears.
/// - iOS hangs identically → strong evidence the cause is the absent bond rather
///   than the platform, which is what §5.5 already suspects: "the next thing to
///   establish is whether a bond exists at all — `bluetoothctl info <mac>`
///   reporting `Paired: no` would mean no encryption can ever be established and
///   the flag is a symptom rather than the cause."
///
/// THE DESIGN CONSEQUENCE THAT DECIDES EVERY TYPE BELOW: the symptom is a HANG,
/// not an error. A harness that reports "failed" is worthless here, because
/// "failed" collapses the two answers this spike exists to tell apart. So every
/// step carries a hard timeout and three distinguishable endings — answered,
/// refused *with the refusal*, and **nothing at all** — and the report keeps them
/// apart in words.
///
/// No CoreBluetooth in this file. The sequence, the budgets and the sentences are
/// decided here, where `swift test` on Linux asserts them; the app target owns a
/// radio and owns nothing else.
public enum PairingSpike {

    /// The factory PIN `system.authenticate` expects.
    ///
    /// Public in Pollen's own repository, which is exactly why §5.5 calls a robot
    /// with the flag off "readable by a bystander". Naming it here is not a leak;
    /// pretending it were a secret would misrepresent the risk this spike exists
    /// to close.
    public static let factoryPIN = "000000"

    /// The API version that first served `system.authenticate`.
    ///
    /// A robot reporting less than this has no PIN method at all, so an
    /// authenticate step that fails against one is reporting the robot's age
    /// rather than anything about pairing.
    public static let authenticateAddedInAPIVersion: UInt8 = 4

    // MARK: - the sequence, in the order the roadmap asks for it

    /// The eight steps, in the only order they work in.
    ///
    /// THE READ IS THE THIRD-AND-A-HALF STEP AND THE WHOLE REASON FOR THE OTHER
    /// SEVEN. `gatt.rs` requires it before any write — it needs an authenticated
    /// encrypted link, so it is what makes a central pair — and a client that
    /// skips it subscribes, writes, and is refused with no error anybody can see.
    /// Everything before `readVersion` here exists to get the read issued;
    /// everything after it exists to show that a bonded link then carries the
    /// traffic the app would actually need.
    public enum Step: Int, CaseIterable, Sendable {
        case scan, connect, discover, readVersion, subscribe, hello, authenticate, systemInfo

        public var title: String {
            switch self {
            case .scan: return "Scan"
            case .connect: return "Connect"
            case .discover: return "Discover the RPC characteristic"
            case .readVersion: return "Read the API version"
            case .subscribe: return "Subscribe for answers"
            case .hello: return "hello"
            case .authenticate: return "system.authenticate"
            case .systemInfo: return "system.info"
            }
        }

        /// What reaching this step proves, in one sentence.
        public var establishes: String {
            switch self {
            case .scan:
                return "That this iPhone can see this robot at all. The scan is given no service "
                     + "filter — CoreBluetooth honours one strictly and a bonded peripheral often "
                     + "advertises an empty service list — so every device in range is reported to "
                     + "the app and ranked here in software, by the three tiers in DuckLink.Tier."
            case .connect:
                return "That a link opens — which needs no encryption, and so proves nothing yet "
                     + "about pairing."
            case .discover:
                return "That the one characteristic carrying read, write and notify is present on "
                     + "the service this app was written against."
            case .readVersion:
                return "THE ONE THAT MATTERS: that an authenticated encrypted link can be "
                     + "established between an iPhone and a robot serving encrypt_read, which is "
                     + "the fact §5.5 is missing."
            case .subscribe:
                return "That answers can arrive, on the same characteristic the requests leave on."
            case .hello:
                return "That NDJSON JSON-RPC crosses a bonded link and the robot names its own API "
                     + "version back."
            case .authenticate:
                return "That the PIN method works over the same link — the step that has to work "
                     + "before a PIN is worth having."
            case .systemInfo:
                return "That an authenticated call comes back with the robot's own name, SoC "
                     + "serial and uptime — all three of which this report prints — which is the "
                     + "end of the sequence the roadmap asks for."
            }
        }

        /// What a failure HERE would mean — which is a different sentence for
        /// every step, and is why a report that only says "failed" is useless.
        public var failureMeans: String {
            switch self {
            case .scan:
                return "Nothing was seen, and the first thing to rule out is this phone rather "
                     + "than the duck: a radio that is switched off, or an app that has not been "
                     + "allowed to use it, is named in the line above in those words when that is "
                     + "what happened. Otherwise no robot advertised inside the budget. Neither "
                     + "case says anything about pairing."
            case .connect:
                return "A radio or range problem, or a robot already connected to something else. "
                     + "Not a pairing result."
            case .discover:
                return "The peripheral is not serving this app's service, so it is either not a "
                     + "Microduck or is running firmware older than these UUIDs."
            case .readVersion:
                return "The §5.5 question, answered. A TIMEOUT here reproduces the macOS hang on "
                     + "iOS; a REFUSAL means iOS surfaced an error where macOS surfaced silence, "
                     + "and those two want different next moves."
            case .subscribe:
                return "The link is up and encrypted but the notify path is not, which would be a "
                     + "new bug rather than the one being investigated."
            case .hello:
                return "Framing or transport, not pairing: the bond already succeeded upstream of "
                     + "this."
            case .authenticate:
                return "Either the PIN is wrong or the robot predates API version "
                     + "\(authenticateAddedInAPIVersion), which is a robot-age answer and not a "
                     + "pairing answer."
            case .systemInfo:
                return "The authenticated surface is not serving, with the bond and the PIN both "
                     + "already proven above."
            }
        }

        /// How long to wait before calling it a hang, in seconds.
        ///
        /// Every one of these is a deliberate number rather than a default,
        /// because the value of this whole exercise is the difference between
        /// "answered late" and "never answered", and a too-short budget invents
        /// the second out of the first.
        public var timeoutSeconds: TimeInterval {
            switch self {
            case .scan: return 40
            case .connect: return 15
            case .discover: return 10
            case .readVersion: return 60
            case .subscribe: return 10
            case .hello: return 15
            case .authenticate: return 15
            case .systemInfo: return 15
            }
        }

        /// Why that number and not a rounder one. Printed in the report, because
        /// a reader in Pollen's issue tracker has to be able to judge whether a
        /// reported hang was really a hang.
        public var timeoutRationale: String {
            switch self {
            case .scan:
                return "40 s because the longest advertising silence Pollen measured on the old "
                     + "1.28 s default was 31 s (they also saw 9, 14 and 17). Current firmware "
                     + "advertises every 100-150 ms, but a shorter budget would report \"no duck\" "
                     + "for a duck that was there on an older release."
            case .connect:
                return "15 s. A connection either happens in about a second or is not going to."
            case .discover:
                return "10 s. Discovery is local to a link that is already up."
            case .readVersion:
                return "60 s, deliberately the largest budget here, and it is the point of the "
                     + "exercise. On a Mac this read NEVER returns, so a short timeout would "
                     + "report a hang the robot might simply have been slow to answer — and this "
                     + "step has a human in it: somebody has to notice the iOS pairing prompt, "
                     + "read it and tap Pair, possibly after unlocking the phone. A minute is far "
                     + "longer than any of that needs and still finite."
            case .subscribe:
                return "10 s. A local descriptor write on an established link."
            case .hello:
                return "15 s. One small NDJSON round trip, chunked at the MTU."
            case .authenticate:
                return "15 s. One round trip, same as hello."
            case .systemInfo:
                return "15 s. One round trip, same as hello."
            }
        }

        /// The JSON-RPC id this step's request goes out under, or `nil` for a
        /// step that sends no request.
        ///
        /// CLIENT-SIDE BOOKKEEPING RATHER THAN A CLAIM ABOUT THE ROBOT —
        /// JSON-RPC lets the caller pick its own ids, and these are picked here
        /// so that an answer can be filed against the request that asked for it
        /// instead of against whichever step happens to be running when it
        /// lands. That distinction is the difference between a true report and a
        /// fabricated one the moment any step times out, which on this screen is
        /// the expected case rather than the unlucky one.
        ///
        /// The first four steps are GATT operations — a scan, a connection, a
        /// discovery, a characteristic read — and none of them is JSON-RPC at
        /// all, so none of them has an id to be given.
        public var requestID: Int? {
            switch self {
            case .hello: return 1
            case .authenticate: return 2
            case .systemInfo: return 3
            case .scan, .connect, .discover, .readVersion, .subscribe: return nil
            }
        }
    }

    /// Which step an answer belongs to. The inverse of `Step.requestID`.
    public static func step(forRequestID id: Int) -> Step? {
        Step.allCases.first { $0.requestID == id }
    }

    // MARK: - when the phone is the reason, not the duck

    /// Why no scan was ever started, when the reason is this iPhone.
    ///
    /// A SCAN THAT NEVER RAN IS NOT A DUCK THAT NEVER ANSWERED, AND THE REPORT
    /// USED TO SAY IT WAS. With Bluetooth switched off, or with the app refused
    /// permission to use it, `scanForPeripherals` is never called and nothing is
    /// ever reported — so the scan step sat out its whole 40-second budget and
    /// was written up as "TIMED OUT — no answer and no error", under a sentence
    /// blaming the robot for not advertising. That is a fabricated observation
    /// about somebody else's hardware, filed in their issue tracker, produced by
    /// a phone with its radio off. These are the words that go in instead.
    ///
    /// They are `.refused` outcomes and not `.timedOut` ones, because a refusal
    /// is defined here as the ending that comes with something you can show a
    /// person — and this one can be shown to the very person holding the phone,
    /// who can then go and fix it.
    public enum RadioProblem: String, CaseIterable, Sendable {
        case off, notPermitted, noLowEnergyRadio

        public var reason: String {
            switch self {
            case .off:
                return "Bluetooth is off on this iPhone, so no scan was ever started. Nothing "
                     + "here is about the duck."
            case .notPermitted:
                return "This app is not allowed to use Bluetooth on this iPhone — Settings, "
                     + "Privacy & Security, Bluetooth — so no scan was ever started. Nothing "
                     + "here is about the duck."
            case .noLowEnergyRadio:
                return "This device has no Bluetooth LE radio, so no scan was ever started. "
                     + "Nothing here is about the duck."
            }
        }
    }

    // MARK: - how a step can end

    /// The three endings a step can have, plus not having been tried.
    ///
    /// THREE, NOT TWO, AND THE THIRD IS THE DELIVERABLE. Collapsing `.timedOut`
    /// into `.refused` would throw away the only thing this spike measures.
    public enum Outcome: Equatable, Sendable {
        /// It worked, in this many seconds.
        case ok(seconds: Double)
        /// The platform or the robot said no, in this many seconds, in these
        /// words. Somebody can be shown this; the hang below cannot be shown to
        /// anybody.
        case refused(seconds: Double, String)
        /// **THE WHOLE POINT OF THIS TYPE.** The budget ran out with nothing
        /// coming back at all: no answer, no error, no callback. This is the
        /// macOS §5.5 symptom, and it is indistinguishable, from inside a client,
        /// from a robot that is switched off. A harness that reported this as
        /// "failed" would make the entire contribution worthless, because
        /// "failed" is also what a refusal is, and the two are the two answers
        /// this spike exists to tell apart.
        case timedOut(afterSeconds: Double)
        /// An earlier step stopped the run before this one was attempted. Not a
        /// failure of this step and never reported as one.
        case notReached

        /// One line for the report.
        public var line: String {
            switch self {
            case .ok(let seconds):
                return "ok — \(PairingSpike.seconds(seconds))"
            case .refused(let seconds, let why):
                return "REFUSED after \(PairingSpike.seconds(seconds)) — \(why)"
            case .timedOut(let after):
                return "TIMED OUT after \(PairingSpike.seconds(after)) — no answer and no error"
            case .notReached:
                return "not reached"
            }
        }

        public var isOK: Bool {
            if case .ok = self { return true }
            return false
        }
    }

    /// Seconds, formatted the one way, so two reports of the same run read the
    /// same.
    public static func seconds(_ value: Double) -> String {
        String(format: "%.2f s", value)
    }

    /// An outcome line, ended as a sentence.
    ///
    /// A REFUSAL CARRIES SOMEBODY ELSE'S WORDS AND THEY MAY ALREADY END. iOS
    /// error strings and this app's own reasons are written as sentences, so
    /// dropping a full stop after one gave the report "Nothing here is about the
    /// duck.." — a typo in the middle of the paragraph a maintainer is being
    /// asked to trust, and one that appears exactly when the reason is the most
    /// carefully written.
    public static func stopped(_ line: String) -> String {
        line.hasSuffix(".") ? line : line + "."
    }

    /// When a run happened, in the one notation that means the same thing to
    /// everybody who reads it.
    ///
    /// UTC AND ISO 8601, NOT THE TESTER'S LOCALE. The reader is in France and
    /// the tester may be anywhere; "01/09/2026, 14:30" is two different days
    /// depending on who is holding it, and a local time with no zone on it
    /// cannot be lined up against a log on the robot. This takes the date it is
    /// given and never asks the system for one — a timestamp produced inside
    /// `report()` would be the moment somebody re-rendered the text rather than
    /// the moment of the run, and no test could pin a function that reads a
    /// clock.
    public static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    /// An uptime, in seconds and then in words.
    ///
    /// BOTH, BECAUSE THEY ANSWER DIFFERENT QUESTIONS. The number is the field
    /// `system.info` actually returned and is what somebody would grep a log
    /// for; the gloss is what tells a reader at a glance that this robot was
    /// rebooted a minute before the run, which is the kind of thing that
    /// explains a result.
    public static func uptime(_ totalSeconds: Int) -> String {
        guard totalSeconds >= 0 else { return "\(totalSeconds) s" }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        var words = ""
        if hours > 0 { words += "\(hours) h " }
        if hours > 0 || minutes > 0 { words += "\(minutes) m " }
        words += "\(secs) s"
        return "\(totalSeconds) s (\(words))"
    }

    // MARK: - what the reading of a run is

    /// What a finished run means for §5.5, in Pollen's own terms.
    ///
    /// SEPARATE FROM THE REPORT TEXT ON PURPOSE, so the honesty of the conclusion
    /// is a thing tests assert directly rather than something inferred from a
    /// wall of prose.
    public struct Reading: Equatable, Sendable {

        /// The five materially different things a run can mean. There is no
        /// "inconclusive but promising" case, because that is the failure mode
        /// this whole file is built to prevent.
        public enum Verdict: String, Sendable {
            /// The encrypted read completed on iOS. Supports flipping the flag.
            case flagCanDefaultOn
            /// The encrypted read hung, exactly as it does on macOS.
            case readHung
            /// The read failed with an error instead of hanging — a different
            /// finding, and a more tractable one.
            case readRefused
            /// The read completed, but against a robot serving it unencrypted,
            /// so it was not the read §5.5 is about.
            case readWasNotEncrypted
            /// The run stopped before the read was ever issued.
            case establishesNothing
        }

        public let verdict: Verdict
        public let headline: String
        public let body: String

        public init(verdict: Verdict, headline: String, body: String) {
            self.verdict = verdict
            self.headline = headline
            self.body = body
        }
    }

    // MARK: - a run

    /// One pass of the spike, and everything a reader needs to judge it.
    public struct Run: Equatable, Sendable {

        /// What each step did. A step missing from this map never ran.
        public let outcomes: [Step: Outcome]

        /// Whether iOS showed the pairing prompt. **`nil` means nobody watched**,
        /// which is a third answer and not a `false`: a run where the tester was
        /// not looking at the screen must not be reported as a run where no
        /// prompt appeared.
        public let pairingPromptShown: Bool?

        /// Whether `btd` was started with `--require-pairing` ON.
        ///
        /// LOAD-BEARING, AND THE EASIEST WAY TO PRODUCE A FALSE GREEN. §5.5 is a
        /// fact about `encrypt_read`; with the flag off the robot serves that
        /// read unencrypted, so a read that sails through proves the pipe works
        /// and nothing whatsoever about pairing. The reading refuses to be
        /// encouraging about such a run.
        public let requirePairing: Bool

        /// e.g. "iPhone 15 Pro". A hang on one radio generation is not a hang on
        /// all of them, and the issue will be read by somebody holding different
        /// hardware.
        public let deviceModel: String

        /// e.g. "18.2". The pairing-prompt behaviour this spike is testing is
        /// iOS's, and iOS changes.
        public let iOSVersion: String

        /// The one byte the read returned, when it returned. `nil` when the read
        /// never completed — which is itself part of the finding.
        ///
        /// A BYTE HERE DOES NOT MEAN THE READ SUCCEEDED. It can also be a
        /// straggler that arrived after the budget expired, and `report()` says
        /// which of the two it was rather than printing a version beside a
        /// reading that says nothing came back.
        public let robotAPIVersion: UInt8?

        /// The PIN `system.authenticate` was actually given.
        ///
        /// PRINTED ONLY WHEN IT IS THE PUBLIC ONE. `factoryPIN` is in Pollen's
        /// own repository and naming it costs nothing; a PIN somebody set on a
        /// provisioned robot is a real secret, and this report exists to be
        /// pasted into a public issue tracker. So the value is carried, the fact
        /// that a PIN was tried is always stated, and the digits appear only in
        /// the case where they are already published.
        public let pin: String

        /// When the run started.
        ///
        /// PASSED IN, NEVER READ HERE. The kit takes no clock reading of its own
        /// — a report whose timestamp came from inside `report()` would be the
        /// time somebody re-rendered it rather than the time of the run, and
        /// nothing in `swift test` could pin a function that asks the system
        /// what time it is.
        public let startedAt: Date

        /// How many runs this phone has made against this peripheral, this one
        /// included. `nil` when nothing was counted.
        ///
        /// COUNTED AGAINST THE PERIPHERAL IDENTIFIER, WHICH IS NOT THE DUCK.
        /// See `DuckLink.identifierIsNotAnIdentity`: the identifier survives a
        /// rename and does not survive a change of Bluetooth address, so a duck
        /// that changed address starts again at 1. The report says so rather
        /// than presenting the number as a fact about the robot.
        public let runNumber: Int?

        /// Every candidate the scan window recorded, in the order first seen.
        ///
        /// EVERY CANDIDATE, NOT THE FIRST ONE. The scan step used to end at the
        /// first sighting of anything, and the duck that was then tested need
        /// not have been it — so a report could name a hang against a robot
        /// while the row somebody actually tapped was a different device
        /// entirely. Listing the window is what lets a reader see that.
        public let sightings: [DuckLink.Sighting]

        /// The one that was picked and run against. `nil` when the run stopped
        /// before anybody picked.
        public let tested: DuckLink.Sighting?

        /// What `hello` answered, when it answered.
        public let hello: DuckLink.Hello?

        /// What `system.info` answered, when it answered.
        public let info: DuckLink.SystemInfo?
        /// Answers that arrived for a step AFTER it had ended, keyed by step.
        ///
        /// KEPT SO THAT "NO ANSWER AND NO ERROR" IS NEVER PRINTED ABOUT A ROBOT
        /// THAT ANSWERED. The step keeps its timeout — the client had given up
        /// — but the report says an answer came, and when.
        public let lateAnswers: [Step: String]
        /// Methods of id-less JSON-RPC lines the robot sent during the run.
        public let notifications: [String]
        /// Whether `system.authenticate`'s write was confirmed on the wire.
        /// `false` when the step ended before any write — the link gone, or the
        /// line unserialisable — so the PIN line can say the PIN was never sent.
        public let authenticateWritten: Bool

        public init(outcomes: [Step: Outcome],
                    pairingPromptShown: Bool?,
                    requirePairing: Bool,
                    deviceModel: String,
                    iOSVersion: String,
                    robotAPIVersion: UInt8?,
                    pin: String,
                    startedAt: Date,
                    runNumber: Int? = nil,
                    sightings: [DuckLink.Sighting] = [],
                    tested: DuckLink.Sighting? = nil,
                    hello: DuckLink.Hello? = nil,
                    info: DuckLink.SystemInfo? = nil,
                    lateAnswers: [Step: String] = [:],
                    notifications: [String] = [],
                    authenticateWritten: Bool = true) {
            self.outcomes = outcomes
            self.pairingPromptShown = pairingPromptShown
            self.requirePairing = requirePairing
            self.deviceModel = deviceModel
            self.iOSVersion = iOSVersion
            self.robotAPIVersion = robotAPIVersion
            self.pin = pin
            self.startedAt = startedAt
            self.runNumber = runNumber
            self.sightings = sightings
            self.tested = tested
            self.hello = hello
            self.info = info
            self.lateAnswers = lateAnswers
            self.notifications = notifications
            self.authenticateWritten = authenticateWritten
        }

        /// What a step did, with "never tried" as a real answer rather than a
        /// missing key.
        public func outcome(for step: Step) -> Outcome {
            outcomes[step] ?? .notReached
        }

        /// The first step that did not succeed, or `nil` for a clean run.
        public var stoppedAt: Step? {
            Step.allCases.first { !outcome(for: $0).isOK }
        }

        /// What a failure at this step means IN THIS RUN.
        ///
        /// `Step.failureMeans` is what a failure there means in general, and for
        /// seven of the eight steps that is the whole answer. `authenticate` is
        /// the exception, and it was offering the reader an ambiguity this run
        /// had already resolved: "either the PIN is wrong or the robot predates
        /// API version 4" — when the read step, four steps earlier, printed the
        /// robot's API version at the top of the same report. A report that asks
        /// its reader to consider a possibility its own Setup section rules out
        /// is teaching them not to trust the rest of it.
        public func explanation(for step: Step) -> String {
            // THE READ IS THE PREMISE OF EVERY SENTENCE BELOW IT, so a run in
            // which the read did not complete may not print them. `subscribe`
            // says "the link is up and encrypted", `hello` says "the bond
            // already succeeded upstream", `systemInfo` says "the bond and the
            // PIN both already proven above" — and the run this spike exists
            // to produce, §5.5's hang, is exactly the one where all three are
            // false: the read times out, the harness carries on past it on
            // purpose, and every later step times out too. Those sentences
            // were being printed under each of them.
            if step == .readVersion, outcome(for: .readVersion) == .notReached {
                return "The read was never issued: the link ended before it could be. Nothing about "
                     + "§5.5 was measured here."
            }
            if step.rawValue > Step.readVersion.rawValue, !outcome(for: .readVersion).isOK {
                return PairingSpike.downstreamOfAnUnfinishedRead
            }
            guard step == .authenticate else { return step.failureMeans }
            guard let version = robotAPIVersion else {
                return step.failureMeans + " This run cannot say which: the read never returned a "
                     + "version, so the robot's age is unknown here. That is one more reason to "
                     + "fix the read first."
            }
            if version < PairingSpike.authenticateAddedInAPIVersion {
                return "The robot reported API version \(version) on the read, and "
                     + "system.authenticate arrived in \(PairingSpike.authenticateAddedInAPIVersion) "
                     + "— so this robot has no PIN method at all. That is the robot's age, and it "
                     + "says nothing about the PIN or about pairing."
            }
            return "The robot reported API version \(version) on the read, which is at or past the "
                 + "\(PairingSpike.authenticateAddedInAPIVersion) that added system.authenticate — "
                 + "so this is NOT the robot's age. The PIN itself was refused or went unanswered."
        }

        /// What this run says about §5.5.
        ///
        /// THE LOGIC IS WRITTEN TO DISAPPOINT. A run that never reached the read
        /// establishes nothing and says so; a read served without encryption
        /// establishes nothing and says so; only the encrypted read that actually
        /// returned is allowed to support flipping the flag.
        public var reading: Reading {
            let read = outcome(for: .readVersion)

            switch read {
            case .notReached:
                let stopper = stoppedAt ?? .readVersion
                return Reading(
                    verdict: .establishesNothing,
                    headline: "This run never reached the read, so it establishes nothing about §5.5.",
                    body: "The spike stopped at \(stopper.title) — "
                        + "\(PairingSpike.stopped(outcome(for: stopper).line)) "
                        + "§5.5 is a question about exactly one operation, the encrypted read of the "
                        + "API version, and that operation was never issued here. Nothing in this run "
                        + "supports flipping --require-pairing on, and nothing in it contradicts "
                        + "doing so either. \(explanation(for: stopper)) Fix that and run it "
                        + "again.")

            case .timedOut(let after):
                // THE FLAG IS THE EXPERIMENTAL CONDITION, SO IT IS CHECKED IN
                // EVERY BRANCH. It used to be consulted only in `.ok`, so a
                // hung read reported "issued against a robot started with
                // --require-pairing on" whatever the tester had actually set —
                // and the screen defaults that toggle OFF, which made the
                // false report the DEFAULT one, in the outcome Pollen most
                // need. A run cannot reproduce §5.5's hang if the operation
                // §5.5 is about was never encrypted.
                guard requirePairing else {
                    return Reading(
                        verdict: .establishesNothing,
                        headline: "The read never answered, but --require-pairing was off — so this "
                                + "is not §5.5's hang and establishes nothing about it.",
                        body: "With the flag off, btd serves this read unencrypted: no bond is "
                            + "required and no pairing prompt is expected. A read that then hangs "
                            + "for \(PairingSpike.seconds(after)) is a fault in something else — the "
                            + "link, the daemon, the characteristic — and it is worth chasing, but "
                            + "it is not evidence about encrypt_read, which is the only thing §5.5 "
                            + "is about. Re-run with btd started --require-pairing on, which is the "
                            + "only configuration the question exists in.")
                }
                return Reading(
                    verdict: .readHung,
                    headline: "The read hung on a real iPhone, exactly as §5.5 records it hanging on "
                            + "macOS. --require-pairing must not be defaulted on off the back of this.",
                    body: "The read was issued against a robot started with --require-pairing on, and "
                        + "after \(PairingSpike.seconds(after)) nothing came back at all — no answer, "
                        + "no error, no retry. That is §5.5's symptom reproduced on the platform the "
                        + "roadmap says it has never been observed on, and it is the answer that "
                        + "moves the question: the cause is then not CoreBluetooth-on-a-laptop. "
                        + "§5.5 already names the next move — \"whether a bond exists at all — "
                        + "bluetoothctl info <mac> reporting Paired: no would mean no encryption can "
                        + "ever be established and the flag is a symptom rather than the cause\". Run "
                        + "that on the robot next. \(promptSentenceForHang)")

            case .refused(let after, let why):
                guard requirePairing else {
                    return Reading(
                        verdict: .establishesNothing,
                        headline: "The read failed, but --require-pairing was off — so the failure "
                                + "is not about encryption and establishes nothing about §5.5.",
                        body: "iOS returned an error after \(PairingSpike.seconds(after)): "
                            + "\"\(why)\". With the flag off that read needed no bond, so whatever "
                            + "refused it refused an unencrypted read — which is a different fault "
                            + "from the one §5.5 describes and wants chasing on its own terms. "
                            + "Re-run with --require-pairing on to say anything about the flag.")
                }
                return Reading(
                    verdict: .readRefused,
                    headline: "The read failed with an error instead of hanging. §5.5's hang was not "
                            + "reproduced, and the flag still cannot be defaulted on.",
                    body: "iOS returned an error after \(PairingSpike.seconds(after)): \"\(why)\". The "
                        + "read did not complete, so nothing here says an encrypted link can be "
                        + "established — but it did not hang either, and that difference is the "
                        + "useful part of this run. A client can put that error in front of a person; "
                        + "the silence §5.5 describes cannot be put in front of anybody. Chase the "
                        + "error text before concluding anything about the bond.")

            case .ok(let after):
                guard requirePairing else {
                    return Reading(
                        verdict: .readWasNotEncrypted,
                        headline: "The read completed, but --require-pairing was off, so this "
                                + "establishes nothing about §5.5.",
                        body: "§5.5 is a fact about encrypt_read on the characteristic. With the flag "
                            + "off, btd serves that read unencrypted: no bond is required, no pairing "
                            + "prompt is expected, and a read that returns in "
                            + "\(PairingSpike.seconds(after)) proves only that the pipe works. This "
                            + "run cannot be quoted for or against flipping the default. Re-run it "
                            + "with btd started --require-pairing on, which is the only configuration "
                            + "the question exists in — and note meanwhile that the flag being off is "
                            + "the state §5.5 describes as leaving \"wifi credentials and a PIN "
                            + "readable by a bystander\".")
                }
                var body = "The read was issued against a robot started with --require-pairing on, so "
                         + "the characteristic required an authenticated encrypted link, and it "
                         + "returned in \(PairingSpike.seconds(after)). An encrypted link was "
                         + "therefore established between this iPhone and this robot. §5.5's hang did "
                         + "not happen here, which is evidence that it is a fact about CoreBluetooth "
                         + "on macOS rather than about the protocol: on this hardware and this iOS "
                         + "version, the flag can be flipped and defaulted on. "
                         + promptSentenceForSuccess
                if let later = firstFailureAfterTheRead {
                    body += " The run did not finish, though: \(later.title) — "
                            + "\(PairingSpike.stopped(outcome(for: later).line)) That is a separate "
                            + "defect from §5.5 and "
                            + "does not weaken the read result above, but nothing here can be quoted "
                            + "as a working end-to-end phone flow until it is understood. "
                            + "\(explanation(for: later))"
                }
                return Reading(
                    verdict: .flagCanDefaultOn,
                    headline: "The encrypted read completed on iOS. This supports flipping "
                            + "--require-pairing on by default.",
                    body: body)
            }
        }

        /// The first step after the read that did not succeed.
        private var firstFailureAfterTheRead: Step? {
            Step.allCases
                .filter { $0.rawValue > Step.readVersion.rawValue }
                .first { !outcome(for: $0).isOK }
        }

        /// What the prompt observation adds when the read succeeded.
        private var promptSentenceForSuccess: String {
            switch pairingPromptShown {
            case .some(true):
                return "iOS showed the pairing prompt and the read completed once it was accepted, "
                     + "which is the first-run path a new owner takes."
            case .some(false):
                return "No pairing prompt appeared, which most likely means this iPhone was already "
                     + "bonded to this robot from an earlier run. That is still an encrypted read, "
                     + "but it is not evidence about a first-time owner: forget the device in "
                     + "Settings › Bluetooth and run it again to exercise the prompt."
            case .none:
                return "Whether iOS showed a pairing prompt was not observed, so the first-run "
                     + "experience remains untested even though the read itself succeeded."
            }
        }

        /// What the prompt observation adds when the read hung — where it is the
        /// single most informative thing anybody can record.
        private var promptSentenceForHang: String {
            switch pairingPromptShown {
            case .some(true):
                return "iOS DID show a pairing prompt and the read still never returned, so the "
                     + "phone tried to bond and the bond did not complete; whatever refused it is on "
                     + "the robot's side."
            case .some(false):
                return "iOS never showed a pairing prompt, so nothing on this phone ever attempted "
                     + "to bond — which is what a robot that cannot be paired with at all would look "
                     + "like from here."
            case .none:
                return "Whether iOS showed a pairing prompt was not observed, and on a hang that is "
                     + "the single most useful thing to record: a prompt means the phone tried to "
                     + "bond, no prompt means it never did."
            }
        }

        // MARK: - the deliverable

        /// A plain-text report somebody can paste into a GitHub issue.
        ///
        /// PASTEABLE IS A REQUIREMENT, NOT A CONVENIENCE. The audience is a
        /// Pollen maintainer reading an issue from a stranger, who has to decide
        /// whether to believe a hang was a hang. So the report states the
        /// hardware, the flag, the budget each step was given and why, every
        /// step's ending in words that keep a refusal and a silence apart, and
        /// then a reading that commits to what it means.
        public func report() -> String {
            var out = ""
            out += "Microduck phone pairing spike — app-path-design.md §5.5\n"
            out += "=======================================================\n\n"

            out += PairingSpike.whatThisIsFor + "\n\n"

            out += "Setup\n-----\n"
            out += "Run started: \(PairingSpike.timestamp(startedAt))\n"
            if let runNumber {
                out += "Run count: this is run \(runNumber) from this phone against this "
                     + "peripheral. The count is kept against the identifier iOS gives the "
                     + "peripheral, which survives a rename and does not survive a change of "
                     + "Bluetooth address — so a duck that changed address starts again at 1.\n"
            }
            out += "Phone: \(deviceModel), iOS \(iOSVersion)\n"
            out += "Robot: btd started with --require-pairing "
            out += requirePairing ? "ON" : "OFF"
            out += " — as answered by whoever launched it. Nothing in the advertisement, the GATT "
                 + "table or the RPC surface says which way, so this line is a person's answer and "
                 + "not a measurement.\n"
            out += "iOS pairing prompt: "
            switch pairingPromptShown {
            case .some(true): out += "shown\n"
            case .some(false): out += "not shown\n"
            case .none: out += "NOT OBSERVED (nobody was watching the screen)\n"
            }
            out += pinLine + "\n"
            out += apiVersionLine + "\n"
            out += "Service \(DuckLink.serviceUUID), characteristic \(DuckLink.rpcUUID)\n\n"

            out += "What the scan saw\n-----------------\n"
            out += scanSection

            out += "Steps\n-----\n"
            for step in Step.allCases {
                let result = outcome(for: step)
                out += "\(step.rawValue + 1). \(step.title) [budget "
                out += "\(PairingSpike.seconds(step.timeoutSeconds))]: \(result.line)\n"
                // A step that was never attempted gets no explanation, because it
                // has nothing to explain and a paragraph under it would read as
                // an accusation.
                switch result {
                case .ok, .notReached:
                    break
                case .refused, .timedOut:
                    if let late = lateAnswers[step] {
                        out += "   LATE ANSWER: \(PairingSpike.stopped(late)) The line above is "
                             + "the client's view — it had given up — and not a silence on the "
                             + "robot's side.\n"
                    }
                    out += "   \(explanation(for: step))\n"
                    out += "   Budget: \(step.timeoutRationale)\n"
                }
            }
            out += "\n"

            out += "What the robot said\n-------------------\n"
            out += robotSection + "\n"

            let reading = self.reading
            out += "Reading\n-------\n"
            out += reading.headline + "\n\n"
            out += reading.body + "\n\n"
            out += PairingSpike.oneRunIsOneObservation + "\n"
            return out
        }

        /// The PIN line, which names the PIN only when the PIN is public — and
        /// only says it was TRIED when the step that would have tried it ran.
        ///
        /// A RUN THAT STOPS AT THE SCAN HAS TRIED NO PIN AT ALL. The value is
        /// carried from the moment the person picks a duck, so a report that
        /// said "PIN tried: 000000" under a run that never reached
        /// `system.authenticate` would be describing a write that was never put
        /// on any wire — the small, plausible kind of false sentence that costs
        /// a maintainer an hour looking for a refusal nobody received.
        private var pinLine: String {
            let neverOnTheWire: String? = {
                if outcome(for: .authenticate) == .notReached {
                    return "PIN never tried — the run stopped before system.authenticate. It would "
                         + "have used"
                }
                // REFUSED BEFORE THE WRITE IS NOT TRIED EITHER. "The link was gone
                // before the write" and a serialisation failure both end the
                // step as a refusal with nothing on any wire; the harness
                // records whether the write was confirmed, and this reads it.
                if !authenticateWritten {
                    return "PIN never put on the wire — system.authenticate ended before its "
                         + "write was confirmed. It would have used"
                }
                return nil
            }()
            let heading = neverOnTheWire ?? "PIN tried:"
            guard pin == PairingSpike.factoryPIN else {
                return "\(heading) a PIN of this robot's own, \(pin.count) characters, NOT printed "
                     + "here — a provisioned PIN is a real secret and this report is written to be "
                     + "pasted in public. Only the factory one is safe to quote."
            }
            return "\(heading) \(pin) — the factory PIN, published in Pollen's own repository, "
                 + "which is exactly why §5.5 calls a robot with the flag off \"readable by a "
                 + "bystander\". Printing it here leaks nothing."
        }

        /// The API-version line, which refuses to print a version beside a
        /// reading that says nothing came back.
        ///
        /// A LATE BYTE IS NOT A READ THAT WORKED, AND THIS REPORT SAID IT WAS.
        /// The harness keeps a read answer that lands after its own deadline —
        /// which version a robot runs is worth knowing however late it arrived,
        /// and recognising it also keeps a stray unframed byte out of the line
        /// reassembler — but the step keeps its `.timedOut`, and the report was
        /// printing "Robot API version: 16, read as one byte off the RPC
        /// characteristic" at the top of a document whose Reading said the read
        /// never answered at all. Two sentences in the same report, one of them
        /// false, in the outcome Pollen most need to believe.
        private var apiVersionLine: String {
            guard let version = robotAPIVersion else {
                return "Robot API version: unknown — the read never returned one"
            }
            guard case .timedOut(let after) = outcome(for: .readVersion) else {
                return "Robot API version: \(version), read as one byte off the RPC characteristic"
            }
            return "Robot API version: \(version) — but that byte arrived AFTER the read's "
                 + "\(PairingSpike.seconds(after)) budget had already run out. A client had given "
                 + "up by then, so the read step below is still a hang; this only says which "
                 + "version the robot runs."
        }

        /// Which duck was tested and what else was in the room.
        private var scanSection: String {
            guard !sightings.isEmpty else {
                return "Nothing was seen.\n\n"
            }
            // HEARD AND REMEMBERED ARE TWO LISTS. iOS hands back a peripheral for
            // any identifier it is asked about, and a report that put those
            // under "seen in the window" would be describing a radio event
            // that never happened.
            let heard = sightings.filter(\.heard)
            let remembered = sightings.filter { !$0.heard }
            var out = ""
            if heard.isEmpty {
                out += "NOTHING WAS HEARD ON THE RADIO in this window. What follows was offered "
                     + "from this phone's memory by identifier, which iOS does for any identifier "
                     + "it is given — switched off, out of range, or in another building.\n"
            }
            if let tested {
                out += "Tested: \(tested.line)\n"
            } else {
                out += "Tested: nothing — the run stopped before a duck was picked.\n"
            }
            let others = heard.filter { $0 != tested }
            if others.isEmpty {
                if !heard.isEmpty { out += "Nothing else was heard in the scan window.\n" }
            } else {
                out += "Also heard in the same window:\n"
                for other in others { out += "  - \(other.line)\n" }
            }
            let rememberedOnly = remembered.filter { $0 != tested }
            if !rememberedOnly.isEmpty {
                out += "Remembered from an earlier run and NOT heard this time:\n"
                for one in rememberedOnly { out += "  - \(one.line)\n" }
            }
            out += "This is a list of CANDIDATES, not a census of the room: the scan is given no "
                 + "service filter, and a device matching none of the three tiers is never "
                 + "recorded. \"Serves our characteristic\" is the only authoritative identity "
                 + "test and it is knowable solely after connecting.\n\n"
            return out
        }

        /// What `hello` and `system.info` actually came back with.
        ///
        /// PRINTED BECAUSE THE REPORT USED TO CLAIM IT WITHOUT LOOKING. The
        /// systemInfo step said it established "that an authenticated call
        /// returns real data" while the harness parsed nothing but the JSON-RPC
        /// id off the line — so "real data" was a claim about a field nobody had
        /// read. Either the report shows the data or it must not use the word.
        private var robotSection: String {
            var out = ""
            if let hello {
                let build = hello.daemonVersion.map { "btd \($0)" } ?? "an unnamed btd build"
                let revision = hello.revision.map { "revision \($0)" }
                    ?? "no revision — a build that did not come from CI"
                out += "hello: \(build), \(revision), API version \(hello.apiVersion)\n"
            } else {
                out += "hello: \(nothingSaid(by: .hello))\n"
            }
            if let info {
                out += "system.info: name \"\(info.name)\", serial \"\(info.serial)\", up "
                     + "\(PairingSpike.uptime(info.uptimeSeconds))\n"
                out += "The serial is the durable identity of this duck — it outlives a rename and "
                     + "a change of Bluetooth address, neither of which the peripheral identifier "
                     + "this app keys on survives.\n"
            } else {
                out += "system.info: \(nothingSaid(by: .systemInfo)) Nothing here names the robot.\n"
            }
            if !notifications.isEmpty {
                out += "The robot also sent \(notifications.count) notification(s) during the run — "
                     + "id-less lines the protocol allows and this app owes no answer to: "
                     + "\(notifications.joined(separator: ", ")).\n"
            }
            return out
        }

        /// Why a step produced no answer to print.
        ///
        /// A SILENCE AND AN UNREADABLE ANSWER ARE THE ONE DISTINCTION THIS WHOLE
        /// DOCUMENT EXISTS TO KEEP, so this section may not blur them either.
        /// "No answer this app could read" was printed under a step that had
        /// timed out — where nothing arrived at all — which is the same
        /// substitution, made in a quieter place.
        private func nothingSaid(by step: Step) -> String {
            switch outcome(for: step) {
            case .notReached:
                return "not asked — the run stopped before this step."
            case .timedOut(let after):
                // A LATE ANSWER IS NOT A SILENCE. The step keeps its timeout —
                // a client that had given up is what this report describes —
                // but "no answer at all" is the one sentence this document may
                // never print about a robot that answered.
                guard let late = lateAnswers[step] else {
                    return "no answer at all inside \(PairingSpike.seconds(after))."
                }
                return "no answer inside \(PairingSpike.seconds(after)) — but one ARRIVED LATE: "
                     + "\(PairingSpike.stopped(late)) The step keeps its timeout; the robot did "
                     + "answer, slowly."
            case .refused(_, let why):
                return "refused — \(PairingSpike.stopped(why))"
            case .ok:
                // The harness only files an `ok` here once the line has parsed,
                // so this is unreachable in a run this app produced. It is
                // written out rather than defaulted, because the day it does
                // happen the report must say something true.
                return "recorded as answered, but nothing was kept — report this, it is a bug in "
                     + "this app rather than a finding about the robot."
            }
        }
    }

    /// What to say to somebody before they run this.
    ///
    /// It names whose blocker this is and that a failure is a result, because a
    /// tester who thinks a hang means they did something wrong will quietly retry
    /// instead of reporting the most valuable outcome available.
    /// What a failed step after an unfinished read is allowed to say.
    ///
    /// ONE SENTENCE FOR ALL OF THEM, because in that run they all mean the same
    /// thing, which is nothing on their own.
    public static let downstreamOfAnUnfinishedRead =
        "Downstream of a read that did not complete, so this says nothing on its own. The "
      + "sentence this step would normally earn presupposes a bond proven by the read, and no "
      + "such thing was proven here. The run carries on past the read on purpose — so that a "
      + "robot which answers late, or answers only some calls, is still described — and in the "
      + "§5.5 outcome every step after the read is expected to end this way. The finding is "
      + "the read, above."

    public static let whatThisIsFor =
        "This is not a feature. It runs one experiment that Pollen Robotics' own roadmap says is "
      + "blocking their phone app: scan, connect, read, hello, authenticate and system.info against "
      + "a real robot with --require-pairing on, from a real iPhone. §5.5 of their app-path design "
      + "records the encrypted read HANGING on macOS — no prompt, no error, no retry — and says "
      + "that flag has to be flipped and defaulted on before a duck is handed to anyone. Nobody has "
      + "yet run it on a phone.\n\n"
      + "Both answers are worth having. If the read completes, the flag can default on and their "
      + "blocker clears. If it hangs here too, that is strong evidence the cause is an absent bond "
      + "rather than the platform — which is the more useful finding of the two. A step that times "
      + "out is a result, not a mistake: do not retry it quietly, report it."

    /// The last line of every report.
    ///
    /// IT ASKS FOR THE RUN TO BE DONE AGAIN, AND THAT IS NOT MODESTY. Everything
    /// above it is one phone, one robot, one room and one moment, and the two
    /// answers this spike exists to tell apart — a hang and a completed read —
    /// are both things a radio can produce by accident once. A report that
    /// stopped at its own verdict invites a maintainer to act on a single
    /// sample; naming the sample size is the difference between evidence and an
    /// anecdote with a timestamp on it.
    ///
    /// It also names the two variations worth the most, because a second
    /// identical run is worth much less than a run from a different phone or a
    /// run that forgets the bond first.
    public static let oneRunIsOneObservation =
        "One run is one observation. This is one phone, one robot, one room and one moment — and "
      + "both of the answers this spike can produce are things a radio will do by accident once. "
      + "Run it again before anybody acts on it, and if you can, vary the two things that matter "
      + "most: a different iPhone model, and a run after Settings › Bluetooth › Forget This Device, "
      + "which is the only way to see the first-run pairing prompt a second time. Send every run, "
      + "including the ones that disagree with this one — a disagreement between two runs is a "
      + "finding, and quietly keeping the tidier of the two is how a real one gets lost."
}
