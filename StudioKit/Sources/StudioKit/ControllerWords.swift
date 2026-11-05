import Foundation

/// The Play tab's controller as words and small rules: the mode switch, the Stop disc and pill,
/// the duck pill, Tell's lines and Auto's goal cards (docs/plans/native-first-redesign.md,
/// "The three control modes" and "Visual language", build 91).
///
/// THE APP DRAWS, THIS DECIDES. Every sentence the controller puts on screen is here, so a Linux
/// test can read it: no em-dash, no engineering word on the front door, and no line that claims
/// Stop cancels a move the robot has already started.
public enum ControllerWords {

    // MARK: - the mode switch

    public static func title(_ mode: ControlArbiter.Mode) -> String {
        switch mode {
        case .drive: return "Drive"
        case .tell: return "Tell"
        case .auto: return "Auto"
        }
    }

    /// Symbols, not colour, carry the modes.
    public static func symbol(_ mode: ControlArbiter.Mode) -> String {
        switch mode {
        case .drive: return "gamecontroller.fill"
        case .tell: return "waveform"
        case .auto: return "sparkles"
        }
    }

    /// What each mode is, for VoiceOver and the one-line caption under the switch.
    public static func line(_ mode: ControlArbiter.Mode) -> String {
        switch mode {
        case .drive: return "Your thumbs move the duck."
        case .tell: return "Type what the duck should do, or tap a tile."
        case .auto: return "The duck works toward a goal while you watch. Touch the stick to take over."
        }
    }

    // MARK: - Stop

    public static let stop = "Stop"
    /// The VoiceOver hint on every Stop. Honest about a started skill.
    public static let stopHint = "Stops the duck now. A move the duck has already started finishes first."
    /// The floating pill on other tabs and sheets while something runs.
    public static let stopPill = "Stop the duck"
    public static let stopPillLine = "Something is running on your duck."

    // MARK: - the duck pill and the stage

    public static let practiceDuck = "Practice duck"
    public static let yourFloor = "On your floor"
    public static let yourDuck = "Your duck"
    public static let driveOn = "Drive on"
    public static let duckDetails = "Duck details"
    /// Closes a sheet the controller opened.
    public static let done = "Done"
    public static let connectYourDuck = "Connect your duck"
    /// The poster on the real duck before a picture arrives.
    public static let noDuckYet = "No duck connected yet. Connect one to drive it here."
    public static let waitingForPicture = "Your duck is connected. Waiting for its camera."
    public static let noCameraAddress = "Your duck is connected. Its camera has no address yet."
    public static func nowDriving(_ name: String) -> String { "Now driving \(name)." }
    /// After a venue switch the stick waits for the finger to lift.
    public static let liftToDrive = "Lift your thumb, then push the stick to drive."

    // MARK: - Tell

    public static let tellPlaceholder = "Tell the duck what to do"
    public static let tellSend = "Go"
    public static let tellNoDuck = "There is no duck to tell yet. Connect one, or use the practice duck."
    public static let tellRunning = "Running. Stop is top right."
    public static func heard(_ text: String) -> String {
        "I heard: \"\(text)\". That is not something I can run yet. Try a tile."
    }
    public static let tellDone = "Done."
    /// The tiles under the field. Names the matcher reads exactly.
    public static let tiles: [(said: String, symbol: String)] = [
        ("stand up", "figure.stand"),
        ("sit down", "chair"),
        ("walk forward", "arrow.up"),
        ("turn left", "arrow.counterclockwise"),
        ("turn right", "arrow.clockwise"),
        ("quack", "speaker.wave.2"),
    ]

    // MARK: - Drive

    public static let headMode = "Head"
    public static let headModeHint = "The sticks aim the head while this is on."
    public static let tookOver = ControlArbiter.Words.tookOver

    // MARK: - the two sheets on Play

    /// The pull-up Moves sheet: the Moves tab's tiles, over the picture.
    public static let movesSheet = "Moves"
    public static let movesSheetHint = "Skills, sounds, your sequences and motions, run on this duck."
    public static let motions = "Motions"
    public static let more = "More"
    public static let moreHint = "Scene, record a sequence, the pad map and the camera."
    public static let moreScene = "Scene"
    public static let moreRecord = "Record a sequence"
    public static let moreRecordLine = "The next stretch of stick and buttons becomes a sequence."
    public static let moreCamera = "Follow the duck"
    public static let moreCameraLine = "Put the camera back behind the duck."
    public static let moreSettings = "Driving settings"
    public static let moreRealDuck = "Scene, recording and the camera view are for the practice duck."

