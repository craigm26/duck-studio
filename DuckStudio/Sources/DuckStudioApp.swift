import SwiftUI
import StudioKit

/// Duck Studio: open a Microduck policy and see what is actually in it.
///
/// TWO TABS, BECAUSE THERE ARE TWO KINDS OF THING. A policy is a network with
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

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { PolicyListView(model: model) }
                    .tabItem { Label("Policies", systemImage: "cpu") }
                NavigationStack { IntentListView() }
                    .tabItem { Label("Intents", systemImage: "figure.walk.motion") }
                NavigationStack { AutomationChatView() }
                    .tabItem { Label("Rules", systemImage: "bubble.left.and.text.bubble.right") }
            }
            // A policy handed over from Files, Mail, AirDrop or another app.
            // Declared in Info.plist as an IMPORTED type — ONNX is not this
            // app's format to own.
            .onOpenURL { model.open($0) }
        }
    }
}
