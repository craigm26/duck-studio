import SwiftUI
import StudioKit

/// The three tabs, in the order a person meets them (build 91).
///
/// PLAY, MOVES, STUDIO. Play is the controller and the app opens on it; Moves is the toy box;
/// Studio is the workshop, holding everything advanced one level down
/// (docs/plans/native-first-redesign.md, "The screen hierarchy"). The Duck sheet opens from the
/// duck pill on Play.
///
/// THE ORDER IS THE TAG ORDER AND THE TAG ORDER IS LOAD-BEARING: `-tab 1` is Moves. The kit's
/// `ScreenHierarchy.launch` reads the argument, by index or by name, and keeps the old names
/// working: `-tab control` is Play, `-tab learn` and `-tab behaviours` are Studio, `-tab duck` is
/// Play with the Duck sheet up. The raw values are the target tree's tab ids, and a Linux test
/// pins the tree.
enum AppTab: String, CaseIterable, Identifiable {
    case play, moves, studio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .play: return "Play"
        case .moves: return "Moves"
        case .studio: return "Studio"
        }
    }

    var symbol: String {
        switch self {
        case .play: return "gamecontroller"
        case .moves: return "square.grid.2x2"
        case .studio: return "wand.and.stars"
        }
    }
}

enum StudioDestination: String, Identifiable, Hashable, CaseIterable {
    case motions, scenes, draft, measure, challenges, evaluations
    /// The two Learn sends somebody to that had no route before.
    case tune, preference
    /// Train a duck to shoot.
    case shoot
    /// Mimic a person (Mac only on the hub; routed for the Mac's Mimic links).
    case mimic
    /// Build 91: the two tabs that folded into Studio.
    case behaviours, learn

    var id: String { rawValue }
}

/// A place inside Play that somebody asked for.
enum PlayRoute: Equatable {
    case drive, tell, auto
    /// Play, with the Duck sheet up.
    case duckSheet
    /// Drive on this duck. Play asks `VenueRule` whether the cause may switch it: only the duck
    /// pill, the Duck sheet's "Drive on" and onboarding can.
    case venue(DriveVenue, VenueRule.Cause)
    /// Play a kept sequence on Play's stick loop (a tap in Moves' "My sequences").
    case sequence(UUID)
}

/// Where a screen can send somebody: a tab, and optionally a place inside it.
enum AppRoute: Equatable {
    case play(PlayRoute? = nil)
    case moves
    case studio(StudioDestination? = nil)
}

/// Which tab is showing, and the one way to change it from inside a screen.
///
/// A SCREEN THAT SENDS SOMEBODY SOMEWHERE MUST BE ABLE TO ACTUALLY SEND THEM, and a tab is not
/// always the whole route: Behaviours > Retrain means Studio > Draft. `pendingStudio` and
/// `pendingPlay` are the second hop, held until the tab that owns it takes it, one-shot rather than
/// stored, so a tab is left where the person left it.
@MainActor final class AppRouter: ObservableObject {
    @Published var tab: AppTab

    /// The place inside Studio somebody has just asked for, or nil. Bound to
    /// `navigationDestination(item:)`, which writes nil back when the screen is dismissed.
    @Published var pendingStudio: StudioDestination?

    /// The mode or sheet inside Play somebody has just asked for; Play clears it when taken.
    @Published var pendingPlay: PlayRoute?

    /// Whether the Duck sheet is up.
    @Published var duckSheet = false

    /// The welcome sheet re-entered from the Duck sheet's "Add your duck", at this page.
    @Published var welcomeAgain: Onboarding.PageID?

    /// The venue Play is on, mirrored by Play for the Duck sheet's "Drive on" checkmark. Written
    /// only by Play: a request to change it is `go(to: .play(.venue(...)))`.
    @Published var playVenue: DriveVenue = .sim

    /// What an import just added to Moves, for the "Added" chip; Moves clears it.
    @Published var added: String?

    init(tab: AppTab = .play) {
        self.tab = tab
    }

    /// Show a tab.
    func go(to tab: AppTab) {
        go(to: tab, then: nil)
    }

    /// Show a tab, and (when the tab is Studio) the place inside it. A destination for a tab
    /// that is not Studio is dropped rather than remembered.
    func go(to tab: AppTab, then destination: StudioDestination?) {
        pendingStudio = tab == .studio ? destination : nil
        self.tab = tab
    }

