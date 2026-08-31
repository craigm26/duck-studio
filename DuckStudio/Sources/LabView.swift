import SwiftUI
import DuckKit
import StudioKit

/// The Lab — where a policy meets a world, and where the other duck apps land.
///
/// WHY THIS TAB EXISTS. Duck Soccer, Duckboard and Duck Diary were three
/// separate apps on paper: each with its own repository, bundle identifier,
/// pre-registered gates and plan, and each needing a shell, an icon, a privacy
/// label and a review cycle before it could show anybody a duck. Two of those
/// repositories contain no code at all. A new Microduck owner should not have
/// to find four apps to use one robot, so they are screens here instead.
///
/// AND IT IS WHERE SIM-TO-REAL BECOMES POSSIBLE RATHER THAN A WORD. Duck
/// Studio can inspect a policy and author a motion and run neither, because an
/// iPhone has no physics. The bench has physics. Once the bench is a place
/// rather than a setting, the loop closes: author a motion, run it against a
/// real solver on a machine on your desk, see what physics did to it, and — when
/// hardware exists — send the same thing to a robot.
///
/// THE ROW THAT CANNOT BE OPENED IS DISABLED AND SAYS WHY. This is the house
/// rule everywhere else in the app and it matters most here, because the Lab is
/// the surface where overclaiming would be easiest: a ghost on your carpet and a
/// duck chasing a ball both LOOK like capability and neither is a robot doing
/// anything. `LabCatalogue` holds the sentences so `swift test` can read them.
struct LabView: View {
    @ObservedObject var scenes: SceneStore
    @ObservedObject var drafts: DraftStore
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore
    /// ROOM CAPTURE IS THE ONE ROW HERE THAT NEEDS A CAMERA TO EXIST AT ALL,
    /// so the Lab reads the door too. The ghost duck and soccer are not in this
    /// list on purpose: both open on a rendered venue and offer the camera only
    /// behind a picker, which disables itself with its own reason.
    @State private var door = CameraDoor.availability

    var body: some View {
        List {
            Section {
                Text(LabCatalogue.preamble)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text(LabCatalogue.rationale)
            }

            Section {
                ForEach(LabCatalogue.modes) { mode in
                    row(mode)
                }
            } header: {
                Text("Modes")
            } footer: {
                // AMENDED WHEN THE CAMERA DOOR WENT IN, BECAUSE IT HAD BECOME
                // FALSE. Room capture is written and reachable, and it still
                // greys out on a build with no camera usage description, on a
                // device that cannot world-track, or when the person has said
                // no — none of which is "nothing is behind it yet". Ideally
                // this sentence lives in `LabCatalogue` beside the others; it
                // is left here only because it was already here.
                Text("A mode is greyed out because nothing is behind it here yet, or because something it needs cannot be opened — this build, this phone, or a permission you have turned off. Never because it is locked. Which one it is is written under its name.")
            }
        }
        .refreshingCameraDoor($door)
        .navigationTitle("Lab")
        // ONE GEAR, SAME PLACE, SAME WORD, ON ALL FIVE TAB ROOTS.
        // Configuration was scattered across three tabs and nothing was called
        // "Settings", which is the first word anybody looks for.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView(models: models, benches: benches) } label: {
                    Image(systemName: "gear").accessibilityLabel(Text("Settings"))
                }
            }
        }
    }

    /// Why a row that IS built still cannot be opened right now.
    ///
    /// THIS IS A DIFFERENT KIND OF REASON FROM `LabCatalogue.Status.reason` AND
    /// THE TWO MUST NOT MERGE. Every status reason means "nobody has written
    /// this"; this one means "it is written, and this build or this phone will
    /// not let you in". Both are drawn in the same place because a person only
    /// wants to know why the row is grey — but a status reason always wins,
    /// because a mode nobody has written cannot be blocked by a camera.
    private func cameraRefusal(for mode: LabCatalogue.Mode) -> String? {
        guard mode.id == "room" else { return nil }
        return door.refusal(for: .roomCapture)
    }

    /// One mode. Live rows navigate; the rest are inert AND look inert, with
    /// the reason under the name rather than in a dialog after the tap.
    @ViewBuilder private func row(_ mode: LabCatalogue.Mode) -> some View {
        let blocked = cameraRefusal(for: mode)
        if mode.status == .here, blocked == nil {
            NavigationLink {
                destination(mode)
            } label: {
                label(mode, reason: nil)
            }
        } else {
            label(mode, reason: mode.status.reason ?? blocked)
                .foregroundStyle(.secondary)
                // Combined so a screen reader gets the name, what it does and
                // why it cannot be opened as one thing, rather than three
                // fragments it has to reassemble.
                .accessibilityElement(children: .combine)
        }
    }

    /// `reason` is nil exactly for a row that can be opened. It is passed in
    /// rather than read off `mode.status` here because a built row can also be
    /// shut by the camera, and the label must not have to know which of the two
    /// happened to draw the sentence.
    private func label(_ mode: LabCatalogue.Mode, reason: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: mode.symbol)
                .font(.title3)
                .frame(width: 28)
                // BOTH BRANCHES ARE A `Color`. `.tertiary` here would be a
                // HierarchicalShapeStyle, which is a different type from
                // `Color.accentColor`, and a ternary needs one type — the kind
                // of mistake `swiftc -parse` waves through on this box because
                // it is a type error, not a syntax one.
                .foregroundStyle(reason == nil ? Color.accentColor : Color.secondary)
                // The name is right there; the symbol is decoration.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(mode.name).font(.subheadline.weight(.semibold))
                Text(mode.blurb)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// WHERE A LIVE MODE GOES.
    ///
    /// THE COMPILER DOES NOT CATCH A MISSING SCREEN, AND SAYING IT DID WOULD BE
    /// THE KIND OF CLAIM THIS APP IS ABOUT. `mode.id` is a `String`, so this
    /// switch has a `default` and is exhaustive by construction — adding a
    /// `.here` mode to the catalogue with no case here compiles fine and pushes
    /// the refusal below. What actually holds the line is a test:
    /// `LabCatalogueTests.testTheLabHasSomethingAPersonCanOpen` pins `usable`
    /// to exactly the ids this switch answers, so the mismatch turns up in
    /// `swift test` rather than on somebody's phone.
    @ViewBuilder private func destination(_ mode: LabCatalogue.Mode) -> some View {
        switch mode.id {
        case "bench":
            RemoteRunView(scenes: scenes, drafts: drafts, models: models, benches: benches)
        case "ghost":
            // The games hub. Golf, fetch, follow me, the bow bridge, the trick
            // run, the slalom and the flamingo hold are all reached from inside
            // it, which is how they were arranged in OpenCastor and is right:
            // every one of them is the same ghost duck doing something else, so
            // seven rows in the Lab would be seven doors into one room.
            GhostDuckView()
        case "soccer":
            DuckSoccerView()
        case "sounds":
            DuckSoundsView()
        case "room":
            RoomCaptureView()
        default:
            // Unreachable while `usable` is pinned by test to exactly the rows
            // this switch answers. It is a refusal rather than an EmptyView
            // because an empty push is the toolbar-less blank screen this app
            // has been bitten by before.
            ContentUnavailableView("That mode has no screen yet",
                                   systemImage: "questionmark.square.dashed",
                                   description: Text("\(mode.name) is listed as usable but nothing is wired to it. That is a bug in this build, not something you did."))
        }
    }
}
