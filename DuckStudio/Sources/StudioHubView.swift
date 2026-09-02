import SwiftUI
import StudioKit

/// Studio — where you make something, and where you find out what physics did
/// to it.
///
/// WHY FOUR TABS BECAME ONE SCREEN. Motions, Scenes, Draft and the Lab were
/// four of the five tabs, and they are four halves of one verb: a motion is
/// what you author, a scene is the place you author it against, drafting with
/// words is another way to write the same motion, and the bench is the only
/// machine in the arrangement with physics in it. Sorting the tab bar by which
/// store a thing lives in is sorting it by how the app is built; a person opens
/// this tab because they want to MAKE something, and then picks which kind.
///
/// AND IT IS WHERE SIM-TO-REAL BECOMES POSSIBLE RATHER THAN A WORD. This app
/// can inspect a policy and author a motion and run neither, because an iPhone
/// has no physics. The bench has physics. Once the bench is a place rather than
/// a setting, the loop closes: author a motion, run it against a real solver on
/// a machine on your desk, see what physics did to it, and — when hardware
/// exists — send the same thing to a robot.
///
/// THE ROW THAT CANNOT BE OPENED IS DISABLED AND SAYS WHY. This is the house
/// rule everywhere else in the app and it matters most in Modes, which is the
/// surface where overclaiming would be easiest: a ghost on your carpet and a
/// duck chasing a ball both LOOK like capability and neither is a robot doing
/// anything. `LabCatalogue` holds the sentences so `swift test` can read them,
/// which is also why nothing on this screen composes one.
///
/// EVERY MODE IS A CARD, AND THE CARDS ARE CONCENTRIC. A mode is a name, a
/// claim about how real it is and — often — a reason it cannot be opened, which
/// is three lines of prose per row; drawn as system rows they ran together into
/// a wall of grey text where nothing said where one mode stopped. The card is
/// `Palette.Radius.card` and the symbol tile inside it is `.card.inner`, taken
/// from the outer radius rather than chosen again, so the corner of the tile is
/// one step down from the corner of the card it sits in. Author and Measure are
/// plain rows on purpose: they are names of places, not claims about reality,
/// and a card around a name would say there was something to weigh up.
struct StudioHubView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var scenes: SceneStore
    @ObservedObject var drafts: DraftStore
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore
    @ObservedObject var plans: PlanStore

    /// ROOM CAPTURE IS THE ONE ROW HERE THAT NEEDS A CAMERA TO EXIST AT ALL,
    /// so this screen reads the door too. The ghost duck and soccer are not in
    /// this list on purpose: both open on a rendered venue and offer the camera
    /// only behind a picker, which disables itself with its own reason.
    @State private var door = CameraDoor.availability

    /// WHERE THE SECOND HOP LANDS. Behaviours → Retrain means Studio → Draft,
    /// and a router that could only select a tab left somebody on this root
    /// looking at four rows with nothing saying which of them they had asked
    /// for. See `AppRouter.pendingStudio`.
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        List {
            Section {
                NavigationLink {
                    place(.motions)
                } label: {
                    Label("Motions", systemImage: "figure.walk.motion")
                }
                // A THIRD KIND OF THING, and it earned its own row the moment
                // the stage started drawing one. A policy is a network, a
                // motion is what one did, and a scene is a PLACE — the floor,
                // the steps, the wall a motion is judged against. Folding
                // places into the motion that happened to be recorded in one is
                // what made every clip play in a void.
                NavigationLink {
                    place(.scenes)
                } label: {
                    Label("Scenes", systemImage: "square.3.layers.3d")
                }
                // NOT `wand.and.stars`, WHICH IS NOW THE TAB'S OWN SYMBOL. A
                // row wearing the same glyph as the tab it sits in reads as the
                // way back out rather than as a way further in.
                NavigationLink {
                    place(.draft)
                } label: {
                    Label("Draft with words", systemImage: "text.bubble")
                }
            } header: {
                SectionHeading(text: "Author")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                // THE SAME SCREEN THE "bench" MODE USED TO OPEN, which is why
                // that mode is skipped below rather than drawn twice. It is up
                // here because measuring is not a mode you play with: it is the
                // one thing on this tab that runs a real solver, and burying it
                // among the ghost duck and the soccer stage put the only honest
                // physics in the app behind the two screens that look most like
                // capability and are not.
                NavigationLink {
                    place(.measure)
                } label: {
                    Label("Run on your network", systemImage: "wifi")
                }
                // THE ONLY ROW IN THE APP THAT TRIES TO MAKE A NETWORK BETTER,
                // and it is under Measure rather than under Author because
                // what it actually does is measure — twenty-eight numbers, a
                // few hundred times, against a reward read out of Pollen's own
                // training config. Nothing is authored and nothing is trained.
                //
                // NOT A `StudioDestination`. The four cases there are the
                // places another tab can send somebody to by name, and nothing
                // routes here: this is a door off Measure and not a fifth room
                // with an address. Adding a case for a screen no router names
                // would be widening a type to describe a wish.
                NavigationLink {
                    TuneView(library: model, benches: benches)
                } label: {
                    Label("Tune it on this phone", systemImage: "slider.horizontal.3")
                }
            } header: {
                SectionHeading(text: "Measure")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                // THE BENCH MODE IS SKIPPED HERE BECAUSE MEASURE HOLDS IT. Its
                // row and the Measure row open the same `RemoteRunView`, and
                // two doors into one room, on one screen, is how a person ends
                // up wondering which of them is the real one. The catalogue is
                // NOT filtered in the kit: `LabCatalogueTests` pins
                // `LabCatalogue.usable` to exactly ["bench", "ghost", "soccer",
                // "room", "sounds"] against `destination(_:)` below, which
                // still answers all five — so the mapping stays provable and
                // only the drawing skips one.
                ForEach(LabCatalogue.modes.filter { $0.id != "bench" }) { mode in
                    row(mode)
                }
            } header: {
                SectionHeading(text: "Modes")
            } footer: {
                // THE HONESTY SENTENCE IS SET IN A TOKEN AND COMES FROM THE
                // KIT. It is the sentence that says nothing here is talking to
                // a robot, which makes it the most load-bearing text on the
                // tab; `.secondary` resolved it against whatever UIKit felt was
                // behind it, while `Theme.textSecondary` is a value
                // `PaletteTests` proves at 4.5:1 on every ground this app sets
                // words on.
                //
                // `modesPreamble` RATHER THAN `preamble`, because the sentence
                // used to name "the Lab" and there is no Lab any more. A screen
                // naming the wrong container is a screen making a claim it
                // cannot support.
                // BOTH SENTENCES, because `rationale` — why three apps became
                // these rows — is product copy a test guards, and the screen
                // that folded here was the only one that drew it.
                VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                    Text(LabCatalogue.modesPreamble)
                    Text(LabCatalogue.rationale)
                }
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        // THE SECOND HOP, AND IT NEEDS NO PATH CONVERSION. The four rows above
        // are still closure `NavigationLink`s — they push a view they name
        // directly, which is what a row a finger is on should do — and this
        // modifier pushes the SAME view when another tab asks for it by name.
        // `navigationDestination(item:)` is the one API that takes a two-way
        // binding, so SwiftUI writes `pendingStudio` back to nil when the
        // person taps Back; a `NavigationPath` here would have meant converting
        // all four rows to `NavigationLink(value:)` and then owning the path's
        // lifetime, to buy nothing this screen needs.
        //
        // ONE DEFINITION OF WHAT A DESTINATION OPENS. Both the row and the
        // route go through `place(_:)`, so Behaviours → Retrain cannot land on
        // a different Draft screen from the one the Draft row opens.
        .navigationDestination(item: $router.pendingStudio) { place($0) }
        .navigationTitle("Studio")
        .navigationBarTitleDisplayMode(.large)
        // ONE GEAR, SAME PLACE, SAME WORD, ONCE PER TAB ROOT. It used to sit on
        // this screen AND on Motions, Scenes and Draft — which are now one tap
        // inside it, so a person met two gears in a row and had to guess
        // whether they led to the same place. They did.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView(models: models, benches: benches) } label: {
                    Image(systemName: "gear").accessibilityLabel(Text("Settings"))
                }
            }
        }
    }

    /// The screen behind one of the four places another tab may name.
    ///
    /// IT IS THE ROWS' DESTINATION TOO, WHICH IS THE POINT. A route that built
    /// its own copy of `AutomationChatView` would be a second wiring of the six
    /// stores, and the failure mode of a second wiring is not a crash: it is a
    /// Draft screen with a different `EndpointStore` behind it, drafting against
    /// a model the rest of the app has not got. `DriveView`'s own comment about
    /// `models:` is the same bug, already paid for once.
    @ViewBuilder private func place(_ destination: StudioDestination) -> some View {
        switch destination {
        case .motions:
            IntentListView(models: models, benches: benches, plans: plans,
                           store: scenes, model: model, drafts: drafts)
        case .scenes:
            SceneListView(store: scenes, models: models, benches: benches)
        case .draft:
            AutomationChatView(drafts: drafts, scenes: scenes, models: models,
                               benches: benches, plans: plans)
        case .measure:
            RemoteRunView(model: model, scenes: scenes, drafts: drafts,
                          models: models, benches: benches)
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
        .overlay(shell.strokeBorder(Theme.separator, lineWidth: StudioHubMetric.hairlineStroke))
    }

    /// The card, and the tile inside it at the next radius down. Written as
    /// `StudioHubMetric.card.inner` rather than as a second constant so that
    /// changing the outer radius moves the inner one with it.
    private var shell: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(StudioHubMetric.card), style: .continuous)
    }

    private var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(StudioHubMetric.card.inner), style: .continuous)
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
    ///
    /// "bench" IS ANSWERED HERE AND NOT DRAWN ABOVE. The Modes list skips it
    /// because Measure already opens this screen; the case stays so the switch
    /// still answers every id the pinned `usable` list holds, and so the test
    /// keeps meaning what it says.
    @ViewBuilder private func destination(_ mode: LabCatalogue.Mode) -> some View {
        switch mode.id {
        case "bench":
            RemoteRunView(model: model, scenes: scenes, drafts: drafts, models: models, benches: benches)
        case "ghost":
            // The games hub. Golf, fetch, follow me, the bow bridge, the trick
            // run, the slalom and the flamingo hold are all reached from inside
            // it, which is how they were arranged in OpenCastor and is right:
            // every one of them is the same ghost duck doing something else, so
            // seven rows here would be seven doors into one room.
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
private enum StudioHubMetric {
    /// A mode card. Its symbol tile takes `card.inner`, which is how the
    /// concentric rule is expressed rather than asserted.
    static let card = Palette.Radius.card

    /// A hairline STROKE. One point, which on every device this ships to is one
    /// to three pixels. Named for the stroke because `Palette.Spacing` already
    /// has a `hairline` and it is four points.
    static let hairlineStroke = DesignMetric.hairlineStroke
}
