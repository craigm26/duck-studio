import SwiftUI
import StudioKit

/// Runs Dream-1 on the duck the bridge reaches, from the camera card.
///
/// THE KEY IS NOT HERE. It is saved on the robot's computer from the bridge
/// screen (`DreamKeySection`); this asks that computer which of the person's
/// models a duck can run, and plays what the chosen one answers through
/// `DreamPilot`, which clamps every step to the sticks' envelope.
@MainActor
final class DreamRunModel: ObservableObject {
    @Published private(set) var models: [DuckDream.Model] = []
    @Published private(set) var key: String?
    @Published private(set) var checked = false
    @Published private(set) var line: String?
    @Published private(set) var running = false
    @Published var chosen: String?
    private var task: Task<Void, Never>?

    /// Where the rows come from: this device's key first, else the robot's computer.
    private var direct: DreamDirect?

    func check(_ peer: any DuckPeer) async {
        do {
            let answer: DuckDream.KeyAnswer
            if let direct = DreamKeyStore.client() {
                self.direct = direct
                answer = try await direct.models()
            } else {
                direct = nil
                answer = try DuckDream.readKey(try await peer.call(.dream(.keyCheck)))
            }
            key = answer.key
            models = answer.duckModels
            if chosen == nil || !models.contains(where: { $0.id == chosen }) { chosen = models.first?.id }
            line = models.isEmpty ? DuckDream.Words.noDuckModel : nil
        } catch let refusal as DuckDream.ReadError {
            key = nil
            models = []
            line = refusal.message
        } catch {
            line = error.localizedDescription
        }
        checked = true
    }

    func run(_ peer: any DuckPeer, feed: DuckCameraFeed, prompt: String,
             stopDriving: (() async -> Void)?) {
        guard !running, let chosen else { return }
        running = true
        line = nil
        feed.keepsDreamFrames = true
        let pilot = DreamPilot(checkpoint: chosen, prompt: prompt)
        let rows: any DreamRows = direct ?? BridgeDreamRows(peer)
        task = Task { [weak self] in
            await stopDriving?()
            // A first window of pictures before the first ask: the model reads motion, not one frame.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await pilot.run(on: peer, rows: rows,
                            frames: { await feed.dreamWindow() },
                            events: { event in await self?.apply(event) })
            await MainActor.run {
                feed.keepsDreamFrames = false
                self?.running = false
            }
        }
    }

    func stop() { task?.cancel() }

    private func apply(_ event: DreamPilot.Event) {
        switch event {
        case .asked: break
        case .played(let rows, let seconds): line = DuckDream.Words.running(rows, seconds)
        case .waiting(let said): line = said
        case .ended(let said): line = said
        }
    }
}

struct DreamRunView: View {
    @ObservedObject var robot: BridgeLink
    @ObservedObject var feed: DuckCameraFeed
    var stopDriving: (() async -> Void)?
    @StateObject private var model = DreamRunModel()
    @AppStorage("dream.prompt") private var prompt = ""
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            Text(DuckDream.Words.heading).font(.headline)
            if model.checked, model.key == nil {
                Text(DuckDream.Words.noKey).font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            if !model.models.isEmpty {
                Picker(DuckDream.Words.model, selection: $model.chosen) {
                    ForEach(model.models) { m in Text(m.label).tag(String?.some(m.id)) }
                }
                .font(.footnote)
                TextField(DuckDream.Words.promptPlaceholder, text: $prompt, axis: .vertical)
                    .font(.callout)
                    .frame(minHeight: DesignMetric.minimumTarget)
                if model.running {
                    Button(DuckDream.Words.stop) { model.stop() }
                        .buttonStyle(.primaryAction)
                } else {
                    Button(DuckDream.Words.run) { confirming = true }
                        .buttonStyle(.primaryActionMoves)
                        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || model.chosen == nil || feed.picture == nil)
                }
            }
            if let line = model.line {
                Text(line).font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            if let peer = robot.peer { await model.check(peer) }
        }
        .onDisappear { model.stop() }
        .confirmationDialog(DuckDream.Words.run, isPresented: $confirming, titleVisibility: .visible) {
            Button(DuckDream.Words.run, role: .destructive) {
                guard let peer = robot.peer else { return }
                model.run(peer, feed: feed, prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                          stopDriving: stopDriving)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DuckDream.Words.howItDrives)
        }
    }
}

/// The key, from the bridge screen: pasted once, checked with Dream Labs by
/// the robot's computer, and kept there. The field empties after a save, so
/// the key is on this screen only while it is being typed.
struct DreamKeySection: View {
    @ObservedObject var robot: BridgeLink
    @State private var typed = ""
    @State private var busy = false
    @State private var said: String?
    @State private var problem: String?

