import SwiftUI
import StudioKit

/// Duck Studio: open a Microduck policy and see what is actually in it.
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
            NavigationStack {
                PolicyListView(model: model)
            }
            // A policy handed over from Files, Mail, AirDrop or another app.
            // Declared in Info.plist as an IMPORTED type — ONNX is not this
            // app's format to own.
            .onOpenURL { model.open($0) }
        }
    }
}
