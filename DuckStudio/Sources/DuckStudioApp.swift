import SwiftUI
import StudioKit

/// The five tabs, in the order a person meets them.
///
/// A TAB PER QUESTION SOMEBODY IS ASKING, NOT PER KIND OF FILE. The old shell
/// was sorted by data type — policies, motions, scenes, drafts, lab — which is
/// how the app is built rather than how it is used, and it made the first
/// screen a list of ONNX files belonging to a robot the person had not yet been
/// shown. These five are the questions instead: which duck is mine, can I move
/// it, what can it do, what can I make, and what is it made of. A file type is
/// something you find once you are inside one of those.
///
/// THE ORDER IS THE TAG ORDER AND THE TAG ORDER IS LOAD-BEARING. `-tab 3` has
/// to keep meaning the fourth tab for the screenshot runs, so `allCases` is the
/// index space `launchTab` counts in — see `DuckStudioApp.launchTab`, which
/// also accepts the raw value so a run can say `-tab studio` and not have to
/// know what number Studio is this week.
enum AppTab: String, CaseIterable, Identifiable {
    case duck, control, behaviours, studio, robot

    var id: String { rawValue }

    /// What the tab bar says. "My Microduck" rather than "Duck": the first tab
    /// is about the one robot this phone is paired to, and the possessive is
    /// the difference between that and a catalogue of ducks.
    var title: String {
        switch self {
        case .duck: return "My Microduck"
        case .control: return "Control"
        case .behaviours: return "Behaviours"
        case .studio: return "Studio"
        case .robot: return "Robot"
        }
    }

    /// The SF Symbol beside the word. Every one of these is a system symbol, so
    /// it scales with Dynamic Type and carries the tint without an asset.
    var symbol: String {
        switch self {
        case .duck: return "bird"
        case .control: return "gamecontroller"
        case .behaviours: return "brain.head.profile"
        case .studio: return "wand.and.stars"
        case .robot: return "wrench.and.screwdriver"
        }
    }
}

/// The four places inside Studio another tab is allowed to name.
///
/// A ROUTE IS A PLACE, NOT A SCREEN. These are the four rows on the Studio root
/// — Motions, Scenes, Draft with words, and Run on your network — and they are
/// spelled as cases rather than as view builders so that the sender does not
/// have to know which view a row opens, or hold the six stores that view wants.
/// `StudioHubView` already holds all six; it is the only place that should be
/// naming `AutomationChatView`.
///
/// FOUR AND NOT EVERY SCREEN IN THE APP, deliberately. A destination that no
/// other tab has ever asked to reach is a destination nobody can prove works,
/// and this enum is the list of the ones that are actually sent to. It grows
/// when a caller appears, not before.
enum StudioDestination: String, Identifiable, Hashable, CaseIterable {
    case motions, scenes, draft, measure

    var id: String { rawValue }
}

/// Which tab is showing, and the one way to change it from inside a screen.
///
/// A SCREEN THAT SENDS SOMEBODY SOMEWHERE MUST BE ABLE TO ACTUALLY SEND THEM.
/// The seven questions the first tab answers end in an action — "drive it" is
/// the Control tab, "install one" is Behaviours — and before this existed the
/// only honest thing a card could do was name the tab and hope. A sentence that
/// tells a person to go and tap a tab is a sentence the app could have obeyed
/// itself.
///
/// AND A TAB IS NOT ALWAYS THE WHOLE ROUTE. Behaviours → Retrain means "write a
/// training request", which is Studio → Draft: two hops, of which the router
/// could only make the first. Landing somebody on the Studio root with four
/// rows in front of them and no mark on the one they asked for is the same
/// failure as naming a tab and hoping, moved one screen further in. `pendingStudio`
/// is the second hop, held until the tab that owns it can take it.
///
/// IT IS STILL A ROUTER AND NOT A NAVIGATION MODEL. It holds which of the five
/// is in front and, optionally, ONE place inside Studio that has just been
/// asked for. Each tab keeps its own `NavigationStack` and its own path, because
/// a tab that rewinds to its root every time another tab nudged it is a tab that
/// loses what somebody was in the middle of — which is why this is a one-shot
/// request rather than a stored location. `StudioHubView` binds it straight to
/// `navigationDestination(item:)`, so SwiftUI clears it back to nil the moment
/// the person taps Back, and the tab is then free to be left where they left it.
@MainActor final class AppRouter: ObservableObject {
    @Published var tab: AppTab

