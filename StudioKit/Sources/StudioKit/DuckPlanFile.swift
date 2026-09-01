import Foundation

/// A retrieval plan, in a format this app both writes AND reads.
///
/// WHY THIS EXISTS. A fetch drafted here could only be exported as a `.duck` —
/// quackd's task format — and this app has no reader for one. So the loop was
/// open at the worst possible point: somebody describes a fetch, the app works
/// out whether the duck can manage it, writes a file, and then refuses to take
/// that file back. The Intents screen said so in as many words: "Duck Studio
/// writes these for quackd to run somewhere else and has no reader for one, so
/// nothing was added."
///
/// AND IT DEPENDS ON NOBODY. `duck-plan/1` is ours. A `.duck` export stays
/// available for anyone who wants to drive quackd with it, but it is no longer
/// the only thing a plan can become, and nothing about keeping a plan in this
/// app now hinges on another project's schema.
///
/// IT STORES THE MEASUREMENT, NOT THE STEPS. `Retrieval.plan(for:)` derives the
/// steps, the refusals and the timing from the object's mass, thickness,
/// distance and friction — against numbers this app measures. Freezing the
/// derived plan into the file would mean a plan written last month disagreeing
/// with the app that opened it, and the file winning. So the file carries what
/// was MEASURED and the plan is recomputed every time it is read.
public struct DuckPlanFile: Equatable, Sendable {

    public static let format = "duck-plan/1"
    /// Formats this reader accepts. One so far; the set exists because the
    /// motion format already needed two and learned that lesson.
    public static let readableFormats: Set<String> = ["duck-plan/1"]

    public let name: String
    public let stick: Retrieval.Stick
    /// The sentence somebody typed, when there was one. Kept because it is the
    /// only record of what was ASKED for, as opposed to what was measured.
    public let asked: String?
    /// Where it came from — a person, or a named model.
    public let provenance: String

    public init(name: String, stick: Retrieval.Stick, asked: String?, provenance: String) {
        self.name = name; self.stick = stick
        self.asked = asked; self.provenance = provenance
    }

    /// The plan itself, recomputed here and now.
    public var plan: Retrieval.Plan { Retrieval.plan(for: stick) }

    // MARK: - writing

    public func encoded() throws -> Data {
        var object: [String: Any] = [
            "format": DuckPlanFile.format,
            "name": name,
            "provenance": provenance,
            "object": [
                "grams": stick.grams,
                "thicknessMillimetres": stick.thicknessMillimetres,
                "metresAway": stick.metresAway,
                "floorFriction": stick.floorFriction,
            ] as [String: Any],
        ]
        if let height = stick.graspHeightMillimetres {
            var measured = object["object"] as! [String: Any]
            measured["graspHeightMillimetres"] = height
            object["object"] = measured
        }
        if let asked, !asked.isEmpty { object["asked"] = asked }
        return try JSONSerialization.data(withJSONObject: object,
                                          options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - reading

    public enum ReadError: Error, Equatable {
        case notJSON
        case wrongFormat(String)
        case missing(String)

        public var message: String {
            switch self {
            case .notJSON:
                return "That file is not a plan this app wrote — it is not even JSON."
            case .wrongFormat(let found):
                return "That plan is in format \"\(found)\", which this version does not read."
            case .missing(let field):
                return "That plan is missing \(field), so the duck's side of it cannot be worked "
                     + "out. It may have been written by a newer version."
            }
        }
    }

    public static func read(_ data: Data) throws -> DuckPlanFile {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        guard let format = top["format"] as? String else { throw ReadError.missing("a format") }
        guard readableFormats.contains(format) else { throw ReadError.wrongFormat(format) }
        guard let measured = top["object"] as? [String: Any] else {
            throw ReadError.missing("the object it is about")
        }
        // EVERY NUMBER IS REQUIRED. A plan with a defaulted mass is a plan about
        // a different object, and it would still print a confident verdict.
        func number(_ key: String) throws -> Double {
            guard let value = measured[key] as? Double else { throw ReadError.missing(key) }
            return value
        }
        let stick = Retrieval.Stick(
            grams: try number("grams"),
            thicknessMillimetres: try number("thicknessMillimetres"),
            metresAway: try number("metresAway"),
            graspHeightMillimetres: measured["graspHeightMillimetres"] as? Double,
            floorFriction: try number("floorFriction"))

        return DuckPlanFile(
            name: (top["name"] as? String) ?? "Fetch",
            stick: stick,
            asked: top["asked"] as? String,
            provenance: (top["provenance"] as? String) ?? "Written here")
    }

    /// The file name this becomes, without a path.
    public var fileName: String { "\(name).duckplan" }
}
