import Foundation
import StudioKit

#if canImport(MLXLLM) && !targetEnvironment(simulator)
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers
#endif

/// Running a downloaded model, in this process, on the phone's GPU.
///
/// EVERY SIGNATURE IN HERE WAS READ FROM mlx-swift-lm 3.31.4's SOURCE, not
/// recalled. This project has shipped three defects this week from APIs written
/// from memory, and MLX is a package whose loading API changed shape between
/// major versions — 3.x moved the downloader and the tokenizer out into
/// protocols with no conformances in the package at all.
///
/// IT COMPILES AWAY IN THE SIMULATOR, AND THAT IS NOT A CONVENIENCE. MLX
/// evaluates on Metal, which the iOS Simulator does not provide, so a build for
/// it must not merely fail at run time — it must not link MLX at all. The
/// `#else` branch answers every call with the same refusal a person would see,
/// so the Simulator build stays usable for everything else in the app.
@MainActor
final class PhoneModelRuntime {

    static let shared = PhoneModelRuntime()
    private init() {}

    enum Failure: Error {
        case unavailable(String)

        var message: String {
            switch self { case .unavailable(let text): return text }
        }
    }

#if canImport(MLXLLM) && !targetEnvironment(simulator)

    /// ONE MODEL RESIDENT AT A TIME. A phone has room for one, and holding a
    /// second is the difference between working and being killed for the
    /// memory. Loading a different repository drops the first.
    private var held: (repository: String, container: ModelContainer)?

    /// ONE LOAD IN FLIGHT AT A TIME, KEYED BY NOTHING. `held` is written only
    /// after the await, so two overlapping calls both ran the loader and put
    /// two multi-gigabyte models resident — breaking this file's own promise
    /// two comments up. It is reachable without a contrived double tap: start a
    /// download on the Models tab, switch to Draft, ask with an installed
    /// model. Unstructured on purpose, so one waiter walking away does not
    /// cancel work another is waiting on.
    private var loading: Task<ModelContainer, Error>?

    /// SET ONCE, BEFORE ANYTHING LOADS. MLX keeps a buffer cache that grows to
    /// fill what it is allowed, and on a phone that competes directly with the
    /// budget iOS kills the app for exceeding.
    private var cappedCache = false
    private func capCacheOnce() {
        guard !cappedCache else { return }
        cappedCache = true
        // 128 MB, AND THIS NUMBER IS A GUESS REPLACING A WORSE ONE. It was
        // 20 MB, copied from Apple's iOS chat example, and the first real run
        // on a phone managed roughly 0.85 tokens a second on a 0.6B — about
        // fifty times slower than that model should be. A cache this small
        // makes MLX allocate and free Metal buffers continuously, which is the
        // most likely explanation and is not yet a measured one. The draft card
        // now prints how long a draft took, so the next run measures it.
        MLX.GPU.set(cacheLimit: 128 * 1024 * 1024)
    }

    /// Deterministic, and bounded. Temperature 0 selects argmax, which is what
    /// an answer parsed as JSON and clamped against joint travel wants — the
    /// 0.6 default is for conversation. `maxTokens` defaults to nil, meaning
    /// unbounded, which on a phone is a hang rather than a long wait.
    private func parameters() -> GenerateParameters {
        var p = GenerateParameters()
        p.temperature = 0
        // 700, NOT 1200. A motion is a short JSON object — the corpus's longest
        // is nowhere near this — and on a phone every unused token in the
        // ceiling is time somebody spends watching a spinner. The first device
        // run burned 1200 tokens over 1409 seconds and emitted no JSON at all,
        // so a smaller ceiling is also a shorter way to find that out.
        p.maxTokens = 700
        return p
    }

