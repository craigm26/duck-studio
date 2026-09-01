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
            // A policy handed over from Files, Mail, AirDrop or another app.
            // Declared in Info.plist as an IMPORTED type — ONNX is not this
            // app's format to own.
            .onOpenURL { model.open($0, into: drafts, plans: plans) }
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
        }
    }
}
