import XCTest
@testable import StudioKit

/// The checked-in JSON schema and the Swift enum say the same thing.
///
/// The schema is what a BYOK tool definition and a Python bench read. If a case, a field or a
/// limit changes in one place and not the other, this fails.
final class DuckDecisionSchemaTests: XCTestCase {

    func schema() throws -> [String: Any] {
        let url = try XCTUnwrap(ModelIntentPlanner.resource("Planner/duck-decision.schema", "json"),
                                "the schema ships with the kit")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func branches() throws -> [String: [String: Any]] {
        let oneOf = try XCTUnwrap(try schema()["oneOf"] as? [[String: Any]])
        var out: [String: [String: Any]] = [:]
        for b in oneOf {
            let props = try XCTUnwrap(b["properties"] as? [String: Any])
            let kind = try XCTUnwrap((props["kind"] as? [String: Any])?["const"] as? String)
            XCTAssertNil(out[kind], "kind \(kind) appears twice")
            out[kind] = b
        }
        return out
    }

    func testTheSchemaHasExactlyTheEnumsKinds() throws {
        let oneOf = try XCTUnwrap(try schema()["oneOf"] as? [[String: Any]])
        let kinds = oneOf.compactMap { (($0["properties"] as? [String: Any])?["kind"] as? [String: Any])?["const"] as? String }
        XCTAssertEqual(kinds, DuckDecision.Kind.allCases.map(\.rawValue))
    }

    func testEachKindHasTheEnumsFieldsAndNoOthers() throws {
        let all = try branches()
        for kind in DuckDecision.Kind.allCases {
            let b = try XCTUnwrap(all[kind.rawValue])
            XCTAssertEqual(b["type"] as? String, "object")
            XCTAssertEqual(b["additionalProperties"] as? Bool, false, kind.rawValue)
            XCTAssertEqual(b["required"] as? [String], ["kind"] + kind.fields, kind.rawValue)
            let props = try XCTUnwrap(b["properties"] as? [String: [String: Any]])
            XCTAssertEqual(Set(props.keys), Set(["kind"] + kind.fields), kind.rawValue)
            for field in kind.fields {
                let p = try XCTUnwrap(props[field])
                switch field {
                case "forward_m", "side_m", "degrees", "seconds":
                    XCTAssertEqual(p["type"] as? String, "number", field)
                case "source":
                    XCTAssertEqual(p["type"] as? String, "string", field)
                    XCTAssertEqual(p["enum"] as? [String], ActionSourceID.allCases.map(\.rawValue), "the closed set of sources")
                case "beats":
                    XCTAssertEqual(p["type"] as? String, "array", field)
                    XCTAssertEqual(p["maxItems"] as? Int, RobotPlanProposal.wireMaxBeats)
                    let items = try XCTUnwrap(p["items"] as? [String: Any])
                    XCTAssertEqual(items["additionalProperties"] as? Bool, false)
                    XCTAssertEqual(items["required"] as? [String], ["action", "speed", "seconds"])
                    let ip = try XCTUnwrap(items["properties"] as? [String: [String: Any]])
                    XCTAssertEqual(ip["action"]?["enum"] as? [String], RobotPlanProposal.actions)
                    XCTAssertEqual(ip["speed"]?["enum"] as? [String], RobotPlanProposal.speeds)
                    XCTAssertEqual(ip["seconds"]?["type"] as? String, "number")
                default:
                    XCTAssertEqual(p["type"] as? String, "string", field)
                    XCTAssertEqual(p["maxLength"] as? Int, DuckDecision.maxTextLength, field)
                }
            }
        }
    }

    /// A small validator for the subset of JSON Schema the file uses.
    func validates(_ doc: [String: Any]) throws -> Bool {
        let matches = try branches().values.filter { b in
            let props = b["properties"] as? [String: [String: Any]] ?? [:]
            let required = b["required"] as? [String] ?? []
            guard required.allSatisfy({ doc[$0] != nil }) else { return false }
            guard doc.keys.allSatisfy({ props[$0] != nil }) else { return false }
            for (k, v) in doc {
                let p = props[k] ?? [:]
                if let c = p["const"] as? String, (v as? String) != c { return false }
                switch p["type"] as? String {
                case "number": if v is String || !(v is NSNumber || v is Int || v is Double) { return false }
                case "string":
                    guard let s = v as? String else { return false }
                    if let m = p["maxLength"] as? Int, s.count > m { return false }
                default: break
                }
            }
            return true
        }
        return matches.count == 1
    }

    func testEveryEncodedDecisionValidates() throws {
        for d in DuckDecisionTests.every {
            let doc = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as? [String: Any])
            XCTAssertTrue(try validates(doc), "\(d)")
        }
    }

    func testTheValidatorCanFail() throws {
        XCTAssertFalse(try validates(["kind": "walk", "forward_m": 1]))
        XCTAssertFalse(try validates(["kind": "walk", "forward_m": 1, "side_m": 0, "speed": 1]))
        XCTAssertFalse(try validates(["kind": "look_at"]))
        XCTAssertFalse(try validates(["kind": "turn", "degrees": "ninety"]))
        XCTAssertFalse(try validates(["kind": "ask",
                                      "question": String(repeating: "a", count: DuckDecision.maxTextLength + 1)]))
    }
}
