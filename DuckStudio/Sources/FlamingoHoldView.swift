import SwiftUI
import DuckKit
import StudioKit

/// Flamingo hold: keep it on one foot while the world shoves it.
///
/// EVERY LIMIT ON THIS SCREEN IS THE POLICY AUTHOR'S. `flamingo-cycle` states
/// in its own manifest what it survives — 0.15 m/s from any direction, a
/// touch-down toward the lifted side, a step-down toward the standing one, and
/// a fall backward at 0.18 — and the game is those four sentences. The only
/// invented rule is that bracing halves a push, which the source says plainly,
/// because the policy has no brace input to measure.
///
/// THE COUNT AND THE FOOT ARE THE TWO THINGS THAT CHANGE, so they are
/// `TelemetryRow`s: a label that stays still beside a value that does not, in
/// tabular figures, stacked rather than truncated when the type is enlarged. A
/// large title beside a right-aligned caption was two columns fighting for one
/// width, and at AX5 the foot — which is the thing you have to know to brace —
/// was the column that lost.
struct FlamingoHoldView: View {
    @ObservedObject var model: GhostDuckModel

    @State private var hold = FlamingoHold()
    @State private var incoming: FlamingoHold.Push?
    @State private var braceDeadline: Date?
    @State private var braced = false
    @State private var message = "Tap the side the shove comes from to lean into it."

    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                // THE STANCE IS A STATE AND STATES ARE WORDS HERE. Standing on
                // the right foot with the left leg up is what `FlamingoHold.Side`
                // says about itself — `standingFoot` and `liftedLeg` are the
                // kit's own words — and the badge puts one of them beside a mark
                // rather than leaving a mark to carry it alone.
                StateBadge(text: hold.over ? "Down" : "On one foot",
                           state: hold.over ? .idle : .active)
                TelemetryRow(label: "Shoves survived", value: "\(hold.survived)")
                TelemetryRow(label: "Standing foot", value: hold.side.standingFoot)
                TelemetryRow(label: "Lifted leg", value: hold.side.liftedLeg)
                // THE MESSAGE GOES ORANGE WHEN IT IS OVER, WHICH IS A COLOUR
                // DOING A SECOND JOB. The sentence already says what happened —
                // `describe(_:)` reads the kit's own result — so the token is
                // `warning` and not a raw `.orange`, and the badge above says
                // "Down" in a word for anybody who cannot see either.
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(hold.over ? Theme.warning : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            if !hold.over {
                Section {
                    if let incoming {
                        // A SHOVE ON ITS WAY IS A WARNING, and the wind symbol
                        // and the two words are what carry it — the colour is
                        // the third signal, not the only one.
                        Label("Shove from \(label(incoming.direction)) — "
                              + String(format: "%.2f m/s", incoming.speed),
                              systemImage: "wind")
                            .font(.subheadline)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // FOUR WAYS TO LEAN, AND EACH ONE LEANS THE DUCK — so they
                    // are the sixty-point variant, like everything else in this
                    // app that moves the machine. They wrap to two rows rather
                    // than shrinking below that: four action capsules across a
                    // phone at any text size above the default is four
                    // truncated words on the control you have one and a half
                    // seconds to press.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.spacing(.tight)) {
                            ForEach(FlamingoHold.Direction.allCases, id: \.self) { direction in
                                lean(direction)
                            }
                        }
                        VStack(spacing: Theme.spacing(.tight)) {
                            HStack(spacing: Theme.spacing(.tight)) {
                                lean(.forward); lean(.backward)
                            }
                            HStack(spacing: Theme.spacing(.tight)) {
                                lean(.towardLifted); lean(.towardStanding)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    // SWAPPING FEET IS A MOVE THE POLICY MAKES — about a second
                    // and a half of real motion, and the clip plays — so it is
                    // sized like every other control here that moves the duck.
                    Button {
                        hold.switchSide()
                        play()
                    } label: {
                        // THE WIDTH GOES ON THE LABEL, NOT ON THE BUTTON. The
                        // style draws its capsule around whatever the label
                        // measures, so a frame outside it centres a pill in an
                        // empty row instead of filling it — which is how
                        // `DriveView`'s transport bar stretches too.
                        Text("Switch feet").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryActionMoves)
                    .disabled(incoming != nil)
                    .accessibilityHint(Text("Puts the lifted leg down and lifts the other. Not while a shove is on its way."))
                } header: {
                    SectionHeading(text: "Lean")
                } footer: {
                    Text("It holds anything up to 0.15 m/s. Harder toward the lifted leg and it touches down and re-lifts; toward the standing foot it steps down and you are finished. Backward at 0.18 it goes over — that is the one the author says it cannot take.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)
            } else {
                Section {
                    // IT STANDS THE DUCK BACK UP, which is the clearest case in
                    // the app of a control that moves the machine.
                    Button { restart() } label: {
                        Text("Stand up and try again").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryActionMoves)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S
        // GREY, and every row keeps a real `surfacePrimary` card under its
        // words — the arrangement `Theme.backgroundSecondary` documents as the
        // only correct one, since the inks fall short of 4.5:1 on that ground
        // and clear it on a card.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Flamingo hold")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { play() }
        // WARMED BEFORE THE FIRST SHOVE, NOT AT IT. The taptic engine spins up
        // on demand and the first tap of a session arrives after the thing it
        // is about.
        .task { Haptic.prepare() }
        .onReceive(tick) { _ in advance() }
        // GOING OVER IS THE ROBOT FALLING, which is the one thing `Haptic.fell`
        // exists for — and it happens on a timer while the person is watching
        // the duck on the stage above this sheet, not the list. On the edge
        // only: `over` stays true until the hold is restarted.
        .onChange(of: hold.over) { _, over in
            if over { Haptic.fell() }
        }
    }

    /// One direction to lean in.
    ///
    /// THE WORD IS THE CONTROL. `label(_:)` gives the kit's four directions the
    /// short words a person can find in a second and a half — front, behind,
    /// lifted, standing — and the accessibility label spells out what pressing
    /// it means, because "lifted" alone is not a sentence anybody can act on
    /// when they are being read to.
    private func lean(_ direction: FlamingoHold.Direction) -> some View {
        Button { brace(against: direction) } label: {
            // The width goes on the label so the style's capsule fills its
            // share of the row rather than floating in the middle of it.
            Text(label(direction)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.primaryActionMoves)
        .accessibilityLabel(Text("Lean toward \(label(direction))"))
    }

    private func label(_ direction: FlamingoHold.Direction) -> String {
        switch direction {
        case .forward: return "front"
        case .backward: return "behind"
        case .towardLifted: return "lifted"
        case .towardStanding: return "standing"
        }
    }

    private func play() {
        let name = hold.side == .leftLifted ? "flamingo_left" : "flamingo_right"
        guard let clip = model.intents[name] else { return }
        model.trick = clip
        model.trickStarted = CACurrentMediaTime()
    }

    private func advance() {
        guard !hold.over, model.isPlaced else { return }
        if let deadline = braceDeadline, Date() >= deadline, let push = incoming {
            let result = hold.take(push, braced: braced, after: 1.0)
            message = describe(result)
            incoming = nil; braceDeadline = nil; braced = false
            if !hold.over { play() }
            return
        }
        guard incoming == nil, Int.random(in: 0..<18) == 0 else { return }
        // A spread that straddles every published threshold, so all four
        // outcomes are reachable and none is a surprise.
        incoming = FlamingoHold.Push(
            direction: FlamingoHold.Direction.allCases.randomElement()!,
            speed: Double.random(in: 0.08...0.34))
        braceDeadline = Date().addingTimeInterval(1.4)
        braced = false
    }

    private func brace(against direction: FlamingoHold.Direction) {
        guard let push = incoming else { return }
        braced = direction == push.direction
        message = braced ? "Leaning into it." : "Wrong way."
    }

    private func describe(_ result: FlamingoHold.Result) -> String {
        switch result {
        case .held: return "Held it."
        case .touchedDownAndRecovered: return "Touched down and picked the leg straight back up."
        case .steppedDown: return "Put the foot down — that ends the hold."
        case .fell: return "Over backwards. \(hold.summary)"
        }
    }

    private func restart() {
        hold = FlamingoHold()
        incoming = nil; braceDeadline = nil; braced = false
        message = "Tap the side the shove comes from to lean into it."
        play()
    }
}
