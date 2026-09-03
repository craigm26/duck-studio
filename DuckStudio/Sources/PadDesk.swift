import SwiftUI
import StudioKit
import DuckEvidence

/// The one object `DriveView` holds for the whole pad-map track.
///
/// ONE `@StateObject` LINE, WHICH IS THE WHOLE POINT OF THE TYPE. The seam into
/// `DriveView` is a single stored property replacing a single deleted one
/// (`chosen`), and everything this track adds hangs off it: the map, the pilot,
/// the sequences, the two stores, and the last thing the bench said it loaded.
/// Three separate `@StateObject`s would have been three seams into a file this
/// track does not own.
///
/// ITS METHODS ARE DISPATCH AND LOOKUP. THERE IS NO ARITHMETIC HERE. Every
/// clamp, stamp, offset, coalesce and cursor lives in `PadPilot`,
/// `DuckSequenceRecording`, `DuckSequenceRun` and `DuckPadMap` — kit structs,
/// tested on Linux — and the API shapes make it structurally hard to add one:
/// `sample` and `advance` both take an ABSOLUTE clock, so no caller here
/// subtracts anything. `scripts/check_no_studio_math.sh` is the gate; this
/// comment is the reason it passes.
///
/// IT KNOWS WHAT THE BENCH HOLDS BECAUSE THE LOOP CANNOT PASS IT EVERY TRIP.
/// `step(steering:simSeconds:policySaid:)` is called once per round trip from
/// inside `drive()`, and the map's answer to "what should be on the servos"
/// depends on `/health`'s policy list and on the bench store's record of the
/// last load. Both are handed in by `settle(against:lastLoaded:)` when the tab
/// connects and by `noteLoaded(_:)` when a swap lands, so the loop's own call
/// stays three arguments long.
@MainActor
final class PadDesk: ObservableObject {

    /// SEEDED WITH THE SHIPPED MAP AND REPLACED IN `init`, rather than left
    /// without a value: a stored property with no default cannot be assigned
    /// from another stored property, and reading `maps.map` before `map` exists
    /// is `self` used before initialisation.
    @Published var map: DuckPadMap = .defaults(in: .walk)
    @Published var pilot = PadPilot()
    @Published private(set) var sequences: [DuckSequence] = []

    private let maps = PadMapStore()
    private let store = SequenceStore()

    /// What `/health` last listed, and what the bench store says was last put
    /// on the servos. Held rather than passed per trip — see the preamble.
    private(set) var policies: [String] = []
    private(set) var lastLoaded: String?

    init() {
        map = maps.map
        sequences = store.sequences
    }

    // MARK: - the loop's one call

    /// ONE CALL PER ROUND TRIP, BEFORE THE NOTIFY, straight into the kit.
    ///
    /// `simSeconds` is `live?.t` — the bench's clock BEFORE this twist is
    /// applied — which is exactly what `DuckBench.Step.at` means. `policySaid`
    /// is `live?.policy`, the bench's own word for what is on the servos, which
    /// is the only thing in this app that measures it.
    func step(steering: DuckDrive.Twist, simSeconds: Double?,
              policySaid: String?) -> PadPilot.Go {
        pilot.step(steering: steering, simSeconds: simSeconds, policySaid: policySaid,
                   wanting: map.toPost(among: policies, lastLoaded: lastLoaded),
                   now: Date())
    }

    // MARK: - what the bench turned out to be

    /// Learn what this bench holds, and degrade anything it cannot honour.
    /// POSTS NOTHING. Returns the one sentence to show, when there is one.
    func settle(against policies: [String], lastLoaded: String?) -> String? {
        self.policies = policies
        self.lastLoaded = lastLoaded
        let said = map.settle(against: policies)
        guard !said.isEmpty else { return nil }
        maps.save(map)
        return said.joined(separator: " ")
    }

    /// A swap landed. The map's automatic locomotion load is guarded against
    /// this, so the tab cannot undo a quick action launched from the front door.
    func noteLoaded(_ policy: String) {
        lastLoaded = policy
    }

    // MARK: - sequences

    func name(ofSequence id: UUID) -> String? {
        sequences.first { $0.id == id }?.name
    }

    /// Start a bound sequence. Returns the line to print.
    ///
    /// A DEAD ID GETS A SENTENCE AND NOT A CRASH. The map degrades a binding
    /// whose sequence has been deleted on the way out of `effect(for:naming:)`,
    /// and this is the second door — a press that arrived through the one-argument
    /// `effect(for:)` still lands here, and here still knows.
    /// `@discardableResult` BECAUSE ONE OF THE TWO CALL SITES DOES NOT WANT
    /// THE LINE. A press through the pad prints it as `lastAction`; the map
    /// section's Play button starts the loop and leaves the readout alone, and
    /// an unused-result warning there would be noise rather than information.
    @discardableResult
    func play(_ id: UUID, thenLoading slot: DuckOfficialPolicies.Slot?,
              among policies: [String], face: String) -> String {
        self.policies = policies
        guard let sequence = sequences.first(where: { $0.id == id }) else {
            return DuckPadMap.sequenceIsGone(face: face)
        }
        pilot.play(sequence, thenLoading: slot)
        return DuckPadMap.pressedToPlay(face: face, named: sequence.name)
    }

    func beginTake(venue: DriveVenue) {
        pilot.startRecording(venue: venue, at: Date())
    }

    /// Name what was driven and keep it. Throws the kit's own refusal.
    @discardableResult
    func keep(named: String) throws -> DuckSequence {
        guard let pending = pilot.pending, let ending = pilot.pendingEnding else {
            throw DuckSequence.Refusal.empty
        }
        let sequence = try pending.finish(named: named, endedBy: ending,
                                          at: pilot.pendingEndedAt ?? Date())
        store.save(sequence)
        sequences = store.sequences
        pilot.discardPending()
        return sequence
    }

    /// Keep a sequence that was written rather than driven.
    func add(_ sequence: DuckSequence) {
        store.save(sequence)
        sequences = store.sequences
    }

    func delete(_ sequence: DuckSequence) {
        store.delete(sequence)
        sequences = store.sequences
        // A BUTTON BOUND TO IT IS NOT SILENTLY UNBOUND. The map keeps the id
        // and `effect(for:naming:)` turns it into a named not-yet, so pressing
        // that button says what happened rather than doing nothing.
    }

    func rename(_ sequence: DuckSequence, to name: String) {
        store.rename(sequence, to: name)
        sequences = store.sequences
    }

    /// The name a fresh take is offered, from the bench's own word for what was
    /// driving and the two numbers it measured.
    func suggestedName(for take: DuckSequenceRecording) -> String {
        DuckSequence.suggestedName(
            policy: take.steps.compactMap(\.policySaid).first,
            simSeconds: take.simSeconds, steps: take.steps.count,
            at: pilot.pendingEndedAt ?? Date())
    }

    // MARK: - editing the map

    func bind(_ effect: DuckPadMap.Effect, to control: DuckPad.Control) {
        map.bind(effect, to: control)
        maps.save(map)
    }

    func clear(_ control: DuckPad.Control) {
        map.clear(control)
        maps.save(map)
    }

    func steer(_ locomotion: DuckPadMap.Locomotion) {
        map.steer(locomotion)
        maps.save(map)
    }

    func putThePadBack() {
        maps.putThePadBack()
        map = maps.map
    }
}
