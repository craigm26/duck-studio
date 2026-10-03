import Foundation

/// The one-line descriptions under the Studio tab's rows.
///
/// ONE LINE EACH, BECAUSE THE TAB IS A LIST OF PLACES. The screens behind the rows explain
/// themselves; a row only has to say which door this is. `StudioHubWordsTests` holds every line
/// to 60 characters so none wraps into a paragraph on a phone.
public enum StudioHubWords {
    public static let shoot = "Teach a duck to score, in real physics."
    public static let motions = "Moves you made or recorded."
    public static let scenes = "Floors, steps and walls to try moves against."
    public static let draft = "Describe a move; a model writes it."
    public static let plan = "Say several steps; edit the plan; run it."
    public static let mimic = "Stand in front of the camera; the duck copies."
    public static let compare = "Watch two, pick the better one."

    public static let measure = "Run on a physics bench on your network."
    public static let tune = "Nudge a network toward a command."
    public static let weights = "Search a whole network on the bench."
    public static let hub = "Rent a GPU and train with Pollen's trainer."
    public static let moveSearch = "Search a move's poses and timing."
    public static let challenges = "Score a published entry, then beat it."
    public static let evaluations = "Measure a network the way others can check."
    public static let multiDuck = "One question, asked of two ducks at once."

    public static let toolsRow = "Training and measuring tools"
    public static let toolsLine = "Learn explains them one at a time, then turns them on."

    public static let all: [String] = [shoot, motions, scenes, draft, plan, mimic, compare,
                                       measure, tune, weights, hub, moveSearch, challenges,
                                       evaluations, multiDuck, toolsLine]
}
