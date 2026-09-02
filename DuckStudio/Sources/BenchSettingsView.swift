import SwiftUI
import StudioKit

/// The benches this app knows about — named, saved, and one of them chosen.
///
/// THIS IS THE MODELS SCREEN FOR BENCHES, on purpose. The Models tab already
/// solved "several saved connections, one selected, each checkable on its own",
/// and the bench had a single unnamed address box instead — so the app could
/// hold one bench, could not say which, and forgot the last one every time you
/// moved between machines. Copying that screen's shape is worth more than a
/// fresh design: somebody who has set up a model already knows how this works.
///
/// A NEW ENTRY CAN BE CHECKED BEFORE IT IS FINISHED. "Check this address" asks
/// for `/health`, which a bench answers without running anything, so it works
/// on an entry with no name and before any policy has been chosen — which is
/// the only moment anybody presses it.
///
/// AN ADDRESS IS THE ONE THING ON THIS SCREEN SET IN FIGURES THAT DO NOT MOVE.
/// A host and port is transcribed character by character off another machine's
/// terminal, so it is mono for the same reason the setup screen's command is:
/// it is a thing to copy, not a thing to read. Everything else — names, the
/// steps, the caveats — is SF.
struct BenchSettingsView: View {
    @ObservedObject var store: BenchStore
    @State private var editing: BenchEndpoint?

