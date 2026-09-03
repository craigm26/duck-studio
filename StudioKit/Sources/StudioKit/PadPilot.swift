import Foundation
import DuckEvidence

/// THE RECORDER AND THE PLAYER ARE STATES OF THE ONE DRIVE LOOP, NOT RIVALS TO
/// IT. A replay written as its own `Task` assigned into `flight` would orphan
/// the running loop — six of the seven `flight = Task` sites in `DriveView` do
/// not cancel first — leaving two intent streams at one bench with Stop able to
/// cancel only the newest. That is the defect `DriveView.swift:1553-1557` was
/// written about, and this type exists so it cannot recur: `drive()` consults
/// the pilot once per round trip and sends whatever it hands back.
///
/// SO THERE IS EXACTLY ONE COMMAND PER ROUND TRIP, ALWAYS. `Go.command` is not
/// optional and there is no second door; whichever state the pilot is in, the
/// loop's next `notify` is the one twist this returned. Recording adds a sample
/// on the way past and changes nothing about what is sent; replaying replaces
/// the thumbs' twist with the list's, and hands the thumbs back the moment the
/// list runs out.
///
/// IT HOLDS NO CLOCK OF ITS OWN. Every timing decision is made against the sim
/// seconds the caller passes in — the bench's clock, before this twist is
/// applied — because the round trip IS the clock on this screen and a timer
/// running beside it would be a second opinion about how fast the world is
/// going. `now` is a wall-clock `Date` and is used for one thing: measuring how
/// long a person spent, which is printed and never used as a time base.
public struct PadPilot: Equatable, Sendable {

    public enum State: Equatable, Sendable {
        case steering
        case recording(DuckSequenceRecording)
        case playing(DuckSequenceRun)
    }

    public private(set) var state: State = .steering

    /// What the loop does this round trip.
    public struct Go: Equatable, Sendable {
        /// The twist to send.
        public let command: DuckDrive.Twist
        /// A network to put on the servos BEFORE that twist. Asked for at most
        /// once per name per engagement, so a bench that refuses is not asked
        /// again on every trip.
        public let load: String?
        /// A slot to load once a chained sequence has finished.
        public let thenLoading: DuckOfficialPolicies.Slot?
        /// Set when the take or the replay ended itself, with the line to show.
        public let note: String?

        public init(command: DuckDrive.Twist, load: String? = nil,
                    thenLoading: DuckOfficialPolicies.Slot? = nil, note: String? = nil) {
            self.command = command
            self.load = load
            self.thenLoading = thenLoading
            self.note = note
        }
    }

    /// Names already asked for on this engagement, so a bench that refuses one
    /// is not asked again on every round trip for the rest of the session.
    private var asked: Set<String> = []
    /// The slot a chained sequence loads when it finishes.
    private var chained: DuckOfficialPolicies.Slot?

    /// Cleared by the app when the keep sheet is dismissed either way.
    public private(set) var pending: DuckSequenceRecording?
    public private(set) var pendingEnding: DuckSequence.Ending?
    /// When the pending take stopped being driven, so the wall reading is the
    /// driving and not the naming.
    public private(set) var pendingEndedAt: Date?

    public init() {}

    /// ONE CALL PER ROUND TRIP, BEFORE THE NOTIFY.
    /// - `steering`: the thumbs' twist, straight through.
    /// - `recording`: the thumbs' twist, sampled on the way past.
    /// - `playing`: the sequence's command at this sim clock; `.still` when the
    ///   bench has given no clock yet; the thumbs again once it has finished.
    /// - `wanting`: the map's answer to `toPost`, surfaced as `load` once.
    public mutating func step(steering: DuckDrive.Twist,
                              simSeconds: Double?,
                              policySaid: String?,
                              wanting: String?,
                              now: Date) -> Go {
        switch state {
        case .steering:
            return Go(command: steering, load: ask(for: wanting))

        case .recording(var recording):
            let load = ask(for: wanting)
            let sampled = recording.sample(steering, atSim: simSeconds,
                                           policySaid: policySaid, now: now)
            if case .closed(let refusal) = sampled {
                state = .recording(recording)
                cutOff(.ceiling(refusal.message))
                return Go(command: steering, load: load, note: refusal.message)
            }
            state = .recording(recording)
            return Go(command: steering, load: load)

        case .playing(var run):
            // THE MAP'S WANTING IS NOT CONSULTED WHILE A REPLAY IS RUNNING.
            // The recording owns which network is on the servos for its own
            // length — that is what makes it a faithful re-run — so the only
            // load that can come out of this branch is one the recording
            // itself asked for.
            // NO CLOCK, NO GUESS. The bench has not answered yet, so there is
            // no point on the recording's own timeline to be at; sending
            // `.still` for one round trip costs a tenth of a second of sim and
            // is the only honest command.
            guard let simSeconds else {
                state = .playing(run)
                return Go(command: .still)
            }
            let beat = run.advance(toSimClock: simSeconds)
            state = .playing(run)
            switch beat {
            case .command(let twist):
                return Go(command: twist)
            case .swap(let name, let twist):
                return Go(command: twist, load: ask(for: name))
            case .finished:
                // THE STICKS TAKE OVER WITH NO ANNOUNCEMENT. A person who has
                // a thumb on the pad while a bound sequence ends does not need
                // a sentence about it; they need their duck back.
                state = .steering
                let slot = chained
                chained = nil
                return Go(command: steering, load: ask(for: wanting), thenLoading: slot)
            }
        }
    }

