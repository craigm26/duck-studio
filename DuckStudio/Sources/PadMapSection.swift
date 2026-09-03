import SwiftUI
import StudioKit
import DuckEvidence

/// The list rows that replaced the policy picker.
///
/// WHERE A GATE WAS, A MAP IS. The block this stands in for was a
/// `Picker("Policy")` plus a footnote saying Drive was waiting for a pick,
/// because `/health` lists what a bench HOLDS and never says what it has
/// LOADED. That refusal was honest and it was the wrong shape: the sticks are
/// always mapped — to a ROLE by default, resolved per bench — so Drive works on
/// a fresh install with nothing touched, and what is actually on the servos is
/// printed from the bench's own reply rather than guessed at here.
///
/// THE STICKS ARE NEVER A BLOCKED SURFACE, WHICH IS THE ONE RULE THIS VIEW
/// KEEPS. On a bench holding somebody's own networks the Walk slot is empty:
/// the map resolves to nothing, NOTHING IS POSTED, Drive still works, and
/// `DuckQuickActions.notHeldHere(.walk)` sits under the row with a menu of what
/// the bench does hold. A named refusal beside a control that still does
/// something, which is this app's whole shape.
///
/// IT IS ROWS AND NOT A `Section`, because it is inserted inside the one the
/// bench picker already lives in — the enclosing footer is where
/// `DuckDrive.hotSwapWorksBecause` already is, and a second copy here would be
/// the same sentence twice on one screen.
///
/// EVERY SENTENCE IS THE KIT'S. Nothing on this surface is composed here.
struct PadMapSection: View {

    @ObservedObject var desk: PadDesk
    let policies: [String]
    /// Post `/policy` for a network somebody picked ON PURPOSE. This always
    /// posts: the "already loaded" guard lives in `DuckPadMap.toPost`, which is
    /// consulted only for the automatic locomotion load, so a deliberate pick
    /// is never silently swallowed.
    let swap: (String) -> Void
    /// Start a sequence, engaging the loop if it is not already running.
    let play: (UUID) -> Void
    /// Filing a take as a Motion needs a bench to re-run it on, the arming
    /// token to reach it, and the SHARED library so a kept Motion appears in
    /// Behaviours without a relaunch — the same three the chrome route gets.
    /// Without them the list's button refused with the address prompt for a
    /// bench picked two rows above it.
    var bench: BenchEndpoint? = nil
    var token: String? = nil
    var library: LibraryModel? = nil

    /// `PadSheet` rather than a bare `DuckPad.Control`, because `.sheet(item:)`
    /// wants `Identifiable` and a control is `padd`'s enum — not this track's
    /// to add a conformance to.
    @State private var editing: PadSheet?
    @State private var showingButtons = false

    var body: some View {
        sticksRow
            // THE SHEET HANGS OFF A ROW THAT IS ALWAYS THERE. A presentation
            // attached to a row that can disappear is a presentation that
            // dismisses itself when the list changes underneath it.
            .sheet(item: $editing) { which in
                if case .map(let control) = which, let control {
                    PadBindSheet(desk: desk, control: control, policies: policies)
                }
            }

        if let refusal = desk.map.locomotionRefusal(among: policies) {
            Label(refusal, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Theme.warning)
            pickANetwork
        }

        Text(DuckPadMap.sticksAreAlwaysMapped)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)

        DisclosureGroup(isExpanded: $showingButtons) {
            ForEach(DuckPadMap.remappable, id: \.rawValue) { control in
                buttonRow(control)
            }
            Button(DuckPadMap.putThePadBack) { desk.putThePadBack() }
                .accessibilityHint(Text(DuckPadMap.putThePadBackDetail))
        } label: {
            Label("The buttons", systemImage: "gamecontroller")
        }

        NavigationLink {
            SequenceListView(desk: desk, play: play, bench: bench, token: token,
                             library: library)
        } label: {
            Label("Sequences", systemImage: "list.bullet.rectangle")
        }

        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            Text(DuckPadMap.modeIsAnAssumption)
            Text(DuckPadMap.mapLivesOnThisPhone)
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
    }

    // MARK: - the sticks

    private var sticksRow: some View {
        Picker(DuckPadMap.sticksRowTitle, selection: locomotion) {
            Text(DuckPadMap.steerBySlot).tag(DuckPadMap.Locomotion.slot(.walk))
            ForEach(policies, id: \.self) { name in
                Text(name).tag(DuckPadMap.Locomotion.named(name))
            }
            Text(DuckPadMap.steerByWhateverIsLoaded)
                .tag(DuckPadMap.Locomotion.whateverIsLoaded)
        }
    }

    /// The picker's binding. Picking a network BY NAME posts it, because that
    /// is a person deciding what should be on the servos right now; picking a
    /// role or "whatever is loaded" posts nothing, because neither names a file
    /// this bench is definitely holding this second.
    private var locomotion: Binding<DuckPadMap.Locomotion> {
        Binding(get: { desk.map.locomotion },
                set: { now in
                    desk.steer(now)
                    if case .named(let name) = now { swap(name) }
                })
    }

    /// What this bench actually holds, put where somebody whose Walk slot is
    /// empty is already looking.
    @ViewBuilder private var pickANetwork: some View {
        Menu {
            ForEach(policies, id: \.self) { name in
                Button(name) {
                    desk.steer(.named(name))
                    swap(name)
                }
            }
        } label: {
            Label(DuckPadMap.pickANetwork, systemImage: "square.stack.3d.up")
        }
        .disabled(policies.isEmpty)
    }

    // MARK: - the fourteen rows

    private func buttonRow(_ control: DuckPad.Control) -> some View {
        let shown = desk.map.shown(for: control, naming: desk.name(ofSequence:),
                                   namingMotion: desk.name(ofMotion:))
        return Button {
            editing = .map(control)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.snug)) {
                Text(control.face)
                    .font(.headline)
                    .frame(minWidth: DesignMetric.minimumTarget, alignment: .leading)
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    HStack(spacing: Theme.spacing(.hairline)) {
                        Text(shown.caption)
                            .font(.body)
                            .foregroundStyle(shown.isLive ? Theme.textPrimary
                                                          : Theme.textSecondary)
                        // THE PERSON'S OWN CHOICE IS MARKED WITH A GLYPH AND
                        // NOT A COLOUR. A dot in the action tint alone is a
                        // hint; the pencil is the information.
                        if shown.isCustom {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundStyle(Theme.measured)
                        }
                    }
                    Text(shown.detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(minHeight: DesignMetric.minimumTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(control.face), \(shown.caption)"))
        .accessibilityHint(Text(shown.detail))
    }
}
