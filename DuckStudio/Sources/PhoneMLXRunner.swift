import Foundation
import StudioKit

/// The app's MLX runtime behind the kit's `PhoneModelRunning`, so `PhoneMLXPlanner` can ask it.
///
/// WIRING ONLY. The kit builds the prompt, reads the answer and decides what is allowed. This
/// passes text through and lists a folder. Nothing on screen uses it yet: no local model has an
/// EvidenceRow, so `OfferRule` keeps every local planner's card hidden.
struct PhoneMLXRunner: PhoneModelRunning {

    func respond(repository: String, instructions: String, prompt: String,
                 deadline: TimeInterval) async throws -> String {
        do {
            return try await PhoneModelRuntime.shared.ask(repository, instructions: instructions,
                                                          prompt: prompt, deadline: deadline)
        } catch let failure as PhoneModelRuntime.Failure {
            throw LocalPlannerError.runnerFailed(failure.message)
        }
    }

    /// The downloaded weights' version. The hub client names each snapshot folder by its commit,
    /// and the kit decides whether that pins it.
    static func version(for repository: String) -> LocalModelVersion {
        let folder = PhoneModelFiles.directory(for: repository)?.appendingPathComponent("snapshots", isDirectory: true)
        let names = folder.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        return LocalModelVersion.huggingFace(repository: repository, snapshots: names)
    }
}
