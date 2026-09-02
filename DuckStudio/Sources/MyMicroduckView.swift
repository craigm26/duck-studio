import SwiftUI
import StudioKit
import DuckEvidence

/// The front door: one duck, seven questions, in the order somebody asks them.
///
/// WHY A SCREEN THAT MOSTLY REPEATS OTHER SCREENS. Everything here exists
/// somewhere else in this app — the link state is on the Drive screen, the
/// bench picker is in Settings, the policies are in the Behaviours tab — and
/// that is precisely the complaint this tab answers. Somebody who has just
/// opened the app wants to know whether their duck is there, what it is doing,
/// and whether they can drive it, and today they find that out by opening three
/// screens and assembling the answer themselves. This assembles it.
///
/// THE ORDER IS THE DESIGN'S ORDER AND IT IS NOT A LAYOUT PREFERENCE. Seven
/// questions, above the fold, in this sequence: is anything wrong, which duck
/// is this, is it online, what is its charge, what is it doing, can I control
/// it, what can I launch. The banner is first because everything under it is
/// worth less when something above it is broken — a battery row read while a
/// bench is unreachable is a row about nothing. The control affordance is sixth
/// rather than second because "can I drive it" is a question you ask about a
/// duck you have already identified.
///
/// NOTHING ON THIS SCREEN IS COMPUTED HERE. Every judgement — which word for
/// the pose, whether a reply is recent enough to call the duck live, whether
/// the Drive button may exist, which quick actions this bench can offer — comes
/// from `DeviceCard` or `DuckQuickActions`, which are in the kit where `swift
/// test` can read them on Linux. This file decides how big things are and what
/// colour, and that is all it decides. The one exception is deliberate and
/// named: the small errand that posts `/policy`, which is I/O and not
/// arithmetic, and which sits here for the same reason `BenchPeer` takes a
/// closure rather than a `URLSession`.
///
/// A BLOCKED SURFACE SHIPS AS AN EXPLICIT "NOT YET". There is no camera preview
/// in this build and there may be no bench configured at all; both draw a
/// sentence saying so rather than an empty card, and every one of those
/// sentences is a constant `swift test` already asserts. An empty card is
/// indistinguishable from a bug, and a person who cannot tell those apart files
/// the wrong one.
struct MyMicroduckView: View {

    /// The five stores the app's roots are handed. THREE OF THEM ARE NOT READ
    /// HERE YET — the library, the scenes and the drafts — and they are in the
    /// signature anyway, because the shell constructs every tab root the same
    /// way and a front door that grows a "recent drafts" row should not change
    /// its initialiser to get one. They are `@ObservedObject` rather than
    /// ignored so that when a row does arrive it redraws.
    @ObservedObject var model: LibraryModel
    @ObservedObject var scenes: SceneStore
    @ObservedObject var drafts: DraftStore
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore

    /// Which tab is showing, so the Drive button can move somebody to the one
    /// that drives. INJECTED RATHER THAN OWNED: a tab root that pushed its own
    /// `NavigationStack` copy of the Control screen would be a second Drive
    /// screen with its own peer, driving the same bench.
    @EnvironmentObject private var router: AppRouter

    /// The peer for the selected bench, rebuilt whenever the selection or its
    /// address changes. See `peerKey`.
    @State private var peer: BenchPeer?

    /// What `/health` last said, which is where the policy list comes from.
    @State private var health: DuckBench.Health?

    /// The last state block, or nil when nothing has been commanded on this
    /// link — which on this screen is the ordinary case, because the front door
    /// never drives anything.
    @State private var live: DuckDrive.Live?

    /// When something last came back. `DeviceCard.Presence` turns this into the
    /// sentence; this file only records the moment.
    @State private var lastReplyAt: Date?

    /// The clock, read here rather than in the kit.
    ///
    /// A STORED DATE UPDATED ON EVERY REFRESH, NOT A TIMER. `DeviceCard.
    /// Presence` takes `now` as an argument precisely so no clock is read
    /// inside the package, and something on this side has to supply one. A
    /// ticking timer was the alternative and is worse: it would redraw this
    /// screen once a second for the sole purpose of ageing one sentence, on a
    /// phone that may be in somebody's pocket.
    @State private var now = Date()

    /// Everything wrong, worst first. Empty draws nothing at all.
    @State private var alarms: [DeviceCard.Alarm] = []

