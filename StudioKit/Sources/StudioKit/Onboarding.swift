import Foundation

/// The welcome sheet a person sees on a fresh install: every sentence it says,
/// and where each answer leads.
///
/// It supersedes `FirstRun`'s three cards (docs/plans/native-first-redesign.md,
/// "What a person does in the first five minutes"). `FirstRun` stays in the kit
/// until build 91's app stops drawing it, so its tests still hold.
///
/// THE FIRST QUESTION IS WHETHER THERE IS A DUCK IN THE ROOM. Today the app
/// greets a real-duck owner as somebody without one; a person without one is
/// one tap from the Practice duck. Either way the sheet ends on the controller.
///
/// IT NEVER TALKS SHOP. Onboarding never mentions benches, models, Hugging
/// Face, detail levels, MuJoCo, the deadman or policies; a test reads every
/// sentence here for those words.
///
/// The view draws pages in this order and asks `next(from:choosing:)` where a
/// button goes. It never decides a route itself.
public enum Onboarding {

    // MARK: Pages

    /// One page of the sheet.
    public enum PageID: String, CaseIterable, Sendable {
        /// "Do you have a Microduck with you?"
        case haveDuck
        /// "Is your duck on your Wi-Fi?"
        case wifi
        /// Shown after "Not yet, or I don't know": Pollen's app does Wi-Fi.
        case wifiHelp
        /// Finding the duck without typing.
        case find
        /// Quack, and "Did your duck just quack?"
        case sayHi
        /// One large Stand up button.
        case standUp
    }

    /// A button on a page.
    public enum ChoiceID: String, CaseIterable, Sendable {
        case yesItsHere, notYet
        case onWifi, notOnWifi
        case openPollensApp, doneThat
        case lookForMyDuck, practiceInstead
        case quacked, notMine
        case standUp
    }

    public struct Choice: Equatable, Sendable, Identifiable {
        public let id: ChoiceID
        public let label: String
        /// Drawn as the large filled button. One per page at most.
        public let prominent: Bool

        public init(_ id: ChoiceID, _ label: String, prominent: Bool = false) {
            self.id = id; self.label = label; self.prominent = prominent
        }
    }

    public struct Page: Equatable, Sendable, Identifiable {
        public let id: PageID
        public let title: String
        public let body: String?
        public let choices: [Choice]
        /// Small print under the buttons.
        public let smallPrint: String?

        public init(id: PageID, title: String, body: String? = nil,
                    choices: [Choice], smallPrint: String? = nil) {
            self.id = id; self.title = title; self.body = body
            self.choices = choices; self.smallPrint = smallPrint
        }
    }

    /// Pollen asked that this app not be mistaken for theirs
    /// (pollen-robotics/microduck#329). The first page carries it.
    public static let companionLine =
        "Microduck Studio is a companion app, not Pollen's official app."

    public static let pages: [Page] = [
        Page(id: .haveDuck,
             title: "Do you have a Microduck with you?",
             choices: [Choice(.yesItsHere, "Yes, it's here", prominent: true),
                       Choice(.notYet, "Not yet, let me practise")],
             smallPrint: companionLine),
        Page(id: .wifi,
             title: "Is your duck on your Wi-Fi?",
             choices: [Choice(.onWifi, "Yes", prominent: true),
                       Choice(.notOnWifi, "Not yet, or I don't know")]),
        Page(id: .wifiHelp,
             title: "Pollen's app puts your duck on Wi-Fi",
             body: "Pollen's Microduck app does Wi-Fi, updates and sign-in. Set your duck up "
                 + "there, then come back here.",
             choices: [Choice(.openPollensApp, "Open Pollen's app", prominent: true),
                       Choice(.doneThat, "I've done that")]),
        Page(id: .find,
             title: "Let Studio find your duck on this network",
             body: "Studio talks to your duck over your home network, so iOS will ask once "
                 + "whether it may look there.",
             choices: [Choice(.lookForMyDuck, "Look for my duck", prominent: true),
                       Choice(.practiceInstead, "Use the Practice duck for now")]),
        Page(id: .sayHi,
             title: "Say hi",
             body: "Studio just asked your duck to quack.",
             choices: [Choice(.quacked, "Yes", prominent: true),
                       Choice(.notMine, "That's not mine")]),
        Page(id: .standUp,
             title: "Your duck is ready",
             body: "Stand it up, then drive it with your thumbs.",
             choices: [Choice(.standUp, "Stand up", prominent: true)]),
    ]

    public static func page(_ id: PageID) -> Page {
        pages.first { $0.id == id }!
    }

    /// The question on the say-hi page, under the quack.
    public static let didItQuack = "Did your duck just quack?"

    // MARK: Routing

    /// Where a button leads.
    public enum Destination: Equatable, Sendable {
        case page(PageID)
        /// Close the sheet onto the controller in Drive mode.
        case controller(onPracticeDuck: Bool)
        /// Hand over to Pollen's app; the sheet stays where it is.
        case openPollensApp
    }

    /// The Duck sheet's "Add your duck" row starts here: the person already
    /// said they have a duck by tapping it.
    public static let addYourDuckStart: PageID = .wifi

