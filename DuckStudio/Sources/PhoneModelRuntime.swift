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

    /// SET ONCE, BEFORE ANYTHING LOADS. MLX keeps a buffer cache that grows to
    /// fill what it is allowed, and on a phone that competes directly with the
    /// budget iOS kills the app for exceeding.
    private var cappedCache = false
    private func capCacheOnce() {
        guard !cappedCache else { return }
        cappedCache = true
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
    }

    /// Deterministic, and bounded. Temperature 0 selects argmax, which is what
    /// an answer parsed as JSON and clamped against joint travel wants — the
    /// 0.6 default is for conversation. `maxTokens` defaults to nil, meaning
    /// unbounded, which on a phone is a hang rather than a long wait.
    private func parameters() -> GenerateParameters {
        var p = GenerateParameters()
        p.temperature = 0
        p.maxTokens = 1200
        return p
    }

    /// Download if needed, then hold it. `progress` is delivered on the main
    /// actor by the hub bridge, so a SwiftUI bar can be driven straight from it.
    @discardableResult
    func load(_ repository: String,
              progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws
        -> ModelContainer {
        if let held, held.repository == repository { return held.container }
        capCacheOnce()
        // THE `id:` OVERLOAD, NOT A REGISTRY CONSTANT. The registry names a
        // fixed set; this app lets somebody pick any mlx-community repository,
        // which only the String-taking form can express.
        let container = try await loadModelContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            id: repository,
            progressHandler: progress)
        held = (repository, container)
        return container
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
    func ask(_ repository: String, instructions: String, prompt: String) async throws -> String {
        let container = try await load(repository)
        let session = ChatSession(container, instructions: instructions,
                                  generateParameters: parameters())
        return try await session.respond(to: prompt)
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

    func ask(_ repository: String, instructions: String, prompt: String) async throws -> String {
        throw Failure.unavailable(PhoneModelInstall.simulatorRefusal)
    }

    var isSupported: Bool { false }

#endif
}