    /// The place inside Studio somebody has just asked for, or nil.
    ///
    /// PUBLISHED AND WRITEABLE BECAUSE SwiftUI POPS IT. `navigationDestination(
    /// item:)` takes a two-way binding: it pushes when this becomes non-nil and
    /// writes nil back when the screen is dismissed. A one-way "consume it on
    /// appear" version would have to guess when the person had left, and would
    /// re-push the same screen the next time the Studio tab was selected.
    @Published var pendingStudio: StudioDestination?

    init(tab: AppTab = .duck) {
        self.tab = tab
    }

    /// Show a tab.
    func go(to tab: AppTab) {
        go(to: tab, then: nil)
    }

    /// Show a tab, and — when the tab is Studio — the place inside it.
    ///
    /// `then` IS SET BEFORE THE TAB CHANGES so that the hub's
    /// `navigationDestination` already has its item when the tab's view tree
    /// comes forward: setting it afterwards makes the push a second animation a
    /// person watches happen to them.
    ///
    /// A DESTINATION WITH A TAB THAT IS NOT STUDIO IS DROPPED RATHER THAN
    /// REMEMBERED. Studio is the only tab that reads this, and a pending
    /// destination left set while somebody is on Control would fire the next
    /// time they touched the Studio tab — a push nobody asked for, arriving
    /// minutes late.
    func go(to tab: AppTab, then destination: StudioDestination?) {
        pendingStudio = tab == .studio ? destination : nil
        self.tab = tab
    }
}

/// Microduck Studio: one robot, and everything you can ask of it.
///
/// FIVE TABS, AND THE FIRST ONE IS THE ROBOT. My Microduck answers seven
/// questions in order and above the fold — which duck, is it online, how much
/// battery, what is it doing, can I safely control it, what can I launch, is
/// anything wrong — and the other four are what you do once you have an answer:
/// Control moves it, Behaviours is what it knows, Studio is what you make, and
/// Robot is what it is made of. Settings is a gear, once per tab root, which is
/// the first word anybody looks for and now the only word.
///
/// The rule this app is built to: **StudioKit computes, DuckStudio displays.**
/// No arithmetic here, and no sentence about a policy written here either —
/// every one of them is built and asserted by `swift test` on Linux, because a
/// refusal message is this app's whole value proposition and one you cannot
/// test is one you find out about in review. The same rule is why a blocked
/// surface ships as an explicit "not yet" in a tested kit string rather than as
/// an empty card or a control that is present and inert.
@main
struct DuckStudioApp: App {
    @StateObject private var model = LibraryModel()
    @StateObject private var scenes = SceneStore()
    @StateObject private var drafts = DraftStore()
    @StateObject private var plans = PlanStore()
    /// Which model writes drafts. One store, shared: Studio's Draft screen uses
    /// it and the Models screen edits it.
    @StateObject private var models = EndpointStore()
    /// Which benches this phone knows about. One store, shared, for the same
    /// reason `models` is: three screens send work to a bench, and a bench
    /// chosen on one of them is the bench the others should use.
    @StateObject private var benches = BenchStore()

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
    @StateObject private var router = AppRouter(tab: DuckStudioApp.launchTab)

    @Environment(\.scenePhase) private var scenePhase