    /// Download if needed, then hold it. `progress` is delivered on the main
    /// actor by the hub bridge, so a SwiftUI bar can be driven straight from it.
    @discardableResult
    func load(_ repository: String,
              progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws
        -> ModelContainer {
        // THE SHORT-CIRCUIT IS CHECKED AGAINST THE DISK, not just against
        // memory: a model deleted while still held would otherwise "re-download"
        // instantly and successfully, having done nothing.
        if let held, held.repository == repository,
           PhoneModelFiles.bytesOnDisk(repository) != nil {
            return held.container
        }
        if let loading {
            _ = try? await loading.value
            if let held, held.repository == repository { return held.container }
        }
        capCacheOnce()
        // DROP THE OLD ONE BEFORE MATERIALISING THE NEW ONE. Without this even
        // strictly sequential switching peaks at both models resident, which on
        // a phone is the difference between working and being killed.
        if held != nil {
            held = nil
            MLX.GPU.clearCache()
        }
        let job = Task<ModelContainer, Error> { [weak self] in
            defer { Task { @MainActor in self?.loading = nil } }
            return try await Self.fetch(repository, progress: progress)
        }
        loading = job
        let container = try await job.value
        held = (repository, container)
        return container
    }

    /// NONISOLATED, AND THAT IS THE WHOLE REASON PROGRESS MOVES.
    ///
    /// This class is @MainActor because its state is read from views — but a
    /// static method inherits that isolation, so the download AND the weight
    /// load ran on the main actor. The hub samples progress every 100 ms and
    /// calls back faithfully; every one of those updates then queued behind
    /// synchronous loading work on the same actor and arrived only when it
    /// finished. The bar sat at the small files and then jumped to done.
    ///
    /// Nothing here touches instance state, so it does not need the actor.
    nonisolated private static func fetch(
        _ repository: String,
        progress: @escaping @Sendable (Progress) -> Void) async throws
        -> ModelContainer {
        // THE `id:` OVERLOAD, NOT A REGISTRY CONSTANT. The registry names a
        // fixed set; this app lets somebody pick any mlx-community repository,
        // which only the String-taking form can express.
        try await loadModelContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            id: repository,
            progressHandler: progress)
    }

    /// Ask it, with the same instructions-and-prompt shape every other kind
    /// uses.
    ///
    /// A FRESH SESSION EACH TIME, because the HTTP path is stateless and this
    /// must match it: `ChatSession` accumulates history, so a reused one would
    /// let one draft inherit another's context and quietly diverge from what
    /// the same prompt does against a server.
    ///
    /// ChatSession AND NOT `MLXLMCommon.generate`: the low-level call starts
    /// its token loop with a plain `Task {}`, which inherits this actor and
    /// would run the whole generation on the UI thread. ChatSession does its
    /// work inside ModelContainer's own mutex actor instead.
    /// Ask it, with a DEADLINE THAT ACTUALLY STOPS IT.
    ///
    /// `DraftBudget` judges between steps, so a single generation that overran
    /// was only noticed once it finished: the first device run reported "1409 s
    /// of the 300 s this was given" — it had been allowed to run for
    /// twenty-three minutes and then been told it was late. An in-process model
    /// has no URLSession timeout to fall back on, so the deadline has to be
    /// here, and it has to cancel.
    func ask(_ repository: String, instructions: String, prompt: String,
             deadline: TimeInterval) async throws -> String {
        let container = try await load(repository)
        // THINKING OFF, BY LABEL NOT POSITION — `speculativeDecoding` sits
        // between `instructions` and `generateParameters`, and
        // `additionalContext` comes after `processing`. Two of the five
        // catalogue models carry Qwen3's hybrid template, whose only
        // suppression path is this flag; without it both reason into the token
        // ceiling at temperature 0, which Qwen's own card warns produces
        // "endless repetitions".
        let session = ChatSession(container,
                                  instructions: instructions,
                                  generateParameters: parameters(),
                                  additionalContext: PhoneModelInstall.templateThinkingOff)
        let asked = PhoneModelInstall.prompt(prompt, for: repository)

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await session.respond(to: asked) }
            group.addTask {
                try await Task.sleep(for: .seconds(deadline))
                throw Failure.unavailable(PhoneModelInstall.tookTooLong(seconds: deadline))
            }
            // Whichever finishes first wins; cancelling the group stops the
            // other, which is the part that was missing.
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw Failure.unavailable(PhoneModelInstall.notLoaded)
            }
            return first
        }
    }

    /// Whether this repository's weights are the ones currently resident.
    func isResident(_ repository: String) -> Bool { held?.repository == repository }

    /// Let go of a specific model, if it is the one being held.
    func unload(ifHolding repository: String) {
        guard held?.repository == repository else { return }
        unload()
    }

    /// Let go of the weights without deleting them from disk.
    func unload() {
        held = nil
        MLX.GPU.clearCache()
    }

    var isSupported: Bool { true }

#else

    /// The Simulator has no Metal device, so MLX is not linked into this build
    /// at all and every call answers with the sentence a person would see.
    func load(_ repository: String,
              progress: @escaping @Sendable (Progress) -> Void) async throws {
        throw Failure.unavailable(PhoneModelInstall.simulatorRefusal)
    }

    func ask(_ repository: String, instructions: String, prompt: String,
             deadline: TimeInterval) async throws -> String {
        throw Failure.unavailable(PhoneModelInstall.simulatorRefusal)
    }

    /// STUB PARITY IS NOT OPTIONAL. Every method must exist in both branches or
    /// the Simulator build — which is what the free compile gate uses — fails
    /// on the first call site added.
    func unload() {}
    func unload(ifHolding repository: String) {}
    func isResident(_ repository: String) -> Bool { false }

    var isSupported: Bool { false }

#endif
}