    /// Push-capable routes: `router.go(to: .studio(.preference))`.
    func go(to route: AppRoute) {
        switch route {
        case .play(let inside):
            pendingStudio = nil
            if inside == .duckSheet { duckSheet = true } else { pendingPlay = inside }
            tab = .play
        case .moves:
            go(to: AppTab.moves)
        case .studio(let inside):
            go(to: .studio, then: inside)
        }
    }

    /// The `-tab` launch argument, read by the kit.
    static var launch: ScreenHierarchy.Launch {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else {
            return ScreenHierarchy.launch(nil)
        }
        return ScreenHierarchy.launch(args[i + 1])
    }

    static func launched() -> AppRouter {
        let asked = launch
        let router = AppRouter(tab: AppTab(rawValue: asked.tab) ?? .play)
        router.duckSheet = asked.duckSheet
        return router
    }
}

/// Microduck Studio: one robot, and everything you can ask of it.
///
/// THREE TABS, AND THE FIRST ONE IS THE CONTROLLER (build 91). Play drives the
/// duck in three modes, Drive, Tell and Auto, with Stop always on screen; Moves
/// is everything the duck can do; Studio is the hub for making, training and the
/// expert tools, one level down. The duck itself lives in the Duck sheet behind
/// the duck pill. See docs/plans/native-first-redesign.md.
///
/// The rule this app is built to: **StudioKit computes, DuckStudio displays.**
/// No arithmetic here, and no sentence about a policy written here either —
/// every one of them is built and asserted by `swift test` on Linux, because a
/// refusal message is this app's whole value proposition and one you cannot
/// test is one you find out about in review. The same rule is why a blocked
/// surface ships as an explicit "not yet" in a tested kit string rather than as
/// an empty card or a control that is present and inert.
///
/// The entry point is `DuckStudioLaunch` (RenderTakes.swift), which starts this unless a Mac was
/// launched with `-render-takes`.
struct DuckStudioApp: App {
    @StateObject private var model = LibraryModel()
    @StateObject private var scenes = SceneStore()
    @StateObject private var drafts = DraftStore()
    @StateObject private var plans = PlanStore()
    /// Which model writes drafts. One store, shared: Studio's Draft screen uses
    /// it and the Models screen edits it.
    @StateObject private var models = EndpointStore()
    /// How much of the app to show, and whether the welcome has been seen.
    @StateObject private var detail = DetailStore()
    /// Which benches this phone knows about. One store, shared, for the same
    /// reason `models` is: three screens send work to a bench, and a bench
    /// chosen on one of them is the bench the others should use.
    @StateObject private var benches = BenchStore()
    /// Which saved machines answered this launch, and which were found on the
    /// network. Checked once as the app opens; see `MachineStore`.
    @StateObject private var machines = MachineStore()
    /// The Hugging Face sign-in that lists ducks from anywhere (REMOTE-REACH.md).
    @StateObject private var remote = RemoteReachStore()
    /// The evaluation logs on this phone, the ones it wrote and the ones it was
    /// handed. Held here rather than inside Studio's own screens because a
    /// shelf built when a screen appears is a shelf that forgets what is on it
    /// every time somebody leaves the tab, and because the run screen files a
    /// log into the same store the list reads.
    @StateObject private var evals = EvalStore()

    /// The machine that runs one evaluation, held beside the shelf it files
    /// into rather than inside the screen that sets one up.
    ///
    /// A RUN OUTLIVES EVERY SCREEN THAT CAN SEE IT, AND THAT IS THE WHOLE
    /// REASON IT IS HERE. It was a `@StateObject` on the setup screen: two taps
    /// on Back destroyed the only reference anything held, while the request
    /// loop went on spending minutes of somebody's bench with no Stop button
    /// anywhere in the app, and a run that was still asking for verdicts could
    /// never file its log, because the queue it waits on is drained by a sheet
    /// that no longer had a screen to sit on. Nothing that was measured
    /// survived. Owned here it lives exactly as long as `evals` does, which is
    /// the store it writes into, so leaving a screen is leaving a screen.
    @StateObject private var evalRunner = EvalRunner()

    /// THE ONE OPEN LINK TO A ROBOT, held here for the reason `evalRunner` is:
    /// it outlives every screen that can see it. A bridge connected on the
    /// Robot tab is the link the Play tab drives, and walking between the
    /// two must not close a socket to a machine with a duck standing on it.
    /// See `BridgeLink`.
    @StateObject private var robot = BridgeLink()