    var body: some View {
        Form {
            if let note = store.unreadableNote {
                Section {
                    Text(note).font(.footnote).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Got it") { store.dismissUnreadableNote() }
                        .foregroundStyle(Theme.actionSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            // TWO ForEach AND NOT ONE WITH A GUARD IN THE DELETE CLOSURE.
            // `.onDelete` is attached to a ForEach and hands back indexes into
            // whatever that ForEach was given; with the phone at index 0 of one
            // combined list, a swipe on the first row would ask the store to
            // delete a bench it must refuse — and a swipe that animates a row
            // away and then puts it back is a control that lies about what it
            // did. Splitting the list means the phone's row has no delete to
            // offer in the first place.
            Section {
                phoneRow
                ForEach(store.benches.filter(\.isEditable)) { bench in
                    row(bench)
                }
                .onDelete { indexes in
                    let editable = store.benches.filter(\.isEditable)
                    indexes.map { editable[$0] }.forEach(store.delete)
                }
            } header: {
                SectionHeading(text: "Run things on")
            } footer: {
                // THE CLAIM AND ITS CAVEAT TRAVEL TOGETHER. `samePhysics` says the
                // phone runs the bench's physics — proven to the digit for the
                // first fifty ticks — and `notTheSameTrajectory` says where the
                // two inference engines part company after that. A screen that
                // drew the first without the second would be the sentence the
                // report file exists to forbid.
                VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                    Text(PhoneBenchReport.alwaysOneBench)
                    Text(PhoneBenchReport.samePhysics)
                    Text(PhoneBenchReport.notTheSameTrajectory)
                }
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                ForEach(BenchSetup.presets) { preset in
                    Button {
                        editing = BenchEndpoint(name: preset.suggestedName,
                                                address: preset.address)
                    } label: {
                        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                            Label(preset.name, systemImage: preset.symbol)
                                .foregroundStyle(Theme.textPrimary)
                            Text(preset.detail)
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                SectionHeading(text: "Add one")
            } footer: {
                Text(BenchSetup.preambleForAdding)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                NavigationLink { BenchSetupView() } label: {
                    Label("The steps", systemImage: "list.number")
                }
            } header: {
                SectionHeading(text: "Setting one up, once")
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        // THE RECESSED GROUND, AND EVERY ROW A CARD ON IT. `Palette` proves the
        // text tokens at 4.5:1 against `surfacePrimary` and documents that
        // `backgroundSecondary` falls short of it — so the coloured words on
        // this screen all sit inside a row, and the headers and footers, which
        // sit outside one, are grey.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Benches")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { bench in
            NavigationStack {
                BenchEditorView(bench: store.armed(bench), store: store)
            }
        }
    }

    /// The bench that is this phone: selectable, and nothing else.
    ///
    /// NO GLYPH, NO SWIPE, NO TOKEN, AND NO "Wi-Fi only". Every one of those
    /// belongs to an address somebody typed, and there is no address here — the
    /// physics runs inside the app on a loopback port the system hands out at
    /// launch. What is left is the one thing this row is for: making it the
    /// bench every other screen will use.
    ///
    /// THE PORT IS NOT DRAWN, DELIBERATELY. It is different every launch and
    /// means nothing to anybody; showing it would invite somebody to type it
    /// somewhere. What IS drawn is whether the bench is up yet, because that is
    /// the one state a person can be waiting on.
    private var phoneRow: some View {
        Button {
            store.selectedID = BenchEndpoint.thisPhone.id
        } label: {
            HStack(spacing: Theme.spacing(.tight)) {
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    Label(PhoneBenchReport.name, systemImage: "iphone")
                        .foregroundStyle(Theme.textPrimary)
                    Text(store.phonePort == 0 ? PhoneBenchReport.notListening
                                              : PhoneBenchReport.phoneRowNote)
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.spacing(.tight))
                if BenchEndpoint.thisPhone.id == store.selectedID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.brandPrimary)
                        .accessibilityLabel(Text("Selected"))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One saved bench: what it is called, where it is, and whether it is the
    /// one every other screen will use.
    ///
    /// TWO CONTROLS IN ONE ROW, AND BOTH ARE REACHABLE IN BOTH DIRECTIONS. The
    /// row selects and the glyph edits, which is the shape the Models screen
    /// already uses — but the glyph was a twenty-point image with no padding,
    /// well under the forty-four points the HIG asks of anything a finger is
    /// aimed at, and the first fix only half worked. Twelve points above and
    /// below make it tall enough; twelve on the LEADING side alone leave it
    /// about thirty-four wide, because there is nothing on the trailing side to
    /// pad against. A target that clears the floor in one direction and misses
    /// it in the other is still a miss, and this is the control that opens an
    /// address somebody transcribed by hand.
    ///
    /// SO THE FLOOR IS STATED RATHER THAN ARRIVED AT. `DesignMetric.minimumTarget`
    /// is the app's one 44 and this names it, the way `PrimaryActionStyle` and
    /// the model picker's search buttons already do, instead of leaving the
    /// number to be recomputed from a glyph size and a gap. The padding stays:
    /// it is what keeps the glyph off the name beside it, which is a spacing
    /// decision and belongs on the spacing scale.
    private func row(_ bench: BenchEndpoint) -> some View {
        HStack(spacing: Theme.spacing(.tight)) {
            Button {
                store.selectedID = bench.id
            } label: {
                HStack(spacing: Theme.spacing(.tight)) {
                    VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                        Text(bench.name).foregroundStyle(Theme.textPrimary)
                        Text(bench.address)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                        // SAID WHILE IT IS STILL WORKING. A Wi-Fi bench fails
                        // on the bus in a way that looks like it going down.
                        //
                        // IN `warning` AND NOT IN GREY, because that is what
                        // this is: a thing that is fine now and will stop being
                        // fine without announcing itself. It is on a card, so
                        // the token is one `PaletteTests` has cleared at 4.5:1
                        // against the ground under it.
                        if !bench.isTailnet {
                            Text("Wi-Fi only")
                                .font(.caption2).foregroundStyle(Theme.warning)
                        }
                    }
                    Spacer(minLength: Theme.spacing(.tight))
                    if bench.id == store.selectedID {
                        // THE TICK IS THE ONLY THING SAYING WHICH BENCH EVERY
                        // OTHER SCREEN WILL USE, and an unlabelled glyph says
                        // it to nobody who cannot see it.
                        Image(systemName: "checkmark")
                            .foregroundStyle(Theme.brandPrimary)
                            .accessibilityLabel(Text("Selected"))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                editing = bench
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Theme.actionSecondary)
                    .padding(.vertical, Theme.spacing(.snug))
                    .padding(.leading, Theme.spacing(.snug))
                    .frame(minWidth: DesignMetric.minimumTarget,
                           minHeight: DesignMetric.minimumTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Edit \(bench.name)"))
        }
    }
}

/// One bench, being edited — with the two questions a person actually has:
/// does this address answer, and what is on it.
///
/// THE VERDICT IS A WORD BEFORE IT IS A SENTENCE. This used to be a tinted
/// circle-glyph beside a paragraph: green tick or orange exclamation, and the
/// only one-glance answer to "did that work" was the colour. `StateBadge` is
/// the app's rule made structural — the word is never allowed out without the
/// dot and the dot is never allowed out without the word — so the badge says
/// "Connected" or "Unreachable" and the sentence under it says which of the
/// several very different reasons it was.
struct BenchEditorView: View {
    @State var bench: BenchEndpoint
    @ObservedObject var store: BenchStore

    @Environment(\.dismiss) private var dismiss
    @State private var diagnosis: BenchSetup.Diagnosis?
    @State private var policies: [String] = []
    @State private var busy = false
    @State private var refusal: String?

    var body: some View {
        Form {
            Section {
                TextField("My bench", text: $bench.name)
            } header: {
                SectionHeading(text: "Name")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                TextField("100.122.199.6:8770", text: $bench.address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    // MONO, BECAUSE IT IS TRANSCRIBED AND NOT READ. A host and
                    // port is copied digit by digit off another machine's
                    // terminal, and proportional figures make 100.122.199.6 and
                    // 100.l22.l99.6 look alike.
                    .font(.body.monospaced())
                    .onSubmit { bench.address = BenchSetup.tidy(bench.address) }
                SecureField("Token, only if you set one", text: Binding(
                    get: { bench.token ?? "" },
                    set: { bench.token = $0 }))
            } header: {
                SectionHeading(text: "Address")
            } footer: {
                Text("Host and port, as the start script prints it. No http://, no trailing "
                   + "slash — this is not a web address.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                // THE ACTION COLOUR ON THE ONE CONTROL THAT LEAVES THE PHONE.
                // Everything else in this form edits a field; this one dials an
                // address, and the capsule is what says so before it is pressed.
                //
                // FORTY-FOUR AND NOT SIXTY. `primaryActionMoves` is for a
                // control pressed by somebody watching a robot rather than the
                // phone; asking a bench for its health moves nothing at all.
                Button {
                    Task { await check() }
                } label: {
                    Text(busy ? "Asking…" : "Check this address")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .disabled(busy)

                if let diagnosis {
                    VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                        StateBadge(text: standing(diagnosis).text,
                                   state: standing(diagnosis).state)
                        Text(diagnosis.message)
                            .font(.footnote)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, Theme.spacing(.hairline))
                }

                if !policies.isEmpty {
                    DisclosureGroup {
                        ForEach(policies, id: \.self) { name in
                            Text(name)
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.textPrimary)
                        }
                    } label: {
                        // A COUNT THAT CHANGES, SET IN FIGURES THAT DO NOT MOVE.
                        // It is different for every bench and different again
                        // after somebody drops a policy on one, which is exactly
                        // what earns tabular digits; the words beside it never
                        // change and stay in SF.
                        //
                        // NOT A `TelemetryRow`, THOUGH IT IS THE SAME PAIR. A
                        // disclosure's label lives inside the disclosure's own
                        // accessibility element, and `TelemetryRow` declares
                        // itself an element with `children: .ignore` — nested,
                        // the expand action ends up on a thing that has already
                        // said it has no children. The pair is drawn the way
                        // that component draws it and left as plain text.
                        HStack(alignment: .firstTextBaseline,
                               spacing: Theme.spacing(.tight)) {
                            Text("What it can run")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: Theme.spacing(.tight))
                            Text("\(policies.count)")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            } header: {
                SectionHeading(text: "Check")
            } footer: {
                Text("Asks the bench for its health — the one thing it answers without running "
                   + "any physics, so this works before anything else is set. It says which of "
                   + "the several very different reasons an address can fail it hit: nothing "
                   + "listening, something else on the port, a token wanted, an address this app "
                   + "will not dial, or connected.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            if !bench.isTailnet, !bench.address.isEmpty {
                Section {
                    // IN `warning`, WHICH IS WHAT THIS IS. The address works
                    // now and will stop working somewhere else, and the failure
                    // looks exactly like the bench going down — which is the
                    // definition of a thing worth colouring before it happens
                    // rather than explaining afterwards.
                    Text(BenchSetup.lanWarning)
                        .font(.caption).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            if let refusal {
                Section {
                    Text(refusal).font(.footnote).foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(bench.name.isEmpty ? "New bench" : bench.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // WARMED BEFORE THE FIRST ANSWER, NOT AT IT. The taptic engine
            // spins up on demand and the first tap of a session lands after the
            // thing it is about — which teaches the person that the buzz and
            // the bench are unrelated, and that is not a lesson a later
            // `prepare()` undoes.
            Haptic.prepare()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
    }

    /// The verdict as a word and a dot.
    ///
    /// COARSER THAN THE DIAGNOSIS, AND DELIBERATELY SO. `BenchSetup.Diagnosis`
    /// separates eight outcomes because eight of them have different remedies,
    /// and the badge collapses them to two because at a glance there are only
    /// two questions: can I use this bench, and if not, do I read on. The
    /// sentence directly under the badge is what says whether nothing was
    /// listening, whether something else holds the port, or whether the bench
    /// answered and wants its token — so nothing is lost by the badge being
    /// blunt, and a person who cannot separate a teal dot from a grey one gets
    /// the answer in a word rather than in a hue.
    ///
    /// `idle` FOR A BENCH THAT ANSWERED, WHICH IS THE HONEST STATE. It means
    /// "powered, and standing still", and that is exactly what a bench is after
    /// `/health` — the one call it serves without running any physics. It is
    /// also the teal, which is this app's colour for something a machine said.
    private func standing(_ diagnosis: BenchSetup.Diagnosis)
        -> (text: String, state: RobotState) {
        diagnosis.isConnected ? ("Connected", .idle) : ("Unreachable", .offline)
    }

    private func save() {
        do {
            try bench.validate()
            store.save(bench)
            dismiss()
        } catch let error as BenchEndpoint.Refusal {
            refusal = error.message
        } catch {
            refusal = error.localizedDescription
        }
    }

    @MainActor private func check() async {
        busy = true; refusal = nil; diagnosis = nil; policies = []
        defer { busy = false }
        bench.address = BenchSetup.tidy(bench.address)

        var status: Int?
        var body: Data?
        var failed = false
        // ONLY DIAL WHAT THE PARSER ACCEPTS. Building a request out of
        // something `DuckBench.address` would refuse is how an app that says it
        // never contacts a public host contacts one.
        if let address = try? bench.resolved() {
            do {
                let token = bench.token?.isEmpty == false ? bench.token : nil
                let request = DuckBench.urlRequest(for: DuckBench.health(address), token: token)
                let (data, response) = try await URLSession.shared.data(for: request)
                status = (response as? HTTPURLResponse)?.statusCode
                body = data
                if let health = try? DuckBench.readHealth(data) { policies = health.policies }
            } catch {
                failed = true
            }
        }
        diagnosis = BenchSetup.diagnose(address: bench.address, status: status,
                                        body: body, transportFailed: failed)
        // THE TAP IS FOR THE ANSWER, NOT FOR THE PRESS. A bench coming back is
        // an event across the room — the same event `Haptic.connected` exists
        // for on the Drive screen — and it arrives seconds after the finger has
        // left the button, which is precisely when a person is no longer
        // looking at the phone.
        if diagnosis?.isConnected == true { Haptic.connected() }
    }
}
