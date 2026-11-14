import XCTest
@testable import StudioKit

/// Keys never appear in gate exports or run summaries (brains-layer.md 6.2 logs, and the build
/// 90 list in section 9: "the key-pattern grep over exports").
///
/// The grep is proved able to fail first: each fake key below matches a pattern on its own. Then
/// every string field a key could be pasted into is filled with one, a run is gated, and the
/// export, chip and summary are grepped.
final class GateKeyExportTests: XCTestCase {

    // Obviously fake, and shorter than real keys so no secret scanner mistakes them for one.
    static let fakeKeys = [
        "dl_live_" + String(repeating: "a1b2c3d4", count: 4),
        "sk-ant-api03-" + String(repeating: "Fake", count: 6),
        "sk-proj-" + String(repeating: "Fake", count: 6),
        "AIza" + String(repeating: "F", count: 31),
        "hf_" + String(repeating: "Fake", count: 6),
        "Bearer " + String(repeating: "fake", count: 4),
    ]

    func testTheGrepCanFail() {
        for key in Self.fakeKeys {
            XCTAssertTrue(KeyScrub.containsKey(key), "pattern misses \(key)")
            XCTAssertTrue(KeyScrub.containsKey("version " + key + " end"), "pattern misses \(key) in a sentence")
            XCTAssertFalse(KeyScrub.containsKey(KeyScrub.scrub(key)), "scrub leaves \(key)")
        }
    }

    func testScrubUsesTheDreamHint() {
        let key = Self.fakeKeys[0]
        XCTAssertEqual(KeyScrub.scrub(key), DuckDream.hint(key))
        XCTAssertEqual(KeyScrub.scrub("model " + key), "model " + DuckDream.hint(key))
    }

    func testACheckpointHashIsNotAKey() {
        let hash = "9dcea89908349acfa10e55cd498b124e3622a050"
        XCTAssertEqual(KeyScrub.scrub(hash), hash)
        XCTAssertEqual(KeyScrub.scrub("model-2026-10"), "model-2026-10")
    }

    func testNoKeyLeavesInAnExportOrASummary() throws {
        for key in Self.fakeKeys {
            let planner = PlannerInfo(id: "byok." + key, modelVersion: key, label: "x", runsOn: .hosted(vendor: "v"),
                                      key: .byok(provider: "v"), decisionDeadline: .seconds(8))
            var gate = DuckEnvelopeGate()
            gate.bind(DuckEnvelopeGate.Binding(planner, venue: .practice, mode: .auto,
                                                allowed: AllowedDecisions(kinds: [.walk, .turn])))
            XCTAssertFalse(KeyScrub.containsKey(gate.binding?.modelVersion ?? ""), "bound with a key")
            for i in 0..<5 {
                _ = try gate.act(DuckEnvelopeGate.Row(t: Double(i) / 10, twist: GateTwist(vx: 0.3, vy: 0, vyaw: 0),
                                                      odomAgeMs: 20, pose: .init(x: 0, y: 0, yaw: 0),
                                                      phase: "act " + key))
            }
            let d = Decided(decision: .walk(forwardM: 0.5, sideM: 0), why: "because " + key,
                            provider: planner, latency: .milliseconds(5))
            _ = try gate.check(d, at: 1)
            _ = try gate.confirm(d, at: 1)

            for event in gate.events {
                for s in event.strings { XCTAssertFalse(KeyScrub.containsKey(s), "event field holds a key: \(s)") }
            }
            let export = try GateExport.jsonLines(gate.events)
            let summary = gate.stats.summary(venue: .practice, limits: gate.limits).joined(separator: "\n")
            for text in [export, gate.stats.chip, summary] {
                XCTAssertFalse(KeyScrub.containsKey(text), "a key pattern is in:\n\(text)")
                XCTAssertFalse(text.contains(key), "the raw key is in:\n\(text)")
                let tail = String(key.dropFirst(6))
                XCTAssertFalse(text.contains(tail), "most of the key is in:\n\(text)")
            }
            XCTAssertTrue(export.contains(DuckDream.hint(key)) || key.hasPrefix("Bearer"),
                          "the export names which key, masked, the way the Dream key is shown")
        }
    }