    /// THE PHYSICS THIS APP SPENT ITS WHOLE LIFE SAYING IT DID NOT HAVE.
    ///
    /// A 1×1 WebView, alpha zero, running MuJoCo compiled to WebAssembly behind
    /// a loopback HTTP server, answering the same ten endpoints the bench on
    /// your network answers. It is held at the top because that is the only
    /// place with a view hierarchy that lives as long as the app: iOS suspends
    /// a WebView's content process the moment it is not in a window, and a
    /// suspended process runs no JavaScript — so a bench parented to a tab
    /// would stop being a bench whenever somebody changed tabs.
    ///
    /// NOTHING ELSE IN THE APP KNOWS IT IS SPECIAL. `BenchStore` puts it first
    /// in the list with its port filled in; every screen that already reads
    /// that list gets it for free, and `BenchPeer` dials it over HTTP exactly
    /// as it dials a Raspberry Pi.
    @StateObject private var phoneBench = PhoneBenchHost()

    /// Which tab is showing, and the only thing that may change it.
    ///
    /// IT EXISTS SO A SCREEN CAN SEND SOMEBODY SOMEWHERE, and — still — SO
    /// SCREENSHOTS CAN BE TAKEN WITHOUT A HUMAN THUMB. `TabView` with no
    /// selection cannot be told which tab to open, and the App Store wants a
    /// picture of each one. A simulator can launch an app with arguments but
    /// cannot tap a tab bar, so the launch argument is the whole mechanism:
    /// `-tab 3` opens the fourth tab and the shot is taken.
    ///
    /// It changes nothing for anybody running the app normally — no argument,
    /// first tab, exactly as before — and it is deliberately not a persisted
    /// preference, because "the tab you were last on" is a different feature
    /// with different opinions and this is not it.
    @StateObject private var router = AppRouter.launched()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // THE SELECTED TAB IS MARKED THE WAY iOS MARKS IT, AND THE BILL IS
            // NOT AVAILABLE HERE. The design system asks for `BillIndicator` —
            // a flat orange bar, squared at one end — under the selected tab,
            // and SwiftUI has no API that will accept one: `TabView` exposes no
            // selection-indicator hook in any form, and the nearest thing on the
            // platform is `UITabBarAppearance.selectionIndicatorImage`, which
            // takes a rasterised `UIImage` rather than a view, sits centred
            // behind the whole item rather than as a bar beneath it, and is not
            // this component. The only remaining route is a hand-drawn tab bar,
            // and the brief for this app is explicit that native beats custom —
            // a custom bar would cost the system's own VoiceOver ordering, its
            // "More" folding, its Dynamic Type behaviour and its scroll-edge
            // material to gain one silhouette. So the selection is carried by
            // the tint, which is where the bill's colour goes instead.
            //
            // `BillIndicator` is used inside the app where the design system's
            // other job for it — the slider fill and the standalone marker — is
            // reachable in SwiftUI.
            TabView(selection: $router.tab) {
                NavigationStack {
                    DriveView(model: model, benches: benches, scenes: scenes, drafts: drafts,
                              robot: robot, models: models, detail: detail)
                }
                    .tabItem { Label(AppTab.play.title, systemImage: AppTab.play.symbol) }
                    .tag(AppTab.play)

                NavigationStack {
                    MovesView(model: model, drafts: drafts, benches: benches, models: models, robot: robot)
                }
                    .stopPill()
                    .tabItem { Label(AppTab.moves.title, systemImage: AppTab.moves.symbol) }
                    .tag(AppTab.moves)

                NavigationStack {
                    StudioHubView(model: model, scenes: scenes, drafts: drafts,
                                  models: models, benches: benches, plans: plans,
                                  evals: evals, evalRunner: evalRunner, detail: detail)
                }
                    .stopPill()
                    .tabItem { Label(AppTab.studio.title, systemImage: AppTab.studio.symbol) }
                    .tag(AppTab.studio)
            }
            // THE DUCK SHEET, from the duck pill on Play (or `-tab duck`, or ⌘D on a Mac).
            .sheet(isPresented: $router.duckSheet) {
                NavigationStack {
                    DuckSheetView(model: model, scenes: scenes, drafts: drafts,
                                  models: models, benches: benches, detail: detail,
                                  machines: machines, remote: remote, robot: robot)
                }
                .environmentObject(router)
                .stopPill()
            }
            // "ADD YOUR DUCK", from the Duck sheet: the welcome again, from the Wi-Fi page.
            .sheet(item: welcomeAgainItem) { start in
                WelcomeView(robot: robot, start: start.page, finish: endWelcomeAgain)
                    .stopPill()
            }
            // THE ROUTER IS INJECTED ON THE TAB VIEW, WHICH IS THE ONLY PLACE
            // EVERY TAB IS DOWNSTREAM OF. A card on My Microduck that says
            // "drive it" declares `@EnvironmentObject private var router:
            // AppRouter` and calls `router.go(to: .control)`; there is no other
            // sanctioned way to move somebody between tabs, because a second
            // source of truth for the selection is a tab bar that disagrees
            // with the screen.
            // THE BENCH THAT IS THIS PHONE, PUT WHERE WebKit WILL KEEP IT
            // RUNNING. An overlay rather than a background: a background can be
            // laid out at zero size, and a WebView with no size is a WebView
            // iOS is entitled to suspend. One point in the corner, alpha zero
            // on the UIView itself rather than `.opacity(0)`, no hit testing
            // and hidden from VoiceOver — present to the system, absent to
            // everybody else.
            .overlay(alignment: .topLeading) {
                PhoneBenchHostView(host: phoneBench)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // STARTED ONCE, WITH THE STORE IT HAS TO TELL. The listener's port
            // comes from the kernel at bind time, so the first row of the bench
            // list is unreachable until this has run — which is a real state
            // with a sentence of its own rather than something to hide behind a
            // spinner.
            .task { phoneBench.start(benches: benches) }
            // CONNECT ON LAUNCH: every saved machine is asked whether its bench
            // and router are up, and the network is browsed for machines
            // nobody has saved. Nothing is added without a tap.
            .task { await machines.check(benches) }
            // Listing opens no session on the rendezvous; it runs only when
            // somebody has signed in.
            .task { await remote.list() }
            .environmentObject(router)
            // LARGE TITLES ARE THE DEFAULT AND THE ROOT DOES NOT IMPOSE THEM.
            // A `NavigationStack` root already gets a large title, so every tab
            // root is large without a word being said — and a screen that wants
            // `.inline`, like the chat transcript inside Studio with a compose
            // bar under it, says so for itself.
            // `navigationBarTitleDisplayMode` applied out here would reach past
            // that decision and overrule it from a file that cannot see it,
            // which is exactly the kind of remote override this app's own theme
            // comment argues against.
            //
            // THE DISPLAY WEIGHT IS NOT SET, AND THAT IS A TRADE RATHER THAN AN
            // OMISSION. The design system asks for `.heavy` on large titles and
            // SwiftUI has no font API for one: the only route is
            // `UINavigationBar.appearance().largeTitleTextAttributes`, and a
            // font put there is a fixed point size that stops responding to
            // Dynamic Type — the appearance proxy is configured once at launch
            // and a bar built from it does not re-scale. That would buy one
            // weight and sell the largest text in the app out of Dynamic Type,
            // on a screen where somebody is reading a refusal at AX5. `Theme`
            // makes the choice in its own words: "Dynamic Type matters more
            // than a matched face" — and a matched weight is worth less than a
            // matched face.

            // A policy handed over from Files, Mail, AirDrop or another app.
            // Declared in Info.plist as an IMPORTED type — ONNX is not this
            // app's format to own.
            // THE WELCOME, ONCE. Only a genuinely empty container gets
            // it — `DetailStore` marks an existing install as having had its
            // first run already, because showing this on somebody's fortieth
            // launch is the update introducing itself as a stranger.
            // A constant binding would re-present on any swipe-down, so this
            // writes through: dismissing the welcome ANY way — Skip, Start, or
            // a flick downwards — counts as having seen it. Being asked twice
            // because you swiped is worse than never being asked.
            .sheet(isPresented: Binding(
                get: { detail.shouldShowFirstRun },
                set: { showing in
                    if !showing, detail.shouldShowFirstRun {
                        detail.finishFirstRun(choosing: nil)
                    }
                })) {
                WelcomeView(robot: robot, finish: endWelcome)
                    .stopPill()
            }
            // AN IMPORT LANDS WHERE ITS KIND LIVES: Moves for sequences, plans and packs, with an
            // "Added" chip; Studio, Make for drafts. It never moves the venue.
            .onOpenURL(perform: openImport)
            // THE 0.4 s SETTLE IS THE POINT AND ALSO THE HOLE. Both stores
            // batch writes so that a finger on a slider does not encode the
            // whole library sixty times a second — and a rename is a single
            // keystroke that lands inside that window. Every other way out of
            // an editor already flushes; being swiped away from the app
            // switcher is the one that did not, and it is the only remaining
            // path by which an edit can be genuinely lost rather than merely
            // look lost. `EndpointStore` is deliberately absent: its `flush` is
            // private, and adding a caller is not this change.
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { scenes.flush(); drafts.flush() }
                // LEAVING THE FOREGROUND ENDS EVERY CHAIN, PLAN AND GOAL. The practice duck cannot
                // run suspended and a real duck's link is not kept alive in the background.
                if phase == .background { DuckRuns.shared.leftForeground() }
                // .background, NOT .inactive: on a Mac a window that merely
                // loses focus is inactive, and a download should survive that.
                if phase == .background { PhoneModelRuntime.shared.stopDownloadForSuspension() }
            }
            // INSIDE THE WindowGroup, ON THE VIEW. `tint` and
            // `preferredColorScheme` are View modifiers; hung on the
            // WindowGroup they are a Scene modifier that does not exist.
            //
            // THIS IS ALSO THE TAB BAR'S TINT. `microduckTheme` sets
            // `.tint(Theme.actionPrimary)` for the whole app, and the selected
            // tab item is the most visible thing that inherits it — Duck Orange
            // on the tab bar, which is where the action colour belongs. Two
            // notes for whoever owns the tokens next. The first is that the
            // scheme is no longer forced: the modifier now carries whatever
            // `Theme.Appearance` the person chose, which is `system` by default
            // and therefore no override at all. The second is a measured
            // caveat: Duck Orange is 2.30:1 on Warm Cream, so in light mode the
            // selected tab's LABEL is an orange word on a near-cream bar and
            // does not clear the 4.5:1 SC 1.4.3 asks of text. The palette
            // already holds the fix — `actionSecondary` is the same orange
            // darkened to 4.52:1 in light and left as Duck Orange in dark — but
            // one `.tint` serves every control in the app, and swapping it here
            // would take the brand value out of every filled control at the
            // same time. It belongs in `Theme`, as a tint that is the ink in
            // light and the brand in dark, not in a per-screen override.
            .microduckTheme()
#if os(macOS)
            // The phone layouts are written for a column; below this they
            // start to wrap mid-control.
            .frame(minWidth: 720, minHeight: 560)
#endif
        }
