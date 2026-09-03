import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking          // Linux keeps URLSession in its own module
#endif
@testable import StudioKit

/// Points the REAL code path at a REAL local model. Skipped unless asked for,
/// because a test suite that needs a server is a test suite that fails on a
/// machine without one.
///
///     STUDIOKIT_LOCAL_MODEL=gemma4:e4b-it-qat \
///     STUDIOKIT_LOCAL_URL=http://localhost:11434/v1 \
///     swift test --filter ZZLocalModelProbe
final class ZZLocalModelProbe: XCTestCase {

    func testALocalModelCanDraftAMotion() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipIf(environment["STUDIOKIT_LOCAL_MODEL"] == nil)
        let endpoint = ModelEndpoint(
            name: "probe", kind: .openAICompatible,
            baseURL: environment["STUDIOKIT_LOCAL_URL"] ?? "http://localhost:11434/v1",
            model: environment["STUDIOKIT_LOCAL_MODEL"]!,
            apiKey: environment["STUDIOKIT_LOCAL_TOKEN"],
            timeout: 900)
        let asked = environment["STUDIOKIT_LOCAL_PROMPT"] ?? "take a bow"
        let kind = ChatDraft.Kind(rawValue: environment["STUDIOKIT_LOCAL_KIND"] ?? "motion")!

        var request = URLRequest(url: try endpoint.chatURL())
        request.httpMethod = "POST"
        request.timeoutInterval = endpoint.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = endpoint.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try ChatWire.requestBody(
            model: endpoint.model,
            instructions: ChatDraft.instructions(for: kind, knownIntents: ["wave", "sit", "walk"]),
            prompt: asked)

        let started = Date()
        let (data, _) = try await URLSession.shared.data(for: request)
        let elapsed = Date().timeIntervalSince(started)

        let reply = try ChatWire.content(from: data)
        print("PROBE model=\(endpoint.model) kind=\(kind.rawValue) \(String(format: "%.1f", elapsed))s")
        print("PROBE raw reply: \(reply.prefix(400))")
        let json = try ChatWire.firstJSONObject(in: reply)
        print("PROBE extracted: \(json.prefix(400))")

        switch kind {
        case .motion:
            let proposal = try ChatDraft.motion(fromJSON: json)
            print("PROBE proposal name=\(proposal.name) keys=\(proposal.keys.count)")
            let draft = try proposal.resolve()
            print("PROBE RESOLVED \(draft.name) — \(draft.keys.count) keyframes, it passed the checker")
        case .rule:
            let proposal = try ChatDraft.rule(fromJSON: json)
            print("PROBE rule \(proposal.name): \(proposal.predicate) \(proposal.value) -> \(proposal.intent)")
        case .tweak:
            let tweak = try ChatDraft.tweak(fromJSON: json)
            print("PROBE tweak \(tweak.summary) — \(tweak.edits.count) edits")
        case .training:
            let request = try ChatDraft.training(fromJSON: json, prop: DuckScene.broom())
            print("PROBE request \(request.name) base=\(request.base.rawValue) "
                  + "rewards=\(request.rewards.map(\.function))")
            print("PROBE trainable=\(request.isTrainable) "
                  + "refusals=\(request.refusals.map(\.message))")
            print("PROBE file \(request.fileName)")
        case .search:
            // A SEARCH CHANGE NEEDS THE SEARCH, which this probe does not
            // hold — `SearchWords.instructions(for:spec:)` takes a move and a
            // spec, and neither is reachable from an environment variable. The
            // reading is still exercised, which is the half that can be.
            let reading = try SearchWords.read(fromJSON: json)
            print("PROBE search \(reading.summary) — \(reading.edits.count) edits")
        case .retrieval:
            let (object, stick) = try ChatDraft.stick(fromJSON: json)
            let plan = Retrieval.plan(for: stick)
            print("PROBE object=\(object ?? "?") \(stick.grams) g \(stick.thicknessMillimetres) mm")
            print("PROBE possible=\(plan.isPossible) \(plan.refusals.map(\.message))")
        }
    }
}
