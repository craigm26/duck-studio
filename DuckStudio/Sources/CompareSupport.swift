import Foundation
import SwiftUI
import DuckKit
import StudioKit

/// Picks today, days with a pick, and the one door every Compare screen
/// writes a preference through.
///
/// THE RECORD GOES THROUGH `FeedbackStore`, the same log and the same sharing
/// choice the recorded walker pairs have always used, so Settings → Feedback
/// governs every pick the same way and nothing here invents a second consent.
@MainActor final class CompareStore: ObservableObject {
    @Published private(set) var today = 0
    @Published private(set) var streak = 0
    let feedback = FeedbackStore()

    private static let daysKey = "duckstudio.compareDays"
    private static let todayKey = "duckstudio.compareToday"

    init() { refresh() }

    private var days: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.daysKey) ?? [])
    }

    private func refresh() {
        let key = Compare.dayKey(Date())
        let stored = UserDefaults.standard.dictionary(forKey: Self.todayKey) as? [String: Int] ?? [:]
        today = stored[key] ?? 0
        streak = Compare.streak(days: days)
    }

    /// Count a pick (the walker pairs write their own record; they call this
    /// for the tally only).
    func counted() {
        let key = Compare.dayKey(Date())
        var d = days; d.insert(key)
        UserDefaults.standard.set(Array(d), forKey: Self.daysKey)
        UserDefaults.standard.set([key: today + 1], forKey: Self.todayKey)
        refresh()
    }

    /// Write one pick between `left` and `right` as the person saw them.
    func pick(left: Compare.Contender, right: Compare.Contender, chose: DuckFeedback.Choice,
              reasons: [DuckFeedback.Reason], context: String, command: [Double]?,
              tournament: String? = nil) {
        // The record's `a` is always the left one, with `order` saying so, so
        // the reader can see a side bias.
        if let record = try? DuckFeedback.preference(
            a: left, b: right, choice: chose, reasons: reasons, where: .phoneBench,
            order: .aLeft, context: context, command: command, tournament: tournament,
            share: feedback.share, client: FeedbackStore.client) {
            feedback.append([record])
        }
        counted()
        Haptic.finished()
    }
}

/// Everything on this phone that can be compared, by kind and by whose it is.
@MainActor enum ContenderCatalog {

    static func all(_ kind: Compare.Contender.Kind, library: LibraryModel,
                    drafts: DraftStore, sequences: SequenceStore) -> [Compare.Contender] {
        switch kind {
        case .behaviour:
            return library.library.entries.filter(\.isRunnable).map { entry in
                Compare.Contender(kind: .behaviour, name: entry.title,
                                  digest: prefixed(entry.identity.value),
                                  source: source(of: entry, library: library), key: entry.id)
            }
        case .motion:
            let bundled = ((try? DuckIntentClip.bundled()) ?? [:]).values
                .sorted { $0.name < $1.name }
                .map { Compare.Contender(kind: .motion, name: $0.name, digest: Compare.digest(of: $0),
                                         source: .pollen, key: "bundled:\($0.name)") }
            let kept = library.importedClips.map {
                Compare.Contender(kind: .motion, name: $0.name, digest: Compare.digest(of: $0),
                                  source: .device, key: "kept:\($0.name)")
            }
            return unique(bundled + kept)
        case .draft:
            return drafts.drafts.filter { !$0.keys.isEmpty }.map { draft in
                Compare.Contender(kind: .draft, name: draft.name,
                                  digest: Compare.digest(of: Data(trackText(draft).utf8)),
                                  source: .yours, key: draft.id.uuidString)
            }
        case .shooter:
            return []   // shooters are compared from Train a duck to shoot, not picked here
        case .sequence:
            return sequences.sequences.filter { $0.benchPolicy != nil }.map { seq in
                Compare.Contender(kind: .sequence, name: seq.name, digest: seq.compareDigest,
                                  source: .yours, key: seq.id.uuidString)
            }
        }
    }

    private static func prefixed(_ v: String) -> String {
        v.hasPrefix("sha256:") ? v : "sha256:\(v)"
    }

    private static func source(of entry: PolicyLibrary.Entry,
                               library: LibraryModel) -> Compare.Contender.Source {
        if case .released = library.standing(for: entry) { return .pollen }
        switch entry.origin {
        case .fetched(let host) where host.contains("huggingface"): return .community
        default: return .yours
        }
    }

    private static func trackText(_ draft: IntentDraft) -> String {
        draft.benchTrack.map { key in
            String(format: "%.3f:", key.at) + key.pose.map { String(format: "%.4f", $0) }
                .joined(separator: ",")
        }.joined(separator: ";")
    }