    public static var sheetWords: [String] {
        [movesSheet, movesSheetHint, motions, more, moreHint, moreScene, moreRecord, moreRecordLine,
         moreCamera, moreCameraLine, moreSettings, moreRealDuck]
    }
}

/// An Auto goal card: what it is, where it runs, and whether it can run here.
public enum AutoGoal: String, CaseIterable, Sendable, Identifiable {
    /// The phone driver (ducknet-s1), Practice duck only.
    case walkToBall
    /// Dream-1 with the person's own key.
    case dream

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .walkToBall: return "Walk to the ball, on this phone"
        case .dream: return "Dream-1 (your key)"
        }
    }

    public var symbol: String {
        switch self {
        case .walkToBall: return "soccerball"
        case .dream: return "sparkles"
        }
    }

    /// Where it runs and whose it is. Neither card is Pollen's.
    public var provenance: String {
        switch self {
        case .walkToBall: return "Runs on this iPhone. Not made by Pollen."
        case .dream: return "Hosted by Dream Labs, your key. Not made by Pollen."
        }
    }

    public enum Availability: Equatable, Sendable {
        case ready
        /// Shown, not runnable, with the reason.
        case unavailable(String)

        public var reason: String? {
            if case .unavailable(let why) = self { return why }
            return nil
        }
    }

    public enum Words {
        public static let practiceOnly = "Practice duck only for now. Runs on this phone, no key needed."
        /// The phone driver is not in the app yet. Said plainly rather than faked.
        public static let notOnThisPhone = "Not on this phone yet. This driver ships in a later build."
        public static let trainedOnSim = "This driver was trained on the simulated duck."
        public static let noDuck = "Connect a duck, or use the practice duck, to start a goal."
        public static let go = "Go"
        public static let running = "Running"
        public static func capped(_ seconds: Double) -> String {
            String(format: "Stops by itself after %.0f s.", seconds)
        }
    }

    /// Whether this card can start now.
    /// - Parameters:
    ///   - duck: the duck the controller is on, or nil when there is none to drive.
    ///   - driverInstalled: whether a phone driver is on this device (walkToBall only).
    public func availability(on duck: DuckIdentity.Kind?, driverInstalled: Bool) -> Availability {
        guard let duck else { return .unavailable(Words.noDuck) }
        switch self {
        case .walkToBall:
            if !driverInstalled { return .unavailable(Words.notOnThisPhone) }
            if duck == .real { return .unavailable(Words.trainedOnSim) }
            return .ready
        case .dream:
            return .ready
        }
    }

    /// The subtitle on the card.
    public func subtitle(on duck: DuckIdentity.Kind?, driverInstalled: Bool) -> String {
        if let reason = availability(on: duck, driverInstalled: driverInstalled).reason { return reason }
        switch self {
        case .walkToBall: return Words.practiceOnly
        case .dream: return "Type a goal on the card, then Go."
        }
    }

    public static var all: [String] {
        allCases.flatMap { [$0.title, $0.provenance] }
            + [Words.practiceOnly, Words.notOnThisPhone, Words.trainedOnSim, Words.noDuck,
               Words.go, Words.running, Words.capped(30)]
    }
}

/// The stick after a venue switch: zeroed, and deaf until the finger lifts
/// (docs/plans/native-first-redesign.md, "The venue switch is explicit and input-safe").
///
/// A thumb that was pushing the practice duck when the person chose their real duck must not
/// become the real duck's first command. So a switch closes the gate, every sample reads as
/// centred while it is closed, and a centred sample (the finger lifted, the stick sprang back)
/// opens it again.
public struct StickGate: Equatable, Sendable {
    public private(set) var waitingForLift = false

    public init() {}

    /// The venue changed: ignore the stick until it comes back to centre.
    public mutating func venueChanged() { waitingForLift = true }

    /// Feed one stick sample; returns whether it may drive. A centred sample (every axis at
    /// rest) opens the gate and is itself allowed, because it commands nothing.
    public mutating func admits(centred: Bool) -> Bool {
        if centred { waitingForLift = false; return true }
        return !waitingForLift
    }
}
