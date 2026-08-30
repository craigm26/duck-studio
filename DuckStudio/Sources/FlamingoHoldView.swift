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
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(hold.survived)").font(.largeTitle.weight(.semibold))
                        Text("shoves survived").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("standing on the \(hold.side.standingFoot)")
                            .font(.footnote.weight(.medium))
                        Text("\(hold.side.liftedLeg) leg up")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(message).font(.footnote)
                    .foregroundStyle(hold.over ? Color.orange : .secondary)
            }

            if !hold.over {
                Section {
                    if let incoming {
                        Label("Shove from \(label(incoming.direction)) — "
                              + String(format: "%.2f m/s", incoming.speed),
                              systemImage: "wind")
                            .font(.subheadline).foregroundStyle(.orange)
                    }
                    HStack(spacing: 8) {
                        ForEach(FlamingoHold.Direction.allCases, id: \.self) { direction in
                            Button(label(direction)) { brace(against: direction) }
                                .buttonStyle(.bordered).controlSize(.small)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Button("Switch feet") {
                        hold.switchSide()
                        play()
                    }
                    .disabled(incoming != nil)
                } header: {
                    Text("Lean")
                } footer: {
                    Text("It holds anything up to 0.15 m/s. Harder toward the lifted leg and it touches down and re-lifts; toward the standing foot it steps down and you are finished. Backward at 0.18 it goes over — that is the one the author says it cannot take.")
                }
            } else {
                Section {
                    Button("Stand up and try again") { restart() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Flamingo hold")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { play() }
        .onReceive(tick) { _ in advance() }
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