    /// One name, once. Nil for a name already asked for on this engagement.
    private mutating func ask(for name: String?) -> String? {
        guard let name, !name.isEmpty, !asked.contains(name) else { return nil }
        asked.insert(name)
        return name
    }

    public mutating func startRecording(venue: DriveVenue, at now: Date) {
        state = .recording(DuckSequenceRecording(startedAt: now, venue: venue))
        chained = nil
    }

    public mutating func play(_ sequence: DuckSequence,
                              thenLoading slot: DuckOfficialPolicies.Slot?) {
        // A TAKE IS NEVER THROWN AWAY BY THE NEXT THING PRESSED. Playing a
        // sequence during a take ends the take the way the chip does — kept
        // and offered — rather than dropping what was driven. `cutOff` resets
        // the state, so the two assignments follow it.
        if case .recording = state { cutOff(.tapped) }
        state = .playing(DuckSequenceRun(sequence))
        chained = slot
    }

    /// Ends a take (KEEPING what was driven) or a replay. Stop, Pause and the
    /// Record chip all land here with their own ending.
    public mutating func cutOff(_ ending: DuckSequence.Ending) {
        switch state {
        case .recording(let recording):
            pending = recording
            pendingEnding = ending
            pendingEndedAt = recording.lastSampledAt
        case .playing, .steering:
            break
        }
        state = .steering
        chained = nil
        asked = []
    }

    public mutating func discardPending() {
        pending = nil
        pendingEnding = nil
        pendingEndedAt = nil
    }

    public var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    public var isPlaying: Bool {
        if case .playing = state { return true }
        return false
    }

    /// The one line the chrome prints. Nil while merely steering.
    public var line: String? {
        switch state {
        case .steering: return nil
        case .recording(let recording):
            return PadPilot.recordingLine(simSeconds: recording.simSeconds,
                                          steps: recording.steps.count)
        case .playing(let run):
            return PadPilot.playingLine(name: run.name, at: run.simElapsed, of: run.duration)
        }
    }

    // MARK: - the sentences

    public static func recordingLine(simSeconds s: Double, steps n: Int) -> String {
        String(format: "Recording — %.1f s of sim, %d %@.", s, n, n == 1 ? "step" : "steps")
    }

    public static func playingLine(name: String, at a: Double, of d: Double) -> String {
        String(format: "Playing %@ — %.1f of %.1f s.", name, a, d)
    }

    public static let recordStartsDriving =
        "Record starts the loop as well, so one tap is enough — the take begins on the first round "
      + "trip. Tap it again, or press Pause or Stop, to end it."

    public static func endedBy(_ ending: DuckSequence.Ending) -> String {
        switch ending {
        case .tapped: return "Take ended. What you drove is kept until you name it or discard it."
        case .paused: return "Pause ended the take. What you drove up to the pause was kept."
        case .stop:   return "Stop ended the take. What you drove up to the stop was kept; the "
                           + "stop itself is not in it."
        case .ceiling(let why): return why
        }
    }

    /// The two chips, and the line above them the first time.
    public static let recordChip = "Record what I do"
    public static let nameItChip = "Name it"
    public static let sayItChip = "Say it"
    public static let sayItCaption =
        "Your words become a list of commands. You see the numbers before anything moves."

    public static let allSentences: [String] = [
        recordStartsDriving, recordChip, nameItChip, sayItChip, sayItCaption,
        recordingLine(simSeconds: 3.4, steps: 9),
        recordingLine(simSeconds: 0.1, steps: 1),
        playingLine(name: "a take", at: 2.1, of: 3.4),
        endedBy(.tapped), endedBy(.paused), endedBy(.stop),
    ]
}
