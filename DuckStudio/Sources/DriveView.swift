import SwiftUI
import StudioKit
import DuckKit

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
    @State private var sticks = DuckDrive.Sticks.centred
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

    private var twist: DuckDrive.Twist { DuckDrive.twist(for: sticks) }

    /// The duck as last seen, or the home stance before the first answer.
    private var pose: StagePose { live?.stance ?? .home }

    var body: some View {
        VStack(spacing: 0) {
            stage
            controls
        }
        .navigationTitle("Drive")
        .navigationBarTitleDisplayMode(.inline)
        .task { await connect() }
        .onDisappear {
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
            VStack(alignment: .leading, spacing: 2) {
                Text(readout).font(.caption2.monospacedDigit().weight(.medium))
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
                    HStack(spacing: 24) {
                        ThumbPad(title: "Move", stick: $sticks.left)
                        ThumbPad(title: "Turn", stick: $sticks.right, verticalIsLive: false)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
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
                    Text(DuckDrive.thisIsNotARobot)
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(DuckDrive.intentMeansSomethingElseOnTheRobot)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
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
        sticks = .centred
        busy = true
        defer { busy = false }
        do {
            live = try DuckDrive.readLive(await ask(try DuckDrive.stop(try requireBench())))
        } catch let error as DuckBench.ReadError { failure = error.message }
        catch { failure = error.localizedDescription }
    }

    @MainActor private func putBack() async {
        running = false
        sticks = .centred
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
