import SwiftUI
import StudioKit
import DuckKit

/// Robot — the machine itself, and the honest length of what this app knows
/// about it.
///
/// WHY A WHOLE TAB FOR HARDWARE WHEN NO HARDWARE EXISTS YET. This is the screen
/// somebody opens after the answer on My Microduck was "no". The front door
/// answers seven questions about one duck in one glance; this one answers the
/// follow-up questions, which are all of the form "what IS this thing, and
/// which part of it is not talking to me" — motors, firmware, network,
/// capabilities, and the one diagnostic this app owns. Those belong behind a
/// tab rather than under a disclosure triangle on the front door, because a
/// person who needs them needs several of them at once.
///
/// THE INTERESTING CONTENT OF THIS SCREEN IS THE ABSENCES, AND THEY ARE DRAWN
/// RATHER THAN OMITTED. Almost every row here has a "not yet" behind it: no
/// robot has been built, the app has no scanner on this screen, BLE carries a
/// deliberate subset that excludes everything continuous, and the only machine
/// that answers today is a physics bench on somebody's desk. A screen that
/// hid those rows would look like a screen with nothing to say, and a screen
/// that faked them would be worse. So each absence ships as a sentence, and
/// EVERY ONE OF THOSE SENTENCES IS A KIT CONSTANT that `swift test` already
/// asserts on Linux — `DuckLink.identifierIsNotAnIdentity`,
/// `DuckLink.whatThisCanDo`, `LabCatalogue.noRobotYet`,
/// `BenchSetup.Diagnosis.nothingTyped`, `BenchPeer.Refusal.nothingHasHappenedYet`,
/// `DuckDrive.thisIsNotARobot`, `PairingSpike.whatThisIsFor`. Nothing on this
/// screen composes prose about a robot.
///
/// THE FOUR PUBLISHED FIGURES ARE LABELLED AS PUBLISHED AND NOT AS READINGS.
/// Height, mass and the sensor list are what Pollen have published about the
/// model; nothing in this app has weighed a duck or seen a LiDAR return. They
/// sit under their own sub-heading, above the rows that would carry a
/// particular robot's name and serial, precisely so the two cannot be read as
/// one list. The motor count is the only one taken from code rather than typed
/// again — `DuckModel.jointCount` — because the model this app simulates and
/// the robot Pollen publish have to agree about how many joints there are, and
/// if they ever stop agreeing that disagreement is a finding rather than a
/// cosmetic difference between two numbers in two files.
///
/// WHAT THIS SCREEN CAN ACTUALLY ASK, AND OF WHOM. One thing: the selected
/// bench, over HTTP, through `BenchStore.makePeer()` — the same peer the front
/// door and the Drive screen use, so there is one errand and one token policy
/// in the app rather than three. `hello` proves the link, `/health` answers the
/// firmware questions no peer can be asked, and `studio.state` answers the
/// joints. All three are reads against a machine on the same desk. Nothing here
/// commands anything, which is why "nothing has happened yet" is the ordinary
/// answer for the motors and is not drawn as a fault.
///
/// THE CAPABILITY TABLE IS THE KIT'S ANSWER IN EVERY CELL. `DuckMethod.reach(for:)`
/// is exhaustive on both axes with no `default` anywhere, and this view calls
/// it once per cell rather than keeping a copy of the routing table — so a
/// method added to the vocabulary, or a transport added to the four, appears
/// here without anybody remembering to come back. A hand-drawn table would be
/// a fifth copy of a decision that exists precisely so there is one.
struct RobotView: View {
    @ObservedObject var benches: BenchStore
    @ObservedObject var models: EndpointStore

    /// The peer for whichever bench is chosen, rebuilt whenever that changes.
    @State private var peer: BenchPeer?

    /// What `/health` last said. The firmware section is this or a "not yet".
    @State private var health: DuckBench.Health?

    /// The last state block, or nil when nothing has been commanded on this
    /// link — which on this screen is always, because this screen never
    /// commands. See `readState`.
    @State private var live: DuckDrive.Live?

    /// The one sentence about why the bench did not answer, when it did not.
    /// Always a kit constant, funnelled through `sentence(for:)`.
    @State private var trouble: String?

    /// Larger text does not mean a narrower table; it means a different table.
    /// See `capabilityRow`.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // MARK: - the screen

