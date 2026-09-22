import Foundation

/// How much of itself the app puts in front of you.
///
/// TWO AUDIENCES ARRIVED AT DIFFERENT TIMES AND THE APP NEVER NOTICED. It was
/// built for people who train these policies — sixty-one observation slots, a
/// z-score per input, a Jacobian ranking what the network listens to, and a
/// structural dump of any file it refuses. Then it grew a Control tab, a pad, a
/// camera that reads a person's pose, and a shelf of modes, and a second
/// audience turned up: somebody who has a Microduck and wants it to walk.
/// Everything is still shown to both, which serves the first badly by burying
/// the inspector under toys and the second badly by opening a network editor at
/// them.
///
/// NOTHING IS DELETED AND NOTHING IS UNREACHABLE. This is the `ReleaseGates`
/// idea applied to a person instead of a release: the code stays, the surface
/// changes, and Simple SAYS what it is not showing and where the switch is. A
/// mode that quietly truncated the app would be worse than no mode at all,
/// because the RL person who installed this for the refusal screen would think
/// it had been removed.
public enum DetailLevel: String, Codable, CaseIterable, Sendable, Identifiable {

    /// Drive it, play with it, record motions. The robot, not the network.
    case simple

    /// Everything, including the parts that are only interesting if you train
    /// these policies yourself.
    case full

    public var id: String { rawValue }

    /// THE DEFAULT IS `full`, AND THAT IS DELIBERATE. Every person who has this
    /// app today got it for the inspector, and quietly hiding it from them on
    /// update would be the app taking something away without asking. A new
    /// install is offered the choice on first run; an existing one keeps what
    /// it has always had until somebody chooses otherwise.
    public static let installedDefault = DetailLevel.full

    public var name: String {
        switch self {
        case .simple: return "Simple"
        case .full: return "Everything"
        }
    }

    public var blurb: String {
        switch self {
        case .simple:
            return "Drive the duck, play with it, record motions. The screens that "
                 + "take a neural network apart stay out of the way."
        case .full:
            return "Every screen, including the observation editor, the z-scores, "
                 + "the sensitivity ranking and the structural dump behind a refused file."
        }
    }

    /// A part of the app that only some people want.
    ///
    /// Each case is a real screen or section that exists today, not a category
    /// invented to fill the enum. Adding one means a screen changed.
    public enum Surface: String, CaseIterable, Sendable, Identifiable {
        /// The sixty-one observation slots, the z-score strip, and the
        /// sensitivity ranking — `BenchView`.
        case networkInternals
        /// A policy's op sequence, initializer dims, parameter count and the
        /// structural table under a refusal — `PolicyListView`.
        case policyForensics
        /// Running a policy on a machine that has physics.
        case physicsBench
        /// Writing a request to train a new policy somewhere with a GPU.
        case training
        /// Pushing a policy or a motion to Hugging Face.
        case publishing

        public var id: String { rawValue }

        /// What it is called on screen, in words that do not assume the job.
        public var name: String {
            switch self {
            case .networkInternals: return "Network internals"
            case .policyForensics: return "Why a file was refused"
            case .physicsBench: return "Physics bench"
            case .training: return "Training requests"
            case .publishing: return "Publishing"
            }
        }
    }

    /// Whether this level shows that surface.
    ///
    /// SIMPLE HIDES FIVE THINGS AND NO MORE. Not the Control tab, not the
    /// modes, not drafting a motion from a sentence, not the scenes — those are
    /// for anybody with a duck. The line is drawn at screens that are only
    /// legible if you already know what a policy is.
    public func shows(_ surface: Surface) -> Bool {
        switch self {
        case .full: return true
        case .simple: return false
        }
    }

    /// What Simple is holding back, for the sentence that offers the way in.
    ///
    /// THE APP HAS TO SAY THIS. Hiding a screen silently is how somebody
    /// concludes a feature was removed; naming it and the switch is the whole
    /// difference between a mode and a missing feature.
    public var withheldNote: String? {
        guard self == .simple else { return nil }
        let names = Surface.allCases.map(\.name)
        return "Simple is not showing: " + names.joined(separator: ", ")
             + ". Settings → Detail turns them back on."
    }

    /// The sentence a hidden section leaves in its place, naming itself.
    public static func placeholder(for surface: Surface) -> String {
        "\(surface.name) is hidden while Detail is set to Simple. "
        + "Settings → Detail shows it again."
    }
}
