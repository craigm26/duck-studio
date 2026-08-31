import Foundation
import DuckKit

/// Mixing trained networks, and being straight about what that is likely to do.
///
/// IT IS ARITHMETIC, AND THE FILE IS ALWAYS VALID. Every policy this family
/// loads has the identical architecture — `DuckPolicy` refuses anything that is
/// not 61-512-256-128-14 with ELU throughout — so a weighted average of two of
/// them is a policy in the only sense the loader recognises, and
/// `DuckPolicyWriter` will write it out to a file robotd would accept. None of
/// that is in doubt and none of it is interesting.
///
/// WHAT IS IN DOUBT IS WHETHER IT WALKS, AND IT DOES NOT. This is no longer a
/// prior. Averaging `alpha_walking` with `BEST_alpha_stand` at four ratios and
/// running each for six seconds on the duckbench, commanded forward at
/// vx = 0.5 on plant `scene.mjb` (3f8c9ab9b409):
///
///     walking, unmodified   travelled 1.207 m, upright
///     25% standing          travelled 0.176 m, FELL (trunk at 44 mm)
///     50% standing          travelled 0.156 m, FELL (trunk at 40 mm)
///     75% standing          travelled 0.002 m, upright
///     standing, unmodified  travelled 0.001 m, upright
///
/// So the blends either fall over or stop being a walk. Averaging weights works
/// between checkpoints that share an ancestor — fine-tunes of one run, the
/// "model soup" case. Pollen's policies are not that: walking, standing, the
/// roulade and the kicks were trained separately, as different tasks, from
/// different initialisations. Two independently trained networks have no reason
/// to put the same meaning in the same neuron, so the average of their weights
/// is not the average of their behaviours.
///
/// READ THE 75% ROW AGAIN, BECAUSE IT IS THE ONE THAT NEARLY GOT MISREPORTED.
/// It scores a perfect 16 of 16 on the bench's own criterion — "ends standing,
/// trunk at least 100 mm up" — while travelling two millimetres. It did not
/// inherit the walk; it collapsed into the standing policy, which passes an
/// uprightness test trivially. A success rate against that criterion cannot
/// distinguish a preserved behaviour from a lost one, which is why `measured`
/// below refuses to report one on its own.
///
/// SO WHY BUILD IT. Because the app can find out in about a minute, and the
/// alternative is arguing. A blend costs a multiply-add over 197,774 numbers,
/// runs on a phone, and can be handed straight to a bench that will run it in
/// physics. That is a measurement where there was a hunch, and this app is
/// built for exactly that trade — the table above cost about four minutes and
/// settles an argument. What it must never do is present the file loading as
/// evidence that the blend works: those are different claims and only one of
/// them is free.
public enum PolicyBlend {

    /// One network in the mixture, with the share it takes.
    public struct Ingredient: Equatable, Sendable {
        /// What the file was called, for the card and the receipt.
        public let name: String
        /// SHA-256 over the source policy's parameters. THE ONLY THING THAT
        /// IDENTIFIES WHICH NETWORK THIS ACTUALLY WAS — a filename is a label
        /// anybody can retype, and a blend whose ingredients cannot be named
        /// exactly is a result nobody can reproduce.
        public let fingerprint: String?
        public let share: Double

        public init(name: String, fingerprint: String?, share: Double) {
            self.name = name; self.fingerprint = fingerprint; self.share = share
        }
    }

    public enum Refusal: Error, Equatable {
        case needsTwo
        case sharesDoNotSum(Double)
        case negativeShare(String)

        public var message: String {
            switch self {
            case .needsTwo:
                return "A blend needs at least two policies. One policy blended with nothing is "
                     + "that policy, and this app already has it."
            case .sharesDoNotSum(let total):
                return "The shares add up to \(String(format: "%.3f", total)), not 1. A mixture "
                     + "whose parts do not make a whole is not an average of anything — scale "
                     + "the numbers so they sum to one."
            case .negativeShare(let name):
                return "\(name) has a negative share. Subtracting one network from another is a "
                     + "different operation with a different meaning, and nothing here has "
                     + "measured what it does to a duck."
            }
        }
    }

    /// Mix the parameters. Every ingredient must be the same architecture, and
    /// `DuckPolicy` has already guaranteed that by loading them.
    public static func mix(
        _ policies: [(parameters: (mean: [Float], std: [Float], layers: [DuckPolicyWriter.Layer]),
                      share: Double)]
    ) throws -> Data {
        guard policies.count >= 2 else { throw Refusal.needsTwo }
        let total = policies.reduce(0) { $0 + $1.share }
        guard abs(total - 1) < 1e-6 else { throw Refusal.sharesDoNotSum(total) }

        func blend(_ pick: ((mean: [Float], std: [Float], layers: [DuckPolicyWriter.Layer])) -> [Float])
            -> [Float] {
            var out = [Float](repeating: 0, count: pick(policies[0].parameters).count)
            for (parameters, share) in policies {
                let w = Float(share)
                for (i, v) in pick(parameters).enumerated() { out[i] += v * w }
            }
            return out
        }

        let mean = blend { $0.mean }
        let std = blend { $0.std }
        let layers = (0..<policies[0].parameters.layers.count).map { index -> DuckPolicyWriter.Layer in
            let shape = policies[0].parameters.layers[index]
            return DuckPolicyWriter.Layer(
                weights: blend { $0.layers[index].weights },
                biases: blend { $0.layers[index].biases },
                inputs: shape.inputs, outputs: shape.outputs)
        }
        return try DuckPolicyWriter.encoded(mean: mean, std: std, layers: layers)
    }

