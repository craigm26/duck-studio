import SwiftUI
import StudioKit
import DuckKit

/// The welcome sheet on a fresh install, and the Duck sheet's "Add your duck" (build 91).
///
/// THE KIT DECIDES, THIS DRAWS. Every page, button and sentence is `Onboarding`'s, and every
/// button asks `Onboarding.next(from:choosing:)` where it goes. The pages are: do you have a duck,
/// is it on your Wi-Fi (Pollen's app does Wi-Fi), find it, say hi, stand up.
///
/// THE LOCAL NETWORK PROMPT IS ASKED FOR IN THE FOREGROUND, on "Look for my duck", by starting a
/// Bonjour browse. That is the only safe moment: a background intent that meets an undetermined
/// permission is silently denied (TN3179). A browse that goes to `.waiting` is how a declined
/// permission shows, and the page then offers Settings and the practice duck.
///
/// THE VENUE SWITCHES ONLY AT THE END, on Stand up, through `finish(.controller(onPracticeDuck:
/// false))`, which the app turns into `.play(.venue(.real, .onboarding))`. One address: the
/// camera address is cleared, so the camera reads the connection's host.
struct WelcomeView: View {
    @ObservedObject var robot: BridgeLink
    let start: Onboarding.PageID
    /// Where the sheet ends: the controller, on the practice duck or the real one.
    let finish: (Onboarding.Destination) -> Void

    @State private var page: Onboarding.PageID
    @State private var finding: Finding = .idle
    @State private var found: [MachineDiscovery.Record] = []
    @State private var typedHost = ""
    @AppStorage("bridge.port") private var port = BridgeHandshake.defaultPort
    @State private var token = ""
    @State private var connecting = false
    @State private var problem: String?
    @State private var quacking = false
    @State private var standing = false
    @State private var standLine: String?
    @AppStorage("robot.camera.address") private var cameraAddress = ""
    @Environment(\.openURL) private var openURL

    private enum Finding: Equatable { case idle, looking, done, declined }