    /// The BYOK planners (AnthropicPlanner, OpenAIPlanner): no key in a planner's printed form,
    /// an error's words, a decision, a gate export of that decision, or any copy, even when the
    /// vendor quotes the key back or the model writes it into its reason.
    func testNoKeyLeavesTheHostedPlanners() async throws {
        let keys = [HostedFixtures.anthropicKey, HostedFixtures.openaiKey]
        for key in keys { XCTAssertTrue(KeyScrub.containsKey(key), "the grep must be able to fail on \(key)") }

        let anthropic = AnthropicPlanner(key: keys[0], http: StubPlannerHTTP())
        let openai = OpenAIPlanner(key: keys[1], http: StubPlannerHTTP())
        var texts: [String] = []
        for p in [anthropic as any Planner, openai as any Planner] {
            texts.append(String(describing: p))
            texts.append(String(reflecting: p))
            var dumped = ""
            dump(p, to: &dumped)
            texts.append(dumped)
            texts.append(String(describing: p.info))
        }

        // Every error, including one whose vendor message quotes the key.
        for key in keys {
            let quoted = "Incorrect API key provided: \(key). You can find your API key at the dashboard."
            texts.append(AnthropicPlanner.error(status: 400, headers: [:],
                                                top: ["error": ["type": "invalid_request_error", "message": quoted]]).says)
            texts.append(OpenAIPlanner.error(status: 400, headers: [:],
                                             top: ["error": ["type": "invalid_request_error", "message": quoted]]).says)
        }
        texts += PlannerErrorWordsTests.allErrors.map(\.says)
        texts += HostedPlannerWords.all

        // A decision whose reason holds a key, and the gate's export of it.
        var events: [GateEvent] = []
        for (vendor, key) in zip(HostedVendor.allCases, keys) {
            let json = vendor == .anthropic
                ? HostedFixtures.anthropicToolUse("walk", #"{"forward_m":0.5,"side_m":0,"why":"use \#(key) now"}"#)
                : HostedFixtures.openaiCall("walk", #"{"forward_m":0.5,"side_m":0,"why":"use \#(key) now"}"#)
            let stub = StubPlannerHTTP(json: json)
            let planner: any Planner = vendor == .anthropic
                ? AnthropicPlanner(key: key, http: stub) : OpenAIPlanner(key: key, http: stub)
            let d = try await planner.decide(HostedFixtures.ask())
            texts += [d.why, String(describing: d), d.provider.modelVersion]
            var gate = DuckEnvelopeGate()
            gate.bind(DuckEnvelopeGate.Binding(d.provider, venue: .practice, mode: .tell, allowed: HostedFixtures.practice))
            _ = try gate.check(d, at: 1)
            events += gate.events
            texts.append(gate.stats.summary(venue: .practice, limits: gate.limits).joined(separator: "\n"))
        }
        texts.append(try GateExport.jsonLines(events))

        for text in texts {
            XCTAssertFalse(KeyScrub.containsKey(text), "a key pattern is in:\n\(text)")
            for key in keys {
                XCTAssertFalse(text.contains(String(key.dropFirst(6))), "most of a key is in:\n\(text)")
            }
        }
    }

    func testTheExportIsOneObjectPerLine() throws {
        var gate = DuckEnvelopeGate()
        gate.bind(DuckEnvelopeGate.Binding(PlannerInfo.duckTalk, venue: .practice, mode: .tell,
                                            allowed: AllowedDecisions(kinds: [.walk])))
        _ = try gate.act(DuckEnvelopeGate.Row(t: 0, twist: GateTwist(vx: 0.1, vy: 0, vyaw: 0), odomAgeMs: 20,
                                              pose: .init(x: 0, y: 0, yaw: 0)))
        _ = try gate.act(DuckEnvelopeGate.Row(t: 0.1, twist: GateTwist(vx: 0.1, vy: 0, vyaw: 0), odomAgeMs: 500,
                                              pose: .init(x: 0, y: 0, yaw: 0)))
        let lines = try GateExport.jsonLines(gate.events).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any])
        XCTAssertEqual(second["verdict"] as? String, "held")
        XCTAssertEqual(second["rule"] as? String, "stale")
        XCTAssertEqual(second["provider_id"] as? String, "phone.ducktalk")
        XCTAssertEqual(second["proximity"] as? String, "unmet")
        let back = try JSONDecoder().decode(GateEvent.self, from: Data(lines[1].utf8))
        XCTAssertEqual(back, gate.events[1])
    }
}