    /// What the last quick action did, in the bench's own answer.
    @State private var lastAction: String?

    /// Whether a request is in flight, which is all the lens's middle state
    /// means.
    @State private var busy = false

    // MARK: - the screen

    var body: some View {
        List {
            bannerSection
            deviceSection
            quickActionSection
            cameraSection
            connectionSection
            benchSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("My Microduck")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView(models: models, benches: benches) } label: {
                    Image(systemName: "gear").accessibilityLabel(Text("Settings"))
                }
            }
        }
        // ONE ENTRY POINT FOR BOTH ARRIVALS. `.task(id:)` runs when the screen
        // appears AND every time the key changes, which is exactly the two
        // moments a peer has to be rebuilt — and unlike an `onAppear` plus an
        // `onChange` it cancels the previous run rather than racing it.
        .task(id: peerKey) { await open() }
        .refreshable { await open() }
    }

    // MARK: - 7. is anything wrong

    /// The banner, or nothing.
    ///
    /// NOTHING IS THE COMMON CASE AND IT MUST DRAW NOTHING. A green "all well"
    /// bar is a row of pixels that is right almost always and is therefore
    /// stopped being read, which costs exactly the times it is not.
    ///
    /// NOT HAVING A BENCH IS NOT AN ALARM. A fresh install has none, and a red
    /// bar telling somebody they have not yet done a thing nobody asked them to
    /// do is an app complaining about its own emptiness. That case is answered
    /// in the device card instead, as an explicit "not yet" with the setup
    /// sentence and somewhere to go.
    @ViewBuilder private var bannerSection: some View {
        if !banner.isEmpty {
            Section {
                ForEach(banner.alarms) { alarm in
                    HStack(alignment: .top, spacing: Theme.spacing(.tight)) {
                        Image(systemName: alarm.severity == .critical
                              ? "exclamationmark.octagon.fill"
                              : "exclamationmark.triangle.fill")
                            .foregroundStyle(colour(of: alarm.severity))
                            .accessibilityHidden(true)
                        Text(alarm.sentence)
                            .font(.footnote)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(alarm.severity == .critical
                                             ? "Problem" : "Warning"))
                    .accessibilityValue(Text(alarm.sentence))
                }
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }

    /// THE SEVERITY IS DRAWN AND NEVER DECIDED HERE. `DeviceCard.Alarm` sorted
    /// the list and set each severity; this maps one to a token and does
    /// nothing else. `Theme.critical` and `Theme.warning` both clear 4.5:1 on
    /// every ground this app sets words on, which `PaletteTests` proves — and
    /// neither colour is alone: the glyph differs, and VoiceOver is told the
    /// word.
    private func colour(of severity: DeviceCard.Alarm.Severity) -> Color {
        switch severity {
        case .critical: return Theme.critical
        case .warning: return Theme.warning
        }
    }

    // MARK: - 1 to 6: the duck itself

    @ViewBuilder private var deviceSection: some View {
        Section {
            if let peer {
                identityRow(peer)
                Text(presence.says(now: now))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text("Connection"))
                    .accessibilityValue(Text(presence.says(now: now)))
                // (3) BATTERY, IN WORDS, IN A SENTENCE'S SHAPE. The design asks
                // for a numeral in mono, and `DeviceCard.Charge` refuses to
                // produce a number because no link in this app carries one —
                // so the honest answer is a sentence, and a sentence does not
                // belong in `TelemetryRow`'s monospaced value column, where it
                // wrapped into five lines of code-font prose. The same shape
                // as the presence line above it.
                Text(DeviceCard.Charge.of(peer.identity).says)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text("Battery"))
                    .accessibilityValue(Text(DeviceCard.Charge.of(peer.identity).says))
                doingRow
                driveRow(peer)
            } else {
                notYetABench
            }
        } header: {
            SectionHeading(text: "Duck")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// (1) Which Microduck: the lens as an avatar, the name, the colourway and
    /// the one word that says whether anything in a room can fall over.
    private func identityRow(_ peer: BenchPeer) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing(.standard)) {
            LensIndicator(state: lens, size: DesignMetric.minimumTarget)
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                HStack(spacing: Theme.spacing(.tight)) {
                    // A SWATCH ONLY FOR A DUCK THAT HAS A COLOUR. A bench has
                    // none — `BenchPeer` defaults its identity to teal because
                    // the type needs a value — so drawing the dot for a sim
                    // would claim a colourway this app has never learned.
                    if who.kind == .real {
                        Circle()
                            .fill(swatch(who.colourway))
                            .frame(width: Theme.spacing(.tight),
                                   height: Theme.spacing(.tight))
                            .overlay(Circle().strokeBorder(Theme.separator,
                                                           lineWidth: DesignMetric.hairlineStroke))
                            .accessibilityHidden(true)
                    }
                    Text(who.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(who.kindWord)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(peer.address.base)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Text(who.nameCameFrom.says)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(who.name))
        .accessibilityValue(Text("\(who.colourway.label), \(who.kindWord), "
                                 + "\(peer.address.base). \(who.nameCameFrom.says)"))
    }

    /// (4) What it is doing, and the one sentence a bench owes somebody
    /// underneath it.
    ///
    /// THE HONESTY CLAUSE IS NOT DECORATION. `BenchPeer.
    /// theWorldOnlyMovesWhenAsked` is the difference between a simulator that
    /// freezes when you let go and a robot that keeps walking until its deadman
    /// fires, and this screen is the first place a new owner reads a state word
    /// about a duck. Putting the word here without the clause would teach the
    /// habit that gets a real duck into a table leg.
    @ViewBuilder private var doingRow: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            StateBadge(text: DeviceCard.Doing.word(upright: live?.upright, running: false),
                       state: live == nil ? .offline : .idle)
            Text(BenchPeer.theWorldOnlyMovesWhenAsked)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// (5) The control affordance — PRESENT OR ABSENT, NEVER PRESENT AND INERT.
    ///
    /// A Drive button that is drawn and does nothing teaches somebody that this
    /// app is broken rather than that this link does not carry `robot.move`. So
    /// the button exists only when `DeviceCard.Control` says the method is
    /// live, and when it is not, its place is taken by the reason — which is
    /// the routing table's own sentence or the bench's own refusal, never one
    /// written here.
    @ViewBuilder private func driveRow(_ peer: BenchPeer) -> some View {
        let control = DeviceCard.Control.of(.move, over: peer.transportKind,
                                            reach: peer.reach)
        if control.isLive {
            Button { router.go(to: .control) } label: {
                Label("Drive", systemImage: "gamecontroller")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryActionMoves)
            .accessibilityLabel(Text("Drive"))
            .accessibilityHint(Text("Opens the Control tab, where the sticks are"))
        } else if let reason = control.reason {
            Text(reason)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text("Cannot drive from here"))
                .accessibilityValue(Text(reason))
        }
    }

    /// The explicit "not yet" for a phone with no bench set up.
    ///
    /// THE SENTENCE IS `BenchSetup.Diagnosis.nothingTyped`'S OWN, which is the
    /// same one the setup screen prints, and it names the next move rather than
    /// the news: start the bench on the other computer and type the address it
    /// prints.
    private var notYetABench: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            Text(BenchSetup.Diagnosis.nothingTyped.message)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink { BenchSettingsView(store: benches) } label: {
                Label("Add a bench", systemImage: "plus.circle")
            }
            .frame(minHeight: DesignMetric.minimumTarget)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - 6. what can I launch

    /// Up to four chips, or the sentence that says why there are none.
    ///
    /// EVERY CHIP IS PRESSABLE, INCLUDING THE ONES THAT WILL NOT RUN. A chip
    /// that refuses says so when it is pressed — `DuckQuickActions` wrote the
    /// reason — which is the same argument `DriveView` makes about the pad
    /// buttons a bench cannot honour: pressing one is how somebody finds out
    /// that the mouth is servo nine and no network drives it. A disabled
    /// control is invisible to VoiceOver and unreachable by Switch Control, and
    /// the sentence is the whole point of the button.
    @ViewBuilder private var quickActionSection: some View {
        Section {
            if actions.isEmpty {
                Text(DuckQuickActions.noneInstalled)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: chipWidth),
                                             spacing: Theme.spacing(.tight))],
                          spacing: Theme.spacing(.tight)) {
                    ForEach(actions) { action in chip(action) }
                }
                .padding(.vertical, Theme.spacing(.hairline))
            }
            if let lastAction {
                Text(lastAction)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text("Last action"))
                    .accessibilityValue(Text(lastAction))
            }
        } header: {
            SectionHeading(text: "Quick actions")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// One chip. ORANGE ONLY WHEN IT RUNS, which is this app's one colour rule
    /// — everything in the action colour changes the robot — and a chip that
    /// is going to answer with a refusal has not changed anything.
    @ViewBuilder private func chip(_ action: DuckQuickActions.Action) -> some View {
        Button { press(action) } label: {
            Text(action.title)
                .frame(maxWidth: .infinity, minHeight: DesignMetric.movingTarget)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(action.runs ? AnyButtonStyle(.primaryActionMoves)
                                 : AnyButtonStyle(QuietChipStyle()))
        .accessibilityLabel(Text(action.title))
        .accessibilityValue(ifPresent: action.reason)
        .accessibilityHint(Text(action.runs
                                ? "Loads this policy on the selected bench"
                                : "Says why this is not available"))
    }

    // MARK: - below the fold

    /// The camera the design asks for and this build cannot draw.
    private var cameraSection: some View {
        Section {
            Text(DeviceCard.noCameraYet)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text("Camera"))
                .accessibilityValue(Text(DeviceCard.noCameraYet))
        } header: {
            SectionHeading(text: "Camera")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// The two doors that open onto hardware.
    private var connectionSection: some View {
        Section {
            NavigationLink { FindDuckView() } label: {
                Label("Find a duck", systemImage: "antenna.radiowaves.left.and.right")
            }
            .frame(minHeight: DesignMetric.minimumTarget)
            NavigationLink { PairingSpikeView() } label: {
                Label("Run the pairing spike", systemImage: "bolt.horizontal")
            }
            .frame(minHeight: DesignMetric.minimumTarget)
        } header: {
            SectionHeading(text: "Connection")
        } footer: {
            Text(DuckLink.whatThisCanDo)
                .foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// Which bench this screen is pointed at, and where to change it.
    ///
    /// THE PICKER IS `DriveView`'S PICKER, bound to the same store, because
    /// there is one selected bench in this app and two screens showing two
    /// different ones would be two screens talking about different ducks.
    private var benchSection: some View {
        Section {
            if benches.benches.isEmpty {
                // NOT A PICKER WITH NOTHING IN IT. On a fresh install the store
                // is empty and a labelled control with no options is present
                // and inert — the exact shape this screen exists to refuse.
                // `DriveView` guards the same case the same way.
                NavigationLink { BenchSettingsView(store: benches) } label: {
                    Label("Set up a bench", systemImage: "plus.circle")
                }
                .frame(minHeight: DesignMetric.minimumTarget)
                Text(BenchSetup.Diagnosis.nothingTyped.message)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Bench", selection: Binding(
                    get: { benches.selectedID }, set: { benches.selectedID = $0 })) {
                    ForEach(benches.benches) { one in
                        Text(one.name).tag(UUID?.some(one.id))
                    }
                }
                NavigationLink { BenchSettingsView(store: benches) } label: {
                    Label("Manage benches", systemImage: "gearshape")
                }
                .frame(minHeight: DesignMetric.minimumTarget)
            }
        } header: {
            SectionHeading(text: "Bench")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - what the kit says about all this

    private var banner: DeviceCard.Banner { DeviceCard.Banner.of(alarms) }

    private var who: DeviceCard.Who {
        guard let peer else {
            return DeviceCard.Who(name: "", nameCameFrom: .benchHost,
                                  colourway: .yellow, kind: .sim)
        }
        return DeviceCard.Who.of(peer.identity, typed: benches.selected?.name)
    }

    private var presence: DeviceCard.Presence {
        DeviceCard.Presence(lastReplyAt: lastReplyAt,
                            transport: peer?.transportKind ?? .bench)
    }

    /// The eye: reaching while a request is in flight, open while something has
    /// answered lately, closed otherwise.
    private var lens: LensIndicator.Connection {
        if busy { return .connecting }
        return presence.isLive(now: now) ? .connected : .asleep
    }

    /// The chips.
    ///
    /// `mode: .walk` IS AN ASSUMPTION AND IT IS WRITTEN DOWN RATHER THAN
    /// HIDDEN. `robotd.toml` has a drive mode and `/health` does not report
    /// one, so this app cannot know whether a duck is on legs or on wheels.
    /// Walking is the default in Pollen's own config, and guessing roller would
    /// silently drop the Stand chip on every duck. When `/health` grows the
    /// field, this line reads it.
    private var actions: [DuckQuickActions.Action] {
        guard let peer else { return [] }
        return DuckQuickActions.installed(policies: health?.policies ?? [],
                                          mode: .walk,
                                          reach: peer.reach,
                                          transport: peer.transportKind)
    }

    /// What the peer is pointed at, as one value `.task(id:)` can compare.
    ///
    /// THE ADDRESS IS IN HERE AND THE TOKEN IS NOT, for `DriveView.peerKey`'s
    /// two measured reasons: Manage benches edits an address in place under the
    /// same id, so a key made of the id alone leaves the peer dialling a host
    /// the person has replaced; and putting the token in evaluates a
    /// synchronous Keychain read on every SwiftUI render. The errand reads it
    /// per request instead, so this only needs to know whether there is one.
    private var peerKey: String {
        guard let bench = benches.selected else { return "" }
        return "\(bench.id.uuidString)·\(bench.address)·\(bench.hasToken)"
    }

    /// A colourway as something to draw.
    ///
    /// `.sRGB` AND NOT `.sRGBLinear`, for the reason `DesignComponents` gives
    /// about the palette: these channels are gamma-encoded, and handing them to
    /// SwiftUI as linear values draws every one of them lighter than the number
    /// that was written down. The numbers themselves are `DuckColourway`'s,
    /// because a view that parsed a hex string would be doing arithmetic about
    /// a robot.
    private func swatch(_ colourway: DuckColourway) -> Color {
        let rgb = colourway.rgb
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    /// How wide a chip wants to be before the grid gives it a second column.
    /// A LAYOUT NUMBER AND NOTHING ELSE: two columns on a phone at the default
    /// text size, one at an accessibility size, because `.adaptive` reflows
    /// rather than shrinking.
    private var chipWidth: CGFloat { 140 }

    // MARK: - talking to the bench

    /// Everything this screen asks, in the order it asks it.
    ///
    /// HELLO FIRST, THROUGH THE PEER, AND THEN `/health` DIRECTLY — which is
    /// two GETs where one would do, and `DriveView.connect` already paid for
    /// the second and explained why. `hello` is the one call every transport in
    /// the vocabulary carries, so asking it is what makes this screen's first
    /// move a peer's rather than a bench's; `/health` answers a question no
    /// peer can be asked, which is which policies this machine holds. Both go
    /// to the same endpoint on this transport and they are still different
    /// questions. It is a status read on a machine on the same desk that
    /// advances no physics, so the cost is a few milliseconds.
    ///
    /// EVERY FAILURE BECOMES AN ALARM THROUGH A KIT CONSTRUCTOR. Nothing in
    /// this function writes a sentence.
    @MainActor private func open() async {
        busy = true
        defer { busy = false }
        now = Date()
        alarms = []
        // THE PEER IS TAKEN FROM THE REBUILD RATHER THAN READ BACK OUT OF
        // `@State`. A `State` write and a read of the same property inside one
        // function is the kind of thing that works until SwiftUI decides to
        // coalesce the update, and what it would produce is a screen that says
        // hello to the bench somebody just stopped using.
        guard let peer = rebuildPeer(), let bench = benches.selected else { return }

        do {
            let greeting = try await peer.call(.hello)
            lastReplyAt = Date()
            if let refusal = greeting.failure {
                add(DeviceCard.Alarm.of(refusal))
                return
            }
        } catch {
            add(alarm(for: error, address: bench.address))
            return
        }

        await readHealth(bench)
        await readState(peer)
        now = Date()
    }

    /// Which policies this bench holds, and what a failure to answer means.
    ///
    /// THE DIAGNOSIS IS THE KIT'S AND SO IS EVERY SENTENCE IT PRODUCES.
    /// `BenchSetup.diagnose` takes the status code, the body and whether the
    /// request completed — the pieces, rather than a `URLSession` — so the
    /// screen that started the request does not have to decide what a 401 or an
    /// unparseable body means. A bench that answers properly diagnoses as
    /// `.connected`, which is not an alarm at all.
    @MainActor private func readHealth(_ bench: BenchEndpoint) async {
        do {
            let armed = benches.armed(bench)
            let call = DuckBench.health(try armed.resolved())
            let (data, response) = try await URLSession.shared.data(
                for: DuckBench.urlRequest(for: call, token: armed.token))
            lastReplyAt = Date()
            let diagnosis = BenchSetup.diagnose(address: bench.address,
                                                status: (response as? HTTPURLResponse)?.statusCode,
                                                body: data, transportFailed: false)
            if let alarm = DeviceCard.Alarm.of(diagnosis) { add(alarm) }
            health = try? DuckBench.readHealth(data)
        } catch {
            add(alarm(for: error, address: bench.address))
        }
    }

    /// What the duck last did, if it has done anything.
    ///
    /// "NOTHING HAS HAPPENED YET" IS THE ORDINARY ANSWER HERE AND IT IS NOT AN
    /// ALARM. This screen never commands anything, and `BenchPeer` answers
    /// `studio.state` out of the block the last command came back with — so on
    /// a freshly opened front door there is genuinely nothing to report, and
    /// that is what `DeviceCard.Doing.word(upright: nil, ...)` already says in
    /// one word. Putting the peer's paragraph in the banner would be a red bar
    /// on every launch saying nothing is wrong at length.
    @MainActor private func readState(_ peer: BenchPeer) async {
        do {
            let reply = try await peer.call(.state)
            if let refusal = reply.failure {
                add(DeviceCard.Alarm.of(refusal))
                return
            }
            live = await peer.live
            lastReplyAt = Date()
        } catch let refusal as BenchPeer.Refusal {
            live = nil
            if refusal != .nothingHasHappenedYet {
                add(DeviceCard.Alarm.of(refusal))
            }
        } catch {
            live = nil
        }
    }

    /// Load a policy on the selected bench, and say what came back.
    ///
    /// THIS IS THE ONE PIECE OF I/O THIS FILE OWNS, AND IT IS I/O RATHER THAN
    /// ARITHMETIC. `POST /policy` is a bench endpoint with no method in the
    /// robot vocabulary — `DriveView` keeps it a `DuckBench.Call` for exactly
    /// that reason — so it cannot go through the peer, and the bearer token and
    /// the session live on this side of the boundary. What is NOT decided here
    /// is whether the action can run at all: `DuckQuickActions` decided that,
    /// and this switch only carries out its answer.
    @MainActor private func press(_ action: DuckQuickActions.Action) {
        guard case .loadsOnABench(let filename) = action.effect else {
            lastAction = action.reason
            return
        }
        Task { await load(filename, titled: action.title) }
    }

    @MainActor private func load(_ filename: String, titled title: String) async {
        guard let bench = benches.selected else {
            lastAction = BenchSetup.Diagnosis.nothingTyped.message
            return
        }
        busy = true
        defer { busy = false }
        do {
            let armed = benches.armed(bench)
            let call = try DuckDrive.load(try armed.resolved(), policy: filename)
            let data = try await URLSession.shared.data(
                for: DuckBench.urlRequest(for: call, token: armed.token)).0
            let state = try DuckDrive.readLive(data)
            live = state
            lastReplyAt = Date()
            now = Date()
            Haptic.behaviourStarted()
            // TWO KIT FRAGMENTS AND A COLON, WHICH IS AS MUCH AS THIS FILE IS
            // ALLOWED TO WRITE. The title is duckkit's own word for the slot
            // and the word after it is `DeviceCard.Doing`'s, so neither half is
            // a sentence invented in a view — and the claim it makes is only
            // what the bench answered with.
            // RECORDED ON THE STORE, so the Control tab's picker shows this
            // policy when it opens instead of loading the first name it sees.
            benches.noteLoaded(filename, on: armed.id)
            lastAction = "\(title): "
                + DeviceCard.Doing.word(upright: state.upright, running: false)
        } catch {
            lastAction = sentence(for: error)
        }
    }

    /// Throw the peer away and build the one this bench needs.
    ///
    /// AN ADDRESS THAT WILL NOT RESOLVE IS NOT SWALLOWED. `BenchStore.makePeer`
    /// answers nil for "no bench" and throws for an address that is not one, so
    /// the two are told apart here: nil leaves the device card showing its
    /// explicit "not yet", and a throw goes into the banner with the paragraph
    /// `BenchSetup` wrote about that particular kind of wrong address.
    /// - Returns: The peer that was built, so a caller does not have to read
    ///   `@State` back immediately after writing it.
    @discardableResult
    @MainActor private func rebuildPeer() -> BenchPeer? {
        health = nil
        live = nil
        lastReplyAt = nil
        do {
            let made = try benches.makePeer()
            peer = made
            return made
        } catch {
            peer = nil
            add(alarm(for: error, address: benches.selected?.address ?? ""))
            return nil
        }
    }

    private func add(_ alarm: DeviceCard.Alarm) {
        alarms.append(alarm)
    }

    /// A thrown thing as an alarm, in the words its own type wrote.
    ///
    /// ONE FUNNEL, BECAUSE THE SENTENCES ARE THE PRODUCT — `DriveView.report`'s
    /// argument, and the same list of types. What is different here is the
    /// tail: anything this app cannot name is handed to `BenchSetup.diagnose`
    /// as a failed transport rather than to `localizedDescription`, because
    /// "nothing answered there — either the bench is not running or that is not
    /// its address" is a true and actionable sentence about a `URLError`, and
    /// "The operation couldn't be completed" is this app admitting it did not
    /// know what it caught.
    private func alarm(for error: Error, address: String) -> DeviceCard.Alarm {
        switch error {
        case let refusal as DuckBench.ReadError:
            return DeviceCard.Alarm.of(refusal)
        case let refusal as BenchPeer.Refusal:
            return DeviceCard.Alarm.of(refusal)
        default:
            let diagnosis = BenchSetup.diagnose(address: address, status: nil,
                                                body: nil, transportFailed: true)
            return DeviceCard.Alarm.of(diagnosis)
                ?? DeviceCard.Alarm(severity: .critical,
                                    sentence: BenchSetup.Diagnosis.nothingListening.message,
                                    source: .benchSetup)
        }
    }

    /// The same funnel, for the one line under the quick actions.
    private func sentence(for error: Error) -> String {
        switch error {
        case let refusal as DuckBench.ReadError: return refusal.message
        case let refusal as DuckBench.Refusal: return refusal.message
        case let refusal as BenchEndpoint.Refusal: return refusal.message
        case let refusal as BenchPeer.Refusal: return refusal.message
        case let misuse as BenchPeer.Misuse: return misuse.message
        case let misuse as DuckCall.Misuse: return misuse.message
        case let refusal as DuckDrive.Refusal: return refusal.message
        default: return BenchSetup.Diagnosis.nothingListening.message
        }
    }
}

// MARK: - a chip that is going to say no

/// The surface a quick action wears when pressing it produces a sentence rather
/// than a policy load.
///
/// NOT `.disabled`, AND THAT IS THE WHOLE DESIGN. A disabled control is
/// invisible to VoiceOver and unreachable by Switch Control, and the sentence
/// is the entire reason the chip exists — the same argument `DriveView` makes
/// about the pad buttons a bench cannot honour, in a style this file has to
/// write again because that one is private to a file that is not this one.
///
/// IT LOSES THE ACTION COLOUR RATHER THAN FADING. Half-opacity takes a label to
/// roughly 2:1 and makes "why can't I press this" unanswerable.
/// `Theme.backgroundSecondary` is the recessed ground and carries
/// `Theme.textSecondary` well past 4.5:1 in both schemes, so this reads as
/// unavailable because it is not orange.
///
/// IT KEEPS THE 60PT FLOOR. What it would have done is change what a robot is
/// doing, and a person reaching for it is looking at the duck rather than at
/// the phone.
private struct QuietChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.spacing(.standard))
            .frame(minHeight: DesignMetric.movingTarget)
            .background(Capsule().fill(configuration.isPressed ? Theme.separator
                                                               : Theme.backgroundSecondary))
            .overlay(Capsule().strokeBorder(Theme.separator,
                                            lineWidth: DesignMetric.hairlineStroke))
            .contentShape(Capsule())
    }
}

/// Two button styles behind one type, so a chip can pick its surface at draw
/// time.
///
/// SWIFTUI HAS NO OTHER WAY TO SAY THIS. `.buttonStyle` takes a concrete type,
/// and a ternary between two different styles is a type error; branching the
/// whole `Button` instead would give the two branches different identities and
/// SwiftUI would rebuild the control — losing its press state — every time an
/// action went from runnable to not. This is the standard erasure and it costs
/// one allocation per chip.
private struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
