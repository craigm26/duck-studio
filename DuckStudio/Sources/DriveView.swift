import SwiftUI
import AVFoundation
import StudioKit
import AppIntents
import DuckKit
import DuckEvidence

/// Drive a policy with your thumbs, live.
///
/// THE ONLY PRESENT-TENSE SCREEN IN THE APP. Everywhere else a network is
/// something you inspect, blend, or watch a recording of. Here it is running
/// right now and answering to a stick — which is the thing somebody means when
/// they ask whether they can control the robot from the phone.
///
/// AND IT IS THE CONTROL TAB'S ROOT NOW, WHICH IS A CHANGE OF ADDRESS RATHER
/// THAN A CHANGE OF SCREEN. It used to be pushed from an overflow menu on a
/// list of files — three taps from launch for the one thing somebody holding a
/// Microduck opens this app to do, and reachable only by people who thought to
/// look in a menu. Nothing about the pads, the loop or the Stop moved; what
/// moved is that there is no longer a screen behind this one. So the bar says
/// the tab's name rather than the verb on the row that opened it, the display
/// mode is a decision this file has to make instead of inheriting (see `body`),
/// and the app's one gear per tab root is up there beside the lens. Nothing
/// here ever depended on a back button or on a title a pusher had set.
///
/// WHAT IT IS ACTUALLY DRIVING IS A BENCH, and the screen says so in
/// `DuckDrive.thisIsNotARobot` rather than in a comment only. This is the one
/// arrangement in the app that reads unmistakably as a robot being driven — a
/// thumb moves, a duck moves — so the admission has to be on the glass.
///
/// THE COMMANDS ARE REAL EVEN THOUGH THE ROBOT IS NOT. `DuckDrive` transcribes
/// `padd`'s stick mapping and Pollen's `robot.move` frame, so what leaves this
/// screen is what would leave a gamepad. Only the transport is a stand-in.
///
/// EVERYTHING ORANGE MOVES THE DUCK, and nothing else on the screen is orange.
/// That is the whole colour rule here and it is worth stating once: Duck Orange
/// is the action colour, so the live pad buttons and the Drive/Stop/Reset bar
/// wear it and the readouts, chips, pickers and notes do not. A person who has
/// learnt one thing about this screen should have learnt that.
///
/// THE STOP IS PINNED AND THE REST SCROLLS. `Stop` used to be a row in the list
/// under a pad deck taller than the screen, which means it was reachable by
/// scrolling to it while the duck was walking. It is now in a bar that never
/// scrolls, and it is on the VoiceOver magic tap as well, so it can be reached
/// without finding it first. See `transport`.
///
/// AND THE STOP IS NEVER DISABLED. It used to go dead whenever any other call
/// was in flight — a health read, a policy swap, a reset — which means the one
/// control on this screen that exists for the moment something is going wrong
/// was unavailable for exactly as long as the screen was busy. It now pre-empts
/// instead: it cancels whatever errand is in flight and sends its own stop on a
/// path that does not look at `busy` at all. See `halt`.
///
/// WHAT A DUCK CAN HEAR GOES THROUGH THE PEER; WHAT ONLY A BENCH CAN DO STAYS A
/// BENCH CALL. This screen used to post to `/intent` and `/stop` itself, which
/// made it a bench screen wearing a robot's vocabulary: everything a person
/// learnt driving here was knowledge about `duckbench.mjs` rather than about a
/// Microduck. `DuckPeer` is the app's one vocabulary and `BenchPeer` is the
/// adapter that speaks it to a bench, so the four things a duck can hear —
/// `hello`, `robot.move`, `robot.stop`, `studio.state` — now leave this screen
/// as calls in that vocabulary and the peer decides what they become on the
/// wire. Three things do not, because no duck has them: `/health` lists the
/// policies a bench holds, `/policy` loads one into the slot a face button
/// names, and `/reset` picks the duck up. Those stay `DuckBench.Call`s, said so
/// in `ask`. The dividing line is the point of the arrangement: drop a WebRTC
/// peer in and the drive loop changes by one initialiser, while the three bench
/// calls stay honestly bench-shaped rather than pretending to be robot ones.
struct DriveView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var benches: BenchStore
    @ObservedObject var scenes: SceneStore
    /// Studio's motions, so one can be run from the picture. See `ControlShelf`.
    @ObservedObject var drafts: DraftStore

    /// The app's one link to a real robot, opened on the Robot tab.
    ///
    /// THE WHOLE POINT OF THIS SCREEN'S CHANGE, IN ONE PROPERTY. The Robot
    /// venue used to be a page of paragraphs about a link nobody had; the link
    /// exists, it is owned above this screen so that arriving here does not
    /// open one and leaving does not close one, and what this screen does with
    /// it is exactly what it does with a bench — call the vocabulary at it.
    @ObservedObject var robot: BridgeLink

    /// The model endpoints, handed down so the gear can open Settings.
    ///
    /// OPTIONAL, AND THE OPTIONALITY IS A HANDOVER NOTE RATHER THAN A DESIGN.
    /// `SettingsView` needs an `EndpointStore`; this screen has never had one
    /// because it was a pushed screen with no settings on it. It is a tab root
    /// now and it carries the one gear, so it needs the app's store — the one
    /// `DuckStudioApp` already hands to `MyMicroduckView` and `PolicyListView`.
    /// Nil means nobody handed it over yet, and `settingsModels` says what
    /// happens then. The fix is one argument at the tab root:
    /// `DriveView(model: model, benches: benches, scenes: scenes, models: models)`.
    var models: EndpointStore?

    /// The store the gear falls back to when none was handed down.
    ///
    /// A SECOND INSTANCE OF THE SAME `UserDefaults`-BACKED STORE, AND THAT IS
    /// WORTH SAYING OUT LOUD BECAUSE IT IS NOT FREE: both instances read and
    /// write the same keys, so an endpoint added through this gear is on disk
    /// immediately and invisible to the rest of the app's screens until the
    /// next launch. That is a real divergence and it exists for exactly as long
    /// as the tab root omits `models:`.
    ///
    /// IT IS STILL BETTER THAN THE TWO ALTERNATIVES. A gear that opens nothing
    /// is the inert control this app is built not to ship, and a required
    /// argument would break three call sites in files this change does not own.
    /// `@StateObject` rather than a default on the memberwise initialiser so it
    /// is built once for the life of the screen instead of on every re-render
    /// of whatever pushed it.
    @StateObject private var ownModels = EndpointStore()

    /// The store Settings actually gets.
    private var settingsModels: EndpointStore { models ?? ownModels }

    private var bench: BenchEndpoint? { benches.selected }
    private var token: String? { bench.flatMap { benches.armed($0).token } }

    @State private var health: DuckBench.Health?
    /// The pad map, the pilot and the sequences — one object, one line.
    ///
    /// NAMED `desk` AND NOT `pad`: `pad` is already the PadReader on this
    /// screen (the Bluetooth controller). See the build log, deviation 1.
    @StateObject private var desk = PadDesk()
    @State private var live: DuckDrive.Live?
    @State private var touchSticks = DuckDrive.Sticks.centred

    /// Whether the sticks are posing the robot's head instead of driving it.
    ///
    /// A MODE, NOT A FIFTH AXIS, AND `padd` IS WHY. Its `Mode::Head` puts BOTH
    /// sticks on the head and zeroes the twist in the same frame — see
    /// `DuckDrive.stillWhilePosingTheHead`. Offered on the robot venue only,
    /// because a bench has no door for a head pose at all and `BenchPeer`
    /// refuses `robot.head` by name.
    @State private var posingHead = false
    @State private var running = false
    @State private var busy = false
    /// Whether a STOP is in flight.
    ///
    /// SEPARATE FROM `busy`, AND THAT SEPARATION IS THE SAFETY FIX. `busy` is
    /// what every other errand raises, and Stop used to be disabled by it —
    /// so the button that exists for the moment a duck is walking somewhere it
    /// should not be went dead for the length of any other call. Stop now runs
    /// on its own path and raises only this, which nothing disables: the lens
    /// reads it so the link still looks live, and pressing Stop twice sends two
    /// stops, which is a duck told twice to do the thing it is already doing.
    @State private var stopping = false
    /// Set by `halt()` just before it cancels the errand in flight, so the
    /// catch that receives the cancellation can tell Stop from the screen
    /// going away. Consumed by `report`.
    @State private var cutOffByStop = false
    @State private var failure: String?
    @State private var failureTitle = DriveView.benchRefusedTitle
    private static let benchRefusedTitle = "The bench refused"
    private static let worldRefusedTitle = "This world cannot be built"
    /// THE THIRD TITLE, because a refusal from a machine on somebody's floor is
    /// not a bench refusing and should not say it is.
    private static let robotRefusedTitle = "The robot refused"
    /// FOLLOWING BY DEFAULT, AND ONLY ON THIS SCREEN.
    ///
    /// `OrbitState.defaults` is Fixed and the reasoning behind that stands
    /// everywhere else: a camera locked to the trunk shows a duck that never
    /// moves and a world that slides past, which cannot tell you whether the
    /// robot reached the step. What changed here is the stage: it is the whole
    /// tab now, so there is room to follow, and the bench's own world puts steps
    /// over a metre to one side of a fixed camera aimed at a bounding box. The
    /// toggle is on the picture, bottom-trailing, either way.
    @State private var orbit = OrbitState.following
    /// The stage's real size in points, measured rather than assumed. It is what
    /// the near stop is fitted to and what the occlusion arithmetic is about.
    @State private var glass: CGSize = .zero
    /// How tall the floating strip at the top and the cluster at the bottom
    /// actually came out, measured — the two footprints the camera has to clear.
    @State private var topChromeHeight: CGFloat = 0
    @State private var bottomChromeHeight: CGFloat = 0
    /// The PAD cluster's own height — the sticks, the buttons and the handle —
    /// measured on the pad itself, so it keeps its last value while the drawer
    /// is up. This, not `bottomChromeHeight`, is the footprint the camera
    /// clears: the drawer is a cover somebody opened and is deliberately not
    /// in the camera's arithmetic (see `stageChrome`).
    @State private var padChromeHeight: CGFloat = 0
    /// The readout panel's height, measured. It is the piece most often over
    /// the duck, and it is folded into the TOP footprint with the strip.
    @State private var notesHeight: CGFloat = 0
    /// The AR venue's own panel, measured, so the readout stacks under it.
    @State private var arHudHeight: CGFloat = 0
    /// Where the robot's own console is. TYPED, NOT DISCOVERED: `mediad` does
    /// not advertise itself over Bonjour, so an address is the honest control
    /// until something on the robot broadcasts one.
    @AppStorage("robot.console.host") private var consoleHost = "duck.local"
    /// Where the duck's camera is: seeded from the bridge's host, since `mediad` runs on the
    /// same computer as `robotd`; a simulated duck's is the laptop and the port duck-sim printed.
    @AppStorage("robot.camera.address") private var cameraAddress = ""
    /// Whether the controls drawer is up.
    ///
    /// PER SCREEN, AND CLOSED BY DEFAULT. `stage.legend.expanded` is app-wide
    /// because "numbers or the duck" is one preference; whether the settings are
    /// over the picture is a judgement about THIS screen, whose controls are a
    /// pad somebody is holding while a robot walks. It ships closed because an
    /// overlay that covers the duck the moment the tab opens is exactly the
    /// build-41 failure this app has already paid for once.
    @AppStorage("control.drawer") private var drawerIsUp = false
    /// Whether the venue's own sentence is open over the picture. Not stored:
    /// it is a thing somebody reads once and closes, and a caption that came
    /// back open on every launch would be an overlay over the duck by default.
    @State private var venueLineIsOpen = false
    /// Which of the two Studio doors is open, and what the last motion run
    /// said. See `ControlShelfChips`.
    @State private var shelf: Shelf?
    @State private var runningMotion: String?
    @State private var motionOutcome: String?

    /// THE POSE BEING BUILT ON THE PICTURE, or nil when nobody is posing.
    /// Fifteen joints, the mouth included, exactly as a draft holds them —
    /// it starts as the duck's live stance and nothing is sent while it moves.
    @State private var posed: [Double]?
    @State private var poseGroup = JointGroup.all[0].title
    @State private var poseProjections = StageProjections()
    @State private var posedJoint: Int?
    @State private var pinnedPoseJoint: Int?
    @State private var openedPoseCluster: Int?
    @State private var poseRefusal: String?
    /// Joints whose handle would fall off the glass, named rather than
    /// silently dropped — the overlay's own accounting.
    @State private var poseOffPicture: [Int] = []

    /// THE RUN, BEING WATCHED. A batch call steps the bench's own second duck,
    /// so the live duck this picture draws does not move while a motion runs —
    /// which read as the motion barely running. This is the answer the bench
    /// sent back, played on the picture at the rate it was recorded.
    @State private var playback: DuckIntentClip?
    @State private var playhead: TimeInterval = 0
    @State private var poseNote: String?

    /// THE PERSON IN FRONT OF THE CAMERA, AS A POSE. While `mimicking` the
    /// engine writes the duck's retargeted stance into `posed` on every
    /// answer, so the picture, `holdThePose` and `keepThePose` all work on it
    /// exactly as they do on a pose built by hand — a mimicked stance is a
    /// stance. The engine is a `@StateObject` so the camera session lives as
    /// long as this screen and is stopped when the bar is closed or the tab
    /// is left, never per render.
    @StateObject private var mimic = PoseCaptureEngine()
    @State private var mimicking = false
    @State private var mimicPosition: AVCaptureDevice.Position = .front
    /// The draft the last mimic recording was kept as, so Run it here has
    /// something to run.
    @State private var mimicKept: IntentDraft?

    private enum Shelf: String, Identifiable {
        case scene, motions, dream
        /// The pull-up Moves sheet: the Moves tab's tiles, kept sequences, motions and Plan.
        case moves
        /// More: scene, record a sequence, the pad map, the camera, and the drive settings.
        case more
        /// A recorded take, offered to keep. Never auto-saved.
        case keep
        /// The Plan editor, from the Moves sheet, with this desk so a plan drives this duck.
        case plan
        var id: String { rawValue }
    }
    /// Round trips completed since Drive was pressed, and the sim seconds they
    /// bought. THE RATE IS THE ONE NUMBER THAT TELLS YOU WHETHER THIS IS
    /// DRIVEABLE: a bench on the far side of a slow link answers so rarely that
    /// the duck moves in lurches, and that reads as a broken policy rather than
    /// as a slow network unless the screen counts it out loud.
    @State private var trips = 0
    /// A real controller, when one is paired.
    @StateObject private var pad = PadReader()
    /// Which overlays are on. See `DuckPad.Layer` — a driver and a tester want
    /// different amounts on top of the same picture.
    @State private var layers = DuckPad.Layer.defaults
    /// What the buttons flashed most recently, so a press is visible even when
    /// the thing it did is off-screen.
    @State private var lastAction: String?
    /// So the viewport can stop clipping at accessibility sizes — see `stage`.
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Whether the last answer had a joint inside `DuckPad.nearLimitRadians` of
    /// a stop.
    ///
    /// KEPT SO THE TAP IS AN EDGE. A joint held against its stop is near it on
    /// every trip, and a bench answering ten times a second would then buzz ten
    /// times a second — which is not a signal, it is a phone with a fault.
    /// `PadReader` makes the same argument about a held button: the event is
    /// the arrival, not the state.
    @State private var wasNearALimit = false

    /// The bench, spoken to in the robot's own vocabulary.
    ///
    /// ONE PEER FOR THE BENCH THAT IS SELECTED, REBUILT WHEN THAT CHANGES OR
    /// THE TOKEN DOES — see `peerKey`. It is held rather than made per call
    /// because a peer is a connection and not a value: `DuckPeer` is `AnyObject`
    /// for exactly that reason, and `BenchPeer` keeps the last state block and
    /// the id counter, both of which a fresh instance per request would throw
    /// away every request.
    @State private var benchPeer: BenchPeer?
    /// Dream-1 on the simulated duck: its drawn head camera, a run, and recordings (`DreamSimSheet`).
    @StateObject private var simHeadCamera = SimHeadCameraFeed()
    @StateObject private var dreamModel = DreamRunModel()
    @ObservedObject private var drivers = PhoneDrivers.shared
    @StateObject private var dreamRecorder = DreamRecorder()

    /// THE PEER THE DRIVE LOOP ACTUALLY TALKS TO, AS THE VOCABULARY AND NOT AS
    /// A TRANSPORT.
    ///
    /// THIS IS THE LINE THE WHOLE SCREEN WAS BLOCKED ON. `peer` was
    /// `BenchPeer?`, concretely, so `drive()` could only ever notify a bench —
    /// and the app therefore never sent a `robot.move` to anything in its life,
    /// despite holding a complete vocabulary, a routing table, a line peer and
    /// a working bridge. It is `any DuckPeer?` now, chosen by venue: the bench
    /// this screen has always driven, or the robot on the other end of the
    /// bridge.
    ///
    /// THE VENUE PICKS IT AND NOT A SETTING, because the venue is the thing a
    /// person can see. Somebody looking at the Robot segment is looking at a
    /// robot; a switch that also had to be flipped somewhere else to decide
    /// where the sticks went would be a way to drive the wrong duck.
    private var peer: (any DuckPeer)? {
        venue == .real ? robot.peer : benchPeer
    }

    /// The bench errand in flight, kept so STOP CAN CUT IT OFF.
    ///
    /// ONE SLOT, HOLDING THE NEWEST. Everything except a stop goes in it —
    /// connect, the drive loop, a reset, a policy swap — and `halt` cancels
    /// whatever is there before sending its own. Without the handle, Stop could
    /// only ask the loop to finish its current round trip, and a request to a
    /// bench that has stopped answering is allowed two minutes to give up
    /// (`DuckBench.urlRequest` sets the timeout); two minutes is not a stop.
    ///
    /// THE NEWEST RATHER THAN ALL OF THEM, which is honest about what this
    /// screen can do at once: Drive and Reset are two presses and each clears
    /// `running` first, so there is never a second loop underneath. A dropped
    /// handle is a request already on its way back.
    @State private var flight: Task<Void, Never>?

    /// What `studio.state` last said, or nil when the peer has nothing to say.
    /// Shown in the `link` layer — see `askWhatItSaw`.
    @State private var stateSaid: String?

    // MARK: - where you are driving, and what you are driving in

    /// Sim, your own floor, or a robot. See `venueSwitch`.
    @State private var venue: DriveVenue = .sim

    /// What the camera can be asked for, refreshed on the way back from
    /// Settings by `refreshingCameraDoor`.
    @State private var cameraDoor = CameraDoor.availability

    /// The picker's selection. IT IS ALWAYS WHAT IS ACTUALLY STANDING, not
    /// what was asked for — every write and every read ends by setting this
    /// from `standingChoice`, so a refused world snaps the control back to the
    /// world the bench is really in rather than leaving a lie in a picker.
    @State private var worldChoice: WorldChoice = .benchOwn

    /// The bench's answer to `GET /world` — the READBACK, which is what the
    /// stage draws. Nil before the first read.
    @State private var world: DuckWorld?

    /// True once the bench has said it has no `/world`. The picker goes dead
    /// and `DuckWorld.noWorldRoute` is printed where the control was, which is
    /// the `/tune` idiom: a blocked surface says why, in the place it is
    /// blocked.
    @State private var worldRouteMissing = false

    /// What the kit worked out about the world that is standing, kept because
    /// SOME OF IT THE BENCH CANNOT SAY.
    ///
    /// THE WIRE IS `{x, top}` AND NOTHING ELSE, which is the whole reason this
    /// exists. `POST /world` carries a block's centre and the height of its
    /// upper face; it has no field for the y a scene drew, none for how tall
    /// the scene wanted the block, and none for a ball a scene left out. The
    /// bench only comments on what it was told, so it answers a four-step
    /// staircase with one note about a wall and says nothing at all about the
    /// flight having landed 1.3 m to the duck's left at 200 mm a block — which
    /// is the most surprising thing that just happened.
    /// `DuckWorld.plan(for:on:)` knows, because it read the scene. So the
    /// readback is printed first and in full, and then exactly the predictions
    /// the wire gave the bench no way to make. See `worldNotes`.
    @State private var predicted: [DuckWorld.Unexpressed] = []

    /// One line about the last world request, when the request itself has
    /// something to say that the readback cannot — picking the bench's own
    /// world after something else is already standing, which sends nothing.
    @State private var worldNote: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The one sanctioned way to another tab: the Mimic bar sends a person to
    /// Studio for the two sources this screen does not draw.
    @EnvironmentObject private var router: AppRouter

    // MARK: - the controller (build 91)

    /// What runs on the duck and the one Stop every screen presses.
    @ObservedObject private var runs = DuckRuns.shared
    /// Who is driving: the person's thumbs, a Tell order or an Auto goal. The kit's rules.
    @State private var arbiter = ControlArbiter()
    /// The stick after a venue switch, deaf until the finger lifts.
    @State private var stickGate = StickGate()
    /// The real duck's picture, the stage on that venue.
    @StateObject private var realFeed = DuckCameraFeed()
    /// The one line under the controller. It goes away on its own (`CaptionLine`), and on a mode
    /// change, a stick drive and the next tap (build 92: one refusal used to stay in every mode).
    @State private var caption: CaptionLine?
    /// Ask the duck: Apple Intelligence plans, the kit validates, `DuckRuns` runs.
    @StateObject private var ask = AskTheDuck()
    /// The mic on Tell and Ask the duck.
    @StateObject private var listener = DuckListener()
    /// What an Auto plan is doing and when it started, for the one status line while it runs.
    @State private var autoWhat: String?
    @State private var autoStarted: Date?
    /// A real duck's stick loop that a stick push started, so letting go ends it with a zero
    /// twist and robot.stop (build 92: the sticks used to need the old Drive button first).
    @State private var stickStarted = false
    /// A Tell order is running.
    @State private var telling = false
    /// Which one-time coach marks are done, as `Onboarding.CoachMarks`' bit set (build 93).
    @AppStorage("coach.done") private var coachDone = 0
    /// Dream-1 on the real duck, as a sheet over its picture.
    @State private var realDream = false
    /// The first walk to the ball on a real duck is waiting for the person's yes.
    @State private var confirmingWalk = false
    /// The driver the person last said yes to on a real duck (`BallWalk.needsConfirming`).
    @AppStorage("walk.real.confirmed") private var walkConfirmed = ""
    @Environment(\.scenePhase) private var scenePhase

    /// A REAL PAD WINS WHILE IT IS BEING HELD. Both inputs are live at once —
    /// a tester can put a thumb on the glass without unpairing anything — and
    /// the physical sticks only take over once they leave centre, so a resting
    /// controller does not pin the on-screen pads to zero.
    private var rawSticks: DuckDrive.Sticks {
        pad.sticks == .centred ? touchSticks : pad.sticks
    }

    /// The sticks that drive: centred while the gate waits for the finger to lift after a
    /// venue switch, so a thumb held on the practice duck is not the real duck's first command.
    private var sticks: DuckDrive.Sticks {
        stickGate.waitingForLift ? .centred : rawSticks
    }

    private var twist: DuckDrive.Twist { DuckDrive.twist(for: sticks) }

    /// THE MODE IS ONLY REAL ON A ROBOT. A bench has no endpoint that takes an
    /// angle, so leaving this true after a venue change would send a stream of
    /// still twists to a simulator and call it posing.
    private var posingRobotHead: Bool { venue == .real && posingHead }

    /// The duck as last seen, or the home stance before the first answer.
    private var pose: StagePose { live?.stance ?? .home }

    /// How much of the app to show. Optional like `models` above, because
    /// this screen is presented from more than one place and not every caller
    /// holds one; a caller that does not gets the installed default.
    var detail: DetailStore?

    private var settingsDetail: DetailStore { detail ?? ownDetail }
    @StateObject private var ownDetail = DetailStore()

    /// THE STORED LEVEL, OBSERVED. `detail` is a plain reference (optional,
    /// see above), so a change made in Settings would not redraw this screen;
    /// the key `DetailStore` writes does. Empty until something is chosen,
    /// when the store's own starting level answers.
    @AppStorage("duckstudio.detailLevel") private var detailRaw = ""

    /// Simple: the pad and the moves, without the authoring chips, the
    /// readout layers or the paragraphs in the drawer.
    private var isSimple: Bool {
        (DetailLevel(rawValue: detailRaw) ?? settingsDetail.level) == .simple
    }

    var body: some View {
        // FULL-BLEED WHERE THERE IS A PICTURE, STACKED WHERE THERE IS NOT.
        //
        // The Control tab's stage used to be a 300-point card with a venue
        // switch above it, a row of chips under it and a settings list under
        // that — a duck the size of a playing card on a screen whose whole
        // subject is the duck. It is now the background of the tab, and the
        // switch, the caption, the readout, the sticks and the camera buttons
        // float ON it. `StageViewport.chromeFloatsSaid` says so on the glass.
        //
        // NOTHING IS PRESENTED AND NOTHING IS RE-PARENTED. There is no
        // `fullScreenCover`, no sheet and no second `DuckStage` or `OrbitState`
        // anywhere in this file. That is what retires the four risks: a cover
        // would fire `onDisappear` (:running = false, flight?.cancel(),
        // pad.stop()) and stop a duck mid-drive; it would re-enter `.task`; it
        // would rebuild `ARDriveContainer`, whose `dismantleUIView` nils the
        // anchor and loses the placed duck; and it would take the slider row a
        // handle tap scrolls to off the glass. The chrome going up and down is
        // an overlay appearing beside the stage, never around it.
        //
        // THE ROBOT VENUE IS THE ONE THAT STAYS STACKED, because it draws no
        // picture at all — `venueStage` is `EmptyView()` there — so a ZStack
        // would be floating chrome over nothing.
        // ONE CONTROLLER ON EVERY VENUE (build 91). The real duck is drawn full-bleed from its
        // camera like the other two; the Robot venue's list is gone.
        stageWithController
        .background(Theme.backgroundPrimary)
        // THE COERCION IS THE KIT'S AND IT RUNS THREE TIMES — on appear,
        // whenever the door changes underneath (somebody walks to Settings and
        // switches the camera off while this is on screen), and on every pick.
        // It hangs on the ROOT rather than on the switch because two layouts
        // draw that switch now, and a rule attached to one of them would be a
        // rule that stops running when the other is on screen.
        .onAppear {
            venue = DriveVenue.coerce(venue, camera: cameraDoor)
            // THE DRAWER WENT INTO MORE (build 91); one left up by an older build comes down.
            drawerIsUp = false
        }
        .refreshingCameraDoor($cameraDoor)
        .onChange(of: cameraDoor) { _, _ in
            venue = DriveVenue.coerce(venue, camera: cameraDoor)
        }
        .onChange(of: venue) { was, now in
            entered(from: was, to: now)
            router.playVenue = now
        }
        // THE TAKE IS OFFERED, NEVER AUTO-SAVED (was PadChrome's): a ceiling, a Stop, a Pause and
        // the chip all land here.
        .onChange(of: desk.pilot.pending) { _, take in if take != nil { shelf = .keep } }
        // ARRIVING AT THE ROBOT ASKS IT TO TALK, and so does a link that opens
        // while this tab is already showing — somebody can connect on the Robot
        // tab and walk back here, which is the ordinary way round. Both land on
        // the same idempotent subscribe.
        .task(id: robotLinkKey) { await askTheRobotToTalk() }
        // THE TAB'S NAME, NOT THE VERB. This screen was pushed from a menu row
        // that said "Drive one live", so the bar repeated the row that opened
        // it. It is the Play tab's root now: the tab bar below says Control
        // and the bar above has to say the same word, or the app has two names
        // for one place.
        .navigationTitle("Play")
        // INLINE, DELIBERATELY, AND THIS IS THE ONE DISPLAY-MODE DECISION IN
        // THE APP WORTH WRITING DOWN. A large title is 34pt of type plus its
        // padding — call it 52 points of bar — and it is the FIRST thing under
        // the status bar, which means it comes out of the top of `stage`. What
        // is in `stage` is a duck at a real 25 cm being driven right now, and
        // `DriveMetric` already fights for that height at accessibility text
        // sizes. A big title also collapses to the small one the moment the
        // list under it scrolls, so on the one screen whose content moves under
        // your thumb continuously it would be an animation running beside a
        // live viewport. Inline costs the duck nothing and never moves.
        .navigationBarTitleDisplayMode(.inline)
        // NO BAR OVER THE DUCK. The lens is the live dot on the duck pill and Settings lives in
        // Studio, so the picture runs to the top edge.
#if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
#endif
        // NO BOTTOM BAR (build 92). The old Drive | Stop | Reset bar duplicated the red disc's
        // Stop, hid the real duck's need for Drive, and cost the picture about 70 points. The
        // sticks start the duck, the disc stops it, and Put it back on its feet is in More and the
        // duck pill.
        // THE WORLD IS RE-READ WHEN THE BENCH CHANGES, for the same reason the
        // peer is rebuilt: the answer belongs to one machine. A picker still
        // showing the last bench's staircase would be describing a world this
        // bench has never been in.
        .onChange(of: peerKey) { _, _ in flight = Task { await refreshWorld() } }
        // WHAT STUDIO HOLDS, AS THE PAD SEES IT. A button bound to a motion
        // reads its name from here, and a motion deleted in Studio turns that
        // button into a named not-yet rather than a dead one.
        .onChange(of: drafts.drafts) { _, held in
            desk.learn(motions: Dictionary(held.map { ($0.id, $0.name) },
                                           uniquingKeysWith: { first, _ in first }))
        }
        .task(id: drafts.drafts.count) {
            desk.learn(motions: Dictionary(drafts.drafts.map { ($0.id, $0.name) },
                                           uniquingKeysWith: { first, _ in first }))
        }
        // A STOP THAT DOES NOT HAVE TO BE FOUND. The bar below is always on
        // screen, but "always on screen" is a sighted guarantee: a VoiceOver
        // user still has to swipe to it, and the swipes happen while the duck
        // is walking. The magic tap is two fingers double-tapped ANYWHERE on
        // the screen, which is the only stop that costs nothing to reach.
        //
        // AND IT NO LONGER REFUSES WHILE THE SCREEN IS BUSY. It used to guard
        // on `!busy`, so the stop that costs nothing to reach did nothing at
        // all for as long as any other call was out — silently, because a magic
        // tap that returns early looks exactly like one the system did not
        // deliver. A bench is the only thing it needs, and `halt` cuts off
        // whatever else is in flight on its way past.
#if os(iOS)
        .accessibilityAction(.magicTap) {
            // THE ONE CONTROL THAT MUST BE REACHABLE WITHOUT FINDING IT, and
            // it now covers the robot too: `bench != nil` alone would have made
            // the magic tap dead on the one venue where a stop is a machine in
            // a room rather than a simulation.
            stopNow()
        }
#else
        // ON A MAC THE STOP THAT COSTS NOTHING TO REACH IS ESCAPE. macOS has
        // no magic tap; a key that works wherever focus is in the window is
        // the same promise. A zero-size button carries it because a keyboard
        // shortcut needs a control to belong to.
        .background {
            // ALWAYS LATCHES (build 93): it used to return early with no duck, so a run started a
            // moment later on a sheet was not held back by the latch.
            Button("Stop") { stopNow() }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
#endif
        .task {
            // THE PAD'S PRESSES GO THROUGH THE SAME DOOR as the on-screen ones.
            pad.onPress = { control in Task { await press(control) } }
            pad.begin()
            // WARMED BEFORE THE FIRST LIMIT, NOT AT IT. The taptic engine spins
            // up on demand and the first tap of a session arrives after the
            // thing it is about — which teaches the person that the buzz and
            // the stick are unrelated.
            Haptic.prepare()
            flight = Task { await connect() }
        }
        // THE PEER IS POINTED AT ONE BENCH WITH ONE TOKEN, and both can change
        // while this screen is open — the picker changes the first, Manage
        // benches the second. Rebuilding on either is what stops a peer holding
        // an address the person has stopped using or a token they have replaced.
        .onChange(of: peerKey) { _, _ in rebuildPeer() }
        // THE CAMERA'S ANSWER BECOMES THE POSE ON THE PICTURE. Only while
        // the bar is up: an answer arriving after Done would re-pose a duck
        // somebody has gone back to driving.
        .onReceive(mimic.$duckPose) { answer in
            guard mimicking, let answer else { return }
            posed = answer
        }
        .onDisappear {
            pad.stop()
            // AND THE CAMERA, which is a session iOS keeps running for a
            // screen nobody is looking at until it is told otherwise.
            if mimicking { stopMimic() }
            // LEAVING THE SCREEN STOPS THE LOOP. Without this the task keeps
            // sending intents at a bench for a screen nobody is looking at.
            running = false
            // AND CUTS OFF THE REQUEST ALREADY OUT. `running` ends the loop at
            // the top of its next turn, which is after the round trip in
            // progress comes back; the cancel is what stops that one too. Not
            // a Stop, so the flag says so.
            cutOffByStop = false
            flight?.cancel()
        }
        .sheet(item: $shelf) { which in
            Group {
            switch which {
            case .scene:
                ControlSceneSheet(entries: sceneRows, standing: world?.name,
                                  choose: { slot in
                                      guard worldEntries.indices.contains(slot) else { return }
                                      let picked = worldEntries[slot].choice
                                      guard picked != standingChoice else { return }
                                      flight?.cancel()
                                      flight = Task {
                                          if running { await halt() }
                                          await stand(in: picked)
                                      }
                                  })
            case .motions:
                ControlMotionsSheet(motions: motionRows, running: runningMotion,
                                    outcome: motionOutcome,
                                    run: { id in Task { await runMotion(id) } })
            case .moves:
                movesSheet
            case .more:
                moreSheet
            case .keep:
                SequenceKeepSheet(desk: desk, bench: bench, token: token,
                                  engage: { engageLoop() }, library: model)
            case .plan:
                NavigationStack {
                    PlanEditorView(desk: desk, venue: venue, engage: { engageLoop() }, bench: bench,
                                   models: settingsModels, robot: robot, stopDriving: { await stepAside() })
                }
            case .dream:
                // THE BENCH'S OWN PEER, made if driving has not made it yet: the camera draws its duck.
                DreamSimSheet(peer: (try? requirePeer()) as? BenchPeer, feed: simHeadCamera,
                              model: dreamModel, recorder: dreamRecorder,
                              stopDriving: { await stepAside() })
            }
            }
            .stopPill()
        }
        .alert(failureTitle, isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(failure ?? "") }
    }

    // MARK: - where you are driving it

    /// What a change of venue does to the drive that is already running.
    ///
    /// NOTHING, EXCEPT ON THE WAY TO THE ROBOT. Sim and "Your floor" are the
    /// same drive drawn two ways — the loop, the peer, the pad and the bar are
    /// untouched, so a duck being steered keeps being steered while the floor
    /// under it changes. The robot venue draws no transport bar at all, and a
    /// loop left running under a bar that is no longer on screen is exactly the
    /// arrangement `transport` exists to end: a duck walking with the Stop out
    /// of reach. So that one move sends a real stop, in the same words the
    /// button does, rather than merely pausing.
    /// - Parameter was: the venue being LEFT, and the reason this takes two
    ///   arguments now rather than one.
    ///
    /// A STOP MUST GO TO THE THING THAT IS MOVING, WHICH IS THE ONE BEING LEFT.
    /// `onChange` fires after `venue` has already changed, so the old body's
    /// `halt()` — which resolves its peer from `venue` — would have sent
    /// `robot.stop` to the robot on the way INTO the robot venue while the
    /// bench it was actually driving carried on walking. That is a duck left
    /// walking by the very code written to stop one, and it only became
    /// possible when the peer stopped being a bench unconditionally.
    ///
    /// SIM AND YOUR FLOOR STILL DO NOT STOP ANYTHING. They are the same drive
    /// drawn two ways, so a duck being steered keeps being steered while the
    /// floor under it changes. Crossing the robot boundary in either direction
    /// is the move that stops: the two sides drive different machines.
    @MainActor private func entered(from was: DriveVenue, to now: DriveVenue) {
        let allowed = DriveVenue.coerce(now, camera: cameraDoor)
        if allowed != now { venue = allowed; return }
        guard was != allowed, was == .real || allowed == .real, running else { return }
        // The peer for the venue being left — named explicitly rather than
        // resolved from `venue`, which has already moved on.
        let leaving: (any DuckPeer)? = was == .real ? robot.peer : benchPeer
        // THE HEAD MODE DOES NOT TRAVEL. It is a robot's mode; carrying it to a
        // bench would be a stream of still twists at a simulator.
        posingHead = false
        running = false
        touchSticks = .centred
        desk.pilot.cutOff(.stop)
        flight?.cancel()
        Task { await stop(leaving) }
    }

    /// Zero the command on a NAMED peer, and say nothing if there is none.
    ///
    /// SPLIT OUT OF `halt` SO A STOP CAN BE ADDRESSED. `halt` is the button and
    /// resolves its own peer from the venue somebody is looking at; this is the
    /// half that puts the call on a link chosen by the caller, which is what
    /// leaving a venue needs.
    @MainActor private func stop(_ peer: (any DuckPeer)?) async {
        guard let peer else { return }
        do {
            let answer = try await peer.call(.stop)
            if let refusal = answer.failure {
                failure = DuckBench.ReadError.bench(refusal.message).message
            }
        } catch { if !stopCutItOff(error) { report(error) } }
    }

    /// The picture, or the absence of one.
    @ViewBuilder private var venueStage: some View {
        switch venue {
        case .sim: stage
        case .ar: arStage
        // THE REAL DUCK'S OWN PICTURE, full-bleed, or a calm poster with its state sentence. Never
        // a rendered duck under the real duck's name, and never a list.
        case .real:
            DuckPictureStage(feed: realFeed, connected: robot.isConnected,
                             hasAddress: DuckCamera.Address(cameraAddress.isEmpty ? robot.host : cameraAddress) != nil,
                             connect: { router.duckSheet = true })
        }
    }

    // MARK: - the full-bleed stage and the chrome on it

    /// The Control tab: one picture, filling the tab, with everything else
    /// floating on it.
    ///
    /// EVERY PIECE IS AN OVERLAY ON THE STAGE, NOT A ROW AROUND IT. That is what
    /// makes the picture full-bleed and it is also what keeps the hit-testing
    /// honest: an overlay is laid out in the stage's frame but only hit-tests
    /// what it actually draws, so a pinch or a pan that lands between the switch
    /// and the sticks reaches the `UIPinchGestureRecognizer` underneath. There
    /// is deliberately no full-size `.contentShape` anywhere below.
    ///
    /// NOTHING HERE IS CLIPPED AND NOTHING HERE IS A CARD. The 300-point cap,
    /// the rounded viewport and its hairline all went with the layout that had
    /// something above and below the picture to be a card against.
    private var controlStage: some View {
        venueStage
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .measuringGlass { glass = $0 }
            // THE HANDLES, WHILE SOMEBODY IS POSING. Above the stage and
            // below the chrome: the same layer the editor puts them on, over
            // the same `DuckStage`, so a joint is grabbed here exactly as it
            // is grabbed in Studio.
            .overlay {
                if posed != nil {
                    JointHandleOverlay(handles: poseHandles,
                                       projections: poseProjections,
                                       drawn: poseGroupJoints,
                                       editable: true,
                                       focused: posedJoint,
                                       showsLabel: false,
                                       pinned: $pinnedPoseJoint,
                                       opened: $openedPoseCluster,
                                       refusal: $poseRefusal,
                                       offPicture: $poseOffPicture,
                                       select: { posedJoint = $0 },
                                       write: { joint, value in
                                           guard var pose = posed else { return }
                                           guard pose.indices.contains(joint) else { return }
                                           pose[joint] = value
                                           posed = pose
                                       },
                                       goToEditingKeyframe: {})
                }
            }
            .overlay(alignment: .top) { topChrome }
            .overlay(alignment: .top) {
                if venue == .sim {
                    DreamSimStatus(model: dreamModel, recorder: dreamRecorder)
                        .padding(.top, topChromeHeight + Theme.spacing(.tight))
                }
            }
            .overlay(alignment: .topLeading) { stageNotes }
            // BOTTOM-TRAILING, NEVER TRAILING-CENTRED. Width along an edge is
            // free; height over the middle is what covers a robot.
            .overlay(alignment: .bottomTrailing) { cameraColumn }
            .overlay(alignment: .bottom) { bottomChrome }
            // THE NEAR STOP IS FITTED TO THE GLASS AND THE CHROME ON IT, so the
            // zoom-in button stops before a press could put the duck behind the
            // sticks. Re-run whenever any of the three measurements moves.
            .onChange(of: glass) { _, _ in refitCamera() }
            .onChange(of: topChromeHeight) { _, _ in refitCamera() }
            .onChange(of: notesHeight) { _, _ in refitCamera() }
            .onChange(of: padChromeHeight) { _, _ in refitCamera() }
            .onChange(of: orbit.follows) { _, _ in refitCamera() }
            // A THUMB HELD WHEN THE PADS LEAVE THE GLASS IS NOT THE NEXT
            // COMMAND. `ThumbPad` recentres only in `DragGesture.onEnded`,
            // which never fires for a view that was removed, and its "Centre"
            // action goes with it — so the last deflection would keep being
            // posted by `drive()` with no stick on screen. The same rule
            // `halt()` applies, at the other door. Zeroing on close as well is
            // free: a released pad is already centred, and a real controller
            // is unaffected because `sticks` prefers `pad.sticks` off-centre.
            .onChange(of: drawerIsUp) { _, _ in touchSticks = .centred }
            // PUSH A STICK AND THE DUCK GOES. Drive used to be a separate tap
            // before either stick did anything, which is the first thing a
            // person tries and the first thing that did nothing. Only on a
            // bench (Sim, Your floor): a real robot keeps walking on its last
            // twist until a deadman, so starting it stays a deliberate press.
            // `engageLoop` is the same door the face buttons use, so a load
            // in flight is handled the way it already is.
            .onChange(of: sticks) { _, now in
                let still = DuckDrive.twist(for: now).standsStill
                // YOUR THUMBS WIN: a stick touch ends a Tell order or an Auto goal and snaps to Drive.
                // IN AUTO WITH NOTHING RUNNING THE STICK RESTS (build 93): a game controller lying
                // on the sofa used to flip the switch to Drive. The kit says so in one line, once.
                if !still, arbiter.running != nil || arbiter.mode == .auto {
                    let decision = arbiter.handle(.stickTouch, at: Date())
                    if !decision.passInput {
                        if caption?.text != ControlArbiter.Words.sticksRestInAuto { apply(decision) }
                        return
                    }
                    apply(decision)
                }
                // A STICK DRIVE CLEARS THE LINE: whatever it said was about something else.
                if !still, caption != nil { say(nil) }
                // ON A REAL DUCK, LETTING GO ENDS THE DRIVE: a zero twist and robot.stop, so the
                // duck never waits on its deadman. A replay or a take keeps the loop.
                if still, venue == .real, running, stickStarted,
                   !desk.pilot.isPlaying, !desk.pilot.isRecording {
                    releaseRealStick()
                    return
                }
                // PUSH A STICK AND THE DUCK GOES, ON BOTH DUCKS (build 92). The real duck used to
                // need the old Drive button first, and nothing on screen said so.
                guard !running, somethingToDrive,
                      posed == nil, !mimicking, playback == nil, !still else { return }
                stickStarted = venue == .real
                coach(.stick)
                engageLoop()
            }
            // AND WHENEVER SOMETHING ELSE PUTS THE RANGE BACK. `readWorld` ends
            // on `orbit.frame(nil)` — the build-46 black-stage fix, untouched —
            // which resets the range along with the framing, so without this the
            // near stop silently reverts to the global 0.20 m after every world
            // read and the zoom-in button starts allowing a press that hides the
            // robot. It cannot loop: `refitCamera` is a pure function of the
            // glass, the chrome and `follows`, so re-asserting it writes the
            // same value and the second pass changes nothing.
            .onChange(of: orbit.limits) { _, _ in refitCamera() }
    }

    /// A real duck's stick let go: the loop ends, then a zero twist and `robot.stop` go out.
    @MainActor private func releaseRealStick() {
        stickStarted = false
        running = false
        flight?.cancel()
        guard let peer = robot.peer else { return }
        flight = Task {
            try? await peer.notify(.move(.still))
            _ = try? await peer.call(.stop)
        }
    }

    /// Start the drive loop from anywhere that is not the Drive button, THE
    /// WAY THE DRIVE BUTTON DOES: the errand in `flight` is cancelled first.
    /// A `putBack` or a `swap` left in the slot would otherwise be orphaned,
    /// and Stop's `flight?.cancel()` could no longer reach it — a /reset posted
    /// before a chip was tapped would land after Stop and stand the duck up.
    /// The cost is the one the Drive button already pays: a read-only errand
    /// (`connect`, `refreshWorld`) may be cut and has to be asked again.
    @MainActor private func engageLoop() {
        guard !running else { return }
        flight?.cancel()
        running = true
        flight = Task { await drive() }
    }

    /// The duck as the stage should draw it: the bench's own stance, or the
    /// pose being built ON that stance — the same root, so a posed duck stays
    /// where the physics put it and only its joints move.
    private var posedStance: StagePose {
        // THE RUN FIRST. While a clip is playing it IS what the screen is
        // about, root and all — the batch duck's own trajectory, not the live
        // duck's position with somebody else's joints on it.
        if let playback { return .at(playback.pose(at: playhead)) }
        guard let posed else { return pose }
        return DuckStance(jointAngles: posed, root: pose.root)
    }

    /// How far through the clip the picture is, for the trail's reveal.
    private var playbackProgress: Double {
        guard let playback, playback.duration > 0 else { return 0 }
        return playhead / playback.duration
    }

    /// The console's address, when what was typed can be one.
    private var consoleURL: URL? {
        let host = consoleHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !host.contains("/"), !host.contains(" ") else { return nil }
        return URL(string: DriveVenue.consoleAt(host))
    }

    /// The joints of the group being posed.
    private var poseGroupJoints: Set<Int> {
        Set(JointGroup.all.first { $0.title == poseGroup }?.joints ?? [])
    }

    /// The handles for the pose being built. EMPTY WHEN NOBODY IS POSING, so
    /// the stage draws no targets over a duck somebody is driving.
    private var poseHandles: [JointHandles.Handle] {
        // NO HANDLES ON A MIMICKED POSE: the camera is moving the joints, and
        // a handle on a joint that moves under the finger is a handle that
        // cannot be grabbed.
        guard let posed, !mimicking else { return [] }
        return JointHandles.handles(at: posed).filter { poseGroupJoints.contains($0.joint) }
    }

    /// The world picker's own entries as rows, so the sheet decides nothing
    /// about which worlds exist.
    private var sceneRows: [ControlSceneRow] {
        worldEntries.enumerated().map { slot, entry in
            ControlSceneRow(slot: slot, label: entry.label,
                            isStanding: entry.choice == standingChoice)
        }
    }

    /// Studio's motions, each with the room it will lay for a run. The room is
    /// the motion's own scene — a batch run lays its own world and leaves the
    /// driven one standing, which is what `ControlShelf.runsInItsOwnRoom` says.
    private var motionRows: [ControlMotionRow] {
        drafts.drafts.map { draft in
            let room = draft.sceneID.flatMap { id in scenes.scenes.first { $0.id == id } }
            return ControlMotionRow(
                id: draft.id, name: draft.name,
                room: room.map { ControlShelf.authoredIn($0.name) } ?? ControlShelf.authoredAnywhere)
        }
    }

    /// Run one of Studio's motions on this bench.
    ///
    /// IT STOPS THE DRIVE LOOP FIRST AND SAYS SO BEFOREHAND. A motion is a
    /// track of joint angles, `/perform` and `/climb` are batch calls, and the
    /// live lane carries a velocity twist and nothing else — so there is no
    /// arrangement in which this is a steering command. The route is
    /// `BenchRoute.of`, the same decision the pipeline screen's Run takes, so a
    /// challenge room goes to the harness and everything else lays its own
    /// world; and the outcome is the kit's own sentence about what happened.
    @MainActor private func runMotion(_ id: UUID) async {
        guard runningMotion == nil, let draft = drafts.drafts.first(where: { $0.id == id })
        else { return }
        runningMotion = id.uuidString
        motionOutcome = nil
        // AND THE STICKS COME BACK, because that is what the screen promised
        // before the press. Driving stops for the batch call — there is no
        // arrangement in which a track of joint angles and a velocity twist
        // share the wire — and it starts again afterwards if it was on, which
        // is the half that was missing and read as the Drive button resetting
        // itself.
        let wasDriving = running
        defer { runningMotion = nil }
        flight?.cancel()
        if running { await halt() }
        do {
            let address = try requireBench()
            let scene = draft.sceneID.flatMap { held in scenes.scenes.first { $0.id == held } }
            switch BenchRoute.of(draft: draft, scene: scene,
                                 graspables: health?.graspables ?? []) {
            case .climb(let rise, let cell, let intent, _):
                let call = try DuckBench.climb(address, intent: intent, rise: rise, cell: cell,
                                           clip: true)
                let data = try await askForABatch(call)
                let cellOutcome = Pipeline.CellOutcome(try DuckBench.readClimbed(data),
                                                       when: Date())
                motionOutcome = [StairsChallenge.scoredWhereItIsScored, cellOutcome.told,
                                 StairsChallenge.oneCellIsNotAScore,
                                 ControlShelf.thisIsTheRun].joined(separator: " ")
                await watch(try DuckBench.readClimbedClip(data, named: draft.name))
            case .perform(let standing, let because):
                let call = try DuckBench.perform(address, keys: draft.benchTrack,
                                                 seconds: draft.duration + 0.5, rollouts: 1,
                                                 world: standing?.plan, spawn: standing?.spawn)
                let data = try await askForABatch(call)
                let outcome = try DuckBench.readOutcome(data, when: Date(),
                                                        askedForWorld: standing?.plan != nil)
                motionOutcome = [outcome.told, because, ControlShelf.thisIsTheRun]
                    .compactMap { $0 }.joined(separator: " ")
                await watch(try? DuckBench.readPerformedClip(data, named: draft.name,
                                                             laid: outcome.laid))
            case .notYet(let blocked):
                motionOutcome = blocked.message
            }
            Haptic.behaviourStarted()
        } catch let refusal as DuckBench.Refusal {
            motionOutcome = refusal.message
        } catch let error as DuckBench.ReadError {
            motionOutcome = error.message
        } catch {
            motionOutcome = error.localizedDescription
        }
        // AND SOMEBODY CAN READ IT. `motionOutcome` is drawn in ONE place, the
        // Motions sheet — so every one of these sentences written for a press
        // on a pad button went into a variable nothing renders. A refusal, a
        // route that answered not-yet, a clip that would not read: all silent,
        // on a screen whose whole contract is that a control that does nothing
        // says why. The HUD line is where the buttons already report themselves.
        if let motionOutcome { lastAction = motionOutcome }
        // AND THE STICKS COME BACK, after the run has been watched rather than
        // before it: resuming the loop mid-playback would put the live duck's
        // answers underneath a clip of the other one.
        if wasDriving { engageLoop() }
    }

    /// Play a clip the bench sent back, on the picture, at the rate it was
    /// recorded — then give the picture back to the live duck.
    @MainActor private func watch(_ clip: DuckIntentClip?) async {
        guard let clip, clip.duration > 0 else { return }
        playback = clip
        playhead = 0
        lastAction = ControlShelf.watching(clip.name)
        // THE CAMERA STANDS STILL FOR A RUN, AND THIS IS THE WHOLE BUG.
        //
        // This tab drives with the camera ON the trunk, which is right while
        // somebody is steering — `OrbitState.following` says why, and it is the
        // default here. Play a recorded clip under that same camera and the
        // camera moves exactly as far as the duck does, so it SUBTRACTS the
        // travel: a roll that carries the body half a metre is drawn as a body
        // rolling on the spot. The bench was answering the same seventy-five
        // frames to both tabs the whole time; the editor's player looked right
        // because it opens a fresh, FIXED camera every time it appears.
        //
        // `focus` IS THE SEAM, NOT `follows`. Following is the person's
        // setting and it has to come back exactly as they left it. `DuckStage`
        // already lets an explicit focus beat both — "the one that was worked
        // out for a purpose rather than derived from whatever happens to be in
        // the scene" — so naming the middle of THIS run for as long as it is on
        // screen changes the picture without touching the preference.
        let cameraWas = (focus: orbit.focus, distance: orbit.distance)
        //
        // IN THE CAMERA'S FRAME, NOT THE BENCH'S. The bench is z-up and
        // RealityKit is y-up, and `StagePose.position` — the very thing the
        // following camera aims at — is the one place that conversion is
        // written down. Handing the kit raw bench roots would frame the run
        // with its height and its depth swapped, which on a walk is a camera
        // that stands back for the wrong axis and on a climb is one that does
        // not stand back at all.
        if let framed = StageCamera.framing(forRun: clip.roots.map {
                                                (x: $0.x, y: $0.z, z: -$0.y) },
                                            on: stageGlass,
                                            within: orbit.limits) {
            orbit.focus = SIMD3(Float(framed.x), Float(framed.y), Float(framed.z))
            orbit.distance = Float(framed.distance)
        }
        defer {
            orbit.focus = cameraWas.focus
            orbit.distance = cameraWas.distance
            // AND THE RANGE IS WORKED OUT AGAIN, because `refitCamera` stood
            // down for the whole clip and the readout may have changed height
            // under it while it did.
            refitCamera()
        }
        // THE WALL CLOCK, NOT A COUNT OF SLEEPS. Adding a step per iteration
        // makes the playback as slow as the sleeps actually are — every one
        // overshoots a little, and fifty of them a second turn a two-second
        // motion into three. Reading the clock instead means a frame that is
        // late is skipped rather than shifting everything after it, which is
        // what the editor's own transport does.
        let started = Date()
        while true {
            let elapsed = Date().timeIntervalSince(started)
            if elapsed >= clip.duration || Task.isCancelled { break }
            playhead = elapsed
            try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / max(clip.hz, 1)))
        }
        // THE LAST FRAME IS DRAWN. Ending on whatever the clock said leaves the
        // duck a frame or two short of the pose the motion finished in, which
        // on a motion that ends standing is the difference between "it worked"
        // and "it nearly worked".
        playhead = clip.duration
        // LONG ENOUGH TO READ THE POSE IT FINISHED IN. 120 ms was a blink: the
        // last frame appeared and the picture was already back on the live
        // duck, which stands where it did before the press because the motion
        // ran beside it. Unannounced, that jump reads as the run being undone.
        try? await Task.sleep(nanoseconds: UInt64(DriveMetric.holdLastFrameSeconds * 1e9))
        // AND NO `/state` READ HERE, DELIBERATELY. The obvious reading of the
        // jump back is that `live` is stale — it was last written before the
        // batch call — so the obvious fix is to read the bench again on the way
        // out. It would change nothing and cost a round trip: `/perform` builds
        // its OWN `MjData` (duckbench-core.mjs, `const data = new mj.MjData`),
        // so the duck you drive genuinely did not move and a fresh read returns
        // the same stance. The picture is not wrong when it goes back; it is
        // going back to the other duck, which is the one this tab drives. What
        // was missing was the hold above and a sentence saying so, and the run's
        // own report — which ends on `ControlShelf.thisIsTheRun` — now reaches
        // the screen instead of a variable nothing renders.
        playback = nil
        playhead = 0
        // AND NOTHING IS SAID HERE. Every caller of this already ends on a
        // sentence containing `ControlShelf.thisIsTheRun` — "a motion runs
        // beside the duck you drive rather than on it, so the live duck stayed
        // where it was" — which is the same fact said better and said last. A
        // line written here would be overwritten by that one in the same actor
        // hop and never reach the glass anyway.
    }

    /// One batch call, with the deadline a bench running physics needs. The
    /// drive loop's own requests keep their per-request deadline; this is the
    /// one door on this screen that waits for seconds of physics.
    private func askForABatch(_ call: DuckBench.Call) async throws -> Data {
        var request = DuckBench.urlRequest(for: call, token: token)
        request.timeoutInterval = DriveMetric.motionSeconds
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    /// The glass and the chrome standing on it, as the kit's types.
    private var stageGlass: StageViewport.Glass {
        StageViewport.Glass(widthPoints: Double(glass.width),
                            heightPoints: Double(glass.height))
    }

    /// The chrome the CAMERA has to clear. The drawer is deliberately not in it:
    /// it is a cover somebody opened, `StageViewport.drawerCostSaid` says so,
    /// and no camera distance undoes it — `StageViewport.canClear` answers false
    /// for that footprint and `nearestDistance` would hand back the far stop.
    /// Pushing the camera to four metres because a list is up would be the app
    /// moving for a reason nobody asked for.
    private var stageChrome: StageViewport.Chrome {
        StageViewport.Chrome.column.over(top: Double(topChromeHeight + notesHeight),
                                         bottom: Double(padChromeHeight))
    }

    /// Narrow the zoom range to what this picture can hold.
    ///
    /// ONLY WHILE THE CAMERA FOLLOWS, AND THAT IS AN HONESTY RULE RATHER THAN A
    /// SHORTCUT. A fitted near stop is a claim about where the robot is drawn,
    /// and the kit works it out from the duck's offset FROM THE AIM POINT.
    /// Following, the aim point is the trunk and the offset is nothing, which is
    /// a measurement. Fixed, the aim point is the scene's bounding box and the
    /// offset is whatever the bench's world happens to be — a number nobody here
    /// has measured — so the stage keeps the plain range instead of a fitted one
    /// derived from a guess.
    @MainActor private func refitCamera() {
        // NOT WHILE A RUN IS ON THE PICTURE. `watch` works out where the camera
        // has to stand for the whole clip to be visible and then holds it there
        // — and `orbit.fit` does not merely read the range, it REASSIGNS it and
        // re-clamps `distance` to the new one. The trigger is live rather than
        // theoretical: `watch`'s own first line writes `lastAction`, which
        // changes the readout's height, which fires the `notesHeight` change
        // below, which lands here in the middle of the clip and pulls the
        // camera back in. The framing is restored to the person's own when the
        // clip ends, and this runs again then.
        guard playback == nil else { return }
        guard glass.width > 0, glass.height > 0 else { return }
        guard orbit.follows else {
            orbit.limits = .stage
            return
        }
        orbit.fit(to: stageGlass, chrome: stageChrome)
    }

    /// The strip along the top: where you are driving, and what that means.
    ///
    /// THE CAPTION IS COLLAPSED TO A DISCLOSURE, because `DriveVenue.oneLine` is
    /// three lines of prose on a phone and it would eat the top third of the
    /// picture to say something that does not change while you drive. The
    /// refusal from the camera door is NOT collapsed: a venue that cannot be
    /// entered has to say so where the control is.
    private var topChrome: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            // THE CONTROLLER'S TOP: the duck pill, Drive | Tell | Auto, and the solid red Stop.
            ControllerTopBar(mode: modeBinding, pill: duckPill, stop: { stopNow() })
            // DRIVE'S OWN ROW: pose, scene, record, sequences and plans from the pad, and the head
            // on a real duck. Simple no longer hides any of it: these are part of the toy.
            if arbiter.mode == .drive {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.spacing(.tight)) {
                        if venue == .real {
                            Toggle(isOn: $posingHead) {
                                Label(ControllerWords.headMode, systemImage: "eyes")
                            }
                            .toggleStyle(.button)
                            .font(.footnote)
                            .accessibilityHint(Text(ControllerWords.headModeHint))
                        }
                        // POSE ON THE PRACTICE DUCK, and the take being recorded. Scene,
                        // Record, the pad map and the camera went down into More; sequences,
                        // motions and Plan into the pull-up Moves sheet.
                        if venue != .real {
                            playChip(ControlShelf.poseChip, symbol: "hand.draw",
                                     on: posed != nil && !mimicking) {
                                if mimicking { stopMimic() }
                                if posed == nil {
                                    posed = pose.jointAngles
                                    poseNote = nil
                                } else {
                                    posed = nil
                                    posedJoint = nil
                                }
                            }
                        }
                        if desk.pilot.isRecording || desk.pilot.pending != nil {
                            playChip(PadPilot.nameItChip, symbol: "record.circle", on: true) {
                                if desk.pilot.isRecording { desk.pilot.cutOff(.tapped) } else { shelf = .keep }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.spacing(.hairline))
                }
            }
            // ONE ONE-TIME COACH MARK, a collapsed chip, only in Drive and only with no other line.
            if caption == nil, !stickGate.waitingForLift, somethingToDrive, posed == nil, !mimicking,
               let mark = Onboarding.CoachMarks(done: coachDone).showing(in: arbiter.mode) {
                Button { coach(mark) } label: {
                    Label(mark.says, systemImage: mark.symbol)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .lineLimit(2)
                }
                .buttonStyle(.pondChip)
                .accessibilityHint(Text(Onboarding.CoachMarks.dismissHint))
                .transition(.opacity)
            }
            // IN TELL AND AUTO THE PANEL CARRIES THE LINE, so a refusal sits beside what was asked.
            if let line = (arbiter.mode == .drive ? caption?.text : nil)
                ?? (stickGate.waitingForLift ? ControllerWords.liftToDrive : nil) {
                Text(line)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.spacing(.snug))
                    .padding(.vertical, Theme.spacing(.hairline))
                    .background(Theme.surfacePrimary, in: Capsule())
                    .shadow(color: PondShadow.colour, radius: PondShadow.blur, y: PondShadow.y)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // A FALLEN PRACTICE DUCK GETS ITS WAY BACK UP RIGHT HERE, one small button.
            if venue != .real, bench != nil, live.map({ !$0.upright }) == true {
                Button { flight = Task { await putBack() } } label: {
                    Label(ControllerWords.putBack, systemImage: "figure.stand")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.pondChip)
                .accessibilityHint(Text(ControllerWords.fellOver))
            }
            if let refusal = cameraDoor.refusal(for: .venue), venue != .real {
                Text(refusal)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, Theme.spacing(.tight))
        .measuringChromeHeight { topChromeHeight = $0 }
    }

    /// A Stop pressed somewhere other than Play (a sheet's pill, Moves): put Play's loop down
    /// too, so the next intent does not undo the robot.stop the pill already wrote.
    @MainActor private func stoppedElsewhere() {
        // BEFORE THE GUARD. A plan on its way is not Play's loop, and the Stop that came from Siri
        // or a sheet has already cancelled it; only the panel's own state is left to clear.
        ask.cancelPreview()
        guard running else { return }
        _ = arbiter.handle(.stop, at: Date())
        desk.pilot.cutOff(.stop)
        running = false
        touchSticks = .centred
        if let flight, !flight.isCancelled { cutOffByStop = true }
        flight?.cancel()
    }

    /// The stage with the controller's lifecycle on it: the duck Stop goes to, the real duck's
    /// picture, the stick gate, goals as arbiter runs, the foreground rule and routes into Play.
    /// Split out of `body` so the type checker can see it in one piece.
    private var stageWithController: some View {
        controlStage
        // A STOP PRESSED ON A SHEET OVER PLAY reaches this loop too, and the pill shows while it runs.
        .onChange(of: running) { _, now in runs.playIsDriving = now }
        // AN ORDER FROM OUTSIDE PLAY IS AN ARBITER RUN (build 93): Siri, a Shortcut and a Moves tile
        // used to skip the cap and Take over. `DuckRuns` has already stopped whatever ran and
        // re-opened the latch for the person who asked, so only the bookkeeping happens here.
        .onChange(of: runs.outsideOrder) { _, now in outsideOrderChanged(now) }
        .onChange(of: runs.stops) { _, _ in stoppedElsewhere() }
        // THE DUCK STOP GOES TO, AND THE ONE THE MOVES TILES RUN ON: whichever Play is on.
        .task(id: "\(venue.rawValue)|\(robotLinkKey)|\(peerKey)|\(benchPeer == nil)") {
            runs.attach(peer, kind: venue == .real ? .real : .sim)
        }
        // THE REAL DUCK'S PICTURE, from the address the connection gives. Started only on that
        // venue, so the camera is not polled for a screen nobody is looking at.
        .task(id: "\(venue.rawValue)|\(robot.isConnected)|\(robot.host)|\(cameraAddress)") {
            let typed = cameraAddress.isEmpty ? robot.host : cameraAddress
            if venue == .real, robot.isConnected, let address = DuckCamera.Address(typed) {
                realFeed.start(address)
            } else {
                realFeed.stop()
            }
        }
        // AFTER A VENUE SWITCH THE STICK WAITS FOR THE FINGER TO LIFT.
        .onChange(of: rawSticks) { _, now in _ = stickGate.admits(centred: now == .centred) }
        // THE CAPTION GOES AWAY ON ITS OWN, unless a newer one replaced it first.
        .task(id: caption) {
            guard let shown = caption else { return }
            let wait = shown.hidesAt.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            if !Task.isCancelled, caption == shown { caption = nil }
        }
        // A GOAL RUNNING IS AN ARBITER RUN, so a stick touch takes over and the cap applies.
        .onChange(of: dreamModel.running) { _, now in
            let duck: DuckIdentity.Kind = venue == .real ? .real : .sim
            if now {
                // THE GOAL HAS ALREADY MADE WAY (`DuckRuns.makeWay`). What was booked before it is
                // forgotten quietly: stopping it here would stop the goal that just started.
                if arbiter.running != nil { _ = arbiter.handle(.stop, at: Date()) }
                // A WALK STAYS ON TELL: it is a skill from there, and `.goal` would move the switch.
                apply(arbiter.handle(.start(dreamModel.walking ? .walk : .goal, duck: duck, owner: .app), at: Date()))
            } else {
                finishRun(arbiter.running?.kind == .walk ? .walk : .goal)
                // "You took over." and the cap's line stay; the card keeps the run's own line.
                if !arbiter.saidItsOwnEnding, let walked = dreamModel.lastWalk { say(walked) }
            }
        }
        // THE CAP IS CHECKED WHILE ANY GOAL RUNS: Dream-1 or an Ask the duck plan.
        .task(id: arbiter.running != nil) {
            while arbiter.running != nil, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                apply(arbiter.handle(.tick, at: Date()))
            }
        }
        // LEAVING THE FOREGROUND ENDS RUNS. The app's root stops every registered run; here the
        // stick loop is put down too, and the arbiter remembers that nothing re-arms itself.
        .onChange(of: scenePhase) { _, phase in
            // A THUMB THE SYSTEM TOOK AWAY IS NOT THE NEXT COMMAND: a pulled-down shade or a call
            // can end the touch with no `onEnded`. `onChange(of: sticks)` then lets a real duck go.
            if phase != .active { touchSticks = .centred }
            if phase == .background {
                ask.cancelPreview()
                _ = arbiter.handle(.background, at: Date())
                if dreamModel.running { dreamModel.stop() }
                // A STICK DRIVE IS NOT A REGISTERED RUN, so the root's leftForeground() does not
                // stop it, and cancelling the loop sends nothing: the duck would keep the last
                // twist. The shared stop puts robot.stop on its way first.
                if running {
                    runs.stop()
                    running = false; touchSticks = .centred; flight?.cancel()
                }
            } else if phase == .active {
                _ = arbiter.handle(.foreground, at: Date())
            }
        }
        // A ROUTE INTO PLAY: a mode another screen asked for (Moves' goal rows).
        .onChange(of: router.pendingPlay) { _, asked in takePendingPlay(asked) }
        .onAppear { takePendingPlay(router.pendingPlay) }
        // THE FIRST WALK ON A REAL DUCK ASKS FIRST, in the kit's words. A dialog, not a sheet: nothing
        // runs yet, so there is nothing for a Stop pill to stop. No destructive role, because that
        // draws the button red, and red is Stop and nothing else.
        .confirmationDialog(BallWalk.Words.confirmTitle, isPresented: $confirmingWalk, titleVisibility: .visible) {
            Button(BallWalk.Words.confirmStart) {
                walkConfirmed = drivers.release.folder
                startRealWalk()
            }
            Button(DriverCard.Words.cancel, role: .cancel) {}
        } message: {
            Text(BallWalk.Words.confirmLine(arbiter.caps.seconds(on: .real)))
        }
        .sheet(isPresented: $realDream) {
            NavigationStack {
                ScrollView {
                    DreamPanel(peer: robot.peer, source: realFeed,
                               bridgeAnswersDream: robot.greeting?.answersDream == true,
                               stopDriving: { await stepAside() }, model: dreamModel, recorder: dreamRecorder,
                               hasPicture: realFeed.picture != nil)
                        .padding()
                }
                .navigationTitle(AutoGoal.dream.title)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button(ControllerWords.done) { realDream = false } }
                }
            }
            .stopPill()
        }
    }

    // MARK: - the controller's pieces

    /// The switch, through the arbiter: leaving a mode with something running in it stops it.
    private var modeBinding: Binding<ControlArbiter.Mode> {
        Binding(get: { arbiter.mode },
                set: { next in
                    // A NEW MODE STARTS CLEAN: no line from the last one, no mic left open, no
                    // plan thought about or waiting to start, and no stick: the pads leave the
                    // glass with the mode, and `ThumbPad` cannot recentre a thumb it no longer
                    // has. The same rule as `drawerIsUp`; `onChange(of: sticks)` lets a real duck go.
                    say(nil)
                    listener.cancel()
                    ask.cancelPreview()
                    touchSticks = .centred
                    apply(arbiter.handle(.selectMode(next), at: Date()))
                })
    }

    private var duckPill: DuckPill {
        DuckPill(name: venue == .real ? (robot.isConnected ? ControllerWords.yourDuck : ControllerWords.connectYourDuck)
                                      : DuckPill.name(of: venue),
                 live: pillLive,
                 venues: DriveVenue.allCases.filter { $0.canBeEntered(camera: cameraDoor) },
                 current: venue,
                 pick: choose,
                 details: { router.duckSheet = true },
                 putBack: venue == .sim && bench != nil ? { flight = Task { await putBack() } } : nil)
    }

    /// The live dot: the last thing asked was answered, is being waited on, or nothing is there.
    private var pillLive: LensIndicator.Connection {
        if venue == .real { return robot.isConnected ? .connected : .asleep }
        return linkState
    }

    /// THE EXPLICIT VENUE SWITCH, from the duck pill. The stick zeroes and ignores input until
    /// the finger lifts, and a chip says which duck is now being driven.
    @MainActor private func choose(_ next: DriveVenue) { choose(next, cause: .duckPill) }

    /// THE ONE PLACE THE VENUE IS SWITCHED BY A PERSON. `VenueRule` says whether the cause may
    /// switch it (only the pill, the Duck sheet and onboarding can) and closes the stick gate when
    /// it does; the stick is zeroed and a chip names the duck now being driven.
    @MainActor private func choose(_ next: DriveVenue, cause: VenueRule.Cause) {
        let allowed = next.canBeEntered(camera: cameraDoor) ? next : venue
        let outcome = VenueRule.request(allowed, from: venue, cause: cause, gate: &stickGate)
        guard outcome.switched else { return }
        touchSticks = .centred
        venue = outcome.venue
        say(ControllerWords.nowDriving(DuckPill.name(of: outcome.venue)))
    }

    @MainActor private func takePendingPlay(_ asked: PlayRoute?) {
        guard let asked else { return }
        router.pendingPlay = nil
        let mode: ControlArbiter.Mode
        switch asked {
        case .drive: mode = .drive
        case .tell: mode = .tell
        case .auto: mode = .auto
        case .duckSheet: router.duckSheet = true; return
        case .venue(let next, let cause): choose(next, cause: cause); return
        case .sequence(let id):
            desk.reloadShelf()
            lastAction = desk.play(id, thenLoading: nil, among: health?.policies ?? [], face: "")
            if desk.pilot.isPlaying { engageLoop() }
            return
        }
        apply(arbiter.handle(.selectMode(mode), at: Date()))
    }

    /// Carry out what the arbiter decided, in order.
    @MainActor private func apply(_ decision: ControlArbiter.Decision) {
        for effect in decision.effects {
            switch effect {
            case .stopPath:
                runs.stop()
                if dreamModel.running { dreamModel.stop() }
            case .rearm: runs.path.rearm()
            case .setMode: break
            case .caption(let line): say(line)
            case .endLiveActivity: break
            }
        }
    }

    /// A coach mark is done, for good.
    @MainActor private func coach(_ mark: Onboarding.CoachMarks.Mark) {
        var marks = Onboarding.CoachMarks(done: coachDone)
        guard !marks.isDone(mark) else { return }
        marks.did(mark)
        coachDone = marks.done
    }

    /// Put one line under the controller, or clear it. The line goes away on its own.
    @MainActor private func say(_ line: String?) {
        caption = line.map { CaptionLine($0, at: Date()) }
    }

    /// The kind of duck Play is on, or nil when there is none to drive.
    private var duckKind: DuckIdentity.Kind? {
        peer == nil ? nil : (venue == .real ? .real : .sim)
    }

    /// Whether Dream-1 can run: a key on this phone, or a bridge that holds one.
    private var dreamReady: Bool {
        DreamKeyStore.load() != nil || (venue == .real && robot.greeting?.answersDream == true)
    }

    /// Tell: a sentence or a tile, read with no model, run by the kit's runner on this duck.
    @MainActor private func tell(_ text: String) {
        // WALK TO THE BALL IS A SKILL, NOT AN ORDER: its own start, its own refusals, and the same
        // Stop. Read here and not in the matcher, so Ask the duck and Siri mean what they meant.
        if BallWalk.heard(text) { walkToBall(); return }
        guard let order = DuckOrderMatcher.match(text, skills: Array(RobotPlan.skillSeconds.keys)) else {
            say(ControllerWords.heard(text))
            return
        }
        if order == .stop { stopNow(); return }
        guard peer != nil else { say(ControllerWords.tellNoDuck); return }
        // SAID BEFORE ANYTHING IS SENT: an order this duck cannot do is refused in a sentence.
        if let duck = duckKind, let why = order.notOn(duck) { say(why); return }
        // THE STICK LOOP STEPS ASIDE: a Tell order and the stick never write the duck at once.
        if running { running = false; flight?.cancel() }
        let duck: DuckIdentity.Kind = venue == .real ? .real : .sim
        let decision = arbiter.handle(.start(.tell, duck: duck, owner: .app), at: Date())
        apply(decision)
        // THE ARBITER CAN REFUSE (off screen). A refusal is the end of it, not a line to ignore.
        guard decision.passInput else { return }
        say(ControllerWords.tellRunning)
        telling = true
        Task {
            let watcher = Task { @MainActor in
                while !Task.isCancelled {
                    if let bench = benchPeer, venue != .real { live = await bench.live }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            // DuckRuns asks the duck how it stands first (the practice duck's answer is fixed).
            _ = await runs.run(order)
            watcher.cancel()
            telling = false
            if !arbiter.saidItsOwnEnding { say(runs.caption) }
            finishRun(.tell)
        }
    }

    /// Ask the duck: plan from a sentence (matcher first, then on-device Apple Intelligence), show
    /// the plan for a beat with Cancel, then run it as one Auto run.
    @MainActor private func askPlan(_ text: String) {
        if StopWords.containsStop(text) { stopNow(); return }
        guard let duck = duckKind else { say(ControllerWords.tellNoDuck); return }
        say(nil)
        ask.begin(asking: {
            switch await ask.plan(text, on: duck, skills: nil) {
            case .said(let why):
                if !Task.isCancelled { say(why) }
                return nil
            case .plan(let orders):
                return orders
            }
        }, then: { orders in runAutoPlan(orders, said: text) })
    }

    /// A "Try saying" sentence: read with no model, shown for a beat with Cancel, then run as one
    /// Auto run, exactly like a planned sentence.
    @MainActor private func tryExample(_ text: String) {
        guard let duck = duckKind else { say(ControllerWords.tellNoDuck); return }
        guard let orders = DuckDecider.Words.examplePlan(text, on: duck,
                                                          skills: Array(RobotPlan.skillSeconds.keys)) else {
            say(ControllerWords.heard(text)); return
        }
        say(nil)
        ask.begin(asking: { orders }, then: { orders in runAutoPlan(orders, said: text) })
    }

    /// Run a planned list of orders as an Auto goal: a stick, the pad or Take over ends it, and the
    /// red disc stops it. The cap lives with the run as well as with the arbiter, whose tick ends
    /// when Play leaves the screen.
    @MainActor private func runAutoPlan(_ orders: [DuckOrder], said: String) {
        guard peer != nil else { ask.ended(); say(ControllerWords.tellNoDuck); return }
        if running { running = false; flight?.cancel() }
        let duck: DuckIdentity.Kind = venue == .real ? .real : .sim
        let decision = arbiter.handle(.start(.goal, duck: duck, owner: .app), at: Date())
        apply(decision)
        // THE ARBITER CAN REFUSE (off screen). `runPlan` would re-open the latch and drive.
        guard decision.passInput else { ask.ended(); return }
        autoWhat = said
        autoStarted = Date()
        Task {
            let watcher = Task { @MainActor in
                while !Task.isCancelled {
                    if let bench = benchPeer, venue != .real { live = await bench.live }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            let caps = arbiter.caps
            let ended = await caps.enforce(on: duck, stop: { runs.stop() }) {
                await runs.runPlan(orders) { i in ask.running(step: i, of: orders) }
            }
            if ended.capped { runs.say(ControlArbiter.Words.capped(caps.seconds(on: duck))) }
            watcher.cancel()
            ask.runEnded()
            autoWhat = nil
            autoStarted = nil
            if !arbiter.saidItsOwnEnding { say(runs.caption) }
            finishRun(.goal)
        }
    }

    /// A run of this kind ended on its own. WHAT IS BOOKED NOW MAY BE NEWER: a Siri order stops a
    /// Tell run and books itself before the Tell task gets here, and that finish must not end the
    /// order's booking, or Take over would stop covering it.
    @MainActor private func finishRun(_ kind: ControlArbiter.RunKind) {
        guard arbiter.running?.kind == kind else { return }
        apply(arbiter.handle(.finished, at: Date()))
    }

    /// The one status line while an Auto run, a walk or an outside order goes, so Take over shows
    /// for each of them, in Auto and in Tell.
    private var runStatus: String? {
        guard let kind = arbiter.running?.kind, kind == .goal || kind == .order || kind == .walk else { return nil }
        let what = (kind == .order ? runs.outsideOrder?.what : nil) ?? autoWhat
            ?? (dreamModel.walking ? BallWalk.title
                : dreamModel.running ? AutoGoal.dream.title : AutoGoal.Words.running)
        let started = autoStarted ?? arbiter.running?.startedAt ?? Date()
        let cap = arbiter.caps.seconds(on: venue == .real ? .real : .sim)
        let stepLine = ask.phase.activeStep.map { i -> String in
            if case .running(_, let orders) = ask.phase {
                return DuckDecider.Words.step(i + 1, of: orders.count) + ": "
            }
            return ""
        } ?? ""
        return stepLine + ControllerWords.autoRunning(what, elapsed: Date().timeIntervalSince(started), cap: cap)
    }

    @MainActor private func outsideOrderChanged(_ now: DuckRuns.OutsideOrder?) {
        guard let now else {
            finishRun(.order)
            return
        }
        // WHATEVER THIS SCREEN HAD RUNNING WAS ALREADY STOPPED by `DuckRuns`; forget it quietly so
        // the start below does not stop the new order too.
        ask.cancelPreview()
        if arbiter.running != nil { _ = arbiter.handle(.stop, at: Date()) }
        if running { running = false; stickStarted = false; touchSticks = .centred; flight?.cancel() }
        // AN INTENT CAN ARRIVE A BEAT BEFORE THE SCENE SAYS IT IS ACTIVE AGAIN; the order is on
        // screen by then (every motion intent opens the app), so the arbiter hears that first.
        if scenePhase != .background { _ = arbiter.handle(.foreground, at: Date()) }
        _ = arbiter.handle(.start(.order, duck: now.duck, owner: now.owner), at: Date())
    }

    /// Take over: the run stops through the arbiter and the switch goes to Drive.
    @MainActor private func takeOver() {
        apply(arbiter.handle(.movePress, at: Date()))
        ask.ended()
    }

    /// Something is taking the duck: the stick loop steps aside and the duck is told to stop.
    ///
    /// NOT `halt()`. That is the person's Stop: it ends every run, and a goal or a plan starting up
    /// is a run, so one that called it cancelled itself before its first step. Whatever else was
    /// running has already gone in `DuckRuns.makeWay`.
    @MainActor private func stepAside() async {
        if running { running = false; touchSticks = .centred; flight?.cancel() }
        if let peer { _ = try? await peer.call(.stop) }
    }

    /// Auto: a helper's button.
    @MainActor private func go(_ goal: AutoGoal) {
        switch goal {
        case .dream:
            guard dreamReady else { router.go(to: .studio(nil)); return }
            if venue == .real { realDream = true } else { shelf = .dream }
        }
    }

    /// Tell: Walk to the ball, from its Go or a sentence. Every refusal is said, in Tell's caption.
    @MainActor private func walkToBall() {
        guard !dreamModel.running, !telling else { return }
        let available = BallWalk.availability(on: duckKind, driverInstalled: drivers.phase.isInstalled)
        if let why = available.reason { say(why); return }
        if duckKind == .real { walkRealDuck() } else { walkPracticeDuck() }
    }

    /// M1's run, on the bench this screen is driving.
    @MainActor private func walkPracticeDuck() {
        if simHeadCamera.unavailable != nil { say(DriverCard.Words.needsNewerSystem); return }
        if let why = BallRunStart.refusal(world: world) { say(why); return }
        guard let bench = (try? requirePeer()) as? BenchPeer else { say(ControllerWords.tellNoDuck); return }
        say(nil)
        dreamModel.walkToBall(bench, feed: simHeadCamera, folder: drivers.folder,
                              stepAside: { await stepAside() }, seen: { live = $0 },
                              walkerOn: {
                                  // THE BENCH CHANGED NETWORKS UNDER THE DESK, as in `swap`: the
                                  // next stick drive must not think the old one is still loaded.
                                  if let id = self.bench?.id { benches.noteLoaded(BallRunStart.walker, on: id) }
                                  desk.noteLoaded(BallRunStart.walker)
                                  stateSaid = nil
                              })
    }

    /// NO BLIND DRIVING: with no picture coming in, it says so and nothing is sent to the duck.
    @MainActor private func walkRealDuck() {
        guard !dreamRecorder.recording else { return }
        guard realFeed.running, realFeed.picture != nil, realFeed.problem == nil else {
            say(realFeed.problem ?? BallWalk.Words.noPicture)
            return
        }
        if BallWalk.needsConfirming(confirmed: walkConfirmed, release: drivers.release) {
            confirmingWalk = true
        } else {
            startRealWalk()
        }
    }

    @MainActor private func startRealWalk() {
        guard let peer else { say(ControllerWords.tellNoDuck); return }
        say(nil)
        dreamModel.walkToBallReal(peer, feed: realFeed, folder: drivers.folder, stepAside: { await stepAside() })
    }

    /// The readout and the floor note, under the top strip at the leading edge.
    ///
    /// UNDER IT AND NOT BESIDE IT. Both used to be `.topLeading` and
    /// `.bottomLeading` of a 300-point card that had nothing else on it. On a
    /// full-bleed stage the top is where the venue switch lives, so the readout
    /// is pushed down by the strip's MEASURED height rather than by a guess, and
    /// the floor note comes with it — the bottom corner it used to take is where
    /// a thumb now rests on a stick.
    private var stageNotes: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasReadout { hud }
            if worldRouteMissing { floorCaption }
        }
        // MEASURED BEFORE THE STRIP'S PADDING IS ADDED, so `notesHeight` is the
        // panel alone and the top footprint is strip + panel, not strip twice.
        .measuringChromeHeight { notesHeight = $0 }
        .padding(.top, topChromeHeight + (venue == .ar ? arHudHeight : 0))
    }

    /// The camera's buttons, bottom-trailing — and NOT on your own floor.
    ///
    /// `DriveVenue.arHasNoZoom` is why, and it is one line inside the AR panel's
    /// already-collapsed disclosure rather than a disabled column drawn here.
    /// A zoom on that venue would either do nothing or scale a duck `arIsNot`
    /// promises is drawn at the size it really is.
    @ViewBuilder private var cameraColumn: some View {
        if venue == .sim {
            StageCameraColumn(orbit: $orbit, showsFollow: true, nearStopIsFitted: orbit.follows)
                .padding(.trailing, Theme.spacing(.snug))
                // ABOVE THE PAD, NOT ON IT. Both this column and the Turn stick
                // are bottom-trailing on the same stage, so the column landed
                // on the stick and half of it was off the edge. The pad's own
                // measured height is what lifts it clear, and it is a number
                // this screen already keeps for the camera.
                .padding(.bottom, padChromeHeight + Theme.spacing(.snug))
        }
    }

    /// The bottom of the picture: the pad, or the drawer that slides over it,
    /// and the handle between them.
    ///
    /// THE HANDLE NEVER MOVES AND IS NEVER THE STOP. Stop is the bar below this,
    /// outside the stage, a `safeAreaInset` that this file does not touch. What
    /// this decides is only whether the sticks or the settings are above it.
    private var bottomChrome: some View {
        VStack(spacing: Theme.spacing(.tight)) {
            if drawerIsUp {
                controls
                    .frame(height: CGFloat(StageViewport.drawerHeight(
                        available: Double(glass.height))))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius(DriveMetric.viewport),
                                                style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius(DriveMetric.viewport),
                                              style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: DriveMetric.hairlineStroke))
                    .transition(.move(edge: .bottom))
            } else if mimicking {
                // THE MIMIC BAR TAKES THE SAME PLACE, for the same reason: a
                // person being copied by the duck is not driving it.
                mimicBar
            } else if posed != nil {
                // THE POSE BAR TAKES THE PAD'S PLACE. A person building a pose
                // is not driving, and two thumb pads under a duck being posed
                // would be two controls for two different jobs in one corner.
                poseBar
            } else {
                // THE PAD AND ITS HANDLE ARE THE CAMERA'S FOOTPRINT. Measured
                // here, on the pair that is present when the drawer is down,
                // so the value simply stays while the drawer is up — no zero is
                // written, and the drawer's own height never reaches the camera.
                VStack(spacing: Theme.spacing(.tight)) {
                    // EACH MODE'S PANEL TAKES THE PAD'S PLACE (build 92), so the duck stays in view
                    // and no card is stacked over the sticks. A physical pad still takes over.
                    switch arbiter.mode {
                    case .tell:
                        // THE LINE KEEPS TIME WHILE A WALK RUNS, as Auto's does.
                        TimelineView(.periodic(from: Date(), by: 1)) { _ in
                            TellPanel(duck: duckKind, caption: caption?.text, busy: telling, listener: listener,
                                      walkCard: DriverCard(phase: drivers.phase, duck: duckKind,
                                                           release: drivers.release,
                                                           cameraMissing: simHeadCamera.unavailable != nil,
                                                           lastRun: dreamModel.lastWalk),
                                      walkAct: { drivers.act($0) { walkToBall() } },
                                      running: runStatus,
                                      takeOver: takeOver,
                                      send: tell, stop: { stopNow() },
                                      shortScreenHeight: CGFloat(StageViewport.drawerHeight(
                                          available: Double(glass.height))))
                        }
                        sheetsRow
                    case .auto:
                        TimelineView(.periodic(from: Date(), by: 1)) { _ in
                            AutoPanel(duck: duckKind,
                                      dreamReady: dreamReady,
                                      ask: ask,
                                      listener: listener,
                                      caption: caption?.text,
                                      running: runStatus,
                                      plan: askPlan,
                                      example: tryExample,
                                      go: go,
                                      takeOver: takeOver,
                                      stop: { stopNow() },
                                      shortScreenHeight: CGFloat(StageViewport.drawerHeight(
                                          available: Double(glass.height))))
                        }
                    case .drive:
                        padDeck(compact: true)
                        sheetsRow
                    }
                }
                .measuringChromeHeight { padChromeHeight = $0 }
            }
            if drawerIsUp { sheetsRow }
        }
        .padding(.horizontal, Theme.spacing(.snug))
        .padding(.bottom, Theme.spacing(.tight))
        .measuringChromeHeight { bottomChromeHeight = $0 }
    }

    /// What a pose can do: which joints the handles are on, hold it on the
    /// bench, keep it in Studio, and put the sticks back.
    private var poseBar: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            HStack(spacing: Theme.spacing(.tight)) {
                Picker(ControlShelf.poseChip, selection: $poseGroup) {
                    ForEach(JointGroup.all) { group in Text(group.title).tag(group.title) }
                }
                .pickerStyle(.menu)
                .tint(Theme.actionInk)
                Spacer(minLength: 0)
                Button(ControlShelf.doneposing) {
                    posed = nil; posedJoint = nil; poseNote = nil; poseRefusal = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.actionInk)
                .frame(minHeight: DesignMetric.minimumTarget)
            }
            // THE JOINT UNDER THE FINGER, OFF THE DUCK. Its name, the angle
            // it is at, and a slider for it: the handle says WHERE, this says
            // WHAT and by HOW MUCH, and neither of them covers the part being
            // moved — which the floating card did, on exactly the joints this
            // mode is most used for.
            if let joint = posedJoint, let posed, posed.indices.contains(joint) {
                jointReadout(joint, angle: posed[joint])
            } else if let poseNote {
                Text(poseNote)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(ControlShelf.posingSaid)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Theme.spacing(.tight)) {
                Button(ControlShelf.holdIt) { Task { await holdThePose() } }
                    .buttonStyle(.primaryAction)
                    .disabled(busy || bench == nil)
                Button(ControlShelf.keepItAsAMotion) { keepThePose() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.actionInk)
                    .frame(minHeight: DesignMetric.minimumTarget)
            }
        }
        .padding(Theme.spacing(.snug))
        .onStageChrome(DriveMetric.viewport.inner)
    }

    /// The focused joint, said and settable: a telemetry row and a slider,
    /// the same pair the editor puts under its stage.
    @ViewBuilder private func jointReadout(_ joint: Int, angle: Double) -> some View {
        let control = JointControl(index: joint)
        let travel = control.lower...max(control.upper, control.lower + DriveMetric.oneDegree)
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            TelemetryRow(label: control.name, value: control.degrees(angle))
                .accessibilityHidden(true)
            Slider(value: Binding(get: { angle },
                                  set: { value in
                                      guard var pose = posed, pose.indices.contains(joint)
                                      else { return }
                                      pose[joint] = value
                                      posed = pose
                                  }),
                   in: travel, step: DriveMetric.oneDegree)
                .tint(Theme.actionInk)
                .accessibilityLabel(Text(control.name))
                .accessibilityValue(Text(control.spoken(at: angle)))
            HStack {
                Text(control.travelLabel.lower)
                Spacer()
                Text(control.travelLabel.upper)
            }
            .font(.caption2)
            .foregroundStyle(Theme.textTertiary)
        }
    }

    /// Take the duck from where it is to the pose, on the bench.
    ///
    /// TWO KEYFRAMES AND NOT ONE: where the duck is now, and the pose. One
    /// keyframe would ask the bench to blend from whatever the settle left,
    /// which is a different move every time it is pressed. This is the same
    /// batch door a motion runs through — `ControlShelf.holdingSaid` says so
    /// beside the button — so it stops driving and puts the sticks back.
    @MainActor private func holdThePose() async {
        guard let posed else { return }
        let now = pose.jointAngles
        var draft = IntentDraft.blank(named: ControlShelf.poseChip)
        draft.keys = [IntentDraft.Key(time: 0, pose: now),
                      IntentDraft.Key(time: DriveMetric.poseSeconds, pose: posed)]
        let wasDriving = running
        busy = true
        defer { busy = false }
        flight?.cancel()
        if running { await halt() }
        do {
            let address = try requireBench()
            let call = try DuckBench.perform(address, keys: draft.benchTrack,
                                             seconds: DriveMetric.poseSeconds + 0.5, rollouts: 1)
            let data = try await askForABatch(call)
            let outcome = try DuckBench.readOutcome(data, when: Date(), askedForWorld: false)
            poseNote = [outcome.told, ControlShelf.thisIsTheRun].joined(separator: " ")
            Haptic.behaviourStarted()
            await watch(try? DuckBench.readPerformedClip(data, named: ControlShelf.poseChip,
                                                         laid: nil))
        } catch let refusal as DuckBench.Refusal {
            poseNote = refusal.message
        } catch let error as DuckBench.ReadError {
            poseNote = error.message
        } catch {
            poseNote = error.localizedDescription
        }
        if wasDriving { engageLoop() }
    }

    // MARK: - mimicking

    /// The bar that replaces the pose bar while the camera is posing the duck.
    private var mimicBar: some View {
        MimicBar(engine: mimic, door: cameraDoor, benchIsHere: bench != nil, busy: busy,
                 keptName: mimicKept?.name, note: poseNote,
                 flip: {
                     mimicPosition = mimicPosition == .front ? .back : .front
                     mimic.useCamera(position: mimicPosition)
                 },
                 hold: { Task { await holdThePose() } },
                 keep: { keepMimic() },
                 runIt: {
                     if let kept = mimicKept { Task { await runMotion(kept.id) } }
                 },
                 openStudio: {
                     stopMimic()
                     router.go(to: .studio, then: .mimic)
                 },
                 done: { stopMimic() })
            .onStageChrome(DriveMetric.viewport.inner)
    }

    /// Start posing the duck from the camera. The pose starts as the live
    /// stance and is overwritten by the first answer.
    @MainActor private func startMimic() {
        mimicking = true
        posed = pose.jointAngles
        posedJoint = nil
        poseNote = nil
        mimicKept = nil
        guard cameraDoor.canOffer(.mimic) else { return }
        mimic.useCamera(position: mimicPosition)
    }

    /// Put the camera down and the sticks back.
    @MainActor private func stopMimic() {
        mimic.stopSource()
        mimic.discardRecording()
        mimicking = false
        mimicKept = nil
        posed = nil
        posedJoint = nil
        poseNote = nil
    }

    /// Keep what was recorded — or, with nothing recorded, the stance the
    /// duck is in right now, the way the pose bar keeps one.
    @MainActor private func keepMimic() {
        let name = MimicTrack.name(.camera, ordinal: drafts.drafts.count + 1)
        if let draft = mimic.track.draft(named: name, provenance: MimicTrack.provenance(.camera)) {
            drafts.save(draft)
            mimicKept = draft
            poseNote = Mimic.kept(name)
            Haptic.behaviourStarted()
            return
        }
        guard let posed else { return }
        var draft = IntentDraft.blank(named: name)
        draft.provenance = MimicTrack.provenance(.camera)
        draft.keys = [IntentDraft.Key(time: 0, pose: pose.jointAngles),
                      IntentDraft.Key(time: DriveMetric.poseSeconds, pose: posed)]
        drafts.save(draft)
        mimicKept = draft
        poseNote = Mimic.kept(name)
        Haptic.behaviourStarted()
    }

    /// Keep the pose as a motion in Studio, where every other motion lives.
    @MainActor private func keepThePose() {
        guard let posed else { return }
        var draft = IntentDraft.blank(named: "\(ControlShelf.poseChip) \(drafts.drafts.count + 1)")
        draft.keys = [IntentDraft.Key(time: 0, pose: pose.jointAngles),
                      IntentDraft.Key(time: DriveMetric.poseSeconds, pose: posed)]
        drafts.save(draft)
        poseNote = ControlShelf.keptAsAMotion(draft.name)
        Haptic.behaviourStarted()
    }

    // MARK: - the two sheets on Play (build 91)

    /// One collapsed chip on the picture. A capsule at the minimum target, never taller.
    private func playChip(_ title: String, symbol: String, on: Bool = false,
                          act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(on ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(on ? Theme.onFill : Theme.textPrimary)
                .padding(.horizontal, Theme.spacing(.snug))
                .frame(minHeight: DesignMetric.minimumTarget)
                .background(on ? Theme.actionTeal : Theme.surfacePrimary, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.outline.opacity(on ? 1 : 0.25),
                                                lineWidth: on ? DesignMetric.outlineStroke : 1))
                .shadow(color: PondShadow.colour, radius: PondShadow.blur, y: PondShadow.y)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(on ? "on" : ""))
    }

    /// Where the drawer handle was: the pull-up Moves sheet and More.
    private var sheetsRow: some View {
        HStack(spacing: Theme.spacing(.tight)) {
            playChip(ControllerWords.movesSheet, symbol: "chevron.up") { shelf = .moves }
                .accessibilityHint(Text(ControllerWords.movesSheetHint))
            playChip(ControllerWords.more, symbol: "ellipsis.circle") { shelf = .more }
                .accessibilityHint(Text(ControllerWords.moreHint))
        }
    }

    /// THE PULL-UP MOVES SHEET: the Moves tab's tiles over the picture, so most runs happen with
    /// the duck in view. Sequences play on this stick loop; motions run on the bench; Plan opens
    /// the editor with this desk.
    private var movesSheet: some View {
        NavigationStack {
            List {
                MoveTileSections()
                Section {
                    if desk.sequences.isEmpty {
                        Text(MoveTileSections.noSequences)
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(desk.sequences) { sequence in
                        Button {
                            shelf = nil
                            lastAction = desk.play(sequence.id, thenLoading: nil,
                                                   among: health?.policies ?? [], face: "")
                            if desk.pilot.isPlaying { engageLoop() }
                        } label: {
                            Label(sequence.name, systemImage: "list.bullet.rectangle")
                                .frame(minHeight: DesignMetric.minimumTarget)
                        }
                        .foregroundStyle(Theme.textPrimary)
                    }
                } header: {
                    SectionHeading(text: MoveTileSections.mySequences)
                }
                .listRowBackground(Theme.surfacePrimary)
                if venue != .real {
                    Section {
                        if motionRows.isEmpty {
                            Text(ControlShelf.noMotionsYet)
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(motionRows) { row in
                            Button {
                                Task { await runMotion(row.id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name).foregroundStyle(Theme.textPrimary)
                                    Text(row.room).font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                .frame(minHeight: DesignMetric.minimumTarget, alignment: .leading)
                            }
                            .disabled(runningMotion != nil)
                        }
                        if let motionOutcome {
                            Text(motionOutcome).font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } header: {
                        SectionHeading(text: ControllerWords.motions)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }
                Section {
                    Button { shelf = .plan } label: {
                        HubRow(PlanEditorWords.studioRow, StudioHubWords.plan, PlanEditorWords.studioRowSymbol)
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
            .navigationTitle(ControllerWords.movesSheet)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ControllerWords.done) { shelf = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { desk.reloadShelf() }
    }

    /// MORE: what used to be chips and a drawer over the picture, one level down.
    private var moreSheet: some View {
        NavigationStack {
            Group {
                if venue == .real {
                    List {
                        Text(ControllerWords.moreRealDuck)
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .listRowBackground(Theme.surfacePrimary)
#if os(iOS)
                        // SIRI AND SHORTCUTS: the phrases Ask the duck quotes, one tap away.
                        ShortcutsLink()
                            .listRowBackground(Theme.surfacePrimary)
#endif
                    }
                    .scrollContentBackground(.hidden)
                } else {
                    controls
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if venue != .real {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.spacing(.tight)) {
                            if venue == .sim {
                                playChip(ControllerWords.moreScene, symbol: "square.stack.3d.up") {
                                    shelf = .scene
                                }
                            }
                            playChip(ControllerWords.moreRecord, symbol: "record.circle") {
                                shelf = nil
                                desk.beginTake(venue: venue)
                                lastAction = PadPilot.recordStartsDriving
                                engageLoop()
                            }
                            .accessibilityHint(Text(ControllerWords.moreRecordLine))
                            // PUT IT BACK ON ITS FEET, where the old bar's Reset went. "Follow the
                            // duck" left this row: the camera rail's own button does that.
                            playChip(ControllerWords.putBack, symbol: "figure.stand") {
                                shelf = nil
                                flight = Task { await putBack() }
                            }
                            .disabled(busy || bench == nil)
                            .accessibilityHint(Text(ControllerWords.putBackHint))
                        }
                        .padding(.horizontal, Theme.spacing(.snug))
                        .padding(.vertical, Theme.spacing(.tight))
                    }
                }
            }
            .background(Theme.backgroundSecondary)
            .navigationTitle(ControllerWords.more)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ControllerWords.done) { shelf = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The handle that brings the settings up over the picture.
    private var drawerHandle: some View {
        Button {
            withAnimation(Theme.motion(reduced: reduceMotion)) { drawerIsUp.toggle() }
        } label: {
            HStack(spacing: Theme.spacing(.tight)) {
                Image(systemName: drawerIsUp ? "chevron.down" : "chevron.up")
                Text(StageViewport.drawerSaid(open: drawerIsUp))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.spacing(.standard))
            .frame(minHeight: DesignMetric.minimumTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onStageChrome()
        .accessibilityLabel(Text(StageViewport.drawerSaid(open: drawerIsUp)))
        .accessibilityHint(Text(StageViewport.drawerCostSaid))
    }

    // MARK: - the duck

    /// The viewport: the 3D stage, and the readout floating on it.
    ///
    /// A CARD, WITH THE READOUT AS A CARD INSIDE IT. The radii are concentric —
    /// `Palette.Radius.group` outside and `.inner` (which is `.card`) within —
    /// so the corner of the panel is drawn at the next step down rather than at
    /// whatever looked right. Two radii chosen independently read as two
    /// stacked rectangles; two radii a step apart read as one machined part.
    /// THE PICTURE, AND NOTHING ELSE IN IT.
    ///
    /// THE READOUT AND THE FLOOR NOTE MOVED OUT AND THE CARD WENT ENTIRELY.
    /// This was a `ZStack` inside a 300-point `.frame(maxHeight:)`, clipped to a
    /// rounded viewport with a hairline round it, because it was one card among
    /// several stacked down the tab. It is the tab now: there is nothing above
    /// or below it for a card edge to separate it from, the readout is an
    /// overlay `controlStage` places under the measured top strip, and the cap
    /// is gone in both directions — including the accessibility branch, whose
    /// whole job was to stop a fixed height clipping a reflowed `TelemetryRow`.
    /// Nothing can clip it now; there is no height to lift.
    private var stage: some View {
        // THE READBACK, NOT THE REQUEST. `world` is what `GET /world`
        // answered, so the blocks on the stage are where the bench's own
        // qpos says they are — at y = 1.305 and 200 mm tall whatever the
        // scene asked for, and, on a bench nobody has given a world to,
        // scattered down a column because fourteen 200 kg bodies do not
        // stay in the stack they boot in. Drawing the request instead
        // would draw a staircase that is not there.
        DuckStage(pose: posedStance,
                  environment: drawnEnvironment,
                  props: drawnProps,
                  // THE PATH THE RUN TOOK, WHILE IT IS TAKING IT. The editor's
                  // player has always drawn this and this tab never did, which
                  // is half of why the same clip read as a smaller motion here:
                  // without the line there is nothing on the picture that
                  // survives a frame, so a duck that has travelled looks like a
                  // duck that is back where it started.
                  trail: playback?.roots ?? [],
                  progress: playbackProgress,
                  orbit: $orbit,
                  handles: poseHandles,
                  onProject: { poseProjections = $0 },
                  rolling: rollingBall,
                  // ZOOM AND RESET ARE REAL BUTTONS HERE, so they come off the
                  // rotor: one control in two places is two places for it to
                  // drift. The four orbit actions stay — nothing replaces those.
                  showsCameraActions: false)
    }

    /// What the stage draws standing in the world, with the ball where the
    /// drive loop last saw it.
    ///
    /// THE BALL IS THE ONE THING THAT MOVES BETWEEN READS. `GET /world` is
    /// asked once per change of world; `/state` comes back on every round trip
    /// and carries the ball's position, because a duck kicking a ball is the
    /// most visible thing a drive does. So the readback supplies the ball's
    /// existence, its mass and its size, and the live answer supplies where it
    /// is. Without this the ball would sit at the place the world put it while
    /// the duck shoved it across the room.
    /// The world's props as read back, with the ball where the world put
    /// it. The ball's live position goes through `rollingBall` instead, so a
    /// ball rolling under a drive does not change this list on every round
    /// trip and rebuild every step and wall with it. A bench without a world
    /// route still reports its ball on every round trip; that ball is drawn
    /// at the floor's origin and then moved by `rollingBall` like any other.
    /// The room the picture is of.
    ///
    /// THE RUN'S OWN ROOM WHILE THE RUN IS ON SCREEN, for the same reason
    /// `posedStance` draws the run's own duck: a clip that laid a staircase and
    /// is then drawn against whatever the bench happened to be standing in when
    /// the tab last read `/world` is a picture of a duck climbing nothing.
    ///
    /// AND ONLY WHEN IT ACTUALLY LAID ONE. A motion with no scene does not lay
    /// a world — it runs in whatever the bench already has — and its clip
    /// records that as a bare floor. Drawing the bare floor there would DELETE
    /// a room that is really standing, so the live reading stays in that case,
    /// which is the honest half of the same rule.
    private var drawnEnvironment: DuckIntentClip.Environment {
        if let playback, playback.environment != .bareFloor { return playback.environment }
        return world?.asEnvironment ?? .bareFloor
    }

    private var drawnProps: [DuckScene.Prop] {
        // A CLIP CARRIES NO STUDIO PROPS, so a run drawn in its own laid room
        // is drawn without the live scene's furniture rather than with somebody
        // else's ball parked in it.
        if playback != nil, drawnEnvironment != world?.asEnvironment { return [] }
        if let world { return world.asProps }
        guard live?.ball != nil else { return [] }
        return [DuckScene.ball(x: 0, y: 0)]
    }

    private var rollingBall: SIMD2<Double>? {
        live?.ball.map { SIMD2($0.x, $0.y) }
    }

    /// A bench without a world route: the floor drawn here is the stage's
    /// own, and the caption says so on the picture, held to two lines so the
    /// duck stays in view.
    private var floorCaption: some View {
        // THE BOX MOVED TO `DesignComponents`, THE PLACEMENT STAYED HERE. A
        // second screen needed the same caption and was about to hand-copy
        // this one. Where it sits is this screen's business, and it changed:
        // it used to take the stage's BOTTOM-LEADING corner, which on a
        // full-bleed picture is where a thumb rests on the Move stick. It hangs
        // under the readout at the leading edge instead, capped at the readout's
        // own width so it cannot run under the camera column.
        StageCaptionBox(text: DuckWorld.floorIsNotAReadback)
            .frame(maxWidth: typeSize.isAccessibilitySize ? nil : DriveMetric.readoutWidth,
                   alignment: .leading)
            .padding(.horizontal, Theme.spacing(.snug))
            .padding(.bottom, Theme.spacing(.tight))
    }

    /// The same drive, drawn on the floor you are standing on.
    ///
    /// THE READOUT COMES WITH IT, AT THE OTHER END OF THE PICTURE. Every chip
    /// under the stage switches an overlay drawn from `live` — the sim clock,
    /// the command, the joints, the link — and none of those stops being true
    /// because the floor is a camera feed. Leaving them behind would make nine
    /// chips into nine controls that change nothing, which is the shape this
    /// app does not ship. `ARDriveStage` keeps the top corner for what is real
    /// and what is not; this takes the bottom one.
    /// THE SAME CHROME OVER THE CAMERA FEED, and no camera column — see
    /// `cameraColumn` and `DriveVenue.arHasNoZoom`. The readout comes with it
    /// through `stageNotes`, for the reason above: every chip switches an
    /// overlay drawn from `live`, and none of those stops being true because the
    /// floor is a camera feed.
    private var arStage: some View {
        // `posedStance`, NOT `pose` — THE SAME DUCK THE SIM VENUE DRAWS. This
        // read the live stance, so a motion pressed while the venue switch was
        // on Floor ran on the bench, played into `playback`, and was drawn by
        // nothing at all: a total no-show rather than a partial one. A person
        // posing a joint here had the same experience.
        ARDriveStage(pose: posedStance, world: world, ball: live?.ball,
                     benchIsThisPhone: bench?.isThisPhone == true,
                     trips: trips, tickMillis: health?.host?.tickMillis,
                     // UNDER THE TOP STRIP, NOT BENEATH IT: the AR panel and
                     // the readout share the leading edge, so the panel is
                     // pushed down by the strip and the readout by both.
                     topInset: topChromeHeight,
                     onHudHeight: { arHudHeight = $0 })
    }

    /// Whether the overlay has anything to say. An empty panel is a rectangle
    /// over the duck for no reason, and this one is opaque.
    private var hasReadout: Bool {
        !layers.isEmpty || lastAction != nil || live.map { !$0.upright } == true
    }

    /// The readout, on a real surface rather than a scrim.
    ///
    /// AN OPAQUE PANEL, AND THAT IS THE ACCESSIBILITY DECISION ON THIS SCREEN.
    /// This used to be black at 35% over a live 3D render, which means the
    /// contrast of every word on it was whatever happened to be behind it that
    /// frame — bright floor, dark duck, two different numbers, neither of them
    /// checked by anything. `Theme.surfacePrimary` is one of the four grounds
    /// `PaletteTests` proves every text token against at 4.5:1, so putting the
    /// panel on it is what makes the provenance colours below legible claims
    /// rather than hopeful ones. It costs a corner of the picture; the duck is
    /// centred and the panel is not.
    private var hud: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            if layers.contains(.telemetry) { telemetry }
            if layers.contains(.command) {
                Text(DuckDrive.says(twist))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.asked)
            }
            if layers.contains(.policy) {
                // NOT MONOSPACED, AND THE RULE IS THE DESIGN SYSTEM'S: if it
                // never changes, it is not telemetry. A policy name sits still
                // for a whole session; tabular figures on it tell the reader to
                // watch something that is not going to move.
                Text(policyLine).font(.caption2).foregroundStyle(Theme.measured)
            }
            if layers.contains(.link) {
                // EVERY LINE HERE IS THE PEER'S ANSWER, NOT THIS SCREEN'S
                // CLAIM. See `linkLines`.
                ForEach(linkLines, id: \.self) { line in
                    Text(line)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if layers.contains(.limits), let live {
                // ONLY THE ONES ABOUT TO CLIP. A list of fourteen joints is
                // a list nobody reads; three joints against their stops is
                // the finding.
                let near = DuckPad.nearLimits(live.stance.jointAngles)
                if near.isEmpty {
                    Text("no joint within 10° of a stop")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(near, id: \.name) { joint in
                        Text(String(format: "%@ %.3f → stop %.3f",
                                    joint.name, joint.angle, joint.limit))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.refused)
                    }
                }
            }
            if layers.contains(.joints), let live {
                // A TEXT STYLE, NOT A POINT SIZE. This was `.system(size: 9)`,
                // which is below anything the platform will let a person choose
                // and deaf to Dynamic Type in both directions — the layer is
                // information, and information that ignores the setting a
                // person made in order to read is not being shown to them.
                Text(jointGrid(live.stance.jointAngles, columns: jointColumns))
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.textTertiary)
            }
            if let lastAction {
                Text(lastAction).font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.amber)
            }
            if let live, !live.upright {
                // NOT AN ERROR, AND NOT HIDDEN EITHER. A duck on its side is
                // the most informative thing this screen produces: it is the
                // policy failing under a command you chose, which is the
                // whole reason to drive one.
                //
                // `Theme.warning`, NOT `Theme.refused`, for exactly that
                // reason — a refusal is the bench saying no, and nothing here
                // said no. Warning and `asked` happen to share a value in this
                // palette; the triangle and the sentence are what separate
                // them, which is the same rule the dots follow.
                Label("On its side — Reset puts it back",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(Theme.warning)
            }
        }
        .padding(Theme.spacing(.snug))
        .background(Theme.surfacePrimary, in: readoutPanel)
        .overlay(readoutPanel.strokeBorder(Theme.separator,
                                           lineWidth: DriveMetric.hairlineStroke))
        // UNCAPPED AT ACCESSIBILITY SIZES, for the reason `stage` gives about
        // its own height: a width chosen so the duck is never behind the panel
        // is the wrong constraint once the panel's job is to hold words
        // somebody has asked to be twice as big. The duck gives up the corner;
        // the numbers stay whole.
        .frame(maxWidth: typeSize.isAccessibilitySize ? nil : DriveMetric.readoutWidth,
               alignment: .leading)
        .padding(Theme.spacing(.snug))
    }

    private var readoutPanel: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(DriveMetric.viewport.inner),
                         style: .continuous)
    }

    /// What the duck is, and the three numbers that say how it is getting on.
    ///
    /// ROWS RATHER THAN ONE FORMATTED LINE. The old readout was a single
    /// `%.2f s sim · %.0f mm · upright · %d trips`, which is four facts in a
    /// string: at an accessibility text size it wrapped into a paragraph, and
    /// to VoiceOver it was one utterance nobody could skip through.
    /// `TelemetryRow` gives each one a label that never changes beside a value
    /// that does, and stacks the pair instead of truncating the number.
    @ViewBuilder private var telemetry: some View {
        // `.render`: the readout is over the viewport, not on a card.
        StateBadge(text: duckWord, state: duckState, ground: .render)
        if let live {
            TelemetryRow(label: "Sim clock",
                         value: String(format: "%.2f", live.t), unit: "s")
            TelemetryRow(label: "Trunk height",
                         value: String(format: "%.0f", live.height * 1000), unit: "mm")
            TelemetryRow(label: "Round trips", value: "\(trips)")
        }
    }

    /// The word beside the dot.
    ///
    /// NEVER THE COLOUR ALONE, which is why this is a `StateBadge` and not a
    /// tinted line of text. "Driving" and "Upright" are the same dot to roughly
    /// one man in twelve, and they are the difference between a duck that is
    /// walking and a duck that is standing there.
    ///
    /// THE FIVE WORDS ARE `DeviceCard.Doing`'S NOW, AND THE BRANCHES STAY HERE.
    /// The front door says what the duck is doing too, and two screens holding
    /// their own copies of "On its side" is two screens that drift the day one
    /// of them is reworded — the front door would say one thing about the same
    /// robot the Play tab says another about. The strings moved to StudioKit
    /// where a test can read them letter by letter; what is left here is the
    /// arithmetic that picks one, which is unchanged line for line.
    private var duckWord: String {
        guard let live else {
            return running ? DeviceCard.Doing.waitingForTheBench : DeviceCard.Doing.notDriving
        }
        if !live.upright { return DeviceCard.Doing.onItsSide }
        return running ? DeviceCard.Doing.driving : DeviceCard.Doing.upright
    }

    /// A FALLEN DUCK IS STILL ACTIVE, and calling it anything else would be a
    /// claim about the machine rather than about the pose. The policy is
    /// running and the servos are moving; what has gone wrong is on its side in
    /// the word, and again in the warning below it.
    private var duckState: RobotState {
        guard live != nil else { return running ? .scanning : .offline }
        return running ? .active : .idle
    }

    /// What the lens in the toolbar is doing. The bench has answered, is being
    /// asked, or has not been reached.
    private var linkState: LensIndicator.Connection {
        // THE IRIS IS ABOUT THE LINK THE SCREEN IS USING, AND IN THE ROBOT
        // VENUE THERE ISN'T ONE. An open eye up there while "Robot" is the
        // segment in force would read as a robot that has answered, which is
        // the single claim this venue exists to avoid making. The bench is
        // still connected and nothing on that screen is talking to it.
        if venue == .real { return .asleep }
        if health != nil { return .connected }
        // A STOP IS A CALL LIKE ANY OTHER AS FAR AS THE LENS IS CONCERNED. It
        // keeps its own flag so that nothing can disable the button — see
        // `stopping` — but the eye should still show the link being used.
        return busy || stopping ? .connecting : .asleep
    }

    private var policyLine: String {
        DuckPadMap.drivingLine(mapped: desk.map.locomotionFilename(among: health?.policies ?? []),
                               benchSaid: live?.policy)
    }

    /// What the link is, in the PEER'S own words.
    ///
    /// READ OFF THE PEER, NEVER ASSERTED HERE. Every line below comes from the
    /// object that would have to be replaced to change the answer: the
    /// transport's own label, `reach` — which `BenchPeer` takes straight from
    /// `DuckMethod.reach(for: .bench)` rather than listing a second time — and
    /// the refusal `BenchPeer` publishes for a call it cannot carry. A screen
    /// that wrote "Bench · move, stop" in a string would keep saying it after
    /// the routing table changed its mind, and the person reading it would be
    /// looking at a control that is dead for a reason nothing on the glass
    /// admits.
    ///
    /// PER CONTROL, BECAUSE THAT IS THE QUESTION SOMEBODY HAS. "Is this link
    /// any good" is not answerable; "will Stop work" is, and it is the one that
    /// gets asked while a duck is walking.
    private var linkLines: [String] {
        // TWO CAUSES, AND THIS CANNOT TELL THEM APART, SO IT NAMES BOTH.
        // There is no peer when nothing is selected and there is no peer when
        // the selected bench's address will not resolve; picking one of them to
        // print would be the guess `DuckBench.plantSaid` refuses to make about
        // its own three cases. The refusal with the real reason arrives the
        // moment somebody presses something — see `requirePeer`.
        guard let peer else {
            return ["no peer — nothing selected, or its address will not resolve"]
        }
        var lines = ["\(peer.transportKind.label) · "
                     + (trips == 0 ? "no round trips yet" : "\(trips) trips")]
        if let stateSaid { lines.append(stateSaid) }
        lines.append(reachLine("Drive", .move, peer))
        lines.append(reachLine("Stop", .stop, peer))
        lines.append(reachLine("Read", .state, peer))
        // RESET IS NOT IN THE VOCABULARY AND THE PEER SAYS WHY. `robot.init` is
        // the nearest method and `BenchPeer` refuses it by name — the bench's
        // `/reset` teleports the duck upright, which is not the initial pose,
        // and mapping one onto the other would hide a fall behind it. So the
        // button stays a bench call, and this line reads that refusal's
        // existence off the peer rather than restating the reason.
        lines.append("Reset \(DuckMethod.initPose.rawValue) — "
                     + (BenchPeer.refusal(for: .initPose) == nil
                        ? "carried" : "refused, so Reset stays a bench call"))
        return lines
    }

    private func reachLine(_ control: String, _ method: DuckMethod,
                           _ peer: any DuckPeer) -> String {
        "\(control) \(method.rawValue) — "
            + (peer.reach.contains(method) ? "carried" : "not carried")
    }

    /// Fourteen numbers in a grid, reflowing rather than shrinking.
    ///
    /// THE COLUMN COUNT IS WHAT GIVES WHEN THE TYPE GROWS. Seven `%7.3f`
    /// columns is a fixed-width dump, and at an accessibility size seven of
    /// them are wider than any phone — which is the argument that used to pin
    /// this layer at nine points. It is an argument for fewer columns, not for
    /// type nobody can read: the table folds onto more, shorter rows, the panel
    /// stops capping its width at the same moment (see `hud`), and every number
    /// stays whole. `DriveMetric` holds both counts.
    private func jointGrid(_ angles: [Double], columns: Int) -> String {
        var rows: [String] = []
        var row = ""
        for slot in 0..<DuckModel.policyJointCount {
            row += String(format: "%7.3f", angles[DuckModel.jointOfPolicySlot(slot)])
            if (slot + 1) % columns == 0 { rows.append(row); row = "" }
        }
        if !row.isEmpty { rows.append(row) }
        return rows.joined(separator: "\n")
    }

    /// How many joints go on a line at the text size in force.
    private var jointColumns: Int {
        typeSize.isAccessibilitySize ? DriveMetric.jointColumnsEnlarged
                                     : DriveMetric.jointColumns
    }

    // MARK: - the layers

    /// The layer switches. A SHEET WOULD HIDE THE DUCK, which is the one thing
    /// somebody driving needs to keep watching, so these are a row of chips
    /// under the stage and toggle in place.
    private var layerChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacing(.tight)) {
                ForEach(DuckPad.Layer.allCases) { layer in
                    layerChip(layer)
                }
            }
            .padding(.horizontal, Theme.spacing(.snug))
            .padding(.top, Theme.spacing(.tight))
            .padding(.bottom, Theme.spacing(.snug))
        }
    }

    /// One chip, with the bill under the selected one.
    ///
    /// THE BILL IS THE SELECTION, NOT THE TINT. A chip that only changes colour
    /// when it is on is a chip whose state nobody can read without seeing the
    /// off ones beside it for comparison — and on this palette the difference
    /// between `surfaceInteractive` and the ground is about 1.02:1 in light,
    /// which `Theme` says in as many words is a hint and not information. The
    /// orange bar underneath is the mark that carries it, and the weight of the
    /// word is a third signal for anybody who reads shape before colour.
    ///
    /// IT IS AN OVERLAY RATHER THAN A ROW BELOW so the bill inherits the chip's
    /// exact width and the row does not jog four points taller when a layer
    /// goes on. The padding under the scroll view is what it hangs into.
    private func layerChip(_ layer: DuckPad.Layer) -> some View {
        let on = layers.contains(layer)
        return Button {
            withAnimation(Theme.motion(reduced: reduceMotion)) {
                if on { layers.remove(layer) } else { layers.insert(layer) }
            }
        } label: {
            Text(layer.title)
                .font(.footnote.weight(on ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(on ? Theme.onFill : Theme.textSecondary)
                // THE SPACING SCALE DID NOT REACH THE FLOOR ON ITS OWN, WHICH
                // IS WHY THE MINIMUM IS NAMED HERE. `.snug` above and below a
                // footnote is twelve and twelve around a line box of eighteen:
                // forty-two points, measured, against a floor of forty-four.
                // The old comment asserted "over fifty points tall" and was
                // simply wrong — an assertion about a number is not a number,
                // and this one was two points short on every chip on the
                // screen. `DesignMetric.minimumTarget` is the app's one copy of
                // the floor, taken in both directions the way
                // `PrimaryActionStyle` takes its own; the frame goes on before
                // the background so the capsule, the bill and the hit area are
                // all the same shape.
                .padding(.horizontal, Theme.spacing(.standard))
                .padding(.vertical, Theme.spacing(.snug))
                .frame(minWidth: DesignMetric.minimumTarget,
                       minHeight: DesignMetric.minimumTarget)
                // POND DAY: the selected segment is a teal fill with an ink
                // label and outline; the others keep the hairline.
                .background { if on { Capsule().fill(Theme.actionTeal) } }
                .overlay(Capsule().strokeBorder(on ? Theme.outline : Theme.separator,
                                                lineWidth: on ? DesignMetric.outlineStroke
                                                              : DriveMetric.hairlineStroke))
                .overlay(alignment: .bottom) {
                    if on {
                        BillIndicator().offset(y: Theme.spacing(.tight))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(layer.title))
        .accessibilityValue(Text(on ? "on" : "off"))
        .accessibilityHint(Text(layer.detail))
    }

    // MARK: - the pad

    /// One control on the pad.
    ///
    /// LIVE IS BIG AND ORANGE; DEAD IS SMALL, QUIET AND STILL PRESSABLE. Both
    /// halves are the design: everything that can move the duck is the action
    /// colour at the sixty points `PrimaryActionStyle.moves` exists for, and
    /// everything `padd` binds that a physics server cannot do keeps a real
    /// surface, real secondary text and a real hit area, because pressing it is
    /// how a tester learns WHY rather than concluding the link is broken.
    ///
    /// THE DEAD ONES ARE NOT `.disabled`. A disabled button is unreachable to
    /// VoiceOver and unreachable to Switch Control, and the entire value of
    /// these controls is the sentence they produce when you press them.
    ///
    /// SIXTY POINTS IS WHY THE PAD PICTURE CHANGED SHAPE. The old arrangement —
    /// sticks flanking a face diamond, the way they sit on the thing itself —
    /// fitted only because its buttons were thirty-eight by thirty, well under
    /// the HIG floor and far under what a control that moves a machine owes
    /// somebody who is looking at the machine. Two sticks and a diamond at the
    /// right size are wider than a phone. The clusters stack instead: shoulders
    /// above, sticks, faces, dpad, and the two system buttons that do nothing
    /// here at the bottom. Order within each cluster is `padd`'s.
    @ViewBuilder private func padButton(_ control: DuckPad.Control) -> some View {
        let shown = desk.map.shown(for: control, naming: desk.name(ofSequence:),
                                   namingMotion: desk.name(ofMotion:))
        // SIMPLE DRAWS ONLY WHAT MOVES THE DUCK, NAMED FOR WHAT IT DOES. The
        // dead controls stay pressable under Everything, where a tester wants
        // the sentence they produce; somebody playing wants "Roulade", not "X".
        if !isSimple || liveHere(control, shown: shown) {
            padButtonBody(control, shown: shown)
        }
    }

    /// Whether a control does something on THIS duck. On a real duck only a binding that maps to
    /// one of its own skills (or Stop) is live; the rest are the practice duck's.
    private func liveHere(_ control: DuckPad.Control, shown: DuckPadMap.Shown) -> Bool {
        guard venue == .real else { return shown.isLive }
        return shown.isLive && desk.map.effect(for: control, naming: desk.name(ofSequence:),
                                               namingMotion: desk.name(ofMotion:)).realDuckOrder != nil
    }

    private func padButtonBody(_ control: DuckPad.Control, shown: DuckPadMap.Shown) -> some View {
        let isLive = liveHere(control, shown: shown)
        let label = isSimple ? (shown.name ?? control.face) : control.face
        return Group {
            if isLive {
                padPress(control, label: label).buttonStyle(.faceButton(Self.faceFill(control)))
            } else {
                padPress(control, label: label).buttonStyle(DeadControlStyle())
            }
        }
        // A PRESS THAT CAME FROM THE CONTROLLER, DRAWN LIKE A PRESS. The style
        // darkens its fill under a thumb and cannot see a Bluetooth button at
        // all, so a hardware press is mirrored with the same delta from out
        // here. It is the style's number written twice because the style's copy
        // is private; the two have to feel like one press.
        .brightness(pad.lastPressed == control ? DriveMetric.pressDelta : 0)
        .animation(Theme.motion(reduced: reduceMotion), value: pad.lastPressed)
        .accessibilityLabel(Text(shown.name.map { "\($0), \(control.face)" } ?? control.face))
        .accessibilityHint(Text(shown.detail))
        // A REMAPPED CONTROL SAYS SO WITHOUT A WORD ON THE PICTURE. Four points
        // in the measured colour, and the sentence itself is in `shown.detail`
        // above, which is what VoiceOver reads.
        .overlay(alignment: .topTrailing) {
            if shown.isCustom {
                Circle().fill(Theme.measured)
                    .frame(width: DriveMetric.remapDot, height: DriveMetric.remapDot)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Pond Day's face buttons: A orange, B lavender, X teal, Y yellow, the
    /// way a toy pad colours them. Every other live control is the plain raised
    /// button, so orange still means one thing on the pad.
    static func faceFill(_ control: DuckPad.Control) -> PrimaryActionStyle.Fill {
        switch control {
        case .a: return .orange
        case .b: return .lavender
        case .x: return .teal
        case .y: return .yellow
        default: return .raised
        }
    }

    private func padPress(_ control: DuckPad.Control, label: String) -> some View {
        Button { Task { await press(control) } } label: {
            // `fixedSize` IS THE GUARANTEE, not the padding. A label that a
            // layout may compress is a label that can be clipped to a stroke,
            // which is what "LB" and then "Y" both came out as; this makes the
            // text refuse to shrink, so a column too narrow for the buttons
            // folds them instead of gutting them.
            //
            // BUT ONLY FOR A FACE. Simple draws the bound move's NAME on the
            // button, and a name like `beak_strut_vault_r6_c…` held to its full
            // width ran out of the 60-point circle and over its neighbours
            // (build 79, 2026-10-02). A face letter keeps `fixedSize`; a name is
            // held to the button, may take two lines and shrink to half, and may
            // break after an underscore (a zero-width space, so what is drawn is
            // still the name).
            if label.count <= 3 {
                Text(label).lineLimit(1).fixedSize()
            } else {
                Text(label.replacingOccurrences(of: "_", with: "_\u{200B}"))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .frame(width: DesignMetric.movingTarget - 8)
            }
        }
    }

    /// The pad. ONE BUILDER, TWO LAYOUTS, AND NEITHER OF THEM DRAWS A CONTROL
    /// THE OTHER ALSO DRAWS.
    ///
    /// `compact: true` is what floats over the full-bleed picture: the two
    /// sticks at the bottom corners with the bumpers and the four face buttons
    /// in the gap between them. Those seven are what a hand on the glass reaches
    /// for while a duck is walking, and they sit low and wide so the middle of
    /// the picture — where the robot is — stays picture.
    ///
    /// `compact: false` is the REST of the pad, in the drawer: the dpad and the
    /// two system buttons. They are here because `padd` binds fifteen controls
    /// and pressing a dead one is how a tester learns that the mouth is servo
    /// nine and no network drives it — dropping them to make room would have
    /// deleted the sentence rather than the button. They are not on the picture
    /// because none of them moves the duck against a bench.
    ///
    /// BOTH GO THROUGH `padButton`, so both take the same `press(control:)` door
    /// and the same sixty-point `PrimaryActionStyle.moves` target. Somebody who
    /// has driven the robot should not have to read either layout — see
    /// `padButton` for why the clusters no longer flank the sticks.
    @ViewBuilder private func padDeck(compact: Bool) -> some View {
        if compact {
            HStack(alignment: .bottom, spacing: Theme.spacing(.tight)) {
                ThumbPad(title: "Move", stick: $touchSticks.left)
                Spacer(minLength: Theme.spacing(.tight))
                VStack(spacing: Theme.spacing(.tight)) {
                    // FOUR ACROSS WHERE THEY FIT, TWO BY TWO WHERE THEY DO NOT.
                    // On the narrowest phone still supported, four sixty-point
                    // buttons between two thumb pads are wider than the screen;
                    // `ViewThatFits` folds them rather than truncating a glyph
                    // or clipping a target.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.spacing(.tight)) {
                            padButton(.y); padButton(.x); padButton(.b); padButton(.a)
                        }
                        VStack(spacing: Theme.spacing(.tight)) {
                            HStack(spacing: Theme.spacing(.tight)) {
                                padButton(.y); padButton(.x)
                            }
                            HStack(spacing: Theme.spacing(.tight)) {
                                padButton(.b); padButton(.a)
                            }
                        }
                    }
                }
                Spacer(minLength: Theme.spacing(.tight))
                ThumbPad(title: "Turn", stick: $touchSticks.right, verticalIsLive: false)
            }
            // NO CARD BEHIND THE WHOLE ROW. A full-width opaque band across the
            // bottom of a live picture is the thing this layout exists to avoid;
            // the pads and the buttons each carry their own surface already.
        } else {
            VStack(spacing: Theme.spacing(.snug)) {
                // THE BUMPERS LIVE HERE NOW. On the picture they were a third
                // row in a column about 129 points wide, where two labels of
                // two characters each do not fit and were squeezed to a
                // sliver; the four face buttons fit because their labels are
                // one character. Down here the row is full width, both labels
                // are readable, and the picture gets a 60-point row back.
                HStack(spacing: Theme.spacing(.tight)) {
                    padButton(.leftBumper); padButton(.rightBumper)
                }
                HStack(spacing: Theme.spacing(.tight)) {
                    padButton(.dpadLeft); padButton(.dpadDown); padButton(.dpadRight)
                }
                HStack(spacing: Theme.spacing(.tight)) {
                    padButton(.start); padButton(.select)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.spacing(.snug))
            .background(Theme.surfacePrimary, in: deckCard)
            // THE SAME HAIRLINE EVERY OTHER CARD ON THIS SCREEN HAS. The
            // readout panel, the chips and the thumb pads all take a `separator`
            // edge; the deck alone did not, so the one card that fills the width
            // was the one card with no edge — and on a palette whose grounds sit
            // within about 1.1:1 of each other, an edge is the only thing that
            // says where a surface starts. It is not a decoration here, it is
            // the boundary.
            .overlay(deckCard.strokeBorder(Theme.separator,
                                           lineWidth: DriveMetric.hairlineStroke))
        }
    }

    /// The deck's shape, drawn once so its fill and its edge cannot disagree
    /// about the corner.
    private var deckCard: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(DriveMetric.deck), style: .continuous)
    }

    // MARK: - the controls

    private var controls: some View {
        List {
            if benches.benches.isEmpty {
                Section {
                    NavigationLink { BenchSettingsView(store: benches) } label: {
                        Label("Set up a bench", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("Pick a bench to drive against. This iPhone is one; a machine on your network is another.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)
            } else {
                // THE CHIPS CAME INTO THE DRAWER WITH EVERYTHING ELSE, and they
                // are still not drawn in the Robot venue — this whole list is
                // only reached from `sim` and `ar`, so the rule that used to be
                // an `if venue != .real` in the body now holds for free. Every
                // chip switches an overlay drawn over a duck this app is
                // rendering, and the robot venue renders none.
                // WHERE YOU ARE DRIVING, IN WORDS. It was a row on the
                // picture and it is a thing somebody reads once, so it reads
                // here and the picture keeps the points.
                Section {
                    DisclosureGroup(isExpanded: $venueLineIsOpen) {
                        Text(venue.oneLine)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } label: {
                        Text(StageViewport.captionSaid(expanded: venueLineIsOpen))
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityHint(Text(StageViewport.chromeFloatsSaid))
                }
                .listRowBackground(Theme.surfacePrimary)
                // THE READOUT LAYERS (joints, limits, link, telemetry) ARE
                // DIAGNOSTICS. Simple drives without them.
                if !isSimple {
                    Section {
                        layerChips
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } header: {
                        SectionHeading(text: StageViewport.drawerLayersSaid)
                    }
                }

                Section {
                    padDeck(compact: false)
                        // THE DECK DRAWS ITS OWN CARD, so the row hands it the
                        // whole width and gets out of the way. That is what
                        // makes the concentric radii legible: the card is
                        // `.group`, the pads inside it are `.group.inner`, and
                        // a system row background between them would put a
                        // third corner radius nobody chose in the middle.
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    SectionHeading(text: StageViewport.drawerPadRestSaid)
                } footer: {
                    if !isSimple {
                        Text(DuckDrive.says(twist))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                if !isSimple {
                    Section {
                        // THE BENCH'S OWN DISTINCTION, WORTH REPEATING. Stopping is
                        // something the policy does; resetting is something done TO
                        // it. A policy that cannot stop without falling is a fact
                        // about that policy, and teleporting it upright would hide
                        // exactly the failure worth seeing.
                        Text("Stop zeroes the command and lets the duck settle under it — if it falls over stopping, that is the policy. Reset puts it back on its feet, which is not something a robot can do for itself.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    } header: {
                        SectionHeading(text: "Stop and Reset")
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                Section {
                    Picker("Bench", selection: Binding(
                        get: { benches.selectedID }, set: { benches.selectedID = $0 })) {
                        ForEach(benches.benches) { one in
                            Text(one.name).tag(UUID?.some(one.id))
                        }
                    }
                    worldPicker
                    // WHERE THE POLICY PICKER WAS. The sticks are mapped to a
                    // ROLE with a shipped default, so nothing here waits for a
                    // pick; `DuckPadMap.sticksAreAlwaysMapped` says so under the
                    // row. The swap closure ALWAYS posts — the "already loaded"
                    // guard lives in `DuckPadMap.toPost`, which is consulted for
                    // the automatic locomotion load and nothing else, so a
                    // deliberate pick from the editor is never swallowed.
                    if !isSimple {
                        PadMapSection(desk: desk, policies: health?.policies ?? [],
                                      swap: { name in flight = Task { await swap(to: name) } },
                                      play: { id in
                                          desk.play(id, thenLoading: nil,
                                                    among: health?.policies ?? [], face: "")
                                          engageLoop()
                                      },
                                      bench: bench, token: token, library: model,
                                      host: health?.host,
                                      landed: { _ in Task { await refreshHealth() } })
                    }
                    NavigationLink { BenchSettingsView(store: benches) } label: {
                        Label("Manage benches", systemImage: "gearshape")
                    }
                } footer: {
                    if !isSimple {
                        Text(DuckDrive.hotSwapWorksBecause)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .listRowBackground(Theme.surfacePrimary)

                if !isSimple || pad.name != nil {
                    Section {
                        if let name = pad.name {
                            Label(DuckPad.connected(name), systemImage: "gamecontroller.fill")
                                .font(.footnote).foregroundStyle(Theme.success)
                        } else {
                            Text(DuckPad.noPad).font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } header: {
                        SectionHeading(text: "Controller")
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                if !isSimple {
                    Section {
                        Text(DuckDrive.thisIsNotARobot)
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                        Text(DuckDrive.intentMeansACommandHere)
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }
            }
        }
        // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S GREY.
        // `backgroundSecondary` is the token `Theme` documents as a ground for
        // surfaces rather than for words, which is exactly what a grouped list
        // is: every row keeps a real `surfacePrimary` card under it, so nothing
        // is ever set on the ground the palette says is short of 4.5:1.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
    }

    // MARK: - the robot venue

    // THE ROBOT VENUE'S LIST IS GONE (build 91). The real duck is driven from the same controller
    // as the other venues, with its camera as the stage; its connection, camera address, details
    // and the honest notes about what the link carries live in the Duck sheet.

    // MARK: - the world the bench is standing in

    /// The World picker, and every sentence that belongs under it.
    ///
    /// A MENU AND NOT A SEGMENTED CONTROL, because the list is the bench's own
    /// world, a bare floor, eight staircases, the ball, five built-in scenes
    /// and everything the person has drawn — which is a menu on any phone.
    /// `BenchView` makes the same choice for the same reason.
    ///
    /// THE FIRST ENTRY SENDS NOTHING AND THAT IS THE POINT OF IT. Every number
    /// this app has published from a bench was measured in the world the bench
    /// booted in, and the way to keep a drive comparable with those is to leave
    /// it alone. It is also the honest default: the alternative — laying a bare
    /// floor on connect — would silently park fourteen 200 kg blocks that have
    /// been colliding under every drive this app has ever done, which is a
    /// change to the physics and not a tidy-up. `DuckWorld.bareFloorIsAChange`
    /// says so where the choice is made.
    ///
    /// THE SELECTION IS ALWAYS WHAT IS STANDING. Every path through `stand`
    /// ends with `worldChoice = standingChoice`, read out of `GET /world`, so a
    /// refused request leaves the control showing the world the bench is
    /// really in. A picker that kept the refused choice would be the one lie
    /// this screen cannot afford: the stage draws the readback, so the two
    /// would disagree about the same room.
    @ViewBuilder private var worldPicker: some View {
        Picker("World", selection: $worldChoice) {
            ForEach(worldEntries) { entry in
                Text(entry.label).tag(entry.choice)
            }
        }
        .pickerStyle(.menu)
        // DEAD ONLY WHEN THE BENCH HAS NO ROUTE, and the reason is printed
        // directly underneath — a disabled control with no sentence beside it
        // is the thing this app does not ship.
        .disabled(worldRouteMissing || bench == nil)
        .onChange(of: worldChoice) { _, now in
            // NOT FOR THE WORLD ALREADY STANDING. `stand` sets this from the
            // readback when it finishes, which fires this again; without the
            // guard that is a second request per change, and after a refusal it
            // would be a loop.
            guard now != standingChoice else { return }
            // A world change under a drive is a stop first: the drive loop is
            // cut off and the duck told to stand before the world moves.
            flight?.cancel()
            flight = Task {
                if running { await halt() }
                await stand(in: now)
            }
        }
        // BY POSITION, NOT BY THE SENTENCE. Two `unexpressed` rows can compose
        // the same line — the same field on two steps, said the same way — and
        // `id: \.self` would then draw one of them and drop the other, which is
        // a list of what the world could not say quietly saying less than it
        // was given.
        ForEach(Array(worldNotes.enumerated()), id: \.offset) { _, line in
            Text(line).font(.footnote).foregroundStyle(Theme.textSecondary)
        }
    }

    /// Everything there is to say under the picker, in the order it is worth
    /// reading. Each line is a kit string a test reads letter by letter.
    private var worldNotes: [String] {
        // A BENCH WITHOUT THE ROUTE HAS ONE THING TO SAY AND NOTHING ELSE IS
        // TRUE OF IT. There is no readback to list, no world to reset and no
        // change to warn about.
        if worldRouteMissing { return [DuckWorld.noWorldRoute] }
        var lines: [String] = []
        if let worldNote { lines.append(worldNote) }
        if world?.isSet != true {
            // Nothing has been asked for yet, so both halves of the choice are
            // worth having in front of somebody before they make it: what the
            // bench's own world is, and what leaving it costs.
            lines.append(DuckWorld.benchOwnWorld)
            lines.append(DuckWorld.bareFloorIsAChange)
            lines.append(DuckWorld.ballNeedsAWorld)
        } else {
            // The bench's own world is the row above this one, and it cannot
            // be gone back to: the sentence sits with the choice that ended it.
            lines.append(DuckWorld.oneWayUntilRestart)
            if worldChoice == .bareFloor { lines.append(DuckWorld.bareFloorIsAChange) }
            lines.append(DuckWorld.resetKeepsTheWorld)
        }
        if case .saved(let id, _) = worldChoice,
           !scenes.scenes.contains(where: { $0.id == id }) {
            lines.append(StageCaption.sceneDeleted(.drivenIn))
        }
        if let world, world.isSet {
            // THE BENCH'S OWN ROWS FIRST AND WHOLE. Where it and the kit both
            // speak — a wall this world has not got, a prop this plant lacks, a
            // run that leaves daylight — the bench wins, because it is the one
            // that actually laid the blocks.
            let said = world.unexpressed
            // AND THEN ONLY WHAT THE WIRE GAVE IT NO WAY TO SAY. `{x, top}`
            // carries no y, no size and no ball, so `step` and `ball` are the
            // two kinds of note the bench structurally cannot produce and the
            // kit can. Anything else from the prediction would be a second
            // wording of a row already above it, which is the failure this
            // whole package is built against.
            let missing = predicted.filter { $0.what == "step" || $0.what == "ball" }
            if let heading = DuckWorld.couldNotExpress(said + missing) {
                lines.append(heading)
            }
            lines.append(contentsOf: DuckWorld.groupedSayings(said + missing))
            // THE WALLS ARE REAL AND THEY ARE NOT IN THE PICTURE, said
            // wherever the picture is being drawn from a world.
            lines.append(DuckWorld.arenaIsNotDrawn)
        }
        return lines
    }

    /// One row of the World picker.
    private struct WorldEntry: Identifiable {
        let choice: WorldChoice
        let label: String
        var id: WorldChoice { choice }
    }

    /// Which world a row asks for.
    ///
    /// THE CASES CARRY INDICES AND IDS RATHER THAN SCENES because a `Picker`
    /// tag has to be `Hashable` and cheap to compare on every render, and
    /// because a scene is a value somebody can edit underneath this screen. The
    /// name travels with a saved scene's id for one reason: a scene deleted
    /// while this tab is open must still have a row to be selected in, or the
    /// picker goes blank at exactly the moment `StageCaption.sceneDeleted`
    /// has something to say.
    private enum WorldChoice: Hashable {
        /// Send nothing. What every published number ran in.
        case benchOwn
        /// A world the bench is standing in that this list has no other row
        /// for — one built from a scene since deleted, or by another client.
        case standing(String)
        case bareFloor
        /// An index into `StairsChallenge.rises`.
        case stairs(Int)
        case ballAhead
        /// An index into `DuckScene.starters`.
        case starter(Int)
        /// A scene of the person's own, and the name it had when it was picked.
        case saved(UUID, String)
    }

    private var worldEntries: [WorldEntry] {
        var out: [WorldEntry] = [.init(choice: .benchOwn, label: "The bench's own world")]
        if case .standing(let name) = worldChoice {
            out.append(.init(choice: worldChoice, label: name.isEmpty ? "Standing now" : name))
        }
        if case .saved(let id, let name) = worldChoice,
           !scenes.scenes.contains(where: { $0.id == id }) {
            out.append(.init(choice: worldChoice, label: name))
        }
        out.append(.init(choice: .bareFloor, label: bareFloorLabel))
        for (slot, rise) in StairsChallenge.rises.enumerated() {
            out.append(.init(choice: .stairs(slot), label: stairsScene(rise).name))
        }
        // The ball can be moved once a world is standing and not before:
        // the bench refuses a first world that says nothing about its steps.
        if world?.isSet == true {
            out.append(.init(choice: .ballAhead, label: ballAheadLabel))
        }
        // THE BUILT-IN "BARE FLOOR" IS LEFT OUT BECAUSE THE ROW ABOVE IS IT.
        // `DuckScene.bareFloor()` is named exactly what `Plan.bareFloor()` is
        // named, and two rows with one label is a menu where the selection
        // cannot be read back: `standingChoice` matches on the name the world
        // was sent with, so one of the two could never be the resting choice.
        // The dedicated row is the better of the pair — it sends `clear: true`
        // rather than `steps: []` and carries `bareFloorIsAChange` under it.
        // The INDEX is what `scene(for:)` resolves, so filtering the rows does
        // not shift what any row means.
        for (slot, scene) in DuckScene.starters.enumerated()
        where scene.name != bareFloorLabel {
            out.append(.init(choice: .starter(slot), label: scene.name))
        }
        for scene in scenes.scenes {
            out.append(.init(choice: .saved(scene.id, scene.name), label: scene.name))
        }
        return out
    }

    /// The bare-floor row's word, taken off the plan the row sends rather than
    /// written twice.
    private var bareFloorLabel: String { DuckWorld.Plan.bareFloor().name ?? "Bare floor" }

    /// The ball row's word. The distance is the one the plan carries, so the
    /// row and the request cannot disagree about where the ball is going.
    private var ballAheadLabel: String {
        "Ball, \(String(format: "%.2f", DriveMetric.ballAhead)) m straight ahead"
    }

    /// The challenge's own flight at one rise — the same builder the Stairs
    /// challenge screen uses, so "60 mm" here is the 60 mm that was scored.
    private func stairsScene(_ rise: Double) -> DuckScene {
        DuckScene.stairsChallenge(rise: rise)
    }

    /// The scene a row stands for, or nil for the two rows that send nothing.
    private func scene(for choice: WorldChoice) -> DuckScene? {
        switch choice {
        case .benchOwn, .standing, .bareFloor, .ballAhead: return nil
        case .stairs(let slot):
            guard StairsChallenge.rises.indices.contains(slot) else { return nil }
            return stairsScene(StairsChallenge.rises[slot])
        case .starter(let slot):
            guard DuckScene.starters.indices.contains(slot) else { return nil }
            return DuckScene.starters[slot]
        case .saved(let id, _):
            return scenes.scenes.first { $0.id == id }
        }
    }

    /// The request a row makes, or nil when the row sends nothing.
    ///
    /// `plan(for:on:graspables:)` IS THE KIT'S AND SO IS EVERY REFUSAL IN IT.
    /// A scene with fifteen steps, or a flight that reaches through `wall_e`,
    /// comes back carrying a refusal and `DuckBench.setWorld` throws it before
    /// a byte goes out — the bench would answer 400 with the same reason, and a
    /// round trip to be told what was already known is a person made to wait to
    /// be refused.
    private func planFor(_ choice: WorldChoice) -> DuckWorld.Plan? {
        switch choice {
        case .benchOwn, .standing: return nil
        case .bareFloor: return .bareFloor()
        case .ballAhead:
            // Moving the ball keeps the standing world's name: the world is
            // still the one that was picked, with its ball somewhere else.
            return .moveTheBall(to: DuckWorld.Point(x: DriveMetric.ballAhead, y: 0))
        case .stairs, .starter, .saved:
            guard let scene = scene(for: choice) else { return nil }
            return DuckWorld.plan(for: scene, on: world?.bank ?? .pinned,
                                  graspables: health?.graspables ?? [])
        }
    }

    /// Which row the bench is actually standing in.
    ///
    /// MATCHED BY THE NAME THE WORLD WAS SENT WITH, which is the only handle
    /// there is: `/world` answers a name and a layout, not a row in this
    /// picker. A world whose name matches nothing here — one another client
    /// built, or one from a scene since renamed — gets its own row rather than
    /// being rounded to the nearest entry, because rounding it would put a
    /// staircase in the control that is not the staircase on the stage.
    private var standingChoice: WorldChoice {
        guard let world, world.isSet else { return .benchOwn }
        let name = world.name ?? ""
        // A saved scene keeps its row even after it has been deleted, so the
        // sentence about the deletion has somewhere to be read from.
        if case .saved(_, let picked) = worldChoice, picked == name { return worldChoice }
        if name == bareFloorLabel { return .bareFloor }
        for (slot, rise) in StairsChallenge.rises.enumerated()
        where stairsScene(rise).name == name { return .stairs(slot) }
        for (slot, scene) in DuckScene.starters.enumerated()
        where scene.name == name { return .starter(slot) }
        for scene in scenes.scenes where scene.name == name {
            return .saved(scene.id, scene.name)
        }
        return .standing(name)
    }

    // MARK: - what there is to drive

    /// Whether there is anything for the sticks to talk to.
    ///
    /// TWO DIFFERENT QUESTIONS UNDER ONE NAME. On a bench it is "has this phone chosen a bench";
    /// on a robot it is "is a link open right now". (The Drive | Stop | Reset bar that used to ask
    /// this is gone in build 92: the sticks start the duck and the red disc stops it.)
    private var somethingToDrive: Bool {
        venue == .real ? robot.isConnected : bench != nil
    }

    // MARK: - the pad's presses

    /// Act on a control. THE ONE PATH FOR BOTH INPUTS — a real controller's
    /// press and a tap on the on-screen face button arrive here identically,
    /// so the two can never drift into doing different things.
    ///
    /// NOTHING HERE FIRES A HAPTIC. A press is a tap and the finger already
    /// knows it happened; the taps this screen spends are the ones that come
    /// back from the world, in `swap`, `drive` and `halt`. `Haptic`'s own
    /// preamble makes the argument at length.
    @MainActor private func press(_ control: DuckPad.Control) async {
        // A PRESS IS THE PERSON'S OWN: it ends a Tell order or a goal first.
        if arbiter.running != nil { apply(arbiter.handle(.movePress, at: Date())) }
        // THE STICKS DRIVE A ROBOT AND THE FACE BUTTONS STILL DO NOT, which
        // is a narrower not-yet than the one that used to be here and is worth
        // the distinction. Every face binding in this app ends in a bench call
        // — load a network into a slot, run a recorded motion against a world,
        // replay a take — and `robotd` owns its own slots. A press is told
        // which of those it is rather than being told the robot cannot be
        // driven, which is no longer true.
        if venue == .real {
            // ON A REAL DUCK A FACE BUTTON RUNS THE DUCK'S OWN SKILL (build 92): the shipped A and X
            // load Ground pick and Roulade on the practice duck, and robotd holds those as skills.
            // Anything else is the practice duck's, drawn dead here, and says so if pressed.
            let effect = desk.map.effect(for: control, naming: desk.name(ofSequence:),
                                         namingMotion: desk.name(ofMotion:))
            guard let order = effect.realDuckOrder else {
                say(DuckPadMap.Effect.practiceOnly)
                return
            }
            if order == .stop { stopNow(); return }
            if running { stickStarted = false; running = false; flight?.cancel() }
            let named = DuckDecider.chip(for: order).title
            lastAction = named
            say(named)
            // A FACE BUTTON'S SKILL IS A RUN (build 93): the cap, Take over and the Stop pill cover
            // it, by the same door as a Siri order, so leaving Play does not lose the cap.
            _ = await runs.runOrder(order, owner: .app)
            say(runs.caption)
            return
        }
        // THE PRESS'S RESULT GOES ON THE CONTROLLER'S LINE TOO, not only the readout's.
        let before = lastAction
        defer { if lastAction != before, let line = lastAction { say(line) } }
        // THE MAP IS THE ONE DOOR, AND IT IS NEVER NIL. An unmapped control
        // lifts the shipped `DuckPad.binding(for:)` row unchanged, so the table
        // padd's own order is built from stays the thing a remap departs FROM.
        // THE SAME DOOR THE BUTTON WAS DRAWN THROUGH. This asked the BARE
        // `effect(for:)`, and the drawing side asks the resolving one — so a
        // binding whose motion or sequence has since been deleted in Studio was
        // drawn as a named not-yet and then, on the press, fell into
        // `runMotion`'s `guard let draft` and returned in silence. A control
        // that says nothing when pressed is the one thing this screen is not
        // allowed to have; the not-yet has a sentence and this is where it gets
        // said.
        switch desk.map.effect(for: control, naming: desk.name(ofSequence:),
                               namingMotion: desk.name(ofMotion:)) {
        case .loadSlot(let slot):
            // THE SLOT NAMES A ROLE, NOT A FILE. Which policy fills `roulade`
            // is the bench's business; this asks for the role and lets the
            // health listing say which network that is on this machine.
            // AND THE SENTENCE FOR "IT HASN'T GOT ONE" IS THE KIT'S, NOT THIS
            // SCREEN'S. What was here was composed in the view — "this bench
            // has no Walk policy loaded." — which is a sentence nothing on
            // Linux ever read and, worse, a second wording of the thing the
            // front door's quick-action chips say about the same missing file.
            // `DuckQuickActions.notHeldHere` is that sentence, tested, and it
            // is the one that says a bench full of somebody's own networks is
            // not a broken bench. The face button's name stays in front of it
            // so the line still says WHICH button did nothing.
            // AN UNREAD LIST IS NOT AN EMPTY ONE. With no `/health` yet, "holds no
            // policy" is a claim about a bench nobody has heard from.
            guard health != nil else {
                lastAction = "\(control.face): \(DuckQuickActions.noBenchAnswering(slot))"
                return
            }
            guard let policy = DuckQuickActions.filename(filling: slot,
                                                         among: health?.policies ?? []) else {
                lastAction = isSimple
                    ? DuckQuickActions.notHeldHereShort(slot)
                    : "\(control.face): \(DuckQuickActions.notHeldHere(slot))"
                return
            }
            // ONE SWAP, THROUGH THE LOOP, WHERE STOP CAN CUT IT OFF. This was
            // `flight = Task { await swap(to: policy) }` followed by
            // `engageLoop()` — and `engageLoop()` begins with `flight?.cancel()`.
            // Both ran on the same main-actor turn, so with the loop stopped the
            // swap was cancelled before its request had left the phone, the
            // cancellation was (correctly) swallowed as a stop, and the line
            // below still claimed the load. With the loop already running the
            // swap did land — and the next trip put the walker straight back,
            // because the map wanted it and the bench said something else was
            // driving. Either way the duck stood there. The pilot now carries
            // the name to the next trip's `Go.load`, and `drive()` posts it
            // through the same `swap` every other load takes.
            desk.request(load: policy)
            // SIMPLE SAYS THE MOVE; EVERYTHING ALSO SAYS THE BUTTON AND THE FILE.
            lastAction = isSimple ? slot.title
                                  : "\(control.face) → \(slot.title): \(policy)"
            // AND IT DRIVES. A network loaded while the loop is stopped is a
            // policy on the servos that nothing is stepping: the duck stands
            // there and the button reads as broken, which is the difference
            // this tab had against the lab. Stop is one press away and is
            // never disabled.
            engageLoop()
        case .drive:
            break
        case .stop:
            lastAction = isSimple ? "Stopped" : "\(control.face) → stop"
            await halt()
        case .reset:
            lastAction = isSimple ? "Back on its feet" : "\(control.face) → reset"
            flight = Task { await putBack() }
        case .run(let motion):
            // THE SAME DOOR THE MOTIONS SHEET OPENS. A press is not a round
            // trip here: the loop stops, the bench runs the track once, and
            // the sticks come back — which is what the binding says it does.
            lastAction = isSimple ? (desk.name(ofMotion: motion) ?? "")
                                  : "\(control.face) → \(desk.name(ofMotion: motion) ?? "")"
            await runMotion(motion)
        case .play(let id, let slot):
            // A REPLAY IS A STATE OF THE DRIVE LOOP, NEVER A SECOND ONE. The
            // pilot hands `drive()` the recorded command each round trip; all
            // this does is start the loop if it is not already running.
            lastAction = desk.play(id, thenLoading: slot,
                                   among: health?.policies ?? [], face: control.face)
            if desk.pilot.isPlaying { engageLoop() }
        case .notYet(let why):
            // NOT SILENCE. A tester pressing a button they know from the robot
            // gets told why it does nothing here rather than concluding the
            // link is broken.
            lastAction = "\(control.face): \(why)"
        }
    }

    // WHICH OF THE BENCH'S POLICIES FILLS A SLOT IS `DuckQuickActions`' JOB
    // NOW, and the function that used to be here — role name first, the
    // without-extension fallback second — is that type's `filename(filling:
    // among:)` line for line. It moved because the front door asks the same
    // question to decide what its quick-action chips are, and two matchers
    // disagree the first time somebody's bench lists `alpha_walking` rather
    // than `alpha_walking.onnx`. It also moved because it was arithmetic in a
    // view: nothing could test it on Linux, and `check_no_studio_math.sh`
    // exists to keep exactly this kind of thing out of `DuckStudio/Sources`.
    //
    // THE ONE THING THAT DID NOT MOVE IS THE NIL FOR "NO HEALTH YET". The old
    // private copy returned nil when `health` was nil, before it looked at any
    // slot; the kit function takes the list, so the caller passes
    // `health?.policies ?? []` and an empty list matches nothing. Same answer,
    // one less thing for the kit to know about this screen's state.

    // MARK: - talking to it

    /// One request to the bench, with its bearer token on it.
    ///
    /// NARROWER THAN IT WAS, AND THE NARROWING IS THE POINT. Everything a duck
    /// can hear leaves through `peer` now. What still goes out this way is the
    /// three things a duck has no word for: `/health`, which lists the policies
    /// this bench holds; `/policy`, which loads one of them into the slot a face
    /// button names; and `/reset`, which picks the duck up — and a robot that
    /// could put itself back on its feet would not need somebody to press it.
    @MainActor private func ask(_ call: DuckBench.Call) async throws -> Data {
        try await URLSession.shared.data(
            for: DuckBench.urlRequest(for: call, token: token)).0
    }

    /// The same request, with the STATUS CODE KEPT.
    ///
    /// `/world` IS THE ONE CALL WHERE THE CODE IS THE ANSWER. Every other
    /// endpoint this screen uses either exists on every bench in the family or
    /// says what is wrong in its body; `/world` is new, so an older bench 404s
    /// the path — and a 404 is a fact about the BUILD, not a refusal about a
    /// world. Told apart, it disables the picker and prints
    /// `DuckWorld.noWorldRoute`; conflated with a 400 it would read as "the
    /// bench refused that staircase", which is a sentence about a machine that
    /// was never asked.
    @MainActor private func askStatus(_ call: DuckBench.Call) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(
            for: DuckBench.urlRequest(for: call, token: token))
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 200)
    }

    @MainActor private func requireBench() throws -> DuckBench.Address {
        guard let bench else { throw DuckBench.Refusal.empty }
        return try benches.armed(bench).resolved()
    }

    /// The peer for the bench selected now, built if there is not one yet.
    ///
    /// IT THROWS THE SAME SENTENCES `requireBench` DOES, which is why the peer
    /// is built here rather than only in `rebuildPeer`: an address that cannot
    /// be reached is worth a paragraph at the moment somebody presses Drive,
    /// and worth nothing at all while they are still typing it.
    /// THE NIL IS THE EMPTY BENCH, AND IT THROWS THE SENTENCE IT ALWAYS DID.
    /// `BenchStore.makePeer` answers nil when nothing is selected rather than
    /// throwing, because a store handing back "there is no bench" is a fact and
    /// not a failure — a picker asking what to draw wants the fact. This screen
    /// is the caller that cannot proceed without one, so it turns the fact back
    /// into `DuckBench.Refusal.empty`, which is the exact error the old private
    /// `makePeer` threw out of `requireBench` and the one `report` already knows
    /// how to put on the glass.
    /// - Returns: `any DuckPeer` — see the `peer` accessor for why this is the
    ///   change the Play tab existed without for its whole life.
    ///
    /// THE ROBOT VENUE BUILDS NOTHING. A bench peer is cheap and local and can
    /// be constructed on demand from an address somebody typed; a robot link is
    /// a socket to a machine with a duck on it, and this screen must never open
    /// one as a side effect of somebody pressing Drive. So the robot branch
    /// either hands back the link that is already open or refuses with the
    /// sentence that says where to open one.
    @MainActor private func requirePeer() throws -> any DuckPeer {
        if venue == .real {
            guard let live = robot.peer else { throw BridgeLink.LinkGone.notConnected }
            return live
        }
        if let benchPeer { return benchPeer }
        guard let made = try benches.makePeer() else { throw DuckBench.Refusal.empty }
        benchPeer = made
        return made
    }

    /// The bench, when the thing being driven is one.
    ///
    /// EVERY BENCH-ONLY MEMBER GOES THROUGH THIS AND NONE OF THEM IS FAKED FOR
    /// A ROBOT. `live` (fifteen joint angles and a root), the world, the scene,
    /// `/health`'s policy list, `/policy`, `/reset` — all of them are things a
    /// physics server has and a Microduck does not, and the choice at every one
    /// of them was between guarding it and inventing a robot-shaped answer.
    /// Guarding it means a screen with less on it; inventing one means a duck
    /// drawn standing still while the real one walks. `BridgeDrive.noPictureHere`
    /// and `BridgeDrive.noWorldNoScene` are those absences, said out loud.
    private var drivingABench: BenchPeer? { venue == .real ? nil : benchPeer }

    // POINTING A PEER AT THE SELECTED BENCH IS THE STORE'S JOB NOW. The private
    // `makePeer` that stood here is `BenchStore.makePeer()`, moved whole: the
    // address off `armed(bench).resolved()`, the name, and the errand that
    // reads the token PER REQUEST with `BenchKeyStore.load(for:)` rather than
    // snapshotting it — the paragraph that argued for the per-request read is
    // now in the store beside the code it argues about.
    //
    // IT MOVED BECAUSE THIS IS NO LONGER THE ONLY SCREEN THAT NEEDS ONE. The
    // front door asks a duck what it is doing, which is a peer call, and a
    // second hand-rolled copy of this constructor is a second place for a
    // replaced token to go stale — which is the exact bug the per-request read
    // exists to prevent. One builder, owned by the thing that owns the benches.
    //
    // WHAT DID NOT MOVE IS WHERE THE URLSession LIVES. `BenchPeer` still takes
    // a closure rather than a session so the kit stays drivable by `swift test`
    // on a machine with no phone and no network; the store is in the app target
    // and supplies it.

    /// Throw the peer away and build the one this bench and token need.
    @MainActor private func rebuildPeer() {
        // `try?` BECAUSE THE ONE THING THE INITIALISER REFUSES CANNOT HAPPEN
        // HERE. It throws for a NaN hold and nothing else, and the hold is
        // `DuckDrive.holdSeconds`. An address that will not resolve is a
        // different matter and is not silently swallowed: there is simply no
        // peer until `requirePeer` is asked for one, and that call throws the
        // refusal with the sentence somebody can act on.
        //
        // AND `try?` FLATTENS THE STORE'S OWN NIL INTO THE SAME NOTHING. The
        // builder answers an optional now — nil for "no bench is selected" —
        // and a screen with no bench selected wants exactly what a screen with
        // an unreachable one wants here: no peer, no alert, and the refusal
        // saved for the moment somebody presses Drive.
        benchPeer = try? benches.makePeer()
        // THE NEW PEER HAS SEEN NOTHING. Carrying the old one's state line over
        // would put the last bench's sim clock under the new bench's name.
        stateSaid = nil
    }

    /// The robot link, as one value a `.task(id:)` can compare.
    ///
    /// IT CARRIES THE VENUE because arriving at the robot is as much a reason
    /// to subscribe as a link opening, and it carries the host so that
    /// connecting to a DIFFERENT robot re-asks rather than showing the previous
    /// one's networks under the new one's name.
    private var robotLinkKey: String {
        "\(venue.rawValue)·\(robot.isConnected)·\(robot.host)"
    }

    /// What the peer is pointed at, as one value `onChange` can compare.
    ///
    /// THE ADDRESS IS IN HERE, AND THE TOKEN IS NOT. Manage benches edits an
    /// address in place under the same id, so a key made of the id alone left
    /// the peer dialling a host the person had replaced while `/health` went
    /// to the new one — Stop posting to a dead machine. The token is left out
    /// for the opposite reason: a first cut put it here, which evaluated a
    /// synchronous Keychain read on every SwiftUI render, several times per
    /// round trip of the drive loop, and still missed a replaced token. The
    /// errand reads it per request instead (see `BenchStore.makePeer`), so this key only
    /// needs to know whether there is one.
    private var peerKey: String {
        guard let bench else { return "" }
        return "\(bench.id.uuidString)·\(bench.address)·\(bench.hasToken)"
    }

    /// Put a thrown thing on the glass in the words its own type wrote.
    ///
    /// ONE FUNNEL, BECAUSE THE SENTENCES ARE THE PRODUCT. Every refusal this
    /// app can suffer is a paragraph somebody wrote in the kit — what a bench
    /// does not have and why, what an address is not, which method a link does
    /// not carry — and the only way one of them reaches a person is for the
    /// catch that receives it to ask its own type for its `message`. Anything
    /// falling through to `localizedDescription` prints "The operation couldn't
    /// be completed", which is this app admitting it did not know what it
    /// caught. The list grew when the peer arrived: a peer refuses in three
    /// vocabularies of its own.
    ///
    /// A CALL STOP CUT OFF IS NOT A FAILURE, AND IT IS NOT SILENCE EITHER. It
    /// goes to `lastAction`, where the buttons report themselves, rather than
    /// into the alert — an alert apologising for a cancelled request over a duck
    /// that was just asked to stop is the app apologising for doing as it was
    /// told. Saying nothing at all would be worse: the trip count stops moving
    /// and nothing explains why.
    /// - Note: The list grew again with the robot link. `BridgeLink.LinkGone`
    ///   and `LinePeer.LinkEnded` are the two refusals only a real link can
    ///   produce — "nothing is connected" and "the far end stopped" — and both
    ///   have sentences written for them. Without these two rows they would
    ///   fall through to `localizedDescription`, which is this app admitting it
    ///   did not know what it caught, on the one screen where what it caught is
    ///   a robot.
    @MainActor private func report(_ error: Error) {
        if stopCutItOff(error) {
            // ONLY WHEN IT WAS STOP. Leaving the screen cancels the same errand
            // the same way, and the sentence was being written for that too —
            // a readout claiming a stop on a screen where nobody pressed one.
            if cutOffByStop { lastAction = "Stop cut off the call that was in flight." }
            cutOffByStop = false
            return
        }
        // A SAVED BENCH THAT NEVER ANSWERED IS NOT A REFUSAL TO SHOW IN A
        // DIALOG. Pressing Drive or a face button against a switched-off desk
        // bench used to end in "The bench refused: Could not connect to the
        // server." Play moves to the bench inside the app instead, and says so.
        if venue != .real, let left = bench, !left.isThisPhone, Self.neverAnswered(error) {
            Task { await fallBack(from: left) }
            return
        }
        // THE SYSTEM REFUSED TO SEND, so the bench never heard the request. Same move: the bench
        // in the app, and a sentence that says what to change, not a dialog at launch.
        if venue != .real, let left = bench, !left.isThisPhone, Self.blockedAsInsecure(error) {
            Task {
                await fallBack(from: left)
                lastAction = PhoneBenchReport.blockedAsInsecure(left.name)
            }
            return
        }
        // THE TITLE SAYS WHO REFUSED. A world this bank cannot hold is refused
        // by this app before anything is sent, and calling that a bench
        // refusal blames a bench that never heard about it.
        // AND ON A ROBOT IT IS NOT A BENCH EITHER. "The bench refused" over a
        // duck standing on a floor names the wrong machine, which is the exact
        // fault this title exists to avoid.
        if error is DuckWorld.Refusal {
            failureTitle = Self.worldRefusedTitle
        } else {
            failureTitle = venue == .real ? Self.robotRefusedTitle : Self.benchRefusedTitle
        }
        switch error {
        case let refusal as DuckBench.ReadError: failure = refusal.message
        case let refusal as DuckBench.Refusal: failure = refusal.message
        case let refusal as BenchEndpoint.Refusal: failure = refusal.message
        case let refusal as BenchPeer.Refusal: failure = refusal.message
        case let misuse as BenchPeer.Misuse: failure = misuse.message
        case let misuse as DuckCall.Misuse: failure = misuse.message
        case let refusal as DuckDrive.Refusal: failure = refusal.message
        // A WORLD THIS BANK CANNOT HOLD, REFUSED BEFORE IT WAS SENT. Fifteen
        // steps, a flight that reaches through a wall, a ball outside the
        // arena: `DuckWorld.Refusal` writes each of those in its own words and
        // `DuckBench.setWorld` throws rather than posting.
        case let refusal as DuckWorld.Refusal: failure = refusal.message
        // THE TWO ONLY A REAL LINK CAN THROW.
        case let gone as BridgeLink.LinkGone: failure = gone.message
        case let ended as LinePeer.LinkEnded: failure = ended.message
        case let refusal as DuckSubscription.ReadError: failure = refusal.message
        default: failure = error.localizedDescription
        }
    }

    /// Whether this failure is one Stop caused on purpose.
    ///
    /// BOTH SPELLINGS, BECAUSE THE CANCEL CROSSES A LIBRARY BOUNDARY. A task
    /// cancelled while it is inside `URLSession` comes back as
    /// `URLError.cancelled` — Foundation's word for it — and one cancelled
    /// anywhere else comes back as Swift's `CancellationError`. Checking only
    /// the second would put "cancelled (-999)" in an alert on the one path that
    /// actually happens.
    private func stopCutItOff(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }

    /// What the peer says it last saw, in `studio.state`'s own words.
    ///
    /// A READ THAT TOUCHES NOTHING, WHICH IS THE ONLY REASON A DRIVING LOOP CAN
    /// AFFORD IT. `BenchPeer` answers `studio.state` out of the block the last
    /// command came back with and posts nothing at all, because every endpoint
    /// this bench has advances physics to answer — so a read that went to the
    /// wire would be a measurement that changed what it was measuring. The cost
    /// here is an actor hop.
    ///
    /// THE CLOCK IS THE PEER'S WORD AND NOT THIS SCREEN'S. `t` is sim seconds,
    /// and the reply carries `clock` beside it precisely so that nobody prints
    /// it as elapsed real time; this reads both out rather than captioning the
    /// number itself.
    ///
    /// IT GOES QUIET RATHER THAN GUESSING. Before anything has been commanded
    /// the peer refuses — nothing has happened on this link yet — and after a
    /// `/reset` or a policy load, which are bench calls the peer never made, its
    /// memory is behind this screen's. Both end with no line rather than a stale
    /// one.
    @MainActor private func askWhatItSaw() async {
        // CLEARED BEFORE THE GUARD, so a layer switched off and on again shows
        // nothing rather than the sim clock from whenever it was last on.
        stateSaid = nil
        guard layers.contains(.link) else { return }
        // A ROBOT'S STATE IS NOT ASKED FOR, IT ARRIVES. `studio.state` is this
        // app's own method and `robotd` answers no such thing — which is why
        // `BridgeClient` narrows its reach to exclude it, so the line above
        // reads "not carried" rather than this screen discovering it with a
        // refusal by name. What a robot publishes comes off the subscription,
        // and `BridgeLink` holds the newest one.
        guard drivingABench != nil else {
            stateSaid = robotStateSaid
            return
        }
        guard let peer else { return }
        guard let reply = try? await peer.call(.state), reply.succeeded,
              let clock: String = reply.field("clock"),
              let t: Double = reply.field("t") else { return }
        stateSaid = String(format: "%@ clock %.2f s", clock, t)
    }

    /// What the robot last said about itself, or nil when it has said nothing.
    ///
    /// EVERY FIELD IS OPTIONAL AND EVERY ABSENCE IS SKIPPED RATHER THAN ZEROED.
    /// `DuckState`'s whole design is that a missing block reads as nil, because
    /// "a zero is a lie that looks exactly like data" — so this prints what the
    /// duck actually said and nothing else. A robot whose schema has moved
    /// under this build shows a short line, which is the signal, rather than a
    /// full one made of defaults.
    private var robotStateSaid: String? {
        guard let state = robot.lastState else { return nil }
        var parts: [String] = []
        if let policy = state.policy { parts.append(policy) }
        if state.safety?.fallen == true { parts.append("fallen") }
        if state.safety?.limp == true { parts.append("limp") }
        if let missed = state.loop?.missed, missed > 0 { parts.append("\(missed) missed ticks") }
        if let volts = state.battery?.volts {
            parts.append(String(format: "%.1f V", volts))
        }
        parts.append("\(robot.statesHeard) states")
        return parts.joined(separator: " · ")
    }

    /// `/health` again, and nothing else. A network just put on the bench is
    /// in the bench's list and not yet in this tab's copy, and the next
    /// settle would put the map back to its role with `staleNetwork` for a
    /// name the bench answers to. Re-reading the list is a status GET that
    /// advances no physics.
    @MainActor private func refreshHealth() async {
        guard let address = try? requireBench() else { return }
        if let fresh = try? DuckBench.readHealth(await ask(DuckBench.health(address))) {
            health = fresh
        }
    }

    /// A bench that never answered, as opposed to one that answered no.
    ///
    /// URLSession's connection-level codes only: a bench that is switched off,
    /// asleep, off this network, or at an address that resolves to nothing. A
    /// bench that answered with a refusal is a different fact and keeps its
    /// own sentence.
    private static func neverAnswered(_ error: Error) -> Bool {
        guard let failure = error as? URLError else { return false }
        return [.cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost,
                .notConnectedToInternet, .dnsLookupFailed].contains(failure.code)
    }

    /// iOS's App Transport Security refused a plain-HTTP request before it was sent.
    private static func blockedAsInsecure(_ error: Error) -> Bool {
        (error as? URLError)?.code == .appTransportSecurityRequiresSecureConnection
    }

    /// Move Play to the bench inside the app, connect to it, and say which bench was left.
    @MainActor private func fallBack(from left: BenchEndpoint) async {
        benches.selectedID = BenchEndpoint.thisPhone.id
        await connect(fallingBack: false)
        lastAction = PhoneBenchReport.fellBack(from: left.name,
                                               to: bench?.name ?? PhoneBenchReport.name)
    }

    @MainActor private func connect(fallingBack: Bool = true) async {
        busy = true
        defer { busy = false }
        // THE ROBOT VENUE HAS NOTHING TO CONNECT TO AND MUST NOT BUILD ONE.
        // The link is opened by a person on the Robot tab; what this screen
        // does on arrival is ask the robot to start talking, once.
        if venue == .real {
            await askTheRobotToTalk()
            return
        }
        rebuildPeer()
        do {
            let peer = try requirePeer()
            // WHO IS ON THE OTHER END, ASKED IN THE ROBOT'S OWN WORD. `hello`
            // is the one call every transport in the vocabulary carries, and
            // asking it here is what makes this screen's first move a peer's
            // rather than a bench's.
            //
            // IT LANDS ON `/health`, WHICH THE NEXT LINE ASKS AGAIN FOR A
            // DIFFERENT REASON, and that is two GETs where there used to be
            // one. It is worth the second: `/health` is a status read that
            // advances no physics, on a machine on the same desk, and the two
            // questions are genuinely different — "who are you" is answerable
            // by every peer this app will ever hold, and "which policies do you
            // hold" is answerable by none of them but this one. Collapsing them
            // would mean the handshake was bench-shaped again, which is the
            // thing this change exists to end.
            let greeting = try await peer.call(.hello)
            if let refusal = greeting.failure {
                failure = DuckBench.ReadError.bench(refusal.message).message
                return
            }
            health = try DuckBench.readHealth(
                await ask(DuckBench.health(try requireBench())))
            await askWhatItSaw()
            // NOT GUESSED, AND NOT POSTED. `/health` lists the policies a bench
            // HOLDS and says nothing about which one is loaded, and the old
            // line here loaded the first name in that list on every connect —
            // which, once My Microduck could load a policy of its own, meant
            // opening this tab silently undid the quick action somebody had
            // just launched. The map settles against what this bench holds IN
            // MEMORY ONLY: a network it does not have is put back with
            // `DuckPadMap.staleNetwork`, a role it cannot fill keeps its role,
            // and nothing is asked for.
            //
            // `/health` still says nothing about what is loaded — `/intent`'s
            // reply does, which is why the readout can name it without a
            // request. The first `POST /policy` of a session happens on the
            // first round trip after Drive, where the person can see it coming.
            lastAction = desk.settle(against: health?.policies ?? [],
                                     lastLoaded: benches.lastLoaded(for: bench?.id)) ?? lastAction
            // AND WHAT ROOM IT IS STANDING IN, which is the other half of "what
            // am I looking at". `/health` says which policies the bench holds;
            // this says where the duck is, and the stage draws the answer. An
            // older bench 404s it and the picker goes dead with the reason
            // under it — see `readWorld`.
            await readWorld(try requireBench())
        } catch {
            // THE SIMPLEST BENCH IS THE ONE THAT CANNOT BE SWITCHED OFF. A saved
            // desk bench that never answered left Play with nothing to drive and
            // every face button saying "holds no policy" (build 79, 2026-10-02).
            // The bench inside the app carries every bundled network, so Play
            // moves to it once, keeps it selected — the simplest setup is the
            // default again — and says which bench it left.
            if fallingBack, let left = bench, !left.isThisPhone, Self.neverAnswered(error) {
                busy = false
                await fallBack(from: left)
                return
            }
            report(error)
        }
    }

    /// Ask the robot to start pushing its state, and record what it runs.
    ///
    /// THE FIRST THING THIS SCREEN SAYS TO A ROBOT, AND IT IS NOT A COMMAND.
    /// `robot.subscribe` is answered with what is constant for the life of that
    /// `robotd` — which walking and standing networks are loaded, which skills
    /// exist, or why nothing is driving — and that answer is the honest
    /// replacement for the bench's `/health` policy list. It is also the only
    /// way a state ever arrives: `robotd` pushes `robot.state` to connections
    /// that asked, and to no others.
    ///
    /// IT IS SAFE TO RUN TWICE. A second subscribe on one connection re-states
    /// the rate; nothing is created and nothing moves. So this is called on
    /// arrival and whenever the link changes underneath, without bookkeeping to
    /// stop it.
    @MainActor private func askTheRobotToTalk() async {
        guard robot.isConnected else { return }
        do {
            _ = try await robot.subscribeToState()
            await askWhatItSaw()
        } catch { report(error) }
    }

    /// What world the bench says it is in, and what to do when it has no
    /// opinion because it has no route.
    ///
    /// A FAILED READ IS NOT A FAILED SCREEN. This is called on connect, after
    /// every write and whenever the bench changes, and none of those is a
    /// moment to put an alert in front of somebody: `/health` has already
    /// answered, so a 404 here is the build and a thrown reader is the same
    /// bench answering an unknown path in its own words. Both mean the same
    /// thing to this screen and both end with the picker dead and
    /// `DuckWorld.noWorldRoute` printed where the control was. A transport
    /// failure — the link dropping between the two calls — changes nothing at
    /// all, because "the network went away" is not evidence about a route.
    @MainActor private func readWorld(_ address: DuckBench.Address) async {
        do {
            let (data, status) = try await askStatus(DuckBench.world(address))
            guard status != 404 else {
                worldRouteMissing = true
                world = nil
                return
            }
            world = try DuckBench.readWorld(data)
            worldRouteMissing = false
            worldNote = nil
            // NOBODY PREDICTED THIS ONE. A read finds whatever is standing —
            // laid by a previous session, by another client, or by nothing at
            // all — and the last plan this screen made is not about it.
            predicted = []
            worldChoice = standingChoice
            // THE CAMERA STAYS ON THE DUCK. A world's steps stand 1.305 m to
            // its left and the duck has to be driven to them; framing the
            // flight from here put the duck out of the picture (and framing
            // the bench's own scattered blocks put the camera nineteen
            // metres away and turned the stage black, build 46).
            orbit.frame(nil)
        } catch {
            // NOT A MISSING ROUTE: that answered 404 above and was handled. A
            // bench that has the route and still cannot be read is shown as
            // unread, with its reason in the footnote, and the picture is
            // left as it was.
            world = nil
            worldNote = (error as? DuckBench.ReadError)?.message ?? error.localizedDescription
        }
    }

    /// Ask again, from scratch, because the bench changed underneath.
    @MainActor private func refreshWorld() async {
        // THE VERDICT IS THROWN AWAY FIRST. `worldRouteMissing` is a fact about
        // one machine, and carrying the last bench's answer over would leave
        // the picker dead against a bench that has the route.
        worldRouteMissing = false
        worldNote = nil
        world = nil
        predicted = []
        worldChoice = .benchOwn
        guard let address = try? requireBench() else { return }
        await readWorld(address)
    }

    /// Stand the bench in the world a row asks for.
    ///
    /// THE ANSWER TO THE WRITE IS THE READBACK, so nothing here has to ask
    /// again on the happy path: `POST /world` and `GET /world` return the same
    /// block on purpose. What does ask again is the refusal path — a 400 leaves
    /// the world the bench found, and this screen has to find out what that was
    /// rather than assume the request half-landed.
    ///
    /// TWO ROWS SEND NOTHING, AND THEY ARE NOT INERT. "The bench's own world"
    /// is a real choice with a real consequence — it is the one that keeps a
    /// drive comparable with every published number — and picking it after
    /// something else is standing re-reads and says so, in
    /// `DuckWorld.benchOwnWorld`, rather than pretending to have put the bank
    /// back. Nothing can put it back: `WORLD.set` is one-way on the bench until
    /// the process restarts, and claiming otherwise would be this screen
    /// inventing an endpoint.
    @MainActor private func stand(in choice: WorldChoice) async {
        worldNote = nil
        busy = true
        defer { busy = false }
        do {
            let address = try requireBench()
            guard let plan = planFor(choice) else {
                await readWorld(address)
                if case .benchOwn = choice, world?.isSet == true {
                    worldNote = DuckWorld.oneWayUntilRestart
                }
                worldChoice = standingChoice
                return
            }
            let (data, status) = try await askStatus(try DuckBench.setWorld(address, plan))
            guard status != 404 else {
                worldRouteMissing = true
                world = nil
                return
            }
            world = try DuckBench.readWorld(data)
            worldRouteMissing = false
            predicted = plan.predicted
            worldChoice = standingChoice
        } catch {
            report(error)
            // THE PICKER GOES BACK TO WHAT IS THERE, NOT TO WHAT WAS ASKED FOR.
            if let address = try? requireBench() { await readWorld(address) }
            worldChoice = standingChoice
        }
    }

    /// The loop. One command in flight at a time, and physics only advances
    /// while one is — so this IS the clock, not a timer running beside it.
    ///
    /// IT NOTIFIES RATHER THAN CALLS, WHICH IS THE ROBOT'S OWN DIRECTION FOR A
    /// TWIST. `robot.move` is a continuous intent: sent as a notification at
    /// 20–50 Hz, last-writer-wins, and on hardware it EXPIRES. `BenchPeer.notify`
    /// still awaits a round trip, because a bench answers everything and
    /// answering is how it reports the physics it just ran — but it hands back
    /// nothing, so a loop written here stays valid against a peer that really
    /// does not reply. The pacing is unchanged: one intent at a time, holding
    /// `DuckDrive.holdSeconds` of sim, the round trip as the clock.
    ///
    /// THE STANCE COMES BACK OFF THE PEER, NOT OUT OF THE REPLY. Fifteen joint
    /// angles and a root quaternion are not something anybody reads back with
    /// `DuckReply.field(_:)`, and `BenchPeer` says why it keeps them whole
    /// instead: re-serialising them into a reply would be a second spelling of
    /// `DuckDrive.Live` for the drawing code to parse again. `live` is the
    /// accessor `BenchPeerTests` pins, and it is the one thing a second peer
    /// would have to answer to drive this screen.
    @MainActor private func drive() async {
        while running {
            do {
                let peer = try requirePeer()
                // ONE CONSULT PER ROUND TRIP, BEFORE THE NOTIFY. `live?.t` is
                // the bench's clock BEFORE this twist is applied, which is
                // exactly what `DuckBench.Step.at` means, and `live?.policy` is
                // the bench's own word for what is on the servos. The pilot
                // hands back one command whether it is steering, recording or
                // replaying — there is never a second intent stream.
                //
                // ON A ROBOT BOTH OF THOSE ARE NIL AND THAT IS CORRECT, not a
                // degraded reading. There is no sim clock on a duck standing on
                // a floor, and what is on its servos was named once, when this
                // app subscribed — the pilot's recorder simply has no clock to
                // stamp against, which is why a take is not offered there.
                // A STICK RESTS IN AUTO WITH NOTHING RUNNING (build 93), and that has to hold in
                // this loop too: a practice duck's loop outlives the stick that started it.
                let go = desk.step(steering: arbiter.sticksRest ? .still : twist, simSeconds: live?.t,
                                   policySaid: live?.policy)
                // LOADING A NETWORK IS A BENCH CALL AND STAYS ONE. `robotd`
                // owns its slots; there is no method in the vocabulary for
                // "put this file on the servos", so on a robot the request is
                // reported rather than silently dropped.
                if let want = go.load {
                    if drivingABench != nil {
                        await swap(to: want)
                    } else {
                        lastAction = BridgeDrive.noPolicySwapHere
                    }
                }
                // THE ONE LINE THIS WHOLE CHANGE EXISTS FOR. It is unchanged —
                // that is the point: `notify(.move(_:))` was already written
                // against the vocabulary rather than against a bench, so the
                // only thing that had to move was the TYPE of `peer`.
                //
                // THE HEAD MODE ZEROES THE TWIST AND DOES NOT SKIP IT. Sending
                // no move at all while somebody poses the head would leave the
                // last twist standing until a deadman aged it out, which is a
                // robot that keeps walking for up to half a second because
                // somebody looked around. `padd` puts both in one frame for
                // exactly this reason.
                if posingRobotHead {
                    try await peer.notify(.move(.still))
                    try await peer.notify(.head(DuckDrive.head(for: sticks)))
                } else {
                    try await peer.notify(.move(go.command))
                }
                if let bench = drivingABench {
                    // A BENCH ANSWERS EVERY CALL AND THE ANSWER IS THE PHYSICS
                    // IT JUST RAN, so the round trip is this loop's clock.
                    live = await bench.live
                } else {
                    // A ROBOT DOES NOT ANSWER A TWIST AT ALL — the contract's
                    // continuous intents are notifications — so nothing here
                    // paces the loop and this must pace itself, or it spins as
                    // fast as the CPU will let it and floods a relay with
                    // frames the send slot immediately supersedes.
                    //
                    // THE INTERVAL IS DERIVED FROM THIS BRIDGE'S OWN DEADMAN,
                    // never picked: see `BridgeDrive.interval(_:)`. Sleeping
                    // longer than a third of the shortest deadman in the chain
                    // is handing the duck to a timer while somebody is still
                    // driving it.
                    try await Task.sleep(nanoseconds:
                        UInt64(robot.interval * 1_000_000_000))
                }
                // A CHAINED SEQUENCE LOADS ITS SLOT WHEN IT FINISHES, and a
                // take that closed itself on a ceiling prints its own sentence.
                // Neither is in the seam as written; without them the chain is
                // silently half a chain and the ceiling is silent. See the
                // build log, deviation 3.
                if let slot = go.thenLoading {
                    if let file = DuckQuickActions.filename(filling: slot,
                                                            among: health?.policies ?? []) {
                        await swap(to: file)
                    } else {
                        // NOT SILENCE: the map may chain onto a slot this bench
                        // does not hold, and the pad, the map section and the
                        // bind sheet all say so — the chain says so too.
                        lastAction = isSimple ? DuckQuickActions.notHeldHereShort(slot)
                                              : DuckQuickActions.notHeldHere(slot)
                    }
                }
                if let note = go.note { lastAction = note }
                trips += 1
                noticeJoints()
                await askWhatItSaw()
            } catch {
                // A CANCELLED TRIP IS THE LOOP BEING TOLD TO END — by Pause,
                // by Stop, or by the screen going away — and the loop ending
                // is the whole of what there is to say about it.
                if !stopCutItOff(error) { report(error) }
                running = false
            }
        }
    }

    /// The rigid tap for a joint that has arrived at a stop.
    ///
    /// A JOINT AGAINST ITS STOP IS A WORLD EVENT, which is the only kind this
    /// app spends the taptic engine on: the person is watching the duck, the
    /// screen is showing something else, and a policy driving the neck into the
    /// −1.920 rad stop and staying there is precisely the finding they came to
    /// find. `.rigid` because that is what hitting a wall feels like.
    ///
    /// ON THE EDGE ONLY — see `wasNearALimit`.
    @MainActor private func noticeJoints() {
        guard let live else { wasNearALimit = false; return }
        let near = !DuckPad.nearLimits(live.stance.jointAngles).isEmpty
        if near, !wasNearALimit { Haptic.jointAtStop() }
        wasNearALimit = near
    }

    /// THE STOP A TAP MAKES (build 93). The latch shuts and robot.stop goes on its way INSIDE the
    /// tap handler, before anything is awaited; only the read-back afterwards is a Task. The disc,
    /// Escape, the magic tap and a heard "stop" all come here, so none of them is one main-actor
    /// hop late.
    @MainActor private func stopNow() {
        latchStop()
        Task { await finishStop() }
    }

    /// Stop: zero the command and let the duck settle under it.
    ///
    /// THE ONE ERRAND THAT PRE-EMPTS. Three things happen before a byte goes
    /// out, in this order and for three different reasons. `running` stops the
    /// loop from starting another turn. The sticks go to centre so that a thumb
    /// still on the glass is not the next command. And the errand in flight is
    /// CANCELLED — which is the part that was missing: without it a stop
    /// pressed during a round trip could only queue behind it, and a request to
    /// a bench that has gone quiet is allowed two minutes to give up. A stop
    /// somebody has to wait two minutes for is not a stop.
    ///
    /// IT RAISES `stopping` AND NOT `busy`, so nothing it does can disable the
    /// button that started it. Press it twice and the bench is told twice to do
    /// what it is already doing, which is the correct answer to somebody who is
    /// not sure it heard.
    ///
    /// A DISCRETE CALL, BECAUSE THE CALLER NEEDS TO KNOW IT LANDED. `robot.stop`
    /// is a request in Pollen's contract for exactly that reason — "I asked it
    /// to stop" is not the same claim as "it stopped" — so this is `call` and
    /// not `notify`, and a bench that refuses gets its own sentence rather than
    /// a thrown error that would read like a broken network.
    @MainActor private func halt() async {
        latchStop()
        await finishStop()
    }

    /// Everything a Stop does that needs no answer: the kit's stop, this screen's loop and stick.
    /// Always latches, with or without a duck attached.
    @MainActor private func latchStop() {
        // THE KIT'S STOP FIRST: robot.stop on its way, the latch shut, every run cancelled, nothing
        // awaited. What follows is this screen putting its own loop and stick down.
        runs.stop()
        coach(.stop)
        say(runs.caption)
        _ = arbiter.handle(.stop, at: Date())
        ask.ended()
        listener.cancel()
        stickStarted = false
        if dreamModel.running { dreamModel.stop() }
        running = false
        touchSticks = .centred
        // STOP ENDS A TAKE AND A REPLAY TOO, and what was driven up to the stop
        // is kept. This cannot throw and cannot await, so it changes nothing
        // about the one thing this function exists to do.
        desk.pilot.cutOff(.stop)
        if let flight, !flight.isCancelled { cutOffByStop = true }
        flight?.cancel()
    }

    /// The part of a Stop that waits: a second robot.stop on this screen's peer and the read-back.
    @MainActor private func finishStop() async {
        guard peer != nil else { return }
        stopping = true
        defer { stopping = false }
        do {
            let peer = try requirePeer()
            // `robot.stop` IS THE SAME REQUEST ON BOTH LINKS. It zeroes the
            // command; it is NOT "go limp", which is `robot.relax` and which
            // this screen does not offer, because a duck that goes limp falls
            // over.
            let answer = try await peer.call(.stop)
            if let refusal = answer.failure {
                // THE BENCH'S OWN WORDS, IN THE READER'S OWN WRAPPER. A refusal
                // that came back in a reply rather than as a throw is still the
                // bench saying no, and it is the same sentence `/stop` produced
                // before the peer existed.
                failure = DuckBench.ReadError.bench(refusal.message).message
                return
            }
            live = await drivingABench?.live
            // A DUCK CAN ARRIVE AT A STOP WHILE IT SETTLES, and a stop that
            // ends with a joint clipped is the same finding as one found while
            // driving. The other reason to call it here is bookkeeping: without
            // it the edge would still hold the reading from before the stop.
            noticeJoints()
            await askWhatItSaw()
        } catch { report(error) }
    }

    @MainActor private func putBack() async {
        running = false
        touchSticks = .centred
        // RESET IS NOT DRAWN IN THE ROBOT VENUE AND CANNOT BE REACHED THERE,
        // and this guard is the second lock on the same door: `/reset`
        // teleports a duck upright, which is not something that can be asked of
        // a machine standing on somebody's floor. Without it, a Reset pressed
        // through the magic tap or a keyboard while the venue was Robot would
        // post to whichever bench happened to be selected — a different duck
        // entirely, moving in another room.
        guard drivingABench != nil || venue != .real else {
            lastAction = BridgeDrive.noWorldNoScene
            return
        }
        busy = true
        defer { busy = false }
        do {
            live = try DuckDrive.readLive(await ask(try DuckDrive.reset(try requireBench())))
            trips = 0
            // A RESET IS A NEW WORLD. Whatever was against a stop is not any
            // more, and the next joint that arrives at one should be felt as an
            // arrival rather than swallowed as "still there".
            wasNearALimit = false
            // AND THE PEER DID NOT SEE IT HAPPEN. `/reset` is a bench call —
            // `robot.init` is refused here, and for a good reason — so the block
            // the peer is holding is now older than the duck on the screen. The
            // link layer says nothing rather than saying that.
            stateSaid = nil
        } catch { report(error) }
    }

    /// Hot-swap the network the bench is running.
    ///
    /// THE TAP IS `behaviourStarted`, AND IT IS DELIBERATELY NOT A SELECTION.
    /// A hot-swap is not somebody scrubbing a picker — it is a different
    /// network taking the servos, mid-stance, without the world restarting, and
    /// the duck's behaviour changes underneath a person who is looking at the
    /// duck. That is a world event and `.impact(.medium)` is the design
    /// system's feeling for one. `Haptic` has no `selection()` on purpose and
    /// says why in its own preamble; reaching around it with a raw
    /// `UISelectionFeedbackGenerator` here would put a second haptic vocabulary
    /// in a view file and spend the one channel this app has to the far side of
    /// the room on a tap somebody's own finger already reported.
    ///
    /// AFTER THE ANSWER, NOT AFTER THE PRESS. The tap means the bench swapped,
    /// which is the fact worth feeling; a refused swap produces the alert and
    /// no tap at all.
    /// A BENCH CALL, AND IT STAYS ONE. Loading a network into a slot is not
    /// something a duck can be asked to do: `robotd` owns the switching on the
    /// robot and the pad's face buttons trigger skills through it, so there is
    /// no method in the vocabulary for "put this file on the servos". `/policy`
    /// is the bench's own door and this is the app's one caller of it.
    @MainActor private func swap(to policy: String) async {
        guard !policy.isEmpty else { return }
        guard venue != .real else {
            lastAction = BridgeDrive.noPolicySwapHere
            return
        }
        do {
            live = try DuckDrive.readLive(
                await ask(try DuckDrive.load(try requireBench(), policy: policy)))
            // RECORDED, so the picker can show it next time without a request
            // and My Microduck's card and this tab agree about the servos.
            if let id = bench?.id { benches.noteLoaded(policy, on: id) }
            // AND THE DESK LEARNS IT TOO, so the map's automatic locomotion
            // load does not ask for a network that is already on the servos.
            desk.noteLoaded(policy)
            Haptic.behaviourStarted()
            // THE PEER DID NOT SEE THIS EITHER — see `putBack`. A different
            // network is on the servos and the block the peer is holding came
            // from the one before it.
            stateSaid = nil
        } catch { report(error) }
    }
}

// MARK: - the numbers this screen writes down for itself

/// Dimensions that are layout decisions rather than facts, gathered so the next
/// person can see which ones are load-bearing.
///
/// NOTHING HERE IS A COLOUR OR A CONTRAST, which is the line `Theme` draws and
/// this file stays behind: a ratio is a fact and lives in `Palette` where a test
/// can run the formula over it. How tall to let a viewport get is not a fact
/// about anything, it is a judgement about a phone.
private enum DriveMetric {
    /// A degree, in radians — the step a joint slider takes.
    static let oneDegree = Double.pi / 180
    /// How long the bench takes to move from where the duck is to a posed
    /// pose. Long enough to be a move rather than a snap, short enough that
    /// a person waiting for the sticks does not wonder.
    static let poseSeconds: TimeInterval = 1.2
    /// How long a batch motion run may take. Eight rollouts of a stairs cell
    /// on a small board is minutes; one rollout of a two-second motion is
    /// seconds, and this is the ceiling either way.
    static let motionSeconds: TimeInterval = 900
    /// How long the run's last frame stays on the picture before the live duck
    /// gets it back. Long enough to see what the motion ended in.
    static let holdLastFrameSeconds: TimeInterval = 0.7
    // `captionBacking` MOVED WITH THE BOX IT BELONGED TO. It had exactly one
    // reader, `floorCaption`, and that body is now `StageCaptionBox` in
    // `DesignComponents` — where `StageCaptionBox.backing` is the same 0.85 in
    // the one place a second screen can reach it. Two copies of a backing
    // opacity is the drift the design system exists to prevent.
    /// The viewport card. Its readout takes `viewport.inner`, which is how the
    /// concentric rule is expressed rather than asserted — pick a different
    /// outer radius and the inner one follows.
    static let viewport = Palette.Radius.group
    /// The pad deck card. Its thumb pads take `deck.inner`.
    static let deck = Palette.Radius.group

    // `viewportHeight` HAS GONE WITH THE CAP IT WAS. It was 300 — "how much of
    // the screen the duck is allowed" — one of the five independent copies of
    // that number `StageViewport.standardHeight` exists to replace. This screen
    // does not cap the picture any more: the stage IS the tab, and the two
    // pieces of chrome that stand on it are MEASURED (`topChromeHeight`,
    // `bottomChromeHeight`) rather than budgeted. Nothing in this file reads it,
    // and a constant kept for a layout that is gone is a number the next person
    // has to work out is dead. `StageViewport.standardHeight` is where the 300
    // lives for the screens that still cap.

    /// How wide the three-segment venue switch is allowed to get. The same
    /// argument `VenuePicker` makes about its two: wide enough that "Sim |
    /// Your floor | Robot" is not stretched across an iPad, and lifted
    /// entirely at accessibility sizes, where a segmented control truncates
    /// rather than wrapping.
    static let venueSwitchWidth: CGFloat = 320

    /// Where the ball goes when somebody picks the ball row: straight ahead of
    /// the duck's spawn, comfortably inside the 1.45 m arena and far enough to
    /// be walked at. One number, so the row's label and the request it sends
    /// cannot disagree.
    static let ballAhead = 0.80

    /// How wide the readout may grow. Wide enough for a telemetry label beside
    /// its value at the default text size, narrow enough that the duck — which
    /// is drawn centred — is never behind it. At accessibility sizes
    /// `TelemetryRow` stacks its pair, so this stops being the binding
    /// constraint exactly when it would have been.
    static let readoutWidth: CGFloat = 260

    /// How many joints the `joints` layer puts on one line.
    ///
    /// SEVEN IS HALF THE DRIVEN JOINTS, so the ordinary grid is two rows a
    /// reader can compare down a column. At an accessibility size seven columns
    /// of `%7.3f` are wider than any phone, and a table running off the glass is
    /// a table with numbers missing from it — so the layer folds onto more,
    /// shorter rows instead. Two, not three, because the type at those sizes is
    /// nearly three times as wide per character as it is here.
    static let jointColumns = 7
    static let jointColumnsEnlarged = 2

    /// A hairline STROKE, the app's one.
    static let hairlineStroke = DesignMetric.hairlineStroke

    /// The dot in the corner of a face button somebody has remapped.
    ///
    /// FOUR POINTS IS A MARK, NOT A CONTROL. It is never the only way the
    /// remap is known — `DuckPadMap.Shown.detail` is the accessibility hint on
    /// the same button and the map's own row spells it out — so nothing is
    /// carried by a four-point circle alone, and it takes none of the sixty
    /// points the button owes a thumb.
    static let remapDot: CGFloat = 4

    /// How far a press darkens a control: the delta `PrimaryActionStyle` uses,
    /// by name. It is here because a button pressed on a paired controller has
    /// to look like a button pressed with a thumb, and the style cannot see
    /// Bluetooth.
    static let pressDelta = DesignMetric.pressDelta
}


/// A control that is on the pad and does nothing against a bench.
///
/// DIMMED, AND STILL A REAL BUTTON. `padd` binds fifteen controls and a physics
/// server can honour eight of them; the other seven are drawn because pressing
/// one is how a tester finds out that the mouth is servo nine and no network
/// drives it. So this is not `.disabled` — a disabled control is invisible to
/// VoiceOver and unreachable by Switch Control, and the sentence is the whole
/// point of the button.
///
/// IT KEEPS A REAL SURFACE RATHER THAN FADING. Half-opacity takes a glyph to
/// roughly 2:1 and makes "why can't I press this" unanswerable.
/// `backgroundSecondary` is the palette's recessed ground and carries
/// `textSecondary` at over six to one in light and over nine to one in dark, so
/// this reads as unavailable because it lost the action colour — the same
/// argument `PrimaryActionStyle` makes about its disabled state.
///
/// THE TARGET COMES OFF THE SPACING SCALE. `.loose` either side of a footnote
/// glyph and `.standard` above and below it is a shape comfortably past the
/// HIG's forty-four point floor in both directions, which means this file never
/// writes that floor down as a number — there is exactly one of those in the
/// app and it is in `DesignComponents`.
private struct DeadControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(Theme.spacing(.hairline))
            .frame(minWidth: DesignMetric.movingTarget, minHeight: DesignMetric.movingTarget)
            // PRESSED IS A STEP UP THE PALETTE, NOT AN OPACITY. `separator` is
            // the one token between the surfaces and the type, which is exactly
            // the size of step a press needs to be seen and no larger; it still
            // carries `textSecondary` well past 4.5:1 in both schemes.
            .background(Capsule().fill(configuration.isPressed ? Theme.separator
                                                              : Theme.backgroundSecondary))
            .overlay(Capsule().strokeBorder(Theme.separator,
                                            lineWidth: DriveMetric.hairlineStroke))
            .contentShape(Capsule())
    }
}

// MARK: - the sticks

/// One thumb pad: drag inside it, and it reports where the thumb is as -1...1
/// on each axis. Let go and it springs back to centre.
///
/// SPRINGING BACK IS THE SAFE DEFAULT AND IT IS NOT DECORATION. A pad that kept
/// its last position would leave a command standing after the thumb left the
/// glass, and the duck would keep walking on a stick nobody is touching. A real
/// gamepad's stick is sprung; this is the same promise in software.
///
/// THE KNOB IS A SERVO HORN AND THE TRACK IS ITS COLLAR. `JointNode` is the
/// app's drawing of a joint — a dark hub inside a quieter ring, growing with
/// load — and a stick is the one place in the interface where the person IS the
/// load. Pushed to the edge the knob is at its largest, which says the same
/// thing the rigid tap says and says it to somebody who cannot feel taps. The
/// circle it travels in is the collar, drawn so the deflection the mapping
/// treats as full is a thing you can see rather than a divisor in a gesture.
/// The thumb knob, drawn as the duck's eye: a yellow disc with an ink outline
/// and a white catchlight, growing with load the way `JointNode` does (from
/// `.standard` to `.loose`), so `ThumbPad.travel` still keeps it inside the pad.
private struct PondEyeKnob: View {
    let load: Double

    var body: some View {
        let clamped = CGFloat(min(max(load, 0), 1))
        let free = Theme.spacing(.standard) + Theme.spacing(.hairline)
        let loaded = Theme.spacing(.loose)
        let diameter = free + (loaded - free) * clamped
        Circle()
            .fill(Theme.actionYellow)
            .overlay(Circle().strokeBorder(Theme.outline, lineWidth: DesignMetric.outlineStroke))
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(DesignFixed.catchlight)
                    .frame(width: diameter * 0.28, height: diameter * 0.28)
                    .offset(x: diameter * 0.2, y: diameter * 0.18)
            }
            .frame(width: diameter, height: diameter)
    }
}

struct ThumbPad: View {
    let title: String
    @Binding var stick: DuckDrive.Stick
    /// Whether the vertical axis does anything. The Turn pad's does not —
    /// `padd` spends the right stick's y on head pose, which this does not
    /// offer — so it is drawn as a horizontal track rather than a square that
    /// silently ignores half of what you do in it.
    var verticalIsLive = true

    /// The pad's side.
    ///
    /// SMALLER THAN IT WAS, BECAUSE THE BUTTONS GOT BIGGER. Two of these and a
    /// row of sixty-point controls have to share the narrowest phone still
    /// supported; a hundred and twelve points is still a comfortable thumb pad
    /// and is what leaves room for controls sized the way a control that moves
    /// a machine should be.
    private static let size: CGFloat = 112
    private var radius: CGFloat { Self.size / 2 }

    /// How far the knob's centre goes at full deflection, and the divisor the
    /// drag is measured against — one number, so the ring on the glass and the
    /// mapping underneath it cannot disagree.
    ///
    /// THE PAD'S RADIUS LESS HALF THE LARGEST A JOINT NODE GETS. `JointNode`
    /// grows from `.standard` to `.loose` with load, so a fully-loaded knob
    /// pushed to the edge sits exactly inside the pad rather than half out of
    /// it. It used to be the radius less half a fixed forty-two point circle,
    /// which is the same idea with the knob's size written out as a literal in
    /// two places.
    private var travel: CGFloat { radius - Theme.spacing(.loose) / 2 }

    /// Whether the stick is against a stop, so the rigid tap fires once on
    /// arrival rather than on every frame of a thumb held at the edge.
    @State private var atLimit = false

    /// True while a finger is on the pad. A `GestureState` resets itself however the touch ends,
    /// including the ways `onEnded` never hears: the system taking the touch away.
    @GestureState private var touching = false

    var body: some View {
        VStack(spacing: Theme.spacing(.tight)) {
            ZStack {
                // POND DAY: a pale lavender well with an ink rim (a dusk
                // well with a lavender rim at night), not a dark hole.
                pad.fill(Theme.stickPad)
                pad.strokeBorder(Theme.stickPadRim, lineWidth: DesignMetric.outlineStroke)
                Circle()
                    .strokeBorder(Theme.stickPadRim.opacity(0.35),
                                  lineWidth: DriveMetric.hairlineStroke)
                    .frame(width: travel * 2, height: travel * 2)
                Image(systemName: verticalIsLive
                      ? "arrow.up.and.down.and.arrow.left.and.right"
                      : "arrow.left.and.right")
                    .font(.title3)
                    .foregroundStyle(Theme.textTertiary)
                PondEyeKnob(load: deflection)
                    .offset(x: CGFloat(stick.x) * travel,
                            y: CGFloat(verticalIsLive ? -stick.y : 0) * travel)
                    // THE PAD IS THE ELEMENT, NOT THE KNOB. `JointNode` carries
                    // its own label and value, and left visible it would put a
                    // second thing to swipe past inside a control that already
                    // says where it is pushed.
                    .accessibilityHidden(true)
            }
            .frame(width: Self.size, height: Self.size)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, on, _ in on = true }
                    .onChanged { drag in
                        // SCREEN Y IS DOWN AND THE ROBOT'S IS FORWARD, so the
                        // flip belongs here, in the only place that knows about
                        // glass. `DuckDrive.Stick` documents that it takes the
                        // already-flipped value.
                        let x = Double(drag.location.x - radius) / Double(travel)
                        let y = Double(radius - drag.location.y) / Double(travel)
                        let next = DuckDrive.Stick(
                            x: min(max(x, -1), 1),
                            y: verticalIsLive ? min(max(y, -1), 1) : 0)
                        // A STICK AT ITS LIMIT IS A WALL, AND `.rigid` IS WHAT A
                        // WALL FEELS LIKE. Pushing further does nothing, and the
                        // person is looking at the duck rather than at the pad,
                        // so the only channel left for "that is as fast as it
                        // goes" is the one under their thumb. Once, on arrival:
                        // a thumb parked at the edge would otherwise buzz for as
                        // long as it stayed there.
                        let now = abs(next.x) >= 1
                            || (verticalIsLive && abs(next.y) >= 1)
                        if now, !atLimit { Haptic.stickAtLimit() }
                        atLimit = now
                        stick = next
                    }
                    .onEnded { _ in
                        stick = .centred
                        atLimit = false
                    }
            )
            // A TOUCH THE SYSTEM CANCELLED AND A PAD TAKEN OFF THE GLASS NEVER REACH `onEnded`, and
            // a stick left deflected keeps walking a real duck with nobody touching it.
            .onChange(of: touching) { _, on in
                if !on { stick = .centred; atLimit = false }
            }
            .onDisappear { stick = .centred; atLimit = false }
            .accessibilityElement(children: .ignore)
            // DRIVABLE WITHOUT A DRAG. A pad that answers only to
            // `DragGesture` is a robot nobody using VoiceOver, Switch Control
            // or Voice Control can move at all — the one screen whose whole
            // point is moving it. Swipe up/down adjusts the live axis in
            // quarter steps; the named actions give Voice Control words to say.
            .accessibilityAdjustableAction { direction in
                let step = 0.25
                switch direction {
                case .increment: nudge(x: 0, y: verticalIsLive ? step : 0, xStep: step)
                case .decrement: nudge(x: 0, y: verticalIsLive ? -step : 0, xStep: -step)
                @unknown default: break
                }
            }
            .accessibilityAction(named: Text("Centre")) { stick = .centred }
            .accessibilityAction(named: Text("Left")) { stick = .init(x: max(stick.x - 0.25, -1), y: stick.y) }
            .accessibilityAction(named: Text("Right")) { stick = .init(x: min(stick.x + 0.25, 1), y: stick.y) }
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(spoken))
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                // The pad above already carries this word as its label; read
                // out again it is a second element saying nothing new.
                .accessibilityHidden(true)
        }
    }

    /// The pad's ground, one radius inside the deck's — the concentric rule,
    /// taken from the card this sits in rather than chosen again here.
    private var pad: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(DriveMetric.deck.inner),
                         style: .continuous)
    }

    /// How hard the stick is pushed, 0...1, for the size of the knob. A
    /// presentation quantity — how big to draw a dot — and not a command:
    /// what leaves this screen is `DuckDrive.twist(for:)`'s, computed in the
    /// kit from the same two axes with `padd`'s signs and deadzone.
    private var deflection: Double {
        let y = verticalIsLive ? stick.y : 0
        return min(1, (stick.x * stick.x + y * y).squareRoot())
    }

    /// One adjustable step. The vertical axis when the pad has one; the
    /// horizontal otherwise, so the Turn pad's up/down swipe still does the
    /// one thing that pad can do.
    private func nudge(x: Double, y: Double, xStep: Double) {
        if verticalIsLive {
            stick = .init(x: stick.x, y: min(max(stick.y + y, -1), 1))
        } else {
            stick = .init(x: min(max(stick.x + xStep, -1), 1), y: 0)
        }
    }

    /// What VoiceOver says the pad is doing. A drag pad reports nothing on its
    /// own, and "Move" alone does not say which way it is pushed.
    private var spoken: String {
        if stick == .centred { return "centred" }
        var parts: [String] = []
        if verticalIsLive, stick.y != 0 {
            parts.append(String(format: "%.0f%% %@", abs(stick.y) * 100,
                                stick.y > 0 ? "forward" : "back"))
        }
        if stick.x != 0 {
            parts.append(String(format: "%.0f%% %@", abs(stick.x) * 100,
                                stick.x > 0 ? "right" : "left"))
        }
        return parts.joined(separator: ", ")
    }
}
