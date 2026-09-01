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
///
/// EVERY MODE IS A CARD, AND THE CARDS ARE CONCENTRIC. A mode is a name, a
/// claim about how real it is and — often — a reason it cannot be opened, which
/// is three lines of prose per row; drawn as system rows they ran together into
/// a wall of grey text where nothing said where one mode stopped. The card is
/// `Palette.Radius.card` and the symbol tile inside it is `.card.inner`, taken
/// from the outer radius rather than chosen again, so the corner of the tile is
/// one step down from the corner of the card it sits in.
struct LabView: View {
    @ObservedObject var model: LibraryModel
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
                // THE HONESTY PREAMBLE IS THE FIRST THING ON THE SCREEN AND IT
                // IS SET IN A TOKEN. It is the sentence that says nothing here
                // is talking to a robot, which makes it the most load-bearing
                // text in the tab; `.secondary` resolved it against whatever
                // UIKit felt was behind it, while `Theme.textSecondary` is a
                // value `PaletteTests` proves at 4.5:1 on every ground this app
                // sets words on.
                Text(LabCatalogue.preamble)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } footer: {
                Text(LabCatalogue.rationale)
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

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
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S
        // GREY, and every card on it keeps a real `surfacePrimary` under its
        // words — which is the arrangement `Theme.backgroundSecondary`
        // documents as the only correct one, since the inks fall short of
        // 4.5:1 against that ground and clear it on a card.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
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
    ///
    /// THE CARD DRAWS ITSELF, so the row hands it the whole width and gets out
    /// of the way — the same move `DriveView` makes for its pad deck, and for
    /// the same reason: a system row background between the card and the ground
    /// would put a third corner radius nobody chose in the middle of two that
    /// were picked to be a step apart.
    @ViewBuilder private func row(_ mode: LabCatalogue.Mode) -> some View {
        let blocked = cameraRefusal(for: mode)
        Group {
            if mode.status == .here, blocked == nil {
                NavigationLink {
                    destination(mode)
                } label: {
                    card(mode, reason: nil)
                }
            } else {
                card(mode, reason: mode.status.reason ?? blocked)
                    // Combined so a screen reader gets the name, what it does and
                    // why it cannot be opened as one thing, rather than three
                    // fragments it has to reassemble.
                    .accessibilityElement(children: .combine)
            }
        }
        .listRowInsets(EdgeInsets(top: Theme.spacing(.hairline),
                                  leading: Theme.spacing(.snug),
                                  bottom: Theme.spacing(.hairline),
                                  trailing: Theme.spacing(.snug)))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// `reason` is nil exactly for a row that can be opened. It is passed in
    /// rather than read off `mode.status` here because a built row can also be
    /// shut by the camera, and the card must not have to know which of the two
    /// happened to draw the sentence.
    ///
    /// A BLOCKED CARD LOSES THE ACTION COLOUR RATHER THAN BEING FADED OUT — the
    /// argument `PrimaryActionStyle` makes about its own disabled state. Half
    /// opacity over three lines of explanation takes the explanation to roughly
    /// 2:1, and the explanation is the entire reason the row is still drawn.
    private func card(_ mode: LabCatalogue.Mode, reason: String?) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing(.snug)) {
            Image(systemName: mode.symbol)
                .font(.title3)
                // AN INK, NOT THE BRAND FILL. The glyph is a WORD-sized mark
                // set on a surface rather than a shape filled with the action
                // colour, and Duck Orange is 2.30:1 on cream — `actionSecondary`
                // is the orange that sets marks and clears 4.5:1 in both schemes.
                .foregroundStyle(reason == nil ? Theme.actionSecondary : Theme.textTertiary)
                .frame(width: Theme.spacing(.loose), height: Theme.spacing(.loose))
                .padding(Theme.spacing(.tight))
                .background(Theme.surfaceInteractive, in: tile)
                // The name is right there; the symbol is decoration.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(mode.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(reason == nil ? Theme.textPrimary : Theme.textSecondary)
                Text(mode.blurb)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    // NO FIXED WIDTH ANYWHERE ON THIS CARD. Every string here
                    // is a whole sentence from `LabCatalogue`, and a sentence
                    // in a fixed frame at AX5 is a column of single words.
                    .fixedSize(horizontal: false, vertical: true)
                if let reason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.spacing(.snug))
        .background(Theme.surfacePrimary, in: shell)
        .overlay(shell.strokeBorder(Theme.separator, lineWidth: LabMetric.hairlineStroke))
    }

    /// The card, and the tile inside it at the next radius down. Written as
    /// `LabMetric.card.inner` rather than as a second constant so that changing
    /// the outer radius moves the inner one with it.
    private var shell: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(LabMetric.card), style: .continuous)
    }

    private var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(LabMetric.card.inner), style: .continuous)
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
            RemoteRunView(model: model, scenes: scenes, drafts: drafts, models: models, benches: benches)
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

/// The two numbers this screen writes down for itself.
///
/// NEITHER IS A COLOUR OR A CONTRAST, which is the line `Theme` draws and this
/// file stays behind: a ratio is a fact and lives in `Palette` where a test runs
/// the formula over it. Which radius on the scale a mode card takes is a
/// judgement about a list.
private enum LabMetric {
    /// A mode card. Its symbol tile takes `card.inner`, which is how the
    /// concentric rule is expressed rather than asserted.
    static let card = Palette.Radius.card

    /// A hairline STROKE. One point, which on every device this ships to is one
    /// to three pixels. Named for the stroke because `Palette.Spacing` already
    /// has a `hairline` and it is four points.
    static let hairlineStroke = DesignMetric.hairlineStroke
}
