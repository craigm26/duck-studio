import SwiftUI
import StudioKit
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
    @State private var chosen = ""
    @State private var live: DuckDrive.Live?
    @State private var touchSticks = DuckDrive.Sticks.centred
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
    @State private var orbit = OrbitState.defaults
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
    @State private var peer: BenchPeer?

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A REAL PAD WINS WHILE IT IS BEING HELD. Both inputs are live at once —
    /// a tester can put a thumb on the glass without unpairing anything — and
    /// the physical sticks only take over once they leave centre, so a resting
    /// controller does not pin the on-screen pads to zero.
    private var sticks: DuckDrive.Sticks {
        pad.sticks == .centred ? touchSticks : pad.sticks
    }

    private var twist: DuckDrive.Twist { DuckDrive.twist(for: sticks) }

    /// The duck as last seen, or the home stance before the first answer.
    private var pose: StagePose { live?.stance ?? .home }

    var body: some View {
        VStack(spacing: 0) {
            stage
            layerChips
            controls
        }
        .background(Theme.backgroundPrimary)
        // THE TAB'S NAME, NOT THE VERB. This screen was pushed from a menu row
        // that said "Drive one live", so the bar repeated the row that opened
        // it. It is the Control tab's root now: the tab bar below says Control
        // and the bar above has to say the same word, or the app has two names
        // for one place.
        .navigationTitle("Control")
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // THE LENS IS THE LINK, AND IT BELONGS WHERE NOTHING SCROLLS.
                // The iris opens when the bench answers `/health`, which is the
                // moment the screen becomes able to do anything at all.
                LensIndicator(state: linkState)
            }
            // THE ONE GEAR ON THIS TAB, AND IT IS RIGHTMOST. Every tab root in
            // this app carries exactly one Settings gear in the same corner —
            // `PolicyListView` puts it last among its trailing items, so this
            // one does too, and the two tabs' bars do not swap places under a
            // thumb. The lens keeps the position it has had since it was the
            // only thing up here, because it is the state and the gear is the
            // door.
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView(models: settingsModels, benches: benches) } label: {
                    Image(systemName: "gear").accessibilityLabel(Text("Settings"))
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { transport }
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
        .accessibilityAction(.magicTap) {
            guard bench != nil else { return }
            Task { await halt() }
        }
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
        .onDisappear {
            pad.stop()
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
        .alert("The bench refused", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(failure ?? "") }
    }

    // MARK: - the duck

    /// The viewport: the 3D stage, and the readout floating on it.
    ///
    /// A CARD, WITH THE READOUT AS A CARD INSIDE IT. The radii are concentric —
    /// `Palette.Radius.group` outside and `.inner` (which is `.card`) within —
    /// so the corner of the panel is drawn at the next step down rather than at
    /// whatever looked right. Two radii chosen independently read as two
    /// stacked rectangles; two radii a step apart read as one machined part.
    private var stage: some View {
        ZStack(alignment: .topLeading) {
            DuckStage(pose: pose, environment: .bareFloor, orbit: $orbit)
            if hasReadout { hud }
        }
        // NOT CAPPED AT ACCESSIBILITY SIZES. `TelemetryRow` exists so a
        // stacked label-over-value survives large text — and a fixed 300pt
        // viewport then clipped exactly that reflow, hiding the numbers from
        // the people who enlarged them in order to read them. The duck shrinks
        // to make room; the words do not disappear.
        .frame(maxHeight: typeSize.isAccessibilitySize ? nil : DriveMetric.viewportHeight)
        .clipShape(viewport)
        .overlay(viewport.strokeBorder(Theme.separator,
                                       lineWidth: DriveMetric.hairlineStroke))
        .padding(.horizontal, Theme.spacing(.snug))
        .padding(.top, Theme.spacing(.tight))
    }

    private var viewport: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(DriveMetric.viewport),
                         style: .continuous)
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
    /// robot the Control tab says another about. The strings moved to StudioKit
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
        if health != nil { return .connected }
        // A STOP IS A CALL LIKE ANY OTHER AS FAR AS THE LENS IS CONCERNED. It
        // keeps its own flag so that nothing can disable the button — see
        // `stopping` — but the eye should still show the link being used.
        return busy || stopping ? .connecting : .asleep
    }

    private var policyLine: String {
        guard !chosen.isEmpty else { return "no policy loaded" }
        return "policy \(chosen)"
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
                           _ peer: BenchPeer) -> String {
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
                .foregroundStyle(on ? Theme.textPrimary : Theme.textSecondary)
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
                .background { if on { Capsule().fill(Theme.surfaceInteractive) } }
                .overlay(Capsule().strokeBorder(Theme.separator,
                                                lineWidth: DriveMetric.hairlineStroke))
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
    private func padButton(_ control: DuckPad.Control) -> some View {
        let binding = DuckPad.binding(for: control)
        let isLive = binding?.isLive ?? false
        return Group {
            if isLive {
                padPress(control).buttonStyle(.primaryActionMoves)
            } else {
                padPress(control).buttonStyle(DeadControlStyle())
            }
        }
        // A PRESS THAT CAME FROM THE CONTROLLER, DRAWN LIKE A PRESS. The style
        // darkens its fill under a thumb and cannot see a Bluetooth button at
        // all, so a hardware press is mirrored with the same delta from out
        // here. It is the style's number written twice because the style's copy
        // is private; the two have to feel like one press.
        .brightness(pad.lastPressed == control ? DriveMetric.pressDelta : 0)
        .animation(Theme.motion(reduced: reduceMotion), value: pad.lastPressed)
        .accessibilityLabel(Text(control.face))
        .accessibilityHint(Text(binding.map {
            $0.isLive ? "On the robot: \($0.onTheRobot)" : "Does nothing against a bench"
        } ?? ""))
    }

    private func padPress(_ control: DuckPad.Control) -> some View {
        Button { Task { await press(control) } } label: {
            Text(control.face).lineLimit(1)
        }
    }

    /// The pad, as a card.
    ///
    /// BUMPERS ABOVE THE STICKS, and the rest under them in the clusters a pad
    /// has: faces, dpad, then Start and Select. Somebody who has driven the
    /// robot should not have to read this layout — see `padButton` for why the
    /// clusters no longer flank the sticks.
    private var padDeck: some View {
        VStack(spacing: Theme.spacing(.snug)) {
            HStack(spacing: Theme.spacing(.tight)) {
                padButton(.leftBumper)
                Spacer(minLength: Theme.spacing(.tight))
                padButton(.rightBumper)
            }
            HStack(spacing: Theme.spacing(.standard)) {
                ThumbPad(title: "Move", stick: $touchSticks.left)
                ThumbPad(title: "Turn", stick: $touchSticks.right, verticalIsLive: false)
            }
            // FOUR ACROSS WHERE THEY FIT, TWO BY TWO WHERE THEY DO NOT. On the
            // narrowest phone still supported, four sixty-point buttons plus a
            // card's padding are wider than the screen; `ViewThatFits` folds
            // them rather than truncating a glyph or clipping a target.
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
        // THE SAME HAIRLINE EVERY OTHER CARD ON THIS SCREEN HAS. The viewport,
        // the readout panel, the chips and the thumb pads inside this very deck
        // all take a `separator` edge; the deck alone did not, so the one card
        // that fills the width was the one card with no edge — and on a palette
        // whose grounds sit within about 1.1:1 of each other, an edge is the
        // only thing that says where a surface starts. It is not a decoration
        // here, it is the boundary.
        .overlay(deckCard.strokeBorder(Theme.separator,
                                       lineWidth: DriveMetric.hairlineStroke))
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
                Section {
                    padDeck
                        // THE DECK DRAWS ITS OWN CARD, so the row hands it the
                        // whole width and gets out of the way. That is what
                        // makes the concentric radii legible: the card is
                        // `.group`, the pads inside it are `.group.inner`, and
                        // a system row background between them would put a
                        // third corner radius nobody chose in the middle.
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    Text(DuckDrive.says(twist))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }

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

                Section {
                    Picker("Bench", selection: Binding(
                        get: { benches.selectedID }, set: { benches.selectedID = $0 })) {
                        ForEach(benches.benches) { one in
                            Text(one.name).tag(UUID?.some(one.id))
                        }
                    }
                    if let health {
                        Picker("Policy", selection: $chosen) {
                            ForEach(health.policies, id: \.self) { Text($0).tag($0) }
                        }
                        .onChange(of: chosen) { _, now in
                            // NOT FOR A POLICY THE BENCH ALREADY HOLDS. `connect`
                            // fills the picker from the store's record of the
                            // last load, and My Microduck's quick actions write
                            // that record too; posting `/policy` again for it
                            // would reload what is loaded, or — the case this
                            // guards — undo a quick action just launched from
                            // the front door.
                            guard now != benches.lastLoaded(for: bench?.id) else { return }
                            flight = Task { await swap(to: now) }
                        }
                        if chosen.isEmpty {
                            // WHY DRIVE WAITS. The bench lists what it holds and
                            // never says what is loaded, so this app will not
                            // guess by loading the first name in the list.
                            Text("Pick a policy to drive with. The bench does not say which one it has loaded, so nothing is chosen for you.")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    NavigationLink { BenchSettingsView(store: benches) } label: {
                        Label("Manage benches", systemImage: "gearshape")
                    }
                } footer: {
                    Text(DuckDrive.hotSwapWorksBecause)
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)

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

                Section {
                    Text(DuckDrive.thisIsNotARobot)
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                    Text(DuckDrive.intentMeansACommandHere)
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)
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

    // MARK: - the transport

    /// Drive, Stop and Reset, in a bar that never scrolls.
    ///
    /// THIS IS THE SAFETY LAYER AND IT IS WHY THE LIST LOST A SECTION. These
    /// three were rows below a pad deck that is taller than a phone, so reaching
    /// Stop meant scrolling a list with one hand while a duck walked with the
    /// other. A `safeAreaInset` keeps them on the glass and — because the inset
    /// is real safe area — the list still scrolls its last row clear of them.
    ///
    /// ALL THREE MOVE THE ROBOT, so all three are the sixty-point variant.
    /// Drive starts a gait, Stop zeroes the command and lets it settle, Reset
    /// picks it up. None of them is a control you look at while you press it.
    ///
    /// EACH ONE IS DISABLED BY A DIFFERENT THING, AND STOP BY THE LEAST. Drive
    /// waits for a policy to have been chosen, because there is nothing to drive
    /// until one is loaded. Reset waits for the screen to stop being busy, which
    /// is right: a second reset on top of one already going out is a request the
    /// person cannot follow. Stop waits for nothing except a bench being
    /// selected — it pre-empts instead, cancelling whatever is in flight before
    /// sending its own. See `halt`.
    ///
    /// THREE SHAPES, WIDEST FIRST. Icon and word where the width is there, word
    /// alone on a narrow phone, stacked when the type is at an accessibility
    /// size — `ViewThatFits` picks. The alternative is a truncated verb on the
    /// button that stops a robot.
    @ViewBuilder private var transport: some View {
        if !benches.benches.isEmpty {
            ViewThatFits(in: .horizontal) {
                transportRow(icons: true)
                transportRow(icons: false)
                VStack(spacing: Theme.spacing(.tight)) {
                    driveButton(icons: true, expands: true)
                    stopButton(icons: true, expands: true)
                    resetButton(icons: true, expands: true)
                }
            }
            .padding(.horizontal, Theme.spacing(.snug))
            .padding(.vertical, Theme.spacing(.snug))
            .frame(maxWidth: .infinity)
            .background(alignment: .top) {
                Rectangle().fill(Theme.separator)
                    .frame(height: DriveMetric.hairlineStroke)
            }
            .background(Theme.backgroundPrimary.ignoresSafeArea(edges: .bottom))
        }
    }

    private func transportRow(icons: Bool) -> some View {
        HStack(spacing: Theme.spacing(.tight)) {
            driveButton(icons: icons, expands: false)
            stopButton(icons: icons, expands: false)
            resetButton(icons: icons, expands: false)
        }
    }

    private func driveButton(icons: Bool, expands: Bool) -> some View {
        Button {
            // PAUSE CUTS OFF THE TRIP IN FLIGHT, AND DRIVE NEVER STARTS A
            // SECOND LOOP. Clearing `running` alone left a loop suspended in
            // its round trip; pressed again before it returned, a second loop
            // was started beside it — two intent streams at one bench, and
            // Stop able to cancel only the one `flight` still held.
            flight?.cancel()
            running.toggle()
            if running { flight = Task { await drive() } }
        } label: {
            transportLabel(running ? "Pause" : "Drive",
                           symbol: running ? "pause.circle" : "play.circle",
                           icons: icons, expands: expands)
        }
        .buttonStyle(.primaryActionMoves)
        .disabled(chosen.isEmpty || bench == nil)
        .accessibilityHint(Text(running
            ? "Stops sending intents. The duck keeps whatever command it last had."
            : "Starts the loop that sends the sticks to the bench."))
    }

    private func stopButton(icons: Bool, expands: Bool) -> some View {
        Button { Task { await halt() } } label: {
            transportLabel("Stop", symbol: "stop.circle", icons: icons, expands: expands)
        }
        .buttonStyle(.primaryActionMoves)
        // A BENCH IS THE ONLY THING IT NEEDS. This was `busy || bench == nil`,
        // which meant the stop was dead for the whole of every health read,
        // every policy swap and every reset — and those are precisely the
        // moments when a duck is moving under a command somebody has changed
        // their mind about. A control that stops a machine has no business
        // being unavailable because the software is doing something else; if it
        // cannot be pressed it is not a stop, it is a suggestion. What is left
        // is the one case where the button would have nothing to talk to.
        .disabled(bench == nil)
        .accessibilityHint(Text("Zeroes the command and lets the duck settle under it."))
        // FIRST IN THE BAR FOR A SCREEN READER, whatever order it is drawn in.
        // Sort priority is the only way to say "reach this one first" without
        // moving it away from the thumb that is already over it.
        .accessibilitySortPriority(1)
    }

    private func resetButton(icons: Bool, expands: Bool) -> some View {
        Button { flight = Task { await putBack() } } label: {
            transportLabel("Reset", symbol: "arrow.counterclockwise",
                           icons: icons, expands: expands)
        }
        .buttonStyle(.primaryActionMoves)
        .disabled(busy || bench == nil)
        .accessibilityHint(Text("Puts the duck back on its feet and clears the trip count."))
    }

    @ViewBuilder
    private func transportLabel(_ title: String, symbol: String,
                                icons: Bool, expands: Bool) -> some View {
        Group {
            if icons {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: expands ? CGFloat.infinity : nil)
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
        guard let binding = DuckPad.binding(for: control) else { return }
        switch binding.here {
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
            guard let policy = DuckQuickActions.filename(filling: slot,
                                                         among: health?.policies ?? []) else {
                lastAction = "\(control.face): \(DuckQuickActions.notHeldHere(slot))"
                return
            }
            // ONE SWAP, THROUGH THE PICKER. Setting `chosen` fires the picker's
            // `onChange`, which puts the swap in `flight` where Stop can cut
            // it off. A face button used to ALSO start its own swap here — two
            // `/policy` posts per press, and only the later one cancellable, so
            // a stop pressed after a face button could still be followed by a
            // network landing on the servos. Pressing the slot that is already
            // loaded changes nothing and so swaps nothing, which is right.
            chosen = policy
            lastAction = "\(control.face) → \(slot.title): \(policy)"
        case .drive:
            break
        case .stop:
            lastAction = "\(control.face) → stop"
            await halt()
        case .reset:
            lastAction = "\(control.face) → reset"
            flight = Task { await putBack() }
        case .unsupported(let why):
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
    @MainActor private func requirePeer() throws -> BenchPeer {
        if let peer { return peer }
        guard let made = try benches.makePeer() else { throw DuckBench.Refusal.empty }
        peer = made
        return made
    }

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
        peer = try? benches.makePeer()
        // THE NEW PEER HAS SEEN NOTHING. Carrying the old one's state line over
        // would put the last bench's sim clock under the new bench's name.
        stateSaid = nil
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
    @MainActor private func report(_ error: Error) {
        if stopCutItOff(error) {
            // ONLY WHEN IT WAS STOP. Leaving the screen cancels the same errand
            // the same way, and the sentence was being written for that too —
            // a readout claiming a stop on a screen where nobody pressed one.
            if cutOffByStop { lastAction = "Stop cut off the call that was in flight." }
            cutOffByStop = false
            return
        }
        switch error {
        case let refusal as DuckBench.ReadError: failure = refusal.message
        case let refusal as DuckBench.Refusal: failure = refusal.message
        case let refusal as BenchEndpoint.Refusal: failure = refusal.message
        case let refusal as BenchPeer.Refusal: failure = refusal.message
        case let misuse as BenchPeer.Misuse: failure = misuse.message
        case let misuse as DuckCall.Misuse: failure = misuse.message
        case let refusal as DuckDrive.Refusal: failure = refusal.message
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
        guard layers.contains(.link), let peer else { return }
        guard let reply = try? await peer.call(.state), reply.succeeded,
              let clock: String = reply.field("clock"),
              let t: Double = reply.field("t") else { return }
        stateSaid = String(format: "%@ clock %.2f s", clock, t)
    }

    @MainActor private func connect() async {
        busy = true
        defer { busy = false }
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
            // just launched. `chosen` is now filled only from the store's
            // record of the last policy this app loaded on this bench, and the
            // picker's `onChange` refuses to swap to a policy that record
            // already names, so this fills the picker without a request. With
            // no record, `chosen` stays empty and Drive waits for a pick.
            if chosen.isEmpty, let known = benches.lastLoaded(for: bench?.id) { chosen = known }
        } catch { report(error) }
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
                try await peer.notify(.move(twist))
                live = await peer.live
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
        running = false
        touchSticks = .centred
        if let flight, !flight.isCancelled { cutOffByStop = true }
        flight?.cancel()
        stopping = true
        defer { stopping = false }
        do {
            let peer = try requirePeer()
            let answer = try await peer.call(.stop)
            if let refusal = answer.failure {
                // THE BENCH'S OWN WORDS, IN THE READER'S OWN WRAPPER. A refusal
                // that came back in a reply rather than as a throw is still the
                // bench saying no, and it is the same sentence `/stop` produced
                // before the peer existed.
                failure = DuckBench.ReadError.bench(refusal.message).message
                return
            }
            live = await peer.live
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
        do {
            live = try DuckDrive.readLive(
                await ask(try DuckDrive.load(try requireBench(), policy: policy)))
            // RECORDED, so the picker can show it next time without a request
            // and My Microduck's card and this tab agree about the servos.
            if let id = bench?.id { benches.noteLoaded(policy, on: id) }
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
    /// The viewport card. Its readout takes `viewport.inner`, which is how the
    /// concentric rule is expressed rather than asserted — pick a different
    /// outer radius and the inner one follows.
    static let viewport = Palette.Radius.group
    /// The pad deck card. Its thumb pads take `deck.inner`.
    static let deck = Palette.Radius.group

    /// How much of the screen the duck is allowed. Above this the controls stop
    /// fitting on a small phone; below it the duck is a thumbnail of a duck.
    static let viewportHeight: CGFloat = 300

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
            .padding(.horizontal, Theme.spacing(.loose))
            .padding(.vertical, Theme.spacing(.standard))
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

    var body: some View {
        VStack(spacing: Theme.spacing(.tight)) {
            ZStack {
                pad.fill(Theme.surfaceInteractive)
                pad.strokeBorder(Theme.separator, lineWidth: DriveMetric.hairlineStroke)
                Circle()
                    .strokeBorder(Theme.separator, lineWidth: DriveMetric.hairlineStroke)
                    .frame(width: travel * 2, height: travel * 2)
                Image(systemName: verticalIsLive
                      ? "arrow.up.and.down.and.arrow.left.and.right"
                      : "arrow.left.and.right")
                    .font(.title3)
                    .foregroundStyle(Theme.textTertiary)
                JointNode(load: deflection, label: title)
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
