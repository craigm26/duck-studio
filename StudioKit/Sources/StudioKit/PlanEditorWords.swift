import Foundation

/// Every sentence the plan editor shows, here where `swift test` can read them.
///
/// THE ROUTER IS NAMED AS A PROPOSER EVERYWHERE IT APPEARS. The screen's job is
/// to make it obvious that nothing has been decided until the person decides
/// it: a flagged label says the router was unsure and by how much, a refusal
/// says the router thinks the duck cannot do it, and the Run button is the only
/// thing on the screen that moves anything.
public enum PlanEditorWords {

    public static let title = "Plan with words"
    public static let chip = "Plan it"
    public static let studioRow = "Plan with words"
    public static let studioRowSymbol = "point.3.connected.trianglepath.dotted"

    public static let intro =
        "Say what the duck should do, one thing after another. A router proposes the steps; "
      + "you check them, change anything it got wrong, and then run the plan."
    public static let askPlaceholder = "walk slowly, then turn left, then kick"
    public static let proposeButton = "Propose steps"
    public static let proposing = "The router is reading it…"
    public static let askHeading = "What should it do?"
    public static let stepsHeading = "Steps"
    public static let runHeading = "What will be sent"

    // MARK: - the router's address

    public static let routerHeading = "Router"
    public static let routerPlaceholder = "http://192.168.1.20:8771"
    public static let routerFooter =
        "The router runs on a computer you own, at an address you type — this app has no "
      + "server of its own. Start it with duckbatch's scripts/route_server.py."
    public static let noRouter =
        "Type the router's address first. Without one there is nothing to propose steps."
    public static func notAnAddress(_ typed: String) -> String {
        "\"\(typed)\" is not an address the app can reach. It looks like http://host:8771."
    }
    public static func routerFailed(_ why: String) -> String {
        "The router did not answer: \(why)"
    }
    public static func proposedBy(_ model: String, seconds: Double?) -> String {
        guard let seconds else { return "Proposed by \(model)." }
        return String(format: "Proposed by %@ in %.1f s.", model, seconds)
    }

    // MARK: - one node

    public static func stepNumber(_ n: Int) -> String { "Step \(n)" }
    public static func headName(_ head: DuckIntentPlan.Head) -> String {
        switch head {
        case .action: return "Do"
        case .speed: return "Speed"
        case .head: return "Head"
        case .sound: return "Sound"
        }
    }
    /// The flag: the router was unsure, by its own number.
    public static func unsure(_ head: DuckIntentPlan.Head, confidence: Double) -> String {
        String(format: "Check the %@ — the router was unsure (%.0f%%).",
               headName(head).lowercased(), confidence * 100)
    }
    public static let refusal = "The router thinks this is not something the duck can do."
    public static let discard = "Discard step"
    public static let restore = "Keep step"
    public static let discarded = "Discarded — not sent, and recorded as rejected."
    public static let edited = "Changed by you."
    public static func holdFor(_ seconds: Double) -> String {
        String(format: "Hold for %.1f s", seconds)
    }
    public static let moveUp = "Move up"
    public static let moveDown = "Move down"

    // MARK: - running

    public static let runButton = "Run it"
    public static let keepButton = "Keep as a sequence"
    public static let runNeedsBench =
        "Plans run from the Control tab, against the simulator or a bench. Keep this one and it "
      + "will be on the Sequences shelf there."
    public static func thenSkill(_ name: String) -> String {
        "Then load \(name) when the moves finish."
    }
    public static func kept(_ name: String) -> String {
        "Kept as \(name), on the Sequences shelf in Control."
    }
    public static func flaggedLeft(_ n: Int) -> String {
        n == 1 ? "1 label is still flagged. You can run anyway; it will go as proposed."
               : "\(n) labels are still flagged. You can run anyway; they will go as proposed."
    }
    public static let recorded =
        "What you kept, changed and discarded was written to this phone's feedback log."
}
