import SwiftUI
import StudioKit

/// Microduck Studio: open a Microduck policy and see what is actually in it.
///
/// A TAB PER KIND OF THING. A policy is a network with
/// no time axis: hand it an observation, get fourteen numbers. An intent is a
/// motion with nothing but a time axis: what happened over four seconds when a
/// policy drove a robot in physics. One is probed, the other is watched, and
/// putting them on one screen produced a bench that offered clips having
/// nothing to do with the policy it was opened from.
///
/// The rule this app is built to: **StudioKit computes, DuckStudio displays.**
/// No arithmetic here, and no sentence about a policy written here either —
/// every one of them is built and asserted by `swift test` on Linux, because a
/// refusal message is this app's whole value proposition and one you cannot
/// test is one you find out about in review.
@main
struct DuckStudioApp: App {
    @StateObject private var model = LibraryModel()
    @StateObject private var scenes = SceneStore()
    @StateObject private var drafts = DraftStore()
    @StateObject private var plans = PlanStore()
    /// Which model writes drafts. One store, shared: the Draft tab uses it and
    /// the Models screen edits it.
    @StateObject private var models = EndpointStore()
    /// Which benches this phone knows about. One store, shared, for the same
    /// reason `models` is: three screens send work to a bench, and a bench
    /// chosen on one of them is the bench the others should use.
    @StateObject private var benches = BenchStore()

    @Environment(\.scenePhase) private var scenePhase

    /// Which tab is showing.
    ///
    /// IT EXISTS SO SCREENSHOTS CAN BE TAKEN WITHOUT A HUMAN THUMB. `TabView`
    /// with no selection cannot be told which tab to open, and the App Store
    /// wants a picture of each one. A simulator can launch an app with
    /// arguments but cannot tap a tab bar, so the launch argument is the whole
    /// mechanism: `-tab 3` opens the fourth tab and the shot is taken.
    ///
    /// It changes nothing for anybody running the app normally — no argument,
    /// first tab, exactly as before — and it is deliberately not a persisted
    /// preference, because "the tab you were last on" is a different feature
    /// with different opinions and this is not it.
    @State private var tab = Self.launchTab

    /// The tab a `-tab N` launch argument asked for, or the first.
    static var launchTab: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count,
              let n = Int(args[i + 1]), (0...4).contains(n) else { return 0 }
        return n
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
            TabView(selection: $tab) {
                NavigationStack { PolicyListView(model: model, scenes: scenes, drafts: drafts,
                                               models: models, benches: benches) }
                    .tabItem { Label("Policies", systemImage: "cpu") }
                    .tag(0)
                NavigationStack { IntentListView(models: models, benches: benches, plans: plans, store: scenes, model: model, drafts: drafts) }
                    // "MOTIONS", NOT "INTENTS", AND POLLEN OWN THE OTHER WORD.
                    // This tab holds recordings and authored moves — what a
                    // network DID, played back. In `duck-ipc-proto` an intent is
                    // the opposite: "what a client asks the robot to *do*" —
                    // robot.move, robot.head, robot.stop, robot.enable. Two
                    // vocabularies using one word for opposite ends of the same
                    // pipeline is a confusion that gets worse with every screen,
                    // and the Drive screen is now the one that really does send
                    // intents. So this tab gives the word back.
                    .tabItem { Label("Motions", systemImage: "figure.walk.motion") }
                    .tag(1)
                // A THIRD KIND OF THING, and it earned its own tab the moment
                // the stage started drawing one. A policy is a network, an
                // intent is a motion, and a scene is a PLACE — the floor, the
                // steps, the wall a motion is judged against. Folding places
                // into the motion that happened to be recorded in one is what
                // made every clip play in a void.
                NavigationStack { SceneListView(store: scenes, models: models, benches: benches) }
                    .tabItem { Label("Scenes", systemImage: "square.3.layers.3d") }
                    .tag(2)
                NavigationStack {
                    AutomationChatView(drafts: drafts, scenes: scenes, models: models, benches: benches, plans: plans)
                }
                    .tabItem { Label("Draft", systemImage: "wand.and.stars") }
                    .tag(3)
                // THE FIFTH AND LAST TAB, AND THAT IS A HARD CEILING. iPhone
                // shows five before it folds the rest into "More", where a tab
                // is somewhere people do not go. Anything that arrives after
                // this has to live inside one of the five.
                //
                // It holds what used to be three separate apps. Duck Soccer,
                // Duckboard and Duck Diary each had a repository, a bundle
                // identifier and pre-registered gates, and two of them have no
                // code in them at all — a new Microduck owner should not need
                // four apps to use one robot.
                NavigationStack {
                    LabView(model: model, scenes: scenes, drafts: drafts, models: models, benches: benches)
                }
                    .tabItem { Label("Lab", systemImage: "flask") }
                    .tag(4)
            }
            // LARGE TITLES ARE THE DEFAULT AND THE ROOT DOES NOT IMPOSE THEM.
            // A `NavigationStack` root already gets a large title, so four of
            // the five tabs are large without a word being said — and the
            // fifth, the Draft tab, sets `.inline` on purpose, because a chat
            // transcript with a compose bar under it has nowhere to put a 34pt
            // title. `navigationBarTitleDisplayMode` applied out here would
            // reach past that decision and overrule it from a file that cannot
            // see it, which is exactly the kind of remote override this app's
            // own theme comment argues against. Each screen says it for itself;
            // `IntentListView` now does, out loud.
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
