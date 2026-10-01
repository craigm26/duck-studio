import Foundation
import StudioKit

// One config per base, each carrying EVERY vocabulary term with its declared
// sign, so an import + env build exercises the app's whole reward vocabulary.
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let terms = TrainingRequest.vocabulary.keys.sorted().map { fn -> TrainingRequest.Reward in
    let sign = TrainingRequest.weightSigns[fn] == .negative ? -0.01 : 0.01
    return .init(function: fn, weight: sign, reason: "vocabulary check: \(fn)")
}
var manifest: [[String: String]] = []
for base in TrainingRequest.Base.allCases {
    let req = TrainingRequest(name: "vocab_\(base.moduleName)", summary: "every term on \(base.rawValue)",
                              base: base, rewards: terms, successCriterion: "imports and builds")
    try req.envConfig().write(to: out.appendingPathComponent(req.fileName), atomically: true, encoding: .utf8)
    manifest.append(["file": req.fileName, "factory": "make_\(req.slug)_env_cfg", "base": base.rawValue])
}
let walk = TrainingRequest(name: "walk_on", summary: "walk where told, paid for going", base: .velocity,
    rewards: [.init(function: "forward_speed_reward", weight: 1.0, reason: "pays for going forward"),
              .init(function: "is_alive", weight: 0.5, reason: "pays for staying up")],
    successCriterion: "cmd 0.10 -> >= 0.05 m/s")
try walk.envConfig().write(to: out.appendingPathComponent(walk.fileName), atomically: true, encoding: .utf8)
manifest.append(["file": walk.fileName, "factory": "make_\(walk.slug)_env_cfg", "base": "velocity"])
try JSONSerialization.data(withJSONObject: TrainingRequest.vocabulary.keys.sorted())
    .write(to: out.appendingPathComponent("vocabulary.json"))
let data = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
try data.write(to: out.appendingPathComponent("manifest.json"))
print("wrote \(manifest.count) configs, \(terms.count) terms each")
