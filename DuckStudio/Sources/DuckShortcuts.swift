import AppIntents
import StudioKit

// Siri, Spotlight, the Shortcuts app and the Action button, for the core orders (build 92).
//
// EVERY INTENT IS ONE CALL INTO THE SAME RUNNER the controller uses (`DuckRuns`), so a sentence to
// Siri, a tile and a tap all take the same route to the duck and the same Stop ends them. The
// sentences they answer with are the kit's (`ShortcutWords`, the runner's captions).
//
// MOTION OPENS THE APP. The duck's connection lives in the app, and Play's red Stop is on screen
// while a Siri-started move runs, so nothing moves without a visible Stop. Stop itself runs in
// the background and needs no unlock. Motion asks for an unlock on a locked phone (iOS).
//
// THE PHRASES ARE LITERALS because Siri reads them at build time. `DuckDecider.Words.siriLine`
// quotes one of them on the Ask the duck card; keep the two in step.

/// Where an intent's order goes: the duck Play is on.
@MainActor
enum DuckIntentRunner {

    /// Wait briefly for Play to attach its duck after the app opened for an intent.
    static func waitForDuck(seconds: Double = 3) async {
        let runs = DuckRuns.shared
        var waited = 0.0
        while runs.peer == nil, waited < seconds {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 0.1
        }
    }

    /// Run one order and answer in a sentence.
    static func run(_ order: DuckOrder) async -> String {
        let runs = DuckRuns.shared
        if runs.peer == nil { await waitForDuck() }
        guard runs.peer != nil else { return ShortcutWords.noDuck }
        // PLAY'S STICK LOOP STEPS ASIDE through the shared Stop, so an order and the stick never
        // write the duck at once. The order below re-opens the latch for itself.
        if runs.playIsDriving { runs.stop() }
        switch await runs.run(order) {
        case .finished: return runs.caption ?? ControllerWords.tellDone
        case .stopped: return runs.caption ?? StopPath.Words.stopped
        case .refused(let why): return why
        case .handedOff: return ControllerWords.tellDone
        }
    }
}

struct StopDuckIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop the duck"
    static let description = IntentDescription("Stops the duck now. A move it has already started finishes first.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let runs = DuckRuns.shared
        guard runs.peer != nil || runs.showsStop else {
            return .result(dialog: "\(ShortcutWords.nothingToStop)")
        }
        let said = runs.stop()
        return .result(dialog: "\(said)")
    }
}

struct StandUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Stand the duck up"
    static let description = IntentDescription("Stands your duck up.")
    static let openAppWhenRun = true
#if os(iOS)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
#endif

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(await DuckIntentRunner.run(.stand))")
    }
}

struct SitDownIntent: AppIntent {
    static let title: LocalizedStringResource = "Sit the duck down"
    static let description = IntentDescription("Sits your duck down.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(await DuckIntentRunner.run(.sit))")
    }
}

enum DuckWalkDirection: String, AppEnum {
    case forward, back, left, right, turnLeft, turnRight

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    static let caseDisplayRepresentations: [DuckWalkDirection: DisplayRepresentation] = [
        .forward: "forward", .back: "back", .left: "left", .right: "right",
        .turnLeft: "turn left", .turnRight: "turn right",
    ]

    var direction: DuckOrder.Direction {
        switch self {
        case .forward: return .forward
        case .back: return .back
        case .left: return .left
        case .right: return .right
        case .turnLeft: return .turnLeft
        case .turnRight: return .turnRight
        }
    }
}

struct WalkDuckIntent: AppIntent {
    static let title: LocalizedStringResource = "Walk the duck"
    static let description = IntentDescription("Walks your duck one way for a few seconds, at most five.")
    static let openAppWhenRun = true
#if os(iOS)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
#endif

    @Parameter(title: "Direction", default: .forward)
    var direction: DuckWalkDirection

    @Parameter(title: "Seconds", default: 2)
    var seconds: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The kit clamps the seconds; a surface never decides how long a walk may be.
        .result(dialog: "\(await DuckIntentRunner.run(.walk(direction.direction, seconds: seconds)))")
    }
}

