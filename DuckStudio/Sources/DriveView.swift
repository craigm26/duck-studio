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
        .navigationTitle("Drive")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // THE PAD'S PRESSES GO THROUGH THE SAME DOOR as the on-screen ones.
            pad.onPress = { control in Task { await press(control) } }
            pad.begin()
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

    private var stage: some View {
        ZStack(alignment: .topLeading) {
            DuckStage(pose: pose, environment: .bareFloor, orbit: $orbit)
            VStack(alignment: .leading, spacing: 3) {
                if layers.contains(.telemetry) {
                    Text(readout).font(.caption2.monospacedDigit().weight(.medium))
                }
                if layers.contains(.command) {
                    Text(DuckDrive.says(twist))
                        .font(.caption2.monospacedDigit()).foregroundStyle(Theme.asked)
                }
                if layers.contains(.policy) {
                    Text(policyLine).font(.caption2.monospacedDigit()).foregroundStyle(Theme.measured)
                }
                if layers.contains(.link) {
                    Text(linkLine).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                if layers.contains(.limits), let live {
                    // ONLY THE ONES ABOUT TO CLIP. A list of fourteen joints is
                    // a list nobody reads; three joints against their stops is
                    // the finding.
                    let near = DuckPad.nearLimits(live.stance.jointAngles)
                    if near.isEmpty {
                        Text("no joint within 10° of a stop")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        ForEach(near, id: \.name) { joint in
                            Text(String(format: "%@ %.3f → stop %.3f",
                                        joint.name, joint.angle, joint.limit))
                                .font(.caption2.monospacedDigit()).foregroundStyle(Theme.refused)
                        }
                    }
                }
                if layers.contains(.joints), let live {
                    Text(jointGrid(live.stance.jointAngles))
                        .font(.system(size: 9).monospaced()).foregroundStyle(.secondary)
                }
                if let lastAction {
                    Text(lastAction).font(.caption2.weight(.medium)).foregroundStyle(Theme.amber)
                }
                if let live, !live.upright {
                    // NOT AN ERROR, AND NOT HIDDEN EITHER. A duck on its side is
                    // the most informative thing this screen produces: it is the
                    // policy failing under a command you chose, which is the
                    // whole reason to drive one.
                    Label("On its side — Reset puts it back", systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(8)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
        }
        .frame(maxHeight: 300)
    }

    /// One face button. DIMMED WHERE IT CANNOT WORK, and still pressable —
    /// pressing it is how a tester learns WHY, which is more use than a control
    /// that is missing or inert.
    private func padButton(_ control: DuckPad.Control) -> some View {
        let binding = DuckPad.binding(for: control)
        let live = binding?.isLive ?? false
        let flashing = pad.lastPressed == control
        return Button { Task { await press(control) } } label: {
            Text(control.face)
                .font(.caption.weight(.semibold).monospaced())
                .frame(minWidth: 38, minHeight: 30)
                .background(flashing ? Color.accentColor.opacity(0.5)
                            : live ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(.tertiary, lineWidth: live ? 0 : 1))
                .foregroundStyle(live ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(control.face))
        .accessibilityHint(Text(binding.map {
            $0.isLive ? "On the robot: \($0.onTheRobot)" : "Does nothing against a bench"
        } ?? ""))
    }

    private var policyLine: String {
        guard !chosen.isEmpty else { return "no policy loaded" }
        return "policy \(chosen)"
    }

    private var linkLine: String {
        trips == 0 ? "no round trips yet" : "\(trips) trips"
    }

    /// Fourteen numbers in two rows, small enough to sit over the picture.
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

    /// The layer switches. A SHEET WOULD HIDE THE DUCK, which is the one thing
    /// somebody driving needs to keep watching, so these are a row of chips
    /// under the stage and toggle in place.
    private var layerChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DuckPad.Layer.allCases) { layer in
                    let on = layers.contains(layer)
                    Button {
                        if on { layers.remove(layer) } else { layers.insert(layer) }
                    } label: {
                        Text(layer.title)
                            .font(.caption2.weight(on ? .semibold : .regular))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(on ? Color.accentColor.opacity(0.25) : Color.clear,
                                        in: Capsule())
                            .overlay(Capsule().stroke(.tertiary, lineWidth: on ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(layer.title))
                    .accessibilityValue(Text(on ? "on" : "off"))
                    .accessibilityHint(Text(layer.detail))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private var readout: String {
        guard let live else { return running ? "waiting for the bench…" : "not driving" }
        return String(format: "%.2f s sim · %.0f mm · %@ · %d trips",
                      live.t, live.height * 1000,
                      live.upright ? "upright" : "down", trips)
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
                }
            } else {
                Section {
                    // BUMPERS ABOVE THE STICKS, FACE BUTTONS RIGHT OF THEM, the
                    // way they sit on the thing itself. Somebody who has driven
                    // the robot should not have to read this layout.
                    HStack(spacing: 10) {
                        padButton(.leftBumper)
                        Spacer()
                        padButton(.rightBumper)
                    }
                    .padding(.horizontal, 6)
                    HStack(spacing: 18) {
                        ThumbPad(title: "Move", stick: $touchSticks.left)
                        VStack(spacing: 6) {
                            padButton(.y)
                            HStack(spacing: 6) { padButton(.x); padButton(.b) }
                            padButton(.a)
                        }
                        ThumbPad(title: "Turn", stick: $touchSticks.right, verticalIsLive: false)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    HStack(spacing: 10) {
                        padButton(.dpadLeft)
                        padButton(.dpadDown)
                        padButton(.dpadRight)
                        Spacer()
                        padButton(.start)
                        padButton(.select)
                    }
                    .padding(.horizontal, 6)
                } footer: {
                    Text(DuckDrive.says(twist))
                        .font(.caption.monospacedDigit())
                }

                Section {
                    Button {
                        running.toggle()
                        if running { Task { await drive() } }
                    } label: {
                        Label(running ? "Pause" : "Drive",
                              systemImage: running ? "pause.circle" : "play.circle")
                    }
                    .disabled(chosen.isEmpty || bench == nil)
                    Button { Task { await halt() } } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                    .disabled(busy || bench == nil)
                    Button { Task { await putBack() } } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(busy || bench == nil)
                } footer: {
                    // THE BENCH'S OWN DISTINCTION, WORTH REPEATING. Stopping is
                    // something the policy does; resetting is something done TO
                    // it. A policy that cannot stop without falling is a fact
                    // about that policy, and teleporting it upright would hide
                    // exactly the failure worth seeing.
                    Text("Stop zeroes the command and lets the duck settle under it — if it falls over stopping, that is the policy. Reset puts it back on its feet, which is not something a robot can do for itself.")
                }

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
                }

                Section {
                    if let name = pad.name {
                        Label(DuckPad.connected(name), systemImage: "gamecontroller.fill")
                            .font(.footnote).foregroundStyle(.green)
                    } else {
                        Text(DuckPad.noPad).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Controller")
                }

                Section {
                    Text(DuckDrive.thisIsNotARobot)
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(DuckDrive.intentMeansACommandHere)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - the pad

    /// Act on a control. THE ONE PATH FOR BOTH INPUTS — a real controller's
    /// press and a tap on the on-screen face button arrive here identically,
    /// so the two can never drift into doing different things.
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

    @MainActor private func halt() async {
        running = false
        touchSticks = .centred
        busy = true
        defer { busy = false }
        do {
            live = try DuckDrive.readLive(await ask(try DuckDrive.stop(try requireBench())))
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
        } catch let error as DuckBench.ReadError { failure = error.message }
        catch { failure = error.localizedDescription }
    }

    @MainActor private func swap(to policy: String) async {
        guard !policy.isEmpty else { return }
        do {
            live = try DuckDrive.readLive(
                await ask(try DuckDrive.load(try requireBench(), policy: policy)))
        } catch let error as DuckBench.ReadError { failure = error.message }
        catch { failure = error.localizedDescription }
    }
}

/// One thumb pad: drag inside it, and it reports where the thumb is as -1...1
/// on each axis. Let go and it springs back to centre.
///
/// SPRINGING BACK IS THE SAFE DEFAULT AND IT IS NOT DECORATION. A pad that kept
/// its last position would leave a command standing after the thumb left the
/// glass, and the duck would keep walking on a stick nobody is touching. A real
/// gamepad's stick is sprung; this is the same promise in software.
struct ThumbPad: View {
    let title: String
    @Binding var stick: DuckDrive.Stick
    /// Whether the vertical axis does anything. The Turn pad's does not —
    /// `padd` spends the right stick's y on head pose, which this does not
    /// offer — so it is drawn as a horizontal track rather than a square that
    /// silently ignores half of what you do in it.
    var verticalIsLive = true

    private static let size: CGFloat = 128
    private var radius: CGFloat { Self.size / 2 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.quaternary)
                if verticalIsLive {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.title3).foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "arrow.left.and.right")
                        .font(.title3).foregroundStyle(.tertiary)
                }
                Circle()
                    .fill(.tint)
                    .frame(width: 42, height: 42)
                    .offset(x: CGFloat(stick.x) * (radius - 21),
                            y: CGFloat(verticalIsLive ? -stick.y : 0) * (radius - 21))
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
                        let x = Double(drag.location.x - radius) / Double(radius - 21)
                        let y = Double(radius - drag.location.y) / Double(radius - 21)
                        stick = .init(x: min(max(x, -1), 1),
                                      y: verticalIsLive ? min(max(y, -1), 1) : 0)
                    }
                    .onEnded { _ in stick = .centred }
            )
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(spoken))
            Text(title).font(.caption2).foregroundStyle(.secondary)
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