    init(robot: BridgeLink, start: Onboarding.PageID = .haveDuck,
         finish: @escaping (Onboarding.Destination) -> Void) {
        self.robot = robot
        self.start = start
        self.finish = finish
        _page = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing(.standard)) {
                    let p = Onboarding.page(page)
                    Text(p.title)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let body = p.body {
                        Text(body).font(.body).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if page == .sayHi {
                        Text(Onboarding.didItQuack).font(.headline)
                    }
                    if page == .find { findPanel }
                    if let line = problem ?? standLine {
                        Text(line).font(.footnote).foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: Theme.spacing(.tight)) {
                        ForEach(p.choices) { choice in choiceButton(choice) }
                    }
                    .padding(.top, Theme.spacing(.tight))
                    if let small = p.smallPrint {
                        Text(small).font(.caption).foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.spacing(.loose))
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.backgroundPrimary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // SKIPPING IS ALLOWED, and lands on the practice duck: nothing switches.
                    Button(Onboarding.practiceDuck) { finish(.controller(onPracticeDuck: true)) }
                }
            }
        }
        .onAppear { token = BridgeTokenStore.load() ?? "" }
        .task(id: page) { if page == .sayHi { await sayHi() } }
    }

    // MARK: - buttons

    @ViewBuilder private func choiceButton(_ choice: Onboarding.Choice) -> some View {
        let busy = connecting || quacking || standing || finding == .looking
        let button = Button {
            Task { await press(choice.id) }
        } label: {
            HStack {
                Text(choice.label).frame(maxWidth: .infinity)
                if choice.prominent && busy { ProgressView() }
            }
            .frame(minHeight: DesignMetric.minimumTarget)
        }
        .disabled(busy && choice.prominent)
        // THE APP'S OWN TOY BUTTONS, ink on Beak Orange and ink on white (build 93): the system
        // prominent style set a white label on the orange tint, 2.02:1 at night.
        if choice.prominent {
            button.buttonStyle(.primaryAction)
        } else {
            button.buttonStyle(.raisedAction)
        }
    }

    @MainActor private func press(_ choice: Onboarding.ChoiceID) async {
        problem = nil
        // "Look for my duck" finds and connects first; only a connected duck goes on to Say hi.
        if page == .find, choice == .lookForMyDuck {
            await look()
            return
        }
        if page == .standUp, choice == .standUp {
            guard await standUp() else { return }
        }
        go(Onboarding.next(from: page, choosing: choice))
    }

    @MainActor private func go(_ destination: Onboarding.Destination) {
        switch destination {
        case .page(let next): page = next
        case .openPollensApp: openURL(Provenance.microduckPage.url)
        case .controller: finish(destination)
        }
    }

    // MARK: - find

    @ViewBuilder private var findPanel: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            switch finding {
            case .idle: EmptyView()
            case .looking:
                Label(Onboarding.lookingSaid, systemImage: "antenna.radiowaves.left.and.right")
                    .font(.footnote)
            case .declined:
                Text(Onboarding.localNetworkDeclined).font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
#if os(iOS)
                Button(Onboarding.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
#endif
            case .done:
                if found.isEmpty {
                    Text(Onboarding.foundNoDuck).font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(found, id: \.host) { record in
                    Button {
                        Task { await connect(host: record.host, port: record.port) }
                    } label: {
                        Label(Onboarding.found(record.name.isEmpty ? record.host : record.name),
                              systemImage: "bird")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: DesignMetric.minimumTarget)
                    }
                    .buttonStyle(.bordered)
                }
            }
            // 1. Bluetooth: names nearby ducks. Reading a home address over Bluetooth is
            // unverified (Onboarding.Discovery.bluetooth.verified), so this is a door, not a promise.
            NavigationLink { FindDuckView() } label: {
                Label(Onboarding.Discovery.bluetooth.label, systemImage: "dot.radiowaves.left.and.right")
                    .font(.footnote)
            }
            // The token the bridge printed; remembered once typed.
            if token.isEmpty || finding == .done {
                SecureField("Code the bridge printed", text: $token)
                    .textFieldStyle(.roundedBorder)
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()
            }
            // 4. Typing is last and collapsed.
            DisclosureGroup(Onboarding.Discovery.typed.label) {
                TextField("robot.local or 192.168.1.20", text: $typedHost)
                    .textFieldStyle(.roundedBorder)
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
#endif
                    .autocorrectionDisabled()
                Button(BridgeDrive.connectRow) {
                    Task { await connect(host: typedHost.trimmingCharacters(in: .whitespaces), port: port) }
                }
                .disabled(typedHost.trimmingCharacters(in: .whitespaces).isEmpty || connecting)
            }
            .font(.footnote)
        }
        .padding(Theme.spacing(.snug))
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// The browse that asks for Local Network access, in the foreground, on the person's press.
    /// A single bridge answering with a saved code connects at once.
    @MainActor private func look() async {
        if robot.isConnected { page = .sayHi; return }
        finding = .looking
        let (records, ending) = await MachineDiscovery().discover(type: DuckMachine.duckServiceType,
                                                                  timeout: 4)
        found = records.sorted { $0.name < $1.name }
        finding = ending == .permissionLikelyOff && records.isEmpty ? .declined : .done
        if found.count == 1, !token.isEmpty {
            await connect(host: found[0].host, port: found[0].port)
        }
    }

    @MainActor private func connect(host: String, port: Int) async {
        guard !host.isEmpty else { return }
        connecting = true
        defer { connecting = false }
        do {
            try await robot.connect(host: host, port: port,
                                    token: token.trimmingCharacters(in: .whitespaces))
            BridgeTokenStore.save(token)
            // ONE ADDRESS: the camera reads the connection's host from now on.
            cameraAddress = ""
            Haptic.connected()
            page = .sayHi
        } catch let refusal as BridgeHandshake.Refusal {
            problem = refusal.message
        } catch {
            problem = error.localizedDescription
        }
    }

    // MARK: - say hi and stand up

    /// Quack once, so the person can tell this duck is theirs.
    @MainActor private func sayHi() async {
        guard let peer = robot.peer else { page = .find; return }
        quacking = true
        defer { quacking = false }
        if case .refused(let why) = await DuckRuns.shared.run(.sound(.greet), on: peer) {
            problem = why
        }
    }

    /// init, enable on, start driving, then stand: the kit's runner chains them. A refusal is the
    /// robot's own reason in plain words.
    @MainActor private func standUp() async -> Bool {
        guard let peer = robot.peer else { page = .find; return false }
        standing = true
        defer { standing = false }
        switch await DuckRuns.shared.run(.stand, on: peer) {
        case .finished: return true
        case .refused(let why):
            standLine = Onboarding.standRefused(because: why)
            return false
        case .stopped, .handedOff:
            return false
        }
    }
}

/// Pollen Robotics' pages for the robot and the company, as tappable rows.
///
/// ONE VIEW, TWO PLACES (Settings, About and the foot of Behaviours), so the addresses are the
/// kit's (`Provenance.links`, pinned by `swift test`) and no screen can quietly point elsewhere.
struct ProvenanceLinks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Provenance.links) { link in
                Link(destination: link.url) {
                    Label(link.title, systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }
}