    var body: some View {
        List {
            hardwareSection
            motorSection
            firmwareSection
            networkSection
            capabilitySection
            diagnosticsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundPrimary)
        .navigationTitle("Robot")
        .navigationBarTitleDisplayMode(.large)
        // ONE GEAR, ONCE PER TAB ROOT, SAME PLACE AND SAME WORD as the other
        // four. Settings is reachable from every tab because it is where the
        // benches live, and a person who has just read "no bench" on this
        // screen is one tap from the place that fixes it.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView(models: models, benches: benches) } label: {
                    Image(systemName: "gear").accessibilityLabel(Text("Settings"))
                }
            }
        }
        // ONE ENTRY POINT FOR BOTH ARRIVALS, exactly as the front door does it:
        // `.task(id:)` runs on appear AND whenever the key changes, and cancels
        // the previous run rather than racing it.
        .task(id: peerKey) { await open() }
        .refreshable { await open() }
    }

    // MARK: - hardware

    /// What the model is, then what this particular robot is — in that order,
    /// and never run together.
    private var hardwareSection: some View {
        Section {
            SectionHeading(text: "Published specifications")
            // THE COUNT IS THE KIT'S AND THE OTHER THREE ARE PUBLISHED FIGURES.
            // See the file comment: if `DuckModel.jointCount` ever disagreed
            // with Pollen's published motor count, this row is where somebody
            // would notice, which is worth more than a fifth literal 15.
            TelemetryRow(label: "Motors", value: "\(DuckModel.jointCount)")
            // THE OTHER THREE ARE THE KIT'S TOO. They were literals here, which
            // meant the mass on this row could disagree with the mass every
            // drag refusal in the app is computed from — and it did, 800 g
            // against 737 g. `DuckPublishedSpecs` holds Pollen's figures with
            // their source, and the note under the mass says which is which.
            TelemetryRow(label: "Height", value: "\(DuckPublishedSpecs.heightCentimetres)", unit: "cm")
            TelemetryRow(label: "Mass", value: "\(DuckPublishedSpecs.massGrams)", unit: "g")
            Text(DuckPublishedSpecs.massNote)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TelemetryRow(label: "Sensors", value: DuckPublishedSpecs.sensors)
            Text(DuckPublishedSpecs.source)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)

            SectionHeading(text: "This robot")
            // NAME, SERIAL AND UPTIME ARE `DuckLink.SystemInfo`'S THREE FIELDS
            // AND NONE OF THEM CAN ARRIVE HERE. `system.info` is a Bluetooth
            // call, this screen has no scanner, and the only place in the app
            // that makes that call is the pairing spike. Drawing three empty
            // rows would be an empty card; drawing three dashes would be a
            // robot that answered with nothing. So the kit's own paragraph
            // about the shortcut this app takes goes here instead, and the
            // spike is one tap away.
            Text(DuckLink.identifierIsNotAnIdentity)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text("Name, serial and uptime"))
                .accessibilityValue(Text(DuckLink.identifierIsNotAnIdentity))
            NavigationLink { PairingSpikeView() } label: {
                Label("Run the pairing spike", systemImage: "bolt.horizontal")
            }
            .frame(minHeight: DesignMetric.minimumTarget)
        } header: {
            SectionHeading(text: "Hardware")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - motors

    /// Fifteen joints, and which of them the bench says are about to clip.
    private var motorSection: some View {
        Section {
            if let live {
                jointGrid(live.stance.jointAngles)
                // WHAT A LOADED NODE MEANS, IN THE KIT'S WORDS. `JointNode`
                // takes a 0-to-1 load and this screen has only a yes/no to give
                // it — `DuckPad.nearLimits` answers "is this joint about to
                // clip", not "how hard is it pressing" — so the definition of
                // the mark travels with the mark rather than being left to be
                // guessed from a circle's size.
                Text(DuckPad.Layer.limits.detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text("What a marked joint means"))
                    .accessibilityValue(Text(DuckPad.Layer.limits.detail))
                // EVERY NUMBER ABOVE CAME OUT OF A SIMULATOR AND THE CAPTION
                // SAYS SO. This is the same constant the Drive screen prints,
                // in the same words, because it is the same claim.
                Text(DuckDrive.thisIsNotARobot)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text("What these joints are"))
                    .accessibilityValue(Text(DuckDrive.thisIsNotARobot))
            } else if peer != nil {
                // THE ORDINARY ANSWER, AND NOT A FAULT. This screen reads and
                // never commands; a bench's world only advances inside a
                // request, so there is genuinely no stance to draw until
                // something has driven it. The kit's paragraph says exactly
                // that, at length, and is the reason no red bar appears here.
                notYet(BenchPeer.Refusal.nothingHasHappenedYet.message,
                       labelled: "Joints")
            } else {
                noBench
            }
        } header: {
            SectionHeading(text: "Motors")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// The fifteen joints as nodes, reflowing on their own.
    ///
    /// ADAPTIVE COLUMNS AND A SCALED TILE, so the grid is four across at the
    /// default text size and one or two across at the largest, with no
    /// breakpoint written down. A fixed column count is how a name like
    /// `left_hip_roll` ends up truncated to `left_hip_...` at exactly the size
    /// somebody chose in order to read it.
    private func jointGrid(_ angles: [Double]) -> some View {
        // THE NAMES THE KIT NAMED. `DuckPad.nearLimits` returns the joints it
        // considers near a stop, by name; membership in that set is the whole
        // of this view's decision, and the ten degrees behind it stays in the
        // kit where a test can read it.
        let near = Set(DuckPad.nearLimits(angles).map(\.name))
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: tile),
                                            spacing: Theme.spacing(.snug))],
                         alignment: .leading,
                         spacing: Theme.spacing(.snug)) {
            ForEach(DuckModel.jointNames, id: \.self) { name in
                VStack(spacing: Theme.spacing(.hairline)) {
                    JointNode(load: near.contains(name) ? 1 : 0, label: name)
                        .accessibilityHidden(true)
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(near.contains(name)
                                         ? Theme.refused : Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(name))
                .accessibilityValue(Text(near.contains(name)
                                         ? "Near a stop" : "Clear of its stops"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A joint tile's smallest width, scaled with the person's text size.
    @ScaledMetric(relativeTo: .caption2) private var tile: CGFloat = 76

    // MARK: - firmware

    /// What is running on the machine that answers, and what is not running
    /// anywhere yet.
    private var firmwareSection: some View {
        Section {
            SectionHeading(text: "On the bench")
            if let health {
                // THE PLANT SENTENCE CARRIES BOTH THE NAME AND THE DIGEST AND
                // ALSO THE TWO WAYS THEY CAN BE ABSENT. A bench that will not
                // say which world it runs is still a usable bench and an
                // unattributable result, and `Health.plantSentence` is the one
                // place that difference is written down.
                Text(health.plantSentence)
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text("World"))
                    .accessibilityValue(Text(health.plantSentence))
                TelemetryRow(label: "Software", value: health.bench)
                TelemetryRow(label: "Tick rate",
                             value: String(format: "%.0f", health.tickHz), unit: "Hz")
                TelemetryRow(label: "Cores", value: "\(health.cores)")
            } else if let trouble {
                notYet(trouble, labelled: "Bench")
            } else if peer != nil {
                notYet(BenchSetup.Diagnosis.nothingListening.message, labelled: "Bench")
            } else {
                noBench
            }

            SectionHeading(text: "Over Bluetooth")
            // THE DAEMON VERSION AND THE REVISION ARE `DuckLink.Hello`'S OTHER
            // TWO FIELDS, AND NO HELLO HAS EVER BEEN ANSWERED. That is the last
            // paragraph of the kit's own account of what the Bluetooth path can
            // do — "Nothing here has been run against a robot" — which is
            // exactly the firmware answer, so it is quoted rather than
            // paraphrased into a shorter lie.
            Text(DuckLink.whatThisCanDo)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text("Robot firmware"))
                .accessibilityValue(Text(DuckLink.whatThisCanDo))
        } header: {
            SectionHeading(text: "Firmware")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - network

    /// The one address this app can dial, and the one it cannot.
    private var networkSection: some View {
        Section {
            SectionHeading(text: "Bench")
            if let peer {
                // THE PEER'S OWN ADDRESS, NOT THE STRING SOMEBODY TYPED.
                // `BenchEndpoint.resolved()` has already turned what was typed
                // into a host and a port and refused everything off the local
                // network, and `Address.base` is how the app spells it when it
                // dials. Showing the typed text instead would show a trailing
                // slash and a scheme that never reach the wire.
                TelemetryRow(label: "Address", value: peer.address.base)
                TelemetryRow(label: "Transport", value: peer.transportKind.label)
            } else {
                noBench
            }

            SectionHeading(text: "Advertised address")
            // A ROBOT BROADCASTS ITS OWN ADDRESS IN ITS ADVERTISEMENT — that is
            // what `DuckLink.Address` decodes, in three cases rather than two —
            // and this screen has no scanner to hear one. The reason there is
            // nothing to hear is not a bug in this view, and the kit says it in
            // one line.
            notYet(LabCatalogue.noRobotYet, labelled: "Advertised address")
            NavigationLink { FindDuckView() } label: {
                Label("Find a duck", systemImage: "dot.radiowaves.left.and.right")
            }
            .frame(minHeight: DesignMetric.minimumTarget)
        } header: {
            SectionHeading(text: "Network")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - capabilities

    /// Every word this app can say, and which of the four links carries it.
    private var capabilitySection: some View {
        Section {
            ForEach(DuckMethod.allCases, id: \.self) { method in
                capabilityRow(method)
            }
        } header: {
            SectionHeading(text: "Capabilities")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// One method, four answers.
    ///
    /// TWO LAYOUTS AND NOT ONE THAT SHRINKS. At ordinary sizes the four
    /// transports are a row of small marks under the method's wire name, which
    /// is the shape a table wants: the eye runs down a column and finds the
    /// gaps. At an accessibility size that row cannot survive — four labelled
    /// cells at 53pt is a horizontal scroll bar, and a horizontal scroll bar
    /// inside a vertically scrolling list is a control nobody finds — so it
    /// becomes four labelled rows instead, each one a `TelemetryRow` that
    /// already knows how to stack its own label and value. The information is
    /// identical; only the axis changes.
    @ViewBuilder private func capabilityRow(_ method: DuckMethod) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(method.rawValue)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                ForEach(DuckTransportKind.allCases, id: \.self) { transport in
                    TelemetryRow(label: transport.label,
                                 value: carries(transport, method) ? "Carried" : "Not carried")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                Text(method.rawValue)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                HStack(alignment: .top, spacing: Theme.spacing(.standard)) {
                    ForEach(DuckTransportKind.allCases, id: \.self) { transport in
                        VStack(spacing: Theme.spacing(.hairline)) {
                            Image(systemName: carries(transport, method)
                                  ? "checkmark.circle.fill" : "minus.circle")
                                .foregroundStyle(carries(transport, method)
                                                 ? Theme.success : Theme.textTertiary)
                            Text(transport.label)
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // ONE ELEMENT PER METHOD, NOT FIVE. Thirteen methods times four
            // marks is fifty-two stops for a swipe, which is a table nobody
            // would read to the end of. The row says its own name and then
            // which links carry it.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(method.rawValue))
            .accessibilityValue(Text(spokenReach(method)))
        }
    }

    /// The routing table's answer, asked rather than remembered.
    private func carries(_ transport: DuckTransportKind, _ method: DuckMethod) -> Bool {
        DuckMethod.reach(for: transport).contains(method)
    }

    /// The same four answers as one phrase, for a screen reader.
    ///
    /// A LIST OF THE ONES THAT ARE CARRIED, because that is the shorter list
    /// for most methods and because "not carried by Bench" is a sentence a
    /// person has to negate before it means anything. The transport words are
    /// `DuckTransportKind.label`'s, so the spoken table and the drawn one
    /// cannot drift apart.
    private func spokenReach(_ method: DuckMethod) -> String {
        let carried = DuckTransportKind.allCases
            .filter { carries($0, method) }
            .map(\.label)
        guard !carried.isEmpty else { return "Carried by no link here" }
        return "Carried by " + carried.joined(separator: ", ")
    }

    // MARK: - diagnostics

    /// The one experiment this app owns.
    private var diagnosticsSection: some View {
        Section {
            NavigationLink { PairingSpikeView() } label: {
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    Label("Run the pairing spike", systemImage: "bolt.horizontal")
                    Text(spikeCaption)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: DesignMetric.minimumTarget)
        } header: {
            SectionHeading(text: "Diagnostics")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// The spike's own first sentence, taken whole.
    ///
    /// A PREFIX OF A TESTED CONSTANT RATHER THAN A SUMMARY OF IT. The full
    /// paragraph is four sentences about §5.5 of Pollen's app-path design and
    /// belongs on the spike's own screen; what a row caption has room for is
    /// the first one, and the first one — "This is not a feature." — is the
    /// part somebody about to tap needs. Writing a shorter caption by hand
    /// would be this file making a claim about the spike, which is the thing
    /// the house rule exists to stop.
    private var spikeCaption: String {
        let whole = PairingSpike.whatThisIsFor
        guard let stop = whole.firstIndex(of: ".") else { return whole }
        return String(whole[...stop])
    }

    // MARK: - the two shapes an absence takes

    /// A kit sentence, drawn as itself.
    private func notYet(_ sentence: String, labelled label: String) -> some View {
        Text(sentence)
            .font(.footnote)
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(sentence))
    }

    /// No bench set up at all — which is a fresh install, and not a fault.
    ///
    /// THE SAME SENTENCE AND THE SAME DOOR AS THE FRONT DOOR'S. A person who
    /// meets "no bench" twice in two tabs should meet the same words and the
    /// same button both times, or they will wonder whether they are two
    /// different problems.
    private var noBench: some View {
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

    // MARK: - what this screen asks, and of whom

    /// What the peer is pointed at, as one value `.task(id:)` can compare.
    ///
    /// THE ADDRESS IS IN HERE AND THE TOKEN IS NOT, for the reason `DriveView`
    /// and the front door both measured: an address edited in place under the
    /// same id would otherwise leave the peer dialling a host that has been
    /// replaced, and putting the token in would run a synchronous Keychain read
    /// on every render. The errand reads it per request instead.
    private var peerKey: String {
        guard let bench = benches.selected else { return "" }
        return "\(bench.id.uuidString)·\(bench.address)·\(bench.hasToken)"
    }

    /// Hello, then `/health`, then the state — in that order and for three
    /// different reasons.
    ///
    /// `hello` IS FIRST BECAUSE IT IS THE ONE CALL EVERY TRANSPORT CARRIES, so
    /// asking it makes this screen's first move a peer's rather than a bench's
    /// — the same shape it would have against a robot. `/health` is second and
    /// goes directly, because plant, tick rate and core count are questions no
    /// peer can be asked: `BenchPeer.sayHello` deliberately answers with what a
    /// bench can honestly say and not with a fabricated API version, and the
    /// core count is not in that answer. `studio.state` is last because it is
    /// the only one whose ordinary answer is "nothing yet".
    ///
    /// NOTHING IN HERE WRITES A SENTENCE. Every failure goes through
    /// `sentence(for:)`, which does nothing but pick which kit constant applies.
    @MainActor private func open() async {
        trouble = nil
        health = nil
        live = nil
        peer = nil

        guard let bench = benches.selected else { return }
        let made: BenchPeer?
        do {
            made = try benches.makePeer()
        } catch {
            trouble = sentence(for: error)
            return
        }
        guard let made else { return }
        peer = made

        do {
            let greeting = try await made.call(.hello)
            if let refusal = greeting.failure {
                trouble = refusal.says
                return
            }
        } catch {
            trouble = sentence(for: error)
            return
        }

        await readHealth(bench)
        await readState(made)
    }

    /// The firmware questions, asked of `/health` directly.
    ///
    /// THE DIAGNOSIS IS THE KIT'S. `BenchSetup.diagnose` takes the status code,
    /// the body and whether the request completed — the pieces rather than a
    /// `URLSession` — so this file never decides what a 401 means.
    @MainActor private func readHealth(_ bench: BenchEndpoint) async {
        do {
            let armed = benches.armed(bench)
            let call = DuckBench.health(try armed.resolved())
            let (data, response) = try await URLSession.shared.data(
                for: DuckBench.urlRequest(for: call, token: armed.token))
            let diagnosis = BenchSetup.diagnose(address: bench.address,
                                                status: (response as? HTTPURLResponse)?.statusCode,
                                                body: data, transportFailed: false)
            if !diagnosis.isConnected { trouble = diagnosis.message }
            health = try? DuckBench.readHealth(data)
        } catch {
            trouble = sentence(for: error)
        }
    }

    /// The joints, if anything has ever moved them on this link.
    ///
    /// "NOTHING HAS HAPPENED YET" IS NOT AN ERROR HERE AND MUST NOT BE SHOWN AS
    /// ONE. This screen never commands, and `BenchPeer` answers `studio.state`
    /// out of the block the last command came back with — so on a freshly
    /// opened tab there is genuinely nothing, and the motor section draws the
    /// peer's own paragraph saying so. Putting it in `trouble` as well would
    /// make the firmware section report a fault about a bench that answered.
    @MainActor private func readState(_ peer: BenchPeer) async {
        do {
            let reply = try await peer.call(.state)
            if reply.failure != nil {
                live = nil
                return
            }
            live = await peer.live
        } catch let refusal as BenchPeer.Refusal {
            live = nil
            if refusal != .nothingHasHappenedYet { trouble = refusal.message }
        } catch {
            live = nil
        }
    }

    /// Which kit constant a thrown error is.
    ///
    /// A FUNNEL AND NOT A WRITER. Every branch returns a sentence some other
    /// file already owns and `swift test` already reads; the default is the
    /// bench-setup diagnosis for a link that never completed, which is what a
    /// `URLError` out of `URLSession` means here.
    private func sentence(for error: Error) -> String {
        switch error {
        case let refusal as DuckBench.ReadError: return refusal.message
        case let refusal as DuckBench.Refusal: return refusal.message
        case let refusal as BenchEndpoint.Refusal: return refusal.message
        case let refusal as BenchPeer.Refusal: return refusal.message
        case let misuse as BenchPeer.Misuse: return misuse.message
        case let misuse as DuckCall.Misuse: return misuse.message
        default: return BenchSetup.Diagnosis.nothingListening.message
        }
    }
}