#if os(macOS)
        .defaultSize(width: 1100, height: 780)
        .commands {
            // ONE WINDOW. Every store this app has is a @StateObject on the App,
            // so a second window would be a second view onto the same library,
            // benches and router — switching a tab in one would switch it in
            // both. Until the app is built for several windows, File > New
            // Window is taken away rather than offered and wrong.
            CommandGroup(replacing: .newItem) {}
            TabCommands(router: router)
        }
#endif
    }
}

extension DuckStudioApp {
    /// Where the welcome sheet ended. Stand up is an explicit connect, so it is the one place
    /// outside the duck pill and the Duck sheet that may put Play on the real duck.
    @MainActor func land(_ ended: Onboarding.Destination) {
        guard case .controller(let practice) = ended else { return }
        let venue: DriveVenue = practice ? .sim : .real
        router.go(to: .play(.venue(venue, .onboarding)))
    }

    /// The fresh-install welcome ended: seen, and land where it said.
    @MainActor func endWelcome(_ ended: Onboarding.Destination) {
        detail.finishFirstRun(choosing: nil)
        land(ended)
    }

    /// "Add your duck" ended.
    @MainActor func endWelcomeAgain(_ ended: Onboarding.Destination) {
        router.welcomeAgain = nil
        land(ended)
    }