    /// The tab a `-tab` launch argument asked for, or the first.
    ///
    /// TWO SPELLINGS, ONE MEANING. `-tab 3` is the index into `AppTab.allCases`
    /// and is kept because the screenshot runs already say it that way; `-tab
    /// studio` is the raw value and is the spelling that survives the tabs
    /// being reordered. Anything else — a sixth index, a word that is not a
    /// case — opens the first tab rather than failing, because a screenshot run
    /// that silently shoots the wrong tab is a worse outcome than one that
    /// shoots the first.
    static var launchTab: AppTab {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return .duck }
        let asked = args[i + 1]
        if let n = Int(asked) {
            guard AppTab.allCases.indices.contains(n) else { return .duck }
            return AppTab.allCases[n]
        }
        return AppTab(rawValue: asked) ?? .duck
    }

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
                // 1. WHICH DUCK, AND IS IT ALRIGHT. Everything about the one
                // robot this phone is paired to, in the order somebody asks:
                // name, lens, battery, what it is doing, whether it can be
                // driven, what can be launched, and — above all of it or not at
                // all — whether anything is wrong.
                NavigationStack {
                    MyMicroduckView(model: model, scenes: scenes, drafts: drafts,
                                    models: models, benches: benches)
                }
                    .tabItem { Label(AppTab.duck.title, systemImage: AppTab.duck.symbol) }
                    .tag(AppTab.duck)

                // 2. THE ONE SCREEN THAT MOVES A ROBOT. It was reached through
                // a menu on a list of files, which is three taps from launch
                // for the thing somebody holding a Microduck opens the app to
                // do. `duck-ipc-proto` calls what this sends an intent — the
                // opposite of what this app's Motions once called one, which is
                // why the word went back to Pollen and the motions kept theirs.
                NavigationStack {
                    // `models:` IS PASSED, so the Control gear opens the SAME
                    // Settings the other four roots open. Without it DriveView
                    // falls back to a second EndpointStore whose flush
                    // overwrites the shared one — two Settings screens
                    // disagreeing about one list.
                    DriveView(model: model, benches: benches, scenes: scenes, models: models)
                }
                    .tabItem { Label(AppTab.control.title, systemImage: AppTab.control.symbol) }
                    .tag(AppTab.control)

                // 3. WHAT THE ROBOT KNOWS HOW TO DO. Installed policies,
                // Pollen's catalogue, what the community has published, and the
                // probe that opens one up and shows the fourteen numbers it
                // answers with.
                NavigationStack {
                    PolicyListView(model: model, scenes: scenes, drafts: drafts,
                                   models: models, benches: benches)
                }
                    .tabItem { Label(AppTab.behaviours.title, systemImage: AppTab.behaviours.symbol) }
                    .tag(AppTab.behaviours)

                // 4. WHAT YOU MAKE. Motions, scenes, drafting with words, the
                // bench you measure on, and the modes that used to be their own
                // apps. Four tabs became one because they are all the same
                // verb: authoring something and seeing what physics does to it.
                NavigationStack {
                    StudioHubView(model: model, scenes: scenes, drafts: drafts,
                                  models: models, benches: benches, plans: plans)
                }
                    .tabItem { Label(AppTab.studio.title, systemImage: AppTab.studio.symbol) }
                    .tag(AppTab.studio)

                // 5. THE FIFTH AND LAST TAB, AND THAT IS A HARD CEILING. iPhone
                // shows five before it folds the rest into "More", where a tab
                // is somewhere people do not go. Anything that arrives after
                // this has to live inside one of the five.
                //
                // Hardware, motors, firmware, network and diagnostics: the
                // things you look at when the answer on the first tab was "no".
                NavigationStack {
                    RobotView(benches: benches, models: models)
                }
                    .tabItem { Label(AppTab.robot.title, systemImage: AppTab.robot.symbol) }
                    .tag(AppTab.robot)
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
            .onOpenURL { Imports.open($0, model: model, drafts: drafts, plans: plans) }
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
        }
    }
}

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
    static func open(_ url: URL, model: LibraryModel,
                     drafts: DraftStore, plans: PlanStore) {
        let before = holdings(model: model, drafts: drafts, plans: plans)
        model.open(url, into: drafts, plans: plans)
        if holdings(model: model, drafts: drafts, plans: plans) != before {
            Haptic.finished()
        }
    }

    /// How many things this app is holding that an import can add to.
    ///
    /// Read straight after the call rather than observed, because the stores
    /// publish synchronously: by the time `open` returns, the arrays are the
    /// new ones.
    private static func holdings(model: LibraryModel,
                                 drafts: DraftStore, plans: PlanStore) -> Int {
        model.library.entries.count
            + model.importedClips.count
            + drafts.drafts.count
            + plans.plans.count
    }
}
