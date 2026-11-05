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
    /// The evaluation logs this phone wrote and the ones it was handed. One
    /// store, shared, for the same reason `benches` is: the shelf is one shelf,
    /// and a second store would be a second answer to what is on it.
    @ObservedObject var evals: EvalStore
    /// The one evaluation runner, held as high as the shelf it files into. A
    /// runner owned by the screen that starts a run is a run that dies with
    /// that screen, which is what `DuckStudioApp` explains where it is made.
    @ObservedObject var evalRunner: EvalRunner

    /// ROOM CAPTURE IS THE ONE ROW HERE THAT NEEDS A CAMERA TO EXIST AT ALL,
    /// so this screen reads the door too. The ghost duck and soccer are not in
    /// this list on purpose: both open on a rendered venue and offer the camera
    /// only behind a picker, which disables itself with its own reason.
    @State private var door = CameraDoor.availability

    /// WHERE THE SECOND HOP LANDS. Behaviours → Retrain means Studio → Draft,
    /// and a router that could only select a tab left somebody on this root
    /// looking at a list of rows with nothing saying which of them they had
    /// asked for. See `AppRouter.pendingStudio`.
    @EnvironmentObject private var router: AppRouter

    /// How much of the app to show. Threaded by hand like every other store
    /// here — no screen in this app reads one out of the environment.
    @ObservedObject var detail: DetailStore

    /// "Show expert tools", which replaces Simple and Everything (build 91). Off for new installs;
    /// an install that had chosen Everything is on. It is the same stored level, read as a switch.
    private var expert: Binding<Bool> {
        Binding(get: { detail.level == .full },
                set: { detail.level = $0 ? .full : .simple })
    }

    var body: some View {
        // THE HUB, ONE LEVEL DOWN FROM THE CONTROLLER (docs/plans/native-first-redesign.md, Tab 3).
        // Make, Behaviours, Train, Measure, Learn, Settings. Train (but Compare) and Measure show
        // only with expert tools on. Games moved to Moves; the Learn and Behaviours tabs folded in.
        List {
            Section {
                Toggle(isOn: expert) {
                    HubRow(StudioHubWords.expertTools, StudioHubWords.expertToolsLine, "hammer")
                }
                .tint(Theme.actionPrimary)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                NavigationLink {
                    place(.motions)
                } label: {
                    HubRow("Motions", StudioHubWords.motions, "figure.walk.motion")
                }
                NavigationLink {
                    PlanEditorView(desk: nil, venue: .sim, engage: {}, models: models)
                } label: {
                    HubRow(PlanEditorWords.studioRow, StudioHubWords.plan, PlanEditorWords.studioRowSymbol)
                }
                NavigationLink {
                    place(.draft)
                } label: {
                    HubRow("Draft with words", StudioHubWords.draft, "text.bubble")
                }
                NavigationLink {
                    place(.scenes)
                } label: {
                    HubRow("Scenes", StudioHubWords.scenes, "square.3.layers.3d")
                }
                NavigationLink {
                    DuckSoundsView()
                } label: {
                    HubRow("Duck sounds", "Hear and edit the duck's sounds.", "waveform")
                }
#if os(macOS)
                // MIMIC IS MAC ONLY: never on a phone.
                NavigationLink {
                    place(.mimic)
                } label: {
                    HubRow(Mimic.studioRow, StudioHubWords.mimic, Mimic.studioRowSymbol)
                }
#endif
                // YOUR ROOM LIVES IN THE DUCK SHEET (build 91): it is about where the duck stands.
            } header: {
                SectionHeading(text: "Make")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                NavigationLink {
                    place(.behaviours)
                } label: {
                    HubRow("Behaviours", StudioHubWords.behaviours, "brain.head.profile")
                }
            } header: {
                SectionHeading(text: "Behaviours")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                // COMPARE IS SHOWN EVEN WITH EXPERT TOOLS OFF: human feedback is for everyone.
                NavigationLink {
                    place(.preference)
                } label: {
                    HubRow(CompareWords.studioRow, StudioHubWords.compare, CompareWords.studioRowSymbol)
                }
                if detail.shows(.training) {
                    NavigationLink {
                        HubTrainingView { url in
                            Imports.open(url, model: model, drafts: drafts, plans: plans)
                        }
                    } label: {
                        HubRow(HubTraining.rowTitle, StudioHubWords.hub, "cpu")
                    }
                    NavigationLink {
                        place(.shoot)
                    } label: {
                        HubRow(ShootWords.studioRow, StudioHubWords.shoot, ShootWords.studioRowSymbol)
                    }
                    NavigationLink {
                        place(.tune)
                    } label: {
                        HubRow("Tune it on \(DeviceWords.current.this)", StudioHubWords.tune, "slider.horizontal.3")
                    }
                    NavigationLink {
                        WeightSearchView(library: model, benches: benches)
                    } label: {
                        HubRow("Search its weights on \(DeviceWords.current.this)", StudioHubWords.weights, "brain")
                    }
                    NavigationLink {
                        MoveSearchView(benches: benches, models: models)
                    } label: {
                        HubRow("Search a move's keyframes", StudioHubWords.moveSearch, "magnifyingglass")
                    }
                    HubRow("Drivers", StudioHubWords.drivers, "steeringwheel",
                           reason: BallWalk.Words.ownDriversLater)
                        .accessibilityElement(children: .combine)
                }
            } header: {
                SectionHeading(text: "Train")
            }
            .listRowBackground(Theme.surfacePrimary)

            if detail.shows(.training) {
                Section {
                    NavigationLink {
                        place(.challenges)
                    } label: {
                        HubRow(Challenge.listTitle, StudioHubWords.challenges, "trophy")
                    }
                    NavigationLink {
                        place(.evaluations)
                    } label: {
                        HubRow(EvalTask.rowTitle, StudioHubWords.evaluations, "checklist")
                    }
                    NavigationLink {
                        BenchSettingsView(store: benches)
                    } label: {
                        HubRow("Benches", "The physics benches this phone knows.", "server.rack")
                    }
                    NavigationLink {
                        place(.measure)
                    } label: {
                        HubRow("Run on your network", StudioHubWords.measure, "wifi")
                    }
                    NavigationLink {
                        MultiDuckView(model: model, benches: benches)
                    } label: {
                        HubRow(MultiDuck.studioRow, StudioHubWords.multiDuck, MultiDuck.studioRowSymbol)
                    }
                    NavigationLink {
                        GhostDuckView()
                    } label: {
                        HubRow("Ghost duck", "Replays and the ghost duck's own modes.", "figure.walk.motion")
                    }
                } header: {
                    SectionHeading(text: "Measure")
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            Section {
                NavigationLink {
                    place(.learn)
                } label: {
                    HubRow("Learn", StudioHubWords.learn, "graduationcap")
                }
                NavigationLink {
                    SettingsView(detail: detail, models: models, benches: benches)
                } label: {
                    HubRow("Settings", "Appearance, models, speech and feedback.", "gear")
                }
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .refreshingCameraDoor($door)
        // THE SECOND HOP, AND IT NEEDS NO PATH CONVERSION. The rows above
        // are still closure `NavigationLink`s — they push a view they name
        // directly, which is what a row a finger is on should do — and this
        // modifier pushes the SAME view when another tab asks for it by name.
        // `navigationDestination(item:)` is the one API that takes a two-way
        // binding, so SwiftUI writes `pendingStudio` back to nil when the
        // person taps Back; a `NavigationPath` here would have meant converting
        // all six named rows to `NavigationLink(value:)` and then owning the
        // path's lifetime, to buy nothing this screen needs.
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
                NavigationLink { SettingsView(detail: detail, models: models, benches: benches) } label: {
                    Image(systemName: "gear").accessibilityLabel(Text("Settings"))
                }
            }
        }
    }

    /// The screen behind one of the six places another tab may name.
    ///
    /// IT IS THE ROWS' DESTINATION TOO, WHICH IS THE POINT. A route that built
    /// its own copy of `AutomationChatView` would be a second wiring of the
    /// seven stores and the runner beside them, and the failure mode of a
    /// second wiring is not a crash: it is a Draft screen with a different
    /// `EndpointStore` behind it, drafting against a model the rest of the app
    /// has not got. `DriveView`'s own comment about `models:` is the same bug,
    /// already paid for once.
    @ViewBuilder private func place(_ destination: StudioDestination) -> some View {
        switch destination {
        case .motions:
            IntentListView(models: models, benches: benches, plans: plans,
                           store: scenes, model: model, drafts: drafts)
        case .scenes:
            SceneListView(store: scenes, models: models, benches: benches)
        case .draft:
            AutomationChatView(drafts: drafts, scenes: scenes, models: models,
                               benches: benches, plans: plans, detail: detail)
        case .measure:
            RemoteRunView(model: model, scenes: scenes, drafts: drafts,
                          models: models, benches: benches)
        case .challenges:
            ChallengeListView(drafts: drafts, scenes: scenes,
                              models: models, benches: benches)
        case .evaluations:
            EvalListView(model: model, benches: benches, drafts: drafts,
                         scenes: scenes, evals: evals, runner: evalRunner)
        case .mimic:
            PoseCaptureView(drafts: drafts, scenes: scenes, models: models, benches: benches)
        case .tune:
            TuneView(library: model, benches: benches, models: models)
        case .preference:
            CompareHubView(library: model, drafts: drafts, benches: benches)
        case .shoot:
            ShootLabView(benches: benches)
        case .behaviours:
            PolicyListView(model: model, scenes: scenes, drafts: drafts,
                           models: models, benches: benches, detail: detail)
        case .learn:
            LearnView(detail: detail)
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
    /// A row this kind of machine can never open, left out rather than greyed.
    ///
    /// ROOM CAPTURE ON A MAC. A greyed row is a promise that something could
    /// change — permission, a different room — and on a Mac nothing can: it
    /// measures the floor through ARKit, which a Mac does not have. Every other
    /// row has a stage to fall back on and stays.
    static func hiddenHere(_ mode: LabCatalogue.Mode) -> Bool {
#if os(macOS)
        return mode.id == "room"
#else
        return false
#endif
    }

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
        let reason = mode.status.reason ?? cameraRefusal(for: mode)
        if reason == nil {
            NavigationLink {
                destination(mode)
            } label: {
                HubRow(mode.name, mode.summary, mode.symbol)
            }
        } else {
            // A ROW THAT CANNOT OPEN SAYS WHY, UNDER ITS NAME, rather than in a dialog after
            // the tap. Combined so a screen reader hears name, line and reason as one thing.
            HubRow(mode.name, mode.summary, mode.symbol, reason: reason)
                .accessibilityElement(children: .combine)
        }
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
            DuckSoccerView(library: model, drafts: drafts, benches: benches)
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

/// One row on the Studio list: a symbol in a fixed column, the name, and one line.
///
/// THE SYMBOL COLUMN IS FIXED, so every row's text starts at the same x and the list separators
/// line up; system `Label`s size the icon to the glyph, which is what made one separator on this
/// tab run the full width under "Plan with words". `reason` is set only for a row that cannot open.
struct HubRow: View {
    let title: String
    let line: String
    let symbol: String
    var reason: String? = nil

    init(_ title: String, _ line: String, _ symbol: String, reason: String? = nil) {
        self.title = title; self.line = line; self.symbol = symbol; self.reason = reason
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.snug)) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(reason == nil ? Theme.actionInk : Theme.textTertiary)
                .frame(width: HubRowMetric.symbolColumn)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(reason == nil ? Theme.textPrimary : Theme.textSecondary)
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                if let reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .padding(.vertical, 2)
        .frame(minHeight: DesignMetric.minimumTarget)
    }
}

private enum HubRowMetric {
    /// Wide enough for the widest symbol on the tab at body size.
    static let symbolColumn: CGFloat = 28
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