enum DuckMoveChoice: String, AppEnum {
    case kickLeft = "kick_left"
    case kickRight = "kick_right"
    case roulade
    case groundPick = "ground_pick"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Move"
    static let caseDisplayRepresentations: [DuckMoveChoice: DisplayRepresentation] = [
        .kickLeft: "kick left", .kickRight: "kick right", .roulade: "roulade", .groundPick: "pick up",
    ]
}

struct DoMoveIntent: AppIntent {
    static let title: LocalizedStringResource = "Do a move"
    static let description = IntentDescription("Runs one of your duck's own moves. Only a real duck has them.")
    static let openAppWhenRun = true
#if os(iOS)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
#endif

    @Parameter(title: "Move", default: .roulade)
    var move: DuckMoveChoice

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(await DuckIntentRunner.run(.skill(move.rawValue)))")
    }
}

struct QuackIntent: AppIntent {
    static let title: LocalizedStringResource = "Quack"
    static let description = IntentDescription("Your duck quacks.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(await DuckIntentRunner.run(.sound(DuckOrder.defaultSound)))")
    }
}

struct TellTheDuckIntent: AppIntent {
    static let title: LocalizedStringResource = "Tell the duck"
    static let description = IntentDescription("A short command, like sit down, walk forward or quack.")
    static let openAppWhenRun = true
#if os(iOS)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
#endif

    @Parameter(title: "What should it do?")
    var sentence: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // THE SAME CLOSED GRAMMAR AS TELL, no model: a Siri sentence is read exactly or not at all.
        guard let order = DuckOrderMatcher.match(sentence, skills: Array(RobotPlan.skillSeconds.keys)) else {
            return .result(dialog: "\(ShortcutWords.didNotUnderstand)")
        }
        if order == .stop {
            let said = DuckRuns.shared.stop()
            return .result(dialog: "\(said)")
        }
        return .result(dialog: "\(await DuckIntentRunner.run(order))")
    }
}

/// The phrases. Each one names the app, as Siri requires.
struct DuckShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StopDuckIntent(),
                    phrases: ["Stop the duck in \(.applicationName)",
                              "Freeze the duck in \(.applicationName)",
                              "\(.applicationName) stop the duck"],
                    shortTitle: "Stop the duck", systemImageName: "stop.fill")
        AppShortcut(intent: SitDownIntent(),
                    phrases: ["Sit the duck down in \(.applicationName)",
                              "Tell my duck to sit in \(.applicationName)"],
                    shortTitle: "Sit down", systemImageName: "chair")
        AppShortcut(intent: StandUpIntent(),
                    phrases: ["Stand the duck up in \(.applicationName)",
                              "Tell my duck to stand up in \(.applicationName)",
                              "Wake up the duck in \(.applicationName)"],
                    shortTitle: "Stand up", systemImageName: "figure.stand")
        AppShortcut(intent: WalkDuckIntent(),
                    phrases: ["Walk the duck \(\.$direction) in \(.applicationName)",
                              "Walk the duck in \(.applicationName)"],
                    shortTitle: "Walk", systemImageName: "arrow.up")
        AppShortcut(intent: DoMoveIntent(),
                    phrases: ["Make the duck \(\.$move) in \(.applicationName)",
                              "Make the duck do a move in \(.applicationName)"],
                    shortTitle: "Do a move", systemImageName: "figure.run")
        AppShortcut(intent: QuackIntent(),
                    phrases: ["Quack in \(.applicationName)",
                              "Make the duck quack in \(.applicationName)"],
                    shortTitle: "Quack", systemImageName: "speaker.wave.2")
        AppShortcut(intent: TellTheDuckIntent(),
                    phrases: ["Tell the duck in \(.applicationName)",
                              "Tell my duck in \(.applicationName)"],
                    shortTitle: "Tell the duck", systemImageName: "waveform")
    }
}