    private static func unique(_ list: [Compare.Contender]) -> [Compare.Contender] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.digest).inserted }
    }
}

/// Turns a contender into a clip the stage can play.
///
/// ONE BENCH, ONE WAY PER KIND. A network is recorded under the command; a
/// recorded motion is already a clip; a draft's keyframes are performed once
/// in physics; a sequence is replayed through `/record` with its own schedule.
@MainActor enum ContenderRunner {

    enum Failure: Error { case said(String) }

    static func clip(for contender: Compare.Contender, command: DuckDrive.Twist,
                     library: LibraryModel, drafts: DraftStore, sequences: SequenceStore,
                     benches: BenchStore) async throws -> DuckIntentClip {
        switch contender.kind {
        case .motion:
            if contender.key.hasPrefix("bundled:") {
                let name = String(contender.key.dropFirst("bundled:".count))
                if let clip = (try? DuckIntentClip.bundled())?[name] { return clip }
            } else if let clip = library.importedClips.first(where: { "kept:\($0.name)" == contender.key }) {
                return clip
            }
            throw Failure.said("\(contender.name) is not on \(DeviceWords.current.this) any more.")

        case .behaviour:
            guard let entry = library.library.entries.first(where: { $0.id == contender.key }) else {
                throw Failure.said("\(contender.name) is not in Behaviours any more.")
            }
            let (address, token) = try bench(benches)
            let health = try DuckBench.readHealth(await ask(DuckBench.health(address), token))
            // THE BENCH'S OWN NAME FOR IT, IF IT HAS ONE: the file, the file
            // without ".onnx" (benches often list them that way), or the name
            // an earlier upload was given. Only failing all three is it sent.
            let stem = entry.fileName.replacingOccurrences(of: ".onnx", with: "")
            let name: String
            if let held = [entry.fileName, stem, entry.title].first(where: health.policies.contains) {
                name = held
            } else {
                name = try await BenchUploads.put(entry, address: address, token: token,
                                                  host: health.host)
            }
            let call = try DuckBench.record(address, policy: name, seconds: CompareWords.seconds,
                                            schedule: [DuckBench.Step(at: 0, vx: command.vx,
                                                                      vy: command.vy,
                                                                      vyaw: command.vyaw)])
            return try DuckBench.readClip(await ask(call, token), named: contender.name)

        case .draft:
            guard let draft = drafts.drafts.first(where: { $0.id.uuidString == contender.key }) else {
                throw Failure.said("\(contender.name) is not in your drafts any more.")
            }
            let (address, token) = try bench(benches)
            let call = try DuckBench.perform(address, keys: draft.benchTrack,
                                             seconds: draft.duration + 0.5, rollouts: 1)
            let data = try await ask(call, token)
            let outcome = try DuckBench.readOutcome(data, when: Date())
            return try DuckBench.readPerformedClip(data, named: draft.name, laid: outcome.laid)

        case .shooter:
            throw Failure.said("A shooter is compared from Train a duck to shoot.")
        case .sequence:
            guard let seq = sequences.sequences.first(where: { $0.id.uuidString == contender.key })
                    ?? Self.transient[contender.key] else {
                throw Failure.said("\(contender.name) is not in your sequences any more.")
            }
            return try await clip(of: seq, benches: benches)
        }
    }

    /// Variants made for "Improve by choosing" that are not saved yet.
    static var transient: [String: DuckSequence] = [:]

    static func clip(of sequence: DuckSequence, benches: BenchStore) async throws -> DuckIntentClip {
        guard let policy = sequence.benchPolicy else {
            throw Failure.said(sequence.cannotBeKept ?? DuckSequence.benchNeverNamedANetwork)
        }
        let (address, token) = try bench(benches)
        let call = try DuckBench.record(address, policy: policy, seconds: sequence.simSeconds,
                                        schedule: sequence.benchSchedule())
        return try DuckBench.readClip(await ask(call, token), named: sequence.name)
    }

    private static func bench(_ benches: BenchStore) throws -> (DuckBench.Address, String?) {
        guard let bench = benches.selected else { throw Failure.said(CompareWords.noBench) }
        return (try bench.resolved(), benches.armed(bench).token)
    }

    private static func ask(_ call: DuckBench.Call, _ token: String?) async throws -> Data {
        try await URLSession.shared.data(for: DuckBench.urlRequest(for: call, token: token)).0
    }

    /// Any error, in words.
    static func words(_ error: Error) -> String {
        switch error {
        case Failure.said(let s): return s
        case let r as DuckBench.Refusal: return r.message
        case let r as DuckBench.ReadError: return r.message
        default: return error.localizedDescription
        }
    }
}