    /// The "Add your duck" welcome as a sheet item.
    var welcomeAgainItem: Binding<WelcomeStart?> {
        Binding(get: { router.welcomeAgain.map { WelcomeStart(page: $0) } },
                set: { router.welcomeAgain = $0?.page })
    }

    /// A file handed to the app lands where its kind lives: Moves for sequences, plans and
    /// packs, with an "Added" chip; Studio, Make for drafts. It never moves the venue.
    @MainActor func openImport(_ url: URL) {
        switch Imports.open(url, model: model, drafts: drafts, plans: plans) {
        case .moves:
            router.added = ImportLanding.addedLine(url.deletingPathExtension().lastPathComponent)
            router.go(to: AppTab.moves)
        case .studioMake: router.go(to: .studio(.motions))
        case .studioBehaviours: router.go(to: .studio(.behaviours))
        case .stay: break
        }
    }
}

/// The page "Add your duck" re-enters the welcome at, as a sheet item.
struct WelcomeStart: Identifiable {
    let page: Onboarding.PageID
    var id: String { page.rawValue }
}

#if os(macOS)
/// The tabs as a Go menu, ⌘1 to ⌘3, and ⌘D for the Duck sheet, which is how a Mac app with a
/// tab bar is driven from the keyboard.
struct TabCommands: Commands {
    @ObservedObject var router: AppRouter