    /// Where `choice` on `page` goes. A choice that does not belong to the
    /// page leaves the person on it.
    public static func next(from page: PageID, choosing choice: ChoiceID) -> Destination {
        switch (page, choice) {
        case (.haveDuck, .yesItsHere): return .page(.wifi)
        case (.haveDuck, .notYet): return .controller(onPracticeDuck: true)
        case (.wifi, .onWifi): return .page(.find)
        case (.wifi, .notOnWifi): return .page(.wifiHelp)
        case (.wifiHelp, .openPollensApp): return .openPollensApp
        case (.wifiHelp, .doneThat): return .page(.find)
        case (.find, .lookForMyDuck): return .page(.sayHi)
        case (.find, .practiceInstead): return .controller(onPracticeDuck: true)
        case (.sayHi, .quacked): return .page(.standUp)
        case (.sayHi, .notMine): return .page(.find)
        // Onboarding is an explicit connect action, so this venue switch is
        // allowed (Rules across all modes).
        case (.standUp, .standUp): return .controller(onPracticeDuck: false)
        default: return .page(page)
        }
    }

    /// The buttons a person presses from a fresh install to a standing duck,
    /// with a duck on the Wi-Fi and found on the first look. Picking the duck
    /// from a list of more than one adds a tap the flow cannot count.
    public static let tapsToStand: [(PageID, ChoiceID)] = [
        (.haveDuck, .yesItsHere), (.wifi, .onWifi), (.find, .lookForMyDuck),
        (.sayHi, .quacked), (.standUp, .standUp),
    ]

    // MARK: Finding the duck

    /// The ways Studio looks for a duck, in the order it tries them. Typing is
    /// last and collapsed.
    public enum Discovery: String, CaseIterable, Sendable {
        case bluetooth, bonjour, code, typed

        public var label: String {
            switch self {
            case .bluetooth: return "Ducks nearby"
            case .bonjour: return "A bridge on this network"
            case .code: return "Scan the code on your bridge"
            case .typed: return "Type it"
            }
        }

        /// Reading a duck's home address over Bluetooth is unverified: it
        /// depends on which calls Pollen routes over BLE.
        public var verified: Bool { self != .bluetooth }
    }

    public static let lookingSaid = "Looking for your duck."
    public static let foundNoDuck =
        "No duck answered on this network. Check it is on the same Wi-Fi as this phone, "
      + "or scan the code on your bridge."
    public static func found(_ name: String) -> String { "Found \(name)." }

    /// When the person declined the Local Network prompt.
    public static let localNetworkDeclined =
        "Studio cannot look for your duck without Local Network access. You can allow it in "
      + "Settings, and drive the Practice duck until then."
    public static let openSettings = "Open Settings"

    // MARK: Standing up

    /// A refusal from the robot, in plain words. `reason` is the robot's own
    /// named reason; a trailing full stop is not doubled.
    public static func standRefused(because reason: String) -> String {
        var why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        while why.hasSuffix(".") { why.removeLast() }
        guard !why.isEmpty else { return "Your duck did not stand up." }
        return "Your duck did not stand up: \(why)."
    }

    /// The robot's sitting latch, said the way a person would.
    public static let sittingRefusal = "Your duck is sitting; it can only stand up from here."

    // MARK: The first minutes on the controller

    /// Three one-time coach marks, each a collapsed chip.
    public static let coachMarks = [
        "Press Stand",
        "Push the stick a little",
        "Tap the red disc any time to stop",
    ]

    /// Shown once, after the first successful stand.
    public static let siriTip = "Say: Duck Studio, stop the duck."

    /// The skippable card after about thirty seconds of driving.
    ///
    /// IT SHOWS STEPS AND NEVER CLAIMS TO HAVE DONE THEM. The app cannot place
    /// a Control or set the Action button itself.
    public static let makeItYoursTitle = "Make it yours"
    public static let makeItYoursSteps = [
        "Add Stop to Control Center: open Control Center, touch and hold an empty space, "
      + "tap Add a Control, then choose Stop the duck.",
        "Put Stop on the Action button: open Settings, tap Action Button, swipe to Controls, "
      + "then choose Stop the duck.",
        "Try Siri: say \"Duck Studio, stop the duck.\"",
    ]
    public static let makeItYoursSkip = "Not now"
    /// Seconds of successful driving before the card is offered.
    public static let makeItYoursAfter: TimeInterval = 30

    // MARK: Returning launches

    public static let practiceDuck = "Practice duck"
    public static let connecting = "Connecting"
    public static let reconnect = "Reconnect"
    /// How long a returning launch waits for the last duck before staying on
    /// the Practice duck. It never switches venue by itself.
    public static let reconnectWait: TimeInterval = 1.5

    // MARK: Showing it

    /// The welcome sheet is for a fresh install only. Somebody who saw any
    /// version of `FirstRun` already has the app, and reaches the duck pages
    /// through "Add your duck" in the Duck sheet.
    public static func shouldShow(seenFirstRunVersion: Int?) -> Bool {
        seenFirstRunVersion == nil
    }

    /// Every sentence in the sheet, for the tests that read them.
    public static var allWords: [String] {
        var all = [companionLine, didItQuack, lookingSaid, foundNoDuck, found("Puddle"),
                   localNetworkDeclined, openSettings, sittingRefusal, siriTip,
                   makeItYoursTitle, makeItYoursSkip, practiceDuck, connecting, reconnect,
                   standRefused(because: "it is busy")]
        for p in pages {
            all.append(p.title)
            if let b = p.body { all.append(b) }
            if let s = p.smallPrint { all.append(s) }
            all += p.choices.map(\.label)
        }
        all += coachMarks + makeItYoursSteps + Discovery.allCases.map(\.label)
        return all
    }
}
