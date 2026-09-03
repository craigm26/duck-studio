import SwiftUI
import DuckKit
import StudioKit

/// The two doors from the picture onto Studio: the room the duck is standing
/// in, and the motions somebody has written.
///
/// CHIPS AND NOT A MENU, for the reason `PadChrome`'s row is chips: they sit in
/// the top strip beside the record and talk chips, they are one tap, and each
/// one says what it opens rather than hiding behind a glyph. The scene chip
/// carries a second line — what is standing right now — because "set the
/// scene" and "which scene is set" are the same question asked twice, and a
/// person opening this sheet has usually just asked the second one.
///
/// EVERY SENTENCE IS `ControlShelf`'s. This file decides pixels.
struct ControlShelfChips: View {

    /// The world standing on the bench, as it read back. Nil until a bench has
    /// answered, which is exactly when the chip says the bench's own world.
    let standing: String?
    /// Whether a pose is being built right now, so the chip reads as a state
    /// rather than as a thing that has not happened.
    let posing: Bool
    let openScene: () -> Void
    let openMotions: () -> Void
    let pose: () -> Void

    var body: some View {
        HStack(spacing: Theme.spacing(.tight)) {
            chip(ControlShelf.sceneChip, detail: ControlShelf.standingSaid(standing),
                 glyph: "square.stack.3d.up", act: openScene)
            chip(ControlShelf.motionsChip, detail: nil,
                 glyph: "figure.walk.motion", act: openMotions)
            chip(ControlShelf.poseChip, detail: posing ? ControlShelf.posingNow : nil,
                 glyph: "hand.draw", act: pose)
        }
    }

    /// `PadChrome`'s idiom, with room for a second line on the one chip that
    /// has something measured to say.
    private func chip(_ title: String, detail: String?, glyph: String,
                      act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: Theme.spacing(.hairline)) {
                Image(systemName: glyph)
                    .font(.footnote)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.footnote.weight(.regular))
                        .foregroundStyle(Theme.textSecondary)
                    if let detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.spacing(.snug))
            .frame(minWidth: DesignMetric.minimumTarget, minHeight: DesignMetric.minimumTarget)
            .overlay(Capsule().strokeBorder(Theme.separator,
                                            lineWidth: DesignMetric.hairlineStroke))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(detail ?? ""))
    }
}

/// Every scene this phone holds, laid on the bench being driven.
///
/// IT DRAWS ROWS THE WORLD PICKER ALREADY DECIDED. The picker under the
/// controls is a `Picker` of the same entries, and this is the same list with
/// the same action behind it — one tap from the picture instead of one tap,
/// one drawer and a scroll. Nothing about which worlds exist is decided here.
struct ControlSceneSheet: View {

    let entries: [ControlSceneRow]
    let standing: String?
    let choose: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(entries) { row in
                        Button {
                            choose(row.slot)
                            dismiss()
                        } label: {
                            HStack {
                                Text(row.label)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer(minLength: Theme.spacing(.tight))
                                if row.isStanding {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.measured)
                                }
                            }
                            .frame(minHeight: DesignMetric.minimumTarget)
                        }
                    }
                } header: {
                    SectionHeading(text: ControlShelf.sceneChip)
                } footer: {
                    Text(ControlShelf.sceneSheetSaid)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
            .navigationTitle(ControlShelf.standingSaid(standing))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// One row of the scene sheet. A slot rather than a value, because the world
/// picker's entries are the app's own enumeration and this view holds none of
/// that knowledge.
struct ControlSceneRow: Identifiable {
    let slot: Int
    let label: String
    let isStanding: Bool
    var id: Int { slot }
}

/// Every motion in Studio, runnable on the bench being driven.
struct ControlMotionsSheet: View {

    let motions: [ControlMotionRow]
    let running: String?
    let outcome: String?
    let run: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if motions.isEmpty {
                    Section {
                        Text(ControlShelf.noMotionsYet)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                } else {
                    Section {
                        ForEach(motions) { motion in
                            row(motion)
                        }
                    } header: {
                        SectionHeading(text: ControlShelf.motionsChip)
                    } footer: {
                        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                            Text(ControlShelf.motionSheetSaid)
                            Text(ControlShelf.runsInItsOwnRoom)
                            Text(ControlShelf.runningStopsTheDrive)
                            Text(ControlShelf.alsoOnAButton)
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }
                if let outcome {
                    Section {
                        Text(outcome)
                            .font(.footnote)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    } header: {
                        SectionHeading(text: ControlShelf.whatHappened)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
            .navigationTitle(ControlShelf.motionsChip)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ motion: ControlMotionRow) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Text(motion.name)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
            Text(motion.room)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if running == motion.id.uuidString {
                Text(ControlShelf.running(motion.name))
                    .font(.caption)
                    .foregroundStyle(Theme.measured)
            }
            Button {
                run(motion.id)
            } label: {
                Text(ControlShelf.runItHere).frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .disabled(running != nil)
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }
}

/// One row of the motions sheet: the motion's name and the room it will lay.
struct ControlMotionRow: Identifiable {
    let id: UUID
    let name: String
    let room: String
}