    var body: some View {
        Section {
            Text(DuckDream.Words.whatItIs)
                .font(.footnote).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(DuckDream.Words.keepOnRobot)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField(DuckDream.Words.keyPlaceholder, text: $typed)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
            Button { Task { await save() } } label: {
                HStack(spacing: Theme.spacing(.tight)) {
                    Text(DuckDream.Words.saveKey).frame(maxWidth: .infinity)
                    if busy { ProgressView() }
                }
            }
            .buttonStyle(.primaryAction)
            .disabled(busy || typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let said {
                Text(said).font(.footnote).foregroundStyle(Theme.measured)
                    .fixedSize(horizontal: false, vertical: true)
                Button(DuckDream.Words.clearKey, role: .destructive) { Task { await clear() } }
                    .font(.footnote)
            }
            if let problem {
                Label(problem, systemImage: "xmark.octagon")
                    .font(.footnote).foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: DuckDream.Words.heading)
        }
        .listRowBackground(Theme.surfacePrimary)
        .task { await status() }
    }

    private func status() async {
        guard let peer = robot.peer else { return }
        if let answer = try? DuckDream.readKey(try await peer.call(.dream(.keyCheck))), let key = answer.key {
            said = describe(DuckDream.Words.saved(key), answer)
        }
    }

    private func describe(_ first: String, _ answer: DuckDream.KeyAnswer) -> String {
        answer.duckModels.isEmpty ? first + " " + DuckDream.Words.noDuckModel
            : first + " " + answer.duckModels.map(\.id).joined(separator: ", ")
    }

    private func save() async {
        guard let peer = robot.peer else { return }
        problem = nil
        switch DuckDream.cleaned(typed) {
        case .failure(let why): problem = why.message; return
        case .success(let key):
            busy = true
            defer { busy = false }
            do {
                let answer = try DuckDream.readKey(try await peer.call(.dream(.keySet(key))))
                typed = ""
                said = describe(DuckDream.Words.saved(answer.key ?? DuckDream.hint(key)), answer)
            } catch let refusal as DuckDream.ReadError {
                problem = refusal.message
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func clear() async {
        guard let peer = robot.peer else { return }
        do {
            _ = try DuckDream.readCleared(try await peer.call(.dream(.keyClear)))
            said = nil
        } catch let refusal as DuckDream.ReadError {
            problem = refusal.message
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// The key on this device, from Settings: checked with Dream Labs, then kept in
/// the Keychain. Dream-1 then runs over any link that drives the duck, with
/// nothing about Dream on the robot's computer.
struct DreamKeyHereSection: View {
    @State private var typed = ""
    @State private var busy = false
    @State private var said: String?
    @State private var problem: String?
    @State private var saved = DreamKeyStore.load() != nil

    var body: some View {
        Section {
            SecureField(DuckDream.Words.keyPlaceholder, text: $typed)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
            Button { Task { await save() } } label: {
                Label(busy ? "Checking…" : DuckDream.Words.saveKey, systemImage: "key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .disabled(busy || typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if saved {
                Button(role: .destructive) {
                    DreamKeyStore.clear(); saved = false; said = nil
                } label: {
                    Text(DuckDream.Words.removeHere).foregroundStyle(Theme.critical)
                }
            }
            if let said {
                Text(said).font(.footnote).foregroundStyle(Theme.measured)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem {
                Label(problem, systemImage: "xmark.octagon")
                    .font(.footnote).foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: DuckDream.Words.heading)
        } footer: {
            Text(DuckDream.Words.whatItIsHere).foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
        .task {
            if let key = DreamKeyStore.load() { said = DuckDream.Words.savedHere(DuckDream.hint(key)) }
        }
    }

    private func save() async {
        problem = nil
        switch DuckDream.cleaned(typed) {
        case .failure(let why): problem = why.message
        case .success(let key):
            busy = true
            defer { busy = false }
            do {
                // CHECKED BEFORE IT IS KEPT. A key Dream Labs refuses is not saved.
                let answer = try await DreamDirect(key: key, version: DreamKeyStore.version).models()
                DreamKeyStore.save(key)
                typed = ""
                saved = true
                let first = DuckDream.Words.savedHere(DuckDream.hint(key))
                said = answer.duckModels.isEmpty ? first + " " + DuckDream.Words.noDuckModel
                    : first + " " + answer.duckModels.map(\.id).joined(separator: ", ")
            } catch let refusal as DuckDream.ReadError {
                problem = refusal.message
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
