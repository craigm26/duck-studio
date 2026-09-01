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
struct DriveView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var benches: BenchStore
    @ObservedObject var scenes: SceneStore

    private var bench: BenchEndpoint? { benches.selected }
    private var token: String? { bench.flatMap { benches.armed($0).token } }

    @State private var health: DuckBench.Health?
    @State private var chosen = ""
    @State private var live: DuckDrive.Live?
    @State private var touchSticks = DuckDrive.Sticks.centred
    @State private var running = false
    @State private var busy = false
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
        .navigationTitle("Drive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // THE LENS IS THE LINK, AND IT BELONGS WHERE NOTHING SCROLLS.
                // The iris opens when the bench answers `/health`, which is the
                // moment the screen becomes able to do anything at all.
                LensIndicator(state: linkState)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { transport }
        // A STOP THAT DOES NOT HAVE TO BE FOUND. The bar below is always on
        // screen, but "always on screen" is a sighted guarantee: a VoiceOver
        // user still has to swipe to it, and the swipes happen while the duck
        // is walking. The magic tap is two fingers double-tapped ANYWHERE on
        // the screen, which is the only stop that costs nothing to reach.
        .accessibilityAction(.magicTap) {
            guard bench != nil, !busy else { return }
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
            await connect()
        }
        .onDisappear {
            pad.stop()
            // LEAVING THE SCREEN STOPS THE LOOP. Without this the task keeps
            // sending intents at a bench for a screen nobody is looking at.
            running = false
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
                Text(linkLine)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
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
                Text(jointGrid(live.stance.jointAngles))
                    .font(.system(size: 9).monospaced())
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
        .frame(maxWidth: DriveMetric.readoutWidth, alignment: .leading)
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
        StateBadge(text: duckWord, state: duckState)
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
    private var duckWord: String {
        guard let live else { return running ? "Waiting for the bench" : "Not driving" }
        if !live.upright { return "On its side" }
        return running ? "Driving" : "Upright"
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
        return busy ? .connecting : .asleep
    }

    private var policyLine: String {
        guard !chosen.isEmpty else { return "no policy loaded" }
        return "policy \(chosen)"
    }

    private var linkLine: String {
        trips == 0 ? "no round trips yet" : "\(trips) trips"
    }

    /// Fourteen numbers in two rows, small enough to sit over the picture.
    ///
    /// THE ONE THING ON THIS SCREEN THAT DOES NOT SCALE WITH DYNAMIC TYPE, and
    /// it is left that way knowingly. Seven `%7.3f` columns is a fixed-width
    /// dump: at any size a person could read comfortably it is wider than a
    /// phone, so growing the type would replace a legible small table with an
    /// illegible clipped one. The layer is a tester's, it is off by default,
    /// and every fact in it that matters — which joints are about to clip —
    /// is in the `limits` layer at a readable size.
    private func jointGrid(_ angles: [Double]) -> String {
        var rows: [String] = []
        var row = ""
        for slot in 0..<DuckModel.policyJointCount {
            row += String(format: "%7.3f", angles[DuckModel.jointOfPolicySlot(slot)])
            if (slot + 1) % 7 == 0 { rows.append(row); row = "" }
        }
        if !row.isEmpty { rows.append(row) }
        return rows.joined(separator: "\n")
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
                // `.standard` and `.snug` around a footnote is a target over
                // fifty points tall and sixty wide, which clears the HIG's
                // floor from the spacing scale alone — the app already has
                // exactly one place that writes that floor down as a number,
                // and this is not it.
                .padding(.horizontal, Theme.spacing(.standard))
                .padding(.vertical, Theme.spacing(.snug))
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
        .background(Theme.surfacePrimary,
                    in: RoundedRectangle(cornerRadius: Theme.radius(DriveMetric.deck),
                                         style: .continuous))
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
                    Text("A phone has no physics engine, so there is nothing here to drive until a machine that has one is on your network.")
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
                    Text("Stop and Reset")
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
                            Task { await swap(to: now) }
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
                    Text("Controller")
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
            running.toggle()
            if running { Task { await drive() } }
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
        .disabled(busy || bench == nil)
        .accessibilityHint(Text("Zeroes the command and lets the duck settle under it."))
        // FIRST IN THE BAR FOR A SCREEN READER, whatever order it is drawn in.
        // Sort priority is the only way to say "reach this one first" without
        // moving it away from the thumb that is already over it.
        .accessibilitySortPriority(1)
    }

    private func resetButton(icons: Bool, expands: Bool) -> some View {
        Button { Task { await putBack() } } label: {
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
            guard let policy = policy(filling: slot) else {
                lastAction = "\(control.face): this bench has no \(slot.title) policy loaded."
                return
            }
            chosen = policy
            lastAction = "\(control.face) → \(slot.title): \(policy)"
            await swap(to: policy)
        case .drive:
            break
        case .stop:
            lastAction = "\(control.face) → stop"
            await halt()
        case .reset:
            lastAction = "\(control.face) → reset"
            await putBack()
        case .unsupported(let why):
            // NOT SILENCE. A tester pressing a button they know from the robot
            // gets told why it does nothing here rather than concluding the
            // link is broken.
            lastAction = "\(control.face): \(why)"
        }
    }

    /// Which of the bench's policies fills a slot.
    ///
    /// MATCHED ON THE ROLE NAME, which this app and the robot now share — the
    /// rename to Pollen's role names is what makes a bench's `alpha_sitstand`
    /// findable from `Slot.sitstand` at all. A bench carrying somebody's own
    /// networks may fill none of them, and saying so beats loading the wrong
    /// one.
    private func policy(filling slot: DuckOfficialPolicies.Slot) -> String? {
        guard let policies = health?.policies else { return nil }
        let wanted = DuckOfficialPolicies.releases.first { $0.slot == slot }?.filename
        if let wanted, let exact = policies.first(where: { $0 == wanted }) { return exact }
        // A bench often lists them without the extension.
        let stem = wanted.map { $0.replacingOccurrences(of: ".onnx", with: "") }
        return stem.flatMap { name in policies.first { $0 == name } }
    }

    // MARK: - talking to it

    @MainActor private func ask(_ call: DuckBench.Call) async throws -> Data {
        try await URLSession.shared.data(
            for: DuckBench.urlRequest(for: call, token: token)).0
    }

    @MainActor private func requireBench() throws -> DuckBench.Address {
        guard let bench else { throw DuckBench.Refusal.empty }
        return try benches.armed(bench).resolved()
    }

    @MainActor private func connect() async {
        busy = true
        defer { busy = false }
        do {
            let address = try requireBench()
            health = try DuckBench.readHealth(
                await ask(DuckBench.health(address)))
            if chosen.isEmpty { chosen = health?.policies.first ?? "" }
        } catch let refusal as DuckBench.Refusal { failure = refusal.message }
        catch let error as DuckBench.ReadError { failure = error.message }
        catch { failure = error.localizedDescription }
    }

    /// The loop. One command in flight at a time, and physics only advances
    /// while one is — so this IS the clock, not a timer running beside it.
    @MainActor private func drive() async {
        while running {
            do {
                let address = try requireBench()
                live = try DuckDrive.readLive(
                    await ask(try DuckDrive.intent(address, twist)))
                trips += 1
                noticeJoints()
            } catch let error as DuckBench.ReadError {
                failure = error.message
                running = false
            } catch let refusal as DuckBench.Refusal {
                failure = refusal.message
                running = false
            } catch {
                failure = error.localizedDescription
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

    @MainActor private func halt() async {
        running = false
        touchSticks = .centred
        busy = true
        defer { busy = false }
        do {
            live = try DuckDrive.readLive(await ask(try DuckDrive.stop(try requireBench())))
            // A DUCK CAN ARRIVE AT A STOP WHILE IT SETTLES, and a stop that
            // ends with a joint clipped is the same finding as one found while
            // driving. The other reason to call it here is bookkeeping: without
            // it the edge would still hold the reading from before the stop.
            noticeJoints()
        } catch let error as DuckBench.ReadError { failure = error.message }
        catch { failure = error.localizedDescription }
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
        } catch let error as DuckBench.ReadError { failure = error.message }
        catch { failure = error.localizedDescription }
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
    @MainActor private func swap(to policy: String) async {
        guard !policy.isEmpty else { return }
        do {
            live = try DuckDrive.readLive(
                await ask(try DuckDrive.load(try requireBench(), policy: policy)))
            Haptic.behaviourStarted()
        } catch let error as DuckBench.ReadError { failure = error.message }
        catch { failure = error.localizedDescription }
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
