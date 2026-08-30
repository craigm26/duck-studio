import SwiftUI
import StudioKit

/// Duck Studio: open a Microduck policy and see what is actually in it.
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
    /// Which model writes drafts. One store, shared: the Draft tab uses it and
    /// the Models screen edits it.
    @StateObject private var models = EndpointStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { PolicyListView(model: model, scenes: scenes, drafts: drafts,
                                               models: models) }
                    .tabItem { Label("Policies", systemImage: "cpu") }
                NavigationStack { IntentListView(models: models, store: scenes, model: model, drafts: drafts) }
                    .tabItem { Label("Intents", systemImage: "figure.walk.motion") }
                // A THIRD KIND OF THING, and it earned its own tab the moment
                // the stage started drawing one. A policy is a network, an
                // intent is a motion, and a scene is a PLACE — the floor, the
                // steps, the wall a motion is judged against. Folding places
                // into the motion that happened to be recorded in one is what
                // made every clip play in a void.
                NavigationStack { SceneListView(store: scenes) }
                    .tabItem { Label("Scenes", systemImage: "square.3.layers.3d") }
                NavigationStack {
                    AutomationChatView(drafts: drafts, scenes: scenes, models: models)
                }
                    .tabItem { Label("Draft", systemImage: "wand.and.stars") }
            }
            // A policy handed over from Files, Mail, AirDrop or another app.
            // Declared in Info.plist as an IMPORTED type — ONNX is not this
            // app's format to own.
            .onOpenURL { model.open($0, into: drafts) }
        }
    }
}
