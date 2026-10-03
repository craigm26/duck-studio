import Foundation
import DuckKit
import StudioKit
// Every kind's published manifest, as the app writes it, one JSON per line.
for kind in DuckPolicyKind.allCases {
    let w = PolicyManifest.forPublishing(title: "My \(kind.rawValue) v2", summary: "test",
                                         kind: kind, cautions: ["test"])
    let data = try PolicyManifest.encode(w)
    let obj = try JSONSerialization.jsonObject(with: data)
    print(String(decoding: try JSONSerialization.data(withJSONObject: obj), as: UTF8.self))
}
