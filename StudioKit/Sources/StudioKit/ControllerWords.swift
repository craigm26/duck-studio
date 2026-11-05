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
        case .tell: return "Say or type what the duck should do, or tap a tile."
        case .auto: return "Ask Apple Intelligence for a plan, or pick another helper on the right. Take over any time."
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
    /// The practice duck's tiles: only what it can do. It walks and turns; it has no sitting
    /// latch, no voice and is always on its feet unless it fell (then Put it back on its feet).
    public static let practiceTiles: [(said: String, symbol: String)] = [
        ("walk forward", "arrow.up"),
        ("walk back", "arrow.down"),
        ("turn left", "arrow.counterclockwise"),
        ("turn right", "arrow.clockwise"),
    ]

    /// The tiles for this duck: every tile reads as an order this duck can run.
    public static func tiles(for duck: DuckIdentity.Kind?) -> [(said: String, symbol: String)] {
        duck == .sim ? practiceTiles : tiles
    }

    // MARK: - putting the practice duck back

    /// Reset, renamed for what it does, in More and the duck pill menu, and on the stage after a fall.
    public static let putBack = "Put it back on its feet"
    public static let putBackHint = "Lifts the practice duck upright where it is."
    public static let fellOver = "The duck fell over."
    /// The camera rail's own reset: a different job, so a different name and glyph.
    public static let recentreCamera = "Recentre the camera"

    // MARK: - an Auto run

    public static let takeOver = "Take over"
    public static let takeOverHint = "Stops the goal and gives you the sticks."
    /// The one status line while a goal runs, in place of the cards.
    public static func autoRunning(_ what: String, elapsed: Double, cap: Double) -> String {
        String(format: "%@ · %.0f s of %.0f s", what, max(0, elapsed), cap)
    }
    /// The other helpers, beside Apple Intelligence.
    public static let otherHelpers = "Other helpers"

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
    /// Moves with no duck to run on (build 93): what to do, not only what is missing.
    public static let movesNoDuckTitle = "No duck to run these on yet"
    public static let movesNoDuckLine = "Open Play to drive the Practice duck, or tap the duck pill there to add your own."
    public static let movesGoPlay = "Open Play"

    public static var sheetWords: [String] {
        [movesSheet, movesSheetHint, motions, more, moreHint, moreScene, moreRecord, moreRecordLine,
         moreCamera, moreCameraLine, moreSettings, moreRealDuck, putBack, putBackHint, fellOver,
         recentreCamera, takeOver, takeOverHint, otherHelpers, autoRunning("Walk", elapsed: 4, cap: 60),
         movesNoDuckTitle, movesNoDuckLine, movesGoPlay]
    }
}

/// An Auto goal card: what it is, where it runs, and whether it can run here.
public enum AutoGoal: String, CaseIterable, Sendable, Identifiable {
    /// Dream-1 with the person's own key. First of the helpers beside Apple Intelligence.
    case dream
    /// The phone driver (ducknet-s1), Practice duck only. Its card is `DriverCard`.
    case walkToBall

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .walkToBall: return "Walk to the ball, on this device"
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
        case .walkToBall: return "Runs on this device. Not made by Pollen."
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
        public static let practiceOnly = "Practice duck only for now. Runs on this device, no key needed."
        /// On a real duck, installed or not. THE CAMERA PATH EXISTS (mediad `/frame`), and the driver
        /// is still kept off the robot: it has only ever seen the drawn practice stage, never a real
        /// floor, and no run of it has been judged on one (the build 90 plan's risk 7).
        public static let practiceOnlyForNow = "Practice duck only for now. It has only seen the practice stage."
        /// The driver is a download, not part of the app.
        public static func getFirst(_ size: String) -> String { "Practice duck. Get it first, \(size), in Play, Auto." }
        /// Studio's Drivers row: training your own. The one that ships is in Play, Auto.
        public static let ownDriversLater = "Your own drivers come in a later build. Walk to the ball is in Play, Auto."
        public static let opensDream = "Opens Dream-1 with your goal."
        public static let needsKey = "Needs your Dream Labs key, in Studio, Settings."
        public static let addKey = "Add your key"
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
    /// - Parameter dreamReady: whether a Dream Labs key is on this phone, or the bridge says it
    ///   holds one. Without one the Dream row offers "Add your key" instead of Go.
    public func availability(on duck: DuckIdentity.Kind?, driverInstalled: Bool,
                             dreamReady: Bool = true) -> Availability {
        guard let duck else { return .unavailable(Words.noDuck) }
        switch self {
        case .walkToBall:
            if duck == .real { return .unavailable(Words.practiceOnlyForNow) }
            if !driverInstalled { return .unavailable(Words.getFirst(DriverRelease.walkToBall.size)) }
            return .ready
        case .dream:
            return dreamReady ? .ready : .unavailable(Words.needsKey)
        }
    }

    /// The subtitle on the card.
    public func subtitle(on duck: DuckIdentity.Kind?, driverInstalled: Bool, dreamReady: Bool = true) -> String {
        if let reason = availability(on: duck, driverInstalled: driverInstalled, dreamReady: dreamReady).reason {
            return reason
        }
        switch self {
        case .walkToBall: return Words.practiceOnly
        case .dream: return Words.opensDream
        }
    }

    /// The button on the row: Go, or Add your key when Dream-1 has none.
    public func action(on duck: DuckIdentity.Kind?, driverInstalled: Bool, dreamReady: Bool = true) -> String {
        if self == .dream, duck != nil, !dreamReady { return Words.addKey }
        return Words.go
    }

    public static var all: [String] {
        allCases.flatMap { [$0.title, $0.provenance] }
            + [Words.practiceOnly, Words.practiceOnlyForNow, Words.getFirst(DriverRelease.walkToBall.size),
               Words.ownDriversLater, Words.noDuck, Words.go, Words.running, Words.capped(30), Words.opensDream, Words.needsKey,
               Words.addKey] + DriverCard.Words.all(.walkToBall)
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
