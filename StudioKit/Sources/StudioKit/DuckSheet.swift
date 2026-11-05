import Foundation

/// The Duck sheet: the one place a person sees which duck they drive, its camera, its
/// connection and its details, opened from the duck pill on any tab
/// (docs/plans/native-first-redesign.md, "The screen hierarchy", build 91).
///
/// THE APP DRAWS, THIS DECIDES. The sections, their order, which of them hide behind
/// "Show expert tools", and every sentence the sheet says are here, so a Linux test can
/// pin them to the plan's tree (`ScreenHierarchy.target`, sheet `duckSheet`).
public enum DuckSheet {

    /// One section of the sheet, in the plan's order. The raw value is the node id's last
    /// part in `ScreenHierarchy.target`.
    public enum Section: String, CaseIterable, Sendable, Identifiable {
        case yourDuck, camera, pollen, connection, details, room, siri, add, expert

        public var id: String { rawValue }

        /// The node this section is in the target tree.
        public var node: String { "duckSheet.\(rawValue)" }

        public var title: String {
            switch self {
            case .yourDuck: return "Your duck"
            case .camera: return "Camera"
            case .pollen: return "Open Pollen's app"
            case .connection: return "Connection"
            case .details: return "Robot details"
            case .room: return "Your room"
            case .siri: return "Siri and Shortcuts"
            case .add: return "Add your duck"
            case .expert: return "Expert"
            }
        }

        /// Shown only with "Show expert tools" on.
        public var expertOnly: Bool { self == .expert }

        /// Room capture measures the floor through ARKit, which a Mac does not have.
        public var phoneOnly: Bool { self == .room }
    }

    /// The sections drawn, in order.
    public static func sections(expert: Bool, phone: Bool) -> [Section] {
        Section.allCases.filter { (expert || !$0.expertOnly) && (phone || !$0.phoneOnly) }
    }

    // MARK: Words

    public static let title = "Your duck"
    public static let driveOnLine = "Choose which duck the controller drives. Nothing switches by itself."
    /// The live dot, in words, for the row beside it. It is the toolbar lens, merged.
    public static let liveAnswered = "Answering"
    public static let liveWaiting = "Waiting for an answer"
    public static let liveNone = "Not connected"
    public static let cameraFromConnection =
        "The camera uses your duck's address from the connection, so there is nothing to type."
    public static let pollenLine =
        "Health, updates and Wi-Fi live in Pollen's Microduck app. Studio does not rebuild them."
    public static let connectRow = "Connect by address"
    public static let connectRowLine = "Your duck's bridge, with the code it printed."
    public static let findRow = "Ducks nearby"
    public static let findRowLine = "Scan over Bluetooth."
    public static let detailsLine = "Size, weight, servos and the numbers your duck reports."
    public static let roomLine = "Measure the floor and tables around you."
    public static let addLine = "Set up a duck on this network, step by step."
    public static let siriLine = "Say \"Duck Studio, stop the duck.\" Stop can also go in Control Center "
        + "or on the Action button; Studio shows the steps and never sets them for you."
    public static let expertMachines = "Machines and remote"
    public static let expertMachinesLine = "Saved machines, ducks found on the network, and Pollen's rendezvous."
    public static let expertDiagnostics = "Diagnostics"
    public static let expertDiagnosticsLine = "The Bluetooth test report and the transports."
    public static let expertBenches = "Benches"
    public static let expertBenchesLine = "Benches live in Studio, Measure."

    /// Every sentence the sheet says, for the tests that read them.
    public static var allWords: [String] {
        Section.allCases.map(\.title)
            + [title, driveOnLine, liveAnswered, liveWaiting, liveNone, cameraFromConnection,
               pollenLine, connectRow, connectRowLine, findRow, findRowLine, detailsLine, roomLine,
               addLine, siriLine, expertMachines, expertMachinesLine, expertDiagnostics,
               expertDiagnosticsLine, expertBenches, expertBenchesLine]
            + Onboarding.makeItYoursSteps
    }
}

/// THE VENUE SWITCH IS EXPLICIT AND INPUT-SAFE (the plan's required fix 2).
///
/// The controller's venue changes only when a person asks for a duck: the duck pill, the
/// Duck sheet's "Drive on", or onboarding's Stand up. A reconnect, a game opened from Moves,
/// an import or a launch never moves it. When it does move, the stick gate closes, so the
/// thumb that was on the practice duck is not the real duck's first command.
public enum VenueRule {

    /// Why somebody, or something, asked for a venue.
    public enum Cause: String, CaseIterable, Sendable {
        /// The duck pill's "Drive on" menu.
        case duckPill
        /// The Duck sheet's "Drive on" row.
        case duckSheet
        /// Onboarding's Stand up, or a connect from the welcome sheet.
        case onboarding
        /// A link that came back by itself.
        case reconnect
        /// A game opened from Moves.
        case game
        /// A file arriving.
        case importFile
        /// The app opening.
        case launch

        /// Only a person's own pick may switch.
        public var isExplicit: Bool {
            switch self {
            case .duckPill, .duckSheet, .onboarding: return true
            case .reconnect, .game, .importFile, .launch: return false
            }
        }
    }

    /// What a request does.
    public struct Outcome: Equatable, Sendable {
        /// The venue in force after the request.
        public let venue: DriveVenue
        /// Whether it moved. A move closes the stick gate and says "Now driving ...".
        public let switched: Bool
    }

    /// The venue after `cause` asks for `asked` while `current` is in force. A request that is
    /// not explicit, or that asks for the venue already in force, changes nothing. A switch
    /// closes `gate`.
    public static func request(_ asked: DriveVenue, from current: DriveVenue, cause: Cause,
                               gate: inout StickGate) -> Outcome {
        guard cause.isExplicit, asked != current else {
            return Outcome(venue: current, switched: false)
        }
        gate.venueChanged()
        return Outcome(venue: asked, switched: true)
    }
}

/// Where a file that arrived lands (the plan's "Imports ... landing changed"): sequences,
/// plans, packs and decks in Moves with an "Added" chip; drafts (motions) in Studio, Make;
/// policies in Studio, Behaviours. Nothing that arrives ever switches the venue.
public enum ImportLanding: Equatable, Sendable {
    case moves
    case studioMake
    case studioBehaviours
    /// Nothing new arrived (refused, unreadable, or a replacement): stay where you are.
    case stay

    /// What grew, counted before and after the import.
    public struct Growth: Equatable, Sendable {
        public var drafts = 0
        public var plans = 0
        public var sequences = 0
        public var packs = 0
        public var decks = 0
        public var policies = 0

        public init(drafts: Int = 0, plans: Int = 0, sequences: Int = 0, packs: Int = 0,
                    decks: Int = 0, policies: Int = 0) {
            self.drafts = drafts; self.plans = plans; self.sequences = sequences
            self.packs = packs; self.decks = decks; self.policies = policies
        }
    }

    /// The landing for what grew. A draft is something to work on, so it wins over a toy.
    public static func landing(for growth: Growth) -> ImportLanding {
        if growth.drafts > 0 { return .studioMake }
        if growth.plans > 0 || growth.sequences > 0 || growth.packs > 0 || growth.decks > 0 {
            return .moves
        }
        if growth.policies > 0 { return .studioBehaviours }
        return .stay
    }

    /// The chip on Moves after something lands there.
    public static let added = "Added"
    public static func addedLine(_ what: String) -> String { "Added \(what) to Moves." }
}