    // MARK: - what the screen is allowed to say about it

    /// What a blend IS, before anybody runs it.
    ///
    /// SAID BEFORE, NOT AFTER. A person about to spend a minute on this should
    /// know the prior going in, or the first failure reads as a bug in the app
    /// rather than as the expected outcome it is.
    public static let beforeYouRunIt =
        "Averaging the weights of two networks gives a file that loads — the architecture is "
      + "identical, so the arithmetic always works. Whether it MOVES is another matter, and the "
      + "honest expectation is that it will not. Weight averaging works between checkpoints that "
      + "share an ancestor; these were trained separately, as different tasks, so there is no "
      + "reason the same neuron means the same thing in both. Run it on a bench and find out — "
      + "that takes about a minute and settles it."

    /// The line that must sit next to a blend that has not been run.
    public static let notYetMeasured =
        "This blend has not been run. It loads, which says nothing about whether it works."

    /// What a bench saw, which takes more than a success rate.
    ///
    /// TRAVEL IS HERE BECAUSE UPRIGHTNESS ALONE LIED. See the 75% row in this
    /// type's own doc comment: a blend that lost the entire walk scored a
    /// perfect 16 of 16 on "ends standing". The count and the distance together
    /// separate "it kept working" from "it stopped doing anything", and neither
    /// number can do it alone.
    public struct Behaviour: Equatable, Sendable {
        public let achieves: Int
        public let rollouts: Int
        /// What was actually counted. A rate without its criterion is the shape
        /// of every misleading benchmark.
        public let criterion: String
        /// How far the blend got, in metres, under the command used.
        public let travelled: Double
        /// How far the liveliest INGREDIENT gets under that same command — the
        /// yardstick. Without it there is no way to know whether 0.002 m means
        /// "it failed" or "this was never a motion that travels".
        public let liveliestIngredientTravelled: Double
        public let plant: String

        public init(achieves: Int, rollouts: Int, criterion: String, travelled: Double,
                    liveliestIngredientTravelled: Double, plant: String) {
            self.achieves = achieves; self.rollouts = rollouts; self.criterion = criterion
            self.travelled = travelled
            self.liveliestIngredientTravelled = liveliestIngredientTravelled
            self.plant = plant
        }

        /// Whether the ingredients actually go anywhere. Blending two motions
        /// that both stand still can only ever produce standing still, and
        /// travel says nothing about that case.
        public var ingredientsTravel: Bool { liveliestIngredientTravelled >= 0.05 }

        /// It stayed up but stopped doing the thing. A quarter of the
        /// ingredient's distance is generous: the 75% blend managed 0.2% of it.
        public var wentInertRatherThanFalling: Bool {
            ingredientsTravel && achieves > rollouts / 2
                && travelled < liveliestIngredientTravelled * 0.25
        }
    }

    /// What can be said once a bench has run it.
    ///
    /// THE NUMBER AND ITS CRITERION TRAVEL TOGETHER, and so does the distance,
    /// because those are three facts and any two of them can flatter a blend
    /// that does nothing.
    public static func measured(_ seen: Behaviour) -> String {
        let rate = seen.rollouts > 0 ? Double(seen.achieves) / Double(seen.rollouts) : 0
        let count = "\(seen.achieves) of \(seen.rollouts) — \(seen.criterion)."
        let distance = seen.ingredientsTravel
            ? " It travelled \(m(seen.travelled)) where the liveliest network it was made from "
              + "travels \(m(seen.liveliestIngredientTravelled))."
            : ""

        let verdict: String
        if seen.wentInertRatherThanFalling {
            // THE CASE THE OLD VERSION CALLED A SUCCESS.
            verdict = "It stayed on its feet and stopped doing the thing — passing this criterion "
                    + "only takes standing still, and that is what it is doing. The blend did not "
                    + "keep the behaviour."
        } else if rate == 0 {
            verdict = "It never worked, which is the usual outcome and not a fault in the blend."
        } else if rate < 0.5 {
            verdict = "It sometimes works, which is more than most blends of separately trained "
                    + "networks manage."
        } else {
            verdict = "It mostly works, which is a genuinely surprising result for an average of "
                    + "separately trained networks and worth keeping."
        }
        return "\(count)\(distance) \(seen.plant) \(verdict)"
    }

    private static func m(_ metres: Double) -> String {
        metres < 0.01 ? String(format: "%.0f mm", metres * 1000)
                      : String(format: "%.2f m", metres)
    }

    /// The recipe, in words, for a card or a receipt.
    ///
    /// FINGERPRINTS, NOT FILENAMES. Anybody can call a file
    /// `alpha_walking.onnx`; only the digest says which network it was, and a
    /// blend nobody can reproduce is an anecdote.
    public static func recipe(_ ingredients: [Ingredient]) -> String {
        let parts = ingredients.map { ingredient -> String in
            let percent = String(format: "%.0f%%", ingredient.share * 100)
            guard let print = ingredient.fingerprint, !print.isEmpty else {
                return "\(percent) \(ingredient.name) (no digest, so which network this was "
                     + "cannot be checked)"
            }
            return "\(percent) \(ingredient.name) (\(print.prefix(12)))"
        }
        return parts.joined(separator: " + ")
    }
}