    var body: some Commands {
        CommandMenu("Go") {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { router.tab = tab }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Button("Duck") { router.go(to: .play(.duckSheet)) }
                .keyboardShortcut("d", modifiers: .command)
        }
    }
}
#endif

/// The one door a file comes in through, and the one place the phone says so.
///
/// A HAPTIC BELONGS TO AN EVENT IN THE WORLD, AND AN IMPORT IS ONE. `Haptic`'s
/// whole design is that nothing fires on a tap: a phone that buzzes when you
/// touch it is telling you what you already know. A file arriving is the
/// opposite — the person picked it in another app, or AirDropped it from a
/// laptop, and the moment it lands is the moment they are least likely to be
/// looking at this screen. `finished()` is the mapping the brief gives for
/// "something the person asked for ran to the end".
///
/// IT TAPS FOR AN ARRIVAL, NOT FOR A CALL. `LibraryModel.open` reports every
/// outcome — added, already here, refused by name, unreadable — into one string
/// and returns nothing, so a tap fired on the call itself would fire on
/// "was not added" as loudly as on a motion arriving, and a success feeling
/// that also means failure is a feeling that means nothing. What it watches
/// instead is whether the app is holding more than it was: a policy, a
/// recording, a draft or a plan. That is one comparison over four counts and it
/// cannot disagree with the sentence the screen prints.
///
/// THE ONE SUCCESS IT MISSES IS THE RIGHT ONE TO MISS. Re-importing a
/// `.duckintent` whose name the app already has replaces it — deliberately,
/// see `acceptIntent` — so the counts do not move and the phone stays quiet.
/// Silence on a real success costs a person nothing they can notice; a buzz on
/// a refusal costs the buzz its meaning.
@MainActor
enum Imports {

    /// Hand a file to the library, and tap once if anything actually arrived.
    ///
    /// A CLASS'S DECK ARRIVES WITHOUT MAKING A LIST LONGER. A `.duckcards` file replaces the deck
    /// Studio reads cards with, so it is counted by the decks the store has taken; a refused one
    /// takes nothing and stays quiet. A `.duckpack` is counted the same way, by the packs taken,
    /// since one opened again replaces itself.
    @discardableResult
    static func open(_ url: URL, model: LibraryModel,
                     drafts: DraftStore, plans: PlanStore) -> ImportLanding {
        let policies = model.library.entries.count
        let clips = model.importedClips.count
        let held = (drafts: drafts.drafts.count, plans: plans.plans.count)
        let decks = DuckCardsStore.shared.taken
        let packs = DuckPacksStore.shared.taken
        model.open(url, into: drafts, plans: plans)
        // WHAT GREW, COUNTED, so the kit can say where it lands.
        let growth = ImportLanding.Growth(
            drafts: drafts.drafts.count - held.drafts,
            plans: plans.plans.count - held.plans,
            sequences: model.importedClips.count - clips,
            packs: DuckPacksStore.shared.taken != packs ? 1 : 0,
            decks: DuckCardsStore.shared.taken != decks ? 1 : 0,
            policies: model.library.entries.count - policies)
        let landing = ImportLanding.landing(for: growth)
        if landing != .stay { Haptic.finished() }
        return landing
    }

}
