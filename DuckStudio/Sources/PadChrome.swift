import SwiftUI
import StudioKit
import DuckEvidence

/// The two chips and the pilot line, floating over the live picture.
///
/// COLLAPSED, ONE ROW, AND NEVER ACROSS THE MIDDLE OF THE STAGE. Build 41
/// shipped a legend that covered the duck on the one screen that moves a robot,
/// and the rule this app took from it is that anything drawn over a live
/// picture ships collapsed and stays out of the way. This is a single row of
/// capsules on a translucent `Theme.surfacePrimary` ground at
/// `StageViewport.Chrome.backing` — a 44-point target plus four points of
/// padding either side, so 52 at the default text size — with the `layerChip`
/// idiom's capsule, hairline and `DesignMetric.minimumTarget` floor. Everything
/// it opens is a sheet OVER the stage rather than a panel pushed onto it.
///
/// THE LONG SENTENCE IS NOT DRAWN ON THE PICTURE. `PadPilot.recordStartsDriving`
/// is three lines of prose; over a live stage it is the legend that covered the
/// duck. It is the Record chip's accessibility hint, and it is what
/// `lastAction` says the first time Record is pressed — which is DriveView's
/// own readout line, off the stage, where the rest of the pad's sentences
/// already land.
///
/// ONE TAP IS ONE TAP. Record starts the drive loop as well when it is not
/// already running, because a chip that quietly does nothing until you also
/// press Drive is a chip that looks broken.
///
/// THE COUNTERS ARE MEASURED, NOT ESTIMATED. `PadPilot.line` reads the take's
/// own step count and the bench's own sim clock; nothing here counts anything.
///
/// THE CHIPS ARE ABSENT ON THE ROBOT VENUE RATHER THAN DRAWN DEAD. There is no
/// link that carries driving, so there is nothing to record and nothing to
/// replay; `DriveVenue.robotIsNotDrivenYet` is the sentence and it is already
/// on that screen, in front of where a stick would be.
struct PadChrome: View {

    @ObservedObject var desk: PadDesk
    let venue: DriveVenue
    let bench: BenchEndpoint?
    let token: String?
    @Binding var lastAction: String?
    /// Start the drive loop if it is not already running.
    let engage: () -> Void

    /// The Motions library and the model list the rest of the app shows.
    ///
    /// OPTIONAL, AND THAT IS A SEAM RATHER THAN A PREFERENCE. `DriveView` holds
    /// both; the merge seam that constructs this view passes neither, so they
    /// default to nil and this owns a fallback. `DriveView.ownModels` makes the
    /// identical trade for the identical reason and states the cost: two
    /// instances of one `UserDefaults`-backed store means an endpoint added
    /// through one is invisible to the other until the next launch. Passing the
    /// real ones is a two-argument change at the call site.
    var library: LibraryModel?
    var models: EndpointStore?

    @StateObject private var ownModels = EndpointStore()
    private var modelList: EndpointStore { models ?? ownModels }

    @State private var sheet: PadSheet?

    var body: some View {
        Group {
            if venue != .real {
                HStack(spacing: Theme.spacing(.tight)) {
                    recordChip
                    chip(PadPilot.sayItChip, glyph: "text.bubble", on: false) {
                        sheet = .talk
                    }
                    chip("Sequences", glyph: "list.bullet.rectangle", on: false) {
                        sheet = .sequences
                    }
                    if let line = desk.pilot.line {
                        Text(line)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.measured)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.horizontal, Theme.spacing(.tight))
                .padding(.vertical, Theme.spacing(.hairline))
                .background(Theme.surfacePrimary.opacity(StageViewport.Chrome.backing),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.separator,
                                                lineWidth: DesignMetric.hairlineStroke))
            }
        }
        .onChange(of: desk.pilot.pending) { _, take in
            // THE TAKE IS OFFERED, NEVER AUTO-SAVED. A ceiling that closed the
            // take, a Stop, a Pause and the chip itself all land here.
            // Observing the take and not `!= nil` is what makes the SECOND
            // offer arrive: a dismissed sheet leaves `pending` set, and a Bool
            // that is already true has no edge.
            if take != nil { sheet = .keep }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .keep:
                SequenceKeepSheet(desk: desk, bench: bench, token: token,
                                  engage: engage, library: library)
            case .talk:
                TalkToTheDuckView(desk: desk, venue: venue, engage: engage,
                                  models: modelList)
            case .sequences:
                NavigationStack {
                    SequenceListView(desk: desk, play: { play($0) },
                                     bench: bench, token: token, library: library)
                }
            case .map:
                // The map is edited from the list under the stage, not from the
                // chrome: a fourteen-row editor does not belong on a picture.
                EmptyView()
            }
        }
    }

    // MARK: - the chips

    private var recordChip: some View {
        let recording = desk.pilot.isRecording
        // A HELD TAKE HAS A DOOR BACK. A sheet closed without Keep or Discard
        // leaves the take pending; the chip then reads "Name it" and opens the
        // sheet again, and a new take cannot start over an unresolved one —
        // which was the only path that could have overwritten it.
        let held = !recording && desk.pilot.pending != nil
        return chip(recording || held ? PadPilot.nameItChip : PadPilot.recordChip,
                    glyph: recording ? "stop.circle.fill"
                                     : (held ? "square.and.pencil" : "record.circle"),
                    on: recording || held,
                    hint: PadPilot.recordStartsDriving) {
            if recording {
                desk.pilot.cutOff(.tapped)
            } else if held {
                sheet = .keep
            } else {
                desk.beginTake(venue: venue)
                lastAction = PadPilot.recordStartsDriving
                engage()
            }
        }
    }

    /// `layerChip`'s idiom: a capsule, a hairline, the app's one minimum target
    /// taken in both directions, and the word's weight as a third signal so a
    /// state is readable without comparing colours.
    private func chip(_ title: String, glyph: String, on: Bool, hint: String? = nil,
                      act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Label(title, systemImage: glyph)
                .font(.footnote.weight(on ? .semibold : .regular))
                .lineLimit(1)
                // THREE CHIPS FILL A 393-POINT STRIP AT THE DEFAULT SIZE with
                // ten points to spare; at a larger text size the words shrink
                // a little before the row would clip them.
                .minimumScaleFactor(0.8)
                .foregroundStyle(on ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.spacing(.snug))
                .frame(minWidth: DesignMetric.minimumTarget,
                       minHeight: DesignMetric.minimumTarget)
                .background { if on { Capsule().fill(Theme.surfaceInteractive) } }
                .overlay(Capsule().strokeBorder(Theme.separator,
                                                lineWidth: DesignMetric.hairlineStroke))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(on ? "on" : "off"))
        .accessibilityHint(Text(hint ?? ""))
    }

    /// Start a sequence from the list, and engage the loop if it is not
    /// already running. `face` is empty here because no button was pressed —
    /// the kit's sentence handles that rather than a view composing a second
    /// one.
    private func play(_ id: UUID) {
        lastAction = desk.play(id, thenLoading: nil, among: desk.policies, face: "")
        if desk.pilot.isPlaying { engage() }
        sheet = nil
    }
}
