import SwiftUI
import StudioKit
import DuckEvidence

/// What one button does, and every other thing it could do.
///
/// THE SLOTS ARRIVE ALREADY CARRYING THEIR REFUSAL. Each of the seven rows is a
/// `DuckQuickActions.action(filling:…)`, so a slot this bench does not fill
/// says so BEFORE somebody picks it rather than after they press the button —
/// which is the difference between "there is no roulade network here" and "that
/// button is broken". The row is still selectable: a map is a thing a person
/// keeps across benches, and refusing to let them bind a role their next bench
/// will fill would make the map less portable than the thing it describes.
///
/// **Play a motion** IS BINDABLE AND PRINTS ITS REASON. That is the shipped
/// `DuckPad.unsupported` idiom, not a new one: the row exists, it takes the
/// binding, and pressing that button on the pad prints
/// `DuckPadMap.motionOnAButtonIsNotYet` — which names `/perform`, the rollouts
/// and the minutes, so the not-yet is a job somebody could do rather than a
/// shrug. A greyed-out row would have told nobody anything.
///
/// NOTHING HERE POSTS ANYTHING. Binding is an edit to a file on this phone.
struct PadBindSheet: View {

    @ObservedObject var desk: PadDesk
    let control: DuckPad.Control
    let policies: [String]

    @Environment(\.dismiss) private var dismiss

    private var shown: DuckPadMap.Shown {
        desk.map.shown(for: control, naming: desk.name(ofSequence:))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(shown.caption).font(.headline)
                    Text(shown.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                } header: {
                    SectionHeading(text: "What \(control.face) does now")
                }

                Section {
                    ForEach(DuckOfficialPolicies.Slot.allCases, id: \.rawValue) { slot in
                        slotRow(slot)
                    }
                } header: {
                    SectionHeading(text: "Load a network")
                }

                Section {
                    if desk.sequences.isEmpty {
                        Text(DuckSequence.whatThisIs)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    // ONE ROW PER SEQUENCE, AND ITS MENU CARRIES THE CHAIN.
                    // Two `ForEach`es over one list — one to play, one to
                    // chain — would put the same identity in a list twice.
                    ForEach(desk.sequences) { sequence in
                        sequenceRow(sequence)
                    }
                } header: {
                    SectionHeading(text: "Play a sequence")
                }

                Section {
                    Button { bind(.stop) } label: {
                        row("Stop", second: "Zeroes the command and lets the duck settle.")
                    }
                    .buttonStyle(.plain)
                    Button { bind(.reset) } label: {
                        row("Reset", second: "Puts the duck back on its feet.")
                    }
                    .buttonStyle(.plain)
                    // BINDABLE, AND IT PRINTS ITS REASON WHEN PRESSED.
                    Button { bind(.notYet(DuckPadMap.motionOnAButtonIsNotYet)) } label: {
                        row("Play a motion", second: DuckPadMap.motionOnAButtonIsNotYet)
                    }
                    .buttonStyle(.plain)
                    Button {
                        desk.clear(control)
                        dismiss()
                    } label: {
                        row("Leave as the pad has it",
                            second: DuckPadMap.putThePadBackDetail)
                    }
                    .buttonStyle(.plain)
                } header: {
                    SectionHeading(text: "The bench's own controls")
                } footer: {
                    Text(footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            .navigationTitle(control.face)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// `onTheRobot` SURVIVES EVERY REMAP, and the sentence saying so is the
    /// kit's — it is a claim about what a robot does, not a label.
    private var footnote: String {
        DuckPadMap.onTheRobotSurvivesARemap(shown.onTheRobot)
    }

    // MARK: - rows

    private func slotRow(_ slot: DuckOfficialPolicies.Slot) -> some View {
        let action = DuckQuickActions.action(filling: slot, among: policies,
                                             reach: DuckMethod.reach(for: .bench),
                                             transport: .bench)
        return Button {
            bind(.loadSlot(slot))
        } label: {
            row(slot.title, second: action.reason ?? (action.policyFilename ?? slot.rawValue),
                warning: action.reason != nil)
        }
        .buttonStyle(.plain)
    }

    /// A sequence on its own, or a sequence then a slot — the brief's "chain",
    /// which the map carries as one case rather than two.
    private func sequenceRow(_ sequence: DuckSequence) -> some View {
        Menu {
            Button(DuckPadMap.playIt) {
                bind(.play(sequence: sequence.id, thenLoading: nil))
            }
            ForEach(DuckOfficialPolicies.Slot.allCases, id: \.rawValue) { slot in
                Button(DuckPadMap.playThenLoad(slot)) {
                    bind(.play(sequence: sequence.id, thenLoading: slot))
                }
            }
        } label: {
            row(sequence.name, second: sequence.summary)
        }
    }

    private func row(_ title: String, second: String, warning: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.tight)) {
            if warning {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(title).font(.body).foregroundStyle(Theme.textPrimary)
                Text(second)
                    .font(.caption)
                    .foregroundStyle(warning ? Theme.warning : Theme.textSecondary)
            }
        }
        .frame(minHeight: DesignMetric.minimumTarget)
        .contentShape(Rectangle())
    }

    private func bind(_ effect: DuckPadMap.Effect) {
        desk.bind(effect, to: control)
        dismiss()
    }
}
