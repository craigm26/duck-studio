import Foundation
import DuckKit

/// What a person reads about a finished run: the sentences, the share
/// paragraph, and one self-contained HTML page.
///
/// THE PAGE IS OURS AND IT SAYS SO. `inspect-robots view` renders the same log
/// their way, and their render is the one to trust: it is written by the
/// library that defines the format, and it cannot be wrong about the format in
/// the way a second implementation can. So this page exists for the reader who
/// has a phone and no Python, it carries the honesty sentences their page has
/// no field for, and `notTheirRender` is the last line of it.
///
/// NO NETWORK, NO SCRIPT, NO IMAGE. One document, colours from `Palette` so
/// `PaletteTests` already covers their contrast, and every interpolated string
/// through `escaped(_:)` exactly once. A report that fetched a stylesheet would
/// be a report that goes blank on a plane, and a report with a script in it
/// would be a file nobody should open twice.
public enum EvalReport {

    // MARK: - numbers, in one place

    /// A measured number as a person reads it: four places, trailing zeros
    /// trimmed, and never fewer than one place, so a success rate of one reads
    /// `1.0` rather than `1` and cannot be mistaken for a count.
    public static func number(_ value: Double, places: Int = 4) -> String {
        guard value.isFinite else { return notFinite }
        var text = String(format: "%.\(places)f", value)
        guard text.contains(".") else { return text }
        while text.hasSuffix("0"), !text.hasSuffix(".0") { text.removeLast() }
        return text
    }

    /// L5 of the status rules, on the page. A metric that quietly became null
    /// is a metric nobody investigates, so the word is printed where the number
    /// would have been.
    public static let notFinite = "not a number"

    // MARK: - reading the log

    /// The bench route this log came from, out of the first scene that names
    /// one.
    public static func route(_ log: EvalLog) -> String? {
        for sample in log.samples {
            if let value = sample.sceneMetadata[EvalMeta.route]?.stringValue { return value }
        }
        return nil
    }

    /// Whether the task was one of the published challenge grids, which is the
    /// only case where a leaderboard is even a question.
    public static func isGrid(_ log: EvalLog) -> Bool { challenge(log) != nil }

    public static func challenge(_ log: EvalLog) -> Challenge? {
        guard let route = route(log) else { return nil }
        if route == EvalTask.Route.climb.path { return .stairs }
        if route == EvalTask.Route.chase.path { return .ball }
        return nil
    }

    /// `scene.mjb 3f8c9ab9b409`, from the machine facts rather than from the
    /// identity string, so a log written elsewhere with no plant block says
    /// nothing rather than something parsed out of a name.
    public static func world(_ log: EvalLog) -> String? {
        guard let name = log.eval.embodimentInfo[EvalMeta.plantName]?.stringValue else {
            return nil
        }
        guard let digest = log.eval.embodimentInfo[EvalMeta.plantDigest]?.stringValue,
              !digest.isEmpty else { return name }
        return "\(name) \(digest.prefix(DuckBench.digestShown))"
    }

    /// Every drop height the epoch axis walked, as the scene metadata recorded
    /// them, so an archived log's axis is read off numbers rather than out of
    /// prose.
    public static func drops(_ sample: EvalLog.Sample) -> [Double] {
        (sample.sceneMetadata[EvalMeta.dropHeights]?.arrayValue ?? []).compactMap(\.doubleValue)
    }

    /// Whether this app wrote the log, asked of the log alone.
    ///
    /// IT IS `eval.inspect_robots_version` AND NOT THE ORIGIN FLAG. A file read
    /// back off this phone's own disk has no run behind it any more, and a file
    /// somebody handed over may have been written by another copy of this app.
    /// The producer sentence is the one thing that travels inside the file and
    /// says which, and `EvalRun.wroteItSaid` is the reader of it that the shelf
    /// already trusts. Everything this app says in the first person about how a
    /// number was measured is gated on this.
    public static func wroteHere(_ log: EvalLog) -> Bool {
        EvalRun.wroteItSaid(from: log.eval.inspectRobotsVersion) != nil
    }

    /// The bench's own criterion out of a log, or nil where the file carries
    /// the reader's placeholder instead of anything a bench said.
    public static func statedCriterion(_ log: EvalLog) -> String? {
        DuckBench.statedCriterion(log.eval.policyConfig[EvalMeta.criterion]?.stringValue)
    }

    /// Whether any trial in the log carries the bench's reward terms, which is
    /// what makes the sentence about them a sentence about something.
    static func anyTermsRecorded(_ log: EvalLog) -> Bool {
        log.samples.contains { sample in
            sample.trialMetadata.contains { $0[EvalMeta.terms] != nil }
        }
    }

    /// The scorer this app knows by that name, or nil for a name from
    /// somewhere else. Used only to decide what a column means; a column with
    /// no answer is still drawn, with its own name over it.
    public static func scorer(named name: String) -> EvalScorer? {
        for set in EvalScorerSet.all {
            if let found = set[name] { return found }
        }
        return nil
    }

    /// Metric names in reading order: the success scorers, then the evidence
    /// that keeps them honest, then context, then cost, then anything this app
    /// has no word for.
    ///
    /// SUCCESS AND MOTION EVIDENCE ARE ADJACENT AND THAT IS THE WHOLE POINT.
    /// `success_at_end` is passed perfectly by a duck that never moves, so a
    /// page with the success tiles in one block and the travel tiles in
    /// another is a page whose first block is a lie by omission.
    public static func ordered(_ names: [String]) -> [String] {
        func rank(_ name: String) -> Int {
            switch scorer(named: name)?.role {
            case .success: return 0
            case .motionEvidence: return 1
            case .context: return 2
            case .cost: return 3
            case nil: return 4
            }
        }
        return names.sorted {
            rank($0) == rank($1) ? $0 < $1 : rank($0) < rank($1)
        }
    }

    // MARK: - the sentences

    public static var notTheirRender: String { EvalText.notTheirRender }

    /// Claim 40: what the epochs of one scene did, said honestly in both
    /// directions.
    ///
    /// A ZERO SPREAD IS NOT A CONFIDENCE INTERVAL. These episodes are
    /// deterministic: the same drop height gives the same answer every time, so
    /// eight epochs agreeing means the drop height did not matter for that
    /// number, and nothing more. A page that printed a standard deviation of
    /// zero beside a metric would be inviting exactly the reading this sentence
    /// exists to prevent.
    ///
    /// THE DROP HEIGHT CLAUSE NEEDS A DROP HEIGHT, which is what `hasDropAxis`
    /// is for. A grid cell is one episode and an imported log may have varied
    /// anything at all between its epochs, so telling either reader that "the
    /// drop height changed nothing here" is a sentence about a control that run
    /// never had. Without an axis this says what it can see and stops.
    public static func spreadSaid(_ values: [Double], hasDropAxis: Bool = false) -> String {
        let finite = values.filter { $0.isFinite }
        guard let low = finite.min(), let high = finite.max() else {
            return "Nothing was scored here, so there is no spread to report."
        }
        if low == high {
            guard hasDropAxis else {
                return "Every epoch answered \(number(low)). What varied between them is whatever "
                     + "this run's own axis was, and agreement is not a confidence interval."
            }
            return "Every epoch answered \(number(low)). These episodes are deterministic, so "
                 + "epochs agreeing means the drop height changed nothing here, and it is not a "
                 + "confidence interval."
        }
        guard hasDropAxis else {
            return "Lowest \(number(low)), highest \(number(high)), across "
                 + "\(EvalEpochs.counted(finite.count).lowercased()) epochs. The spread is what "
                 + "this run's own axis changed and it is not a margin of error."
        }
        return "Lowest \(number(low)), highest \(number(high)), across "
             + "\(EvalEpochs.counted(finite.count).lowercased()) epochs. The spread is what the "
             + "drop height changed and it is not a margin of error."
    }

    /// The same sentence for a scene, which is where the axis can be read.
    ///
    /// Nil for a scene with one epoch: telling a reader that one number agrees
    /// with itself is noise standing where a fact should be, and it is the
    /// whole of a grid.
    public static func spreadSaid(_ sample: EvalLog.Sample, scorer name: String) -> String? {
        guard sample.epochs.count > 1 else { return nil }
        let values = sample.epochs.compactMap { $0[name] }
        guard !values.isEmpty else { return nil }
        return spreadSaid(values, hasDropAxis: !drops(sample).isEmpty)
    }

    /// One scorer's row of a scene, for a screen reader.
    ///
    /// A GRID OF BARE NUMBERS IS UNREADABLE OUT LOUD. VoiceOver walks the cells
    /// of the epoch table one at a time and reads "1.0, 0.0, 1.0" with nothing
    /// saying which epoch or which drop each belongs to. This pairs every cell
    /// with its own column head, names the empty cells rather than leaving a
    /// silence a listener reads as a zero, and is one string so the row is one
    /// element.
    public static func spokenEpochs(_ sample: EvalLog.Sample, scorer name: String) -> String {
        let heights = drops(sample)
        var parts: [String] = []
        for index in sample.epochs.indices {
            var head = "Epoch \(index + 1)"
            if index < heights.count { head += ", dropped from \(number(heights[index])) m" }
            if let value = sample.epochs[index][name] {
                parts.append("\(head), \(number(value))")
            } else {
                parts.append("\(head), \(erroredCell)")
            }
        }
        return parts.isEmpty ? nothingScoredHere : parts.joined(separator: ". ") + "."
    }

    /// What an empty epoch is, in a word, because a blank cell read out loud is
    /// silence and silence reads as a zero.
    public static let erroredCell = "recorded and not scored"

    public static let nothingScoredHere = "Nothing was scored in this scene."

    /// A3: the one sentence that makes a shared log reproducible instead of
    /// merely readable.
    ///
    /// NO SECOND FILE FORMAT. The app already carries three of those and each
    /// one is another thing that can go stale. What a person actually needs to
    /// re-run this is the preset's name, the policy and the world, and all
    /// three are already in the log under names this sentence points at.
    ///
    /// AND IT IS ONLY SAID ABOUT A RUN THIS APP COULD MAKE AGAIN. A log written
    /// somewhere else names a task and a policy this app has never had: the
    /// shipped example is a mock arm reaching for a cube, and telling a reader
    /// to pick "cubepick-reach" in Microduck Studio is an instruction that
    /// cannot be followed. The gate is the producer sentence inside the file
    /// (`wroteHere`), which is the same test the shelf uses to decide whether a
    /// log has an author here at all.
    public static func reproduceSaid(_ log: EvalLog) -> String {
        guard wroteHere(log) else { return reproduceElsewhereSaid }
        let world = world(log) ?? log.eval.embodiment
        return "To run this again: pick \(log.eval.task) in Microduck Studio, pick "
             + "\(log.eval.policy), and point it at a bench running \(world). The same preset "
             + "and the same policy on a bench with that plant digest is the same run; a "
             + "different digest is a different measurement whatever the numbers say."
    }

    /// What is said instead, about a run that happened somewhere else.
    public static let reproduceElsewhereSaid =
        "This run was made somewhere else, so there is no preset here to pick and run again. The "
      + "task, the policy and the body it ran on are named in the file as that run named them, "
      + "and running it again is a question for the tools that wrote it."

    /// What this log says about a seed, or nothing at all.
    ///
    /// THREE CASES, AND THE THIRD IS SILENCE. A log that records a seed says
    /// so, in the sentence that admits the run it came from had one. A log this
    /// app wrote says why there is none, in the words its own axis earns: the
    /// walk presets vary a drop height and the grids vary nothing, and the two
    /// sentences are not interchangeable. A log somebody else wrote that
    /// carries no seed gets neither, because "no route on this bench reads one"
    /// is a claim about this bench and nobody here ran that file.
    ///
    /// Printing the first-person sentence unconditionally and then adding the
    /// foreign one after it was a page that said no seed was recorded and, one
    /// line later, that this log records a seed.
    public static func seedSaid(_ log: EvalLog) -> String? {
        if log.eval.seed != nil { return EvalLogFile.foreignSeedSaid }
        guard wroteHere(log) else { return nil }
        let hasDrops = log.samples.contains { !drops($0).isEmpty }
        return hasDrops ? EvalEpochs.noSeedSaid : EvalEpochs.noSeedOnAGridSaid
    }

    /// How the episodes of this run were recorded, chosen by the route it ran.
    ///
    /// A GRID RECORDS NOTHING AND REPORTS NO TICKS. `/climb` and `/chase`
    /// answer with a cell's numbers, so the sentences about a traced first drop
    /// and about a verdict offered on it describe a mechanism the run did not
    /// use, beside `traced: false` on every trial and a `total_steps` of zero.
    public static func recordingCaveats(_ log: EvalLog) -> [String] {
        guard !isGrid(log) else {
            return [EvalRun.noStepsOnAGridSaid, EvalTrace.noTraceOnAGridSaid]
        }
        return [EvalRun.stepCountsSaid, EvalTrace.firstDropOnlySaid,
                EvalVerdict.recordedNotScoredSaid]
    }

    /// Everything a page says about how this run was measured and what it will
    /// not claim, in one list, chosen by the route and by whether this app made
    /// the measurement at all.
    ///
    /// AN IMPORTED LOG GETS NONE OF THEM. Every sentence in this list is a
    /// first-person account of how this app's own bench works: nothing timed
    /// the policy, no frames were stored, the terms under each trial are the
    /// bench's. Printed over a file from somewhere else they are claims about
    /// somebody else's run made by an app that was not there, and two of them
    /// were flatly contradicted by the file's own stats. So a foreign log's
    /// page carries what the file says and nothing this app made up for it.
    public static func caveats(for file: EvalLogFile) -> [String] {
        let log = file.log
        guard wroteHere(log) else { return [] }
        var said = recordingCaveats(log)
        if anyTermsRecorded(log) { said.append(EvalScorer.termsAreNotScoresSaid) }
        said.append(EvalRun.erroredNotScoredSaid)
        said.append(EvalRun.noLatencySaid)
        said.append(EvalRun.noFramesSaid)
        said.append(EvalScorer.notEmittedHere)
        said.append(EvalEmbodiment.digestIsIdentitySaid)
        return said
    }

    /// The two stats fields this app never fills, when a foreign log does fill
    /// them. Labels rather than sentences: the value is the file's.
    public static let latencyLabel = "Mean inference latency, as the file records it"
    public static let framesLabel = "Frames directory, as the file records it"

    /// A7: a log is a record and it is not an entry.
    public static let leaderboardIsTheChallengeScreen =
        "This is a record of a run and not a submission. The challenge screen's own Submit is "
      + "the only way onto a leaderboard, because a leaderboard row carries the move and all of "
      + "its per cell answers and this file carries the run."

    /// Said above the share sheet.
    public static let whatIsShared =
        "Two files: the log, which is the artefact their tools read, and this app's own report "
      + "of it, which is one page with no network in it. Nothing leaves the phone until you "
      + "pick where it goes."

    /// `eval.py`'s aggregation rule, said where the tiles are, because a mean
    /// of means is not what a reader assumes a mean is.
    public static let meanOverScenesSaid =
        "Every tile is the mean over the scenes that carry it, which is inspect-robots' own "
      + "rule, so a scene with more epochs does not weigh more than a scene with fewer."

    /// The horizon, in both units their viewer prints it in.
    public static func horizonSaid(seconds: Double, steps: Int) -> String {
        "The horizon was \(number(seconds, places: 2)) seconds, which is \(steps) control "
      + "ticks. " + EvalTask.maxStepsSaid
    }

    /// The first thing a stopped run says about itself, in the share paragraph
    /// and nowhere else, because everything after it is a partial run's
    /// numbers.
    public static let cancelledLead =
        "Cancelled partway through, and what follows is only what ran before it stopped."

    /// Said when a log arrived from somewhere else and is being passed on.
    public static let passedOnSaid =
        "This log was written somewhere else and is passed on exactly as it arrived."

    /// The closing clause of a share, which is the one claim this app has to
    /// keep repeating.
    public static func wroteItSaid(_ wroteIt: String) -> String {
        "Written by \(wroteIt). Nothing here has met a real Microduck."
    }

    // MARK: - the share paragraph

    /// One paragraph, from measured values only.
    ///
    /// THE RULES IT KEEPS, each with a test: it always names the plant digest,
    /// because a number without one is not comparable with anything; it names
    /// the errored trials when there are any; it leads with the word cancelled
    /// when the run was stopped; it never says trained, learned or improved,
    /// because nothing here trains anything; and it carries no em dash.
    public static func shareSentence(_ file: EvalLogFile) -> String {
        let log = file.log
        var parts: [String] = []
        if log.status == .cancelled { parts.append(cancelledLead) }
        parts.append("\(log.eval.policy) ran \(log.eval.task) on \(log.eval.embodiment).")
        // A grid is fourteen scenes, and fourteen lines pasted into a chat
        // window is not a paragraph. Under the cap every scene is its own line,
        // because that is what stops a mean hiding the one command the policy
        // cannot do; over it, the count and the metrics say the same thing
        // without pretending to be prose.
        if log.samples.count > sceneListCap {
            parts.append(gridLine(log))
        } else {
            for sample in log.samples { parts.append(sceneLine(sample)) }
        }
        if log.results.erroredTrials > 0 {
            parts.append("\(log.results.erroredTrials) of \(log.results.totalTrials) trials "
                       + "errored and none of them is in any number above.")
        } else if log.results.totalTrials > 0 {
            parts.append("Nothing errored.")
        }
        if let world = world(log) {
            parts.append("Measured on \(world), so a number from another world is not "
                       + "comparable with this one.")
        }
        parts.append(file.wroteIt.map { wroteItSaid($0) } ?? passedOnSaid)
        return parts.joined(separator: " ")
    }

    /// How many scenes get a line of their own before the paragraph becomes a
    /// list. The three walk commands fit, and a fourteen cell grid does not.
    public static let sceneListCap = 4

    /// A grid in one line: how many cells met the criterion, and the metrics
    /// as measured. Nothing here is a rank and nothing here is a submission.
    static func gridLine(_ log: EvalLog) -> String {
        let met = log.samples.filter {
            ($0.reduced[EvalScorer.successAtEnd.name] ?? 0) >= 0.5
        }.count
        var line = "\(log.samples.count) scenes, \(met) of them met the bench's own criterion."
        let measured = ordered(Array(log.results.metrics.keys)).compactMap { name -> String? in
            guard let value = log.results.metrics[name] else { return nil }
            return "\(name) \(number(value))"
        }
        if !measured.isEmpty {
            line += " Across the scenes: " + measured.joined(separator: ", ") + "."
        }
        return line
    }

    /// One scene of the share paragraph: how many ended standing, and how far
    /// it went, because the first number without the second rewards stillness.
    static func sceneLine(_ sample: EvalLog.Sample) -> String {
        let successes = sample.epochs.compactMap { $0[EvalScorer.successAtEnd.name] }
        let standing = successes.filter { $0 >= 0.5 }.count
        var line = "\(sample.sceneID): "
        if successes.isEmpty {
            line += "nothing scored"
        } else {
            line += "\(standing) of \(successes.count) ended standing"
        }
        if let travelled = sample.reduced[EvalScorer.travelled.name] {
            line += ", \(number(travelled)) m travelled"
        }
        return line + "."
    }

    // MARK: - escaping, once

    /// Every interpolated string on the page goes through this, exactly once.
    ///
    /// THE TWO LINE SEPARATORS ARE IN THE LIST for the reason they are in
    /// `EvalText`: U+2028 and U+2029 survive a copy and paste and break a line
    /// somewhere nobody chose. There is no script on this page and there is not
    /// going to be one, and escaping them costs nothing.
    public static func escaped(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            case "\u{2028}": out += "&#8232;"
            case "\u{2029}": out += "&#8233;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    // MARK: - the page

    static func hex(_ token: Palette.Token, _ scheme: Palette.Scheme) -> String {
        Palette.color(token, in: scheme).hexString
    }

    /// The whole report, as one string of HTML.
    public static func html(_ file: EvalLogFile) -> String {
        let log = file.log
        var body = ""

        // Who and what, before any number.
        body += "<header>"
        body += "<p class=\"status \(escaped(log.status.rawValue))\">"
             + escaped(statusShown(log.status)) + "</p>"
        body += "<h1>" + escaped(log.eval.task) + "</h1>"
        body += "<dl class=\"identity\">"
        body += row("Policy", log.eval.policy)
        body += row("Embodiment", log.eval.embodiment)
        if let digest = log.eval.embodimentInfo[EvalMeta.plantDigest]?.stringValue {
            body += row("Plant sha256", digest)
        }
        body += row("Started", log.stats.startedAt)
        body += row("Finished", log.stats.completedAt)
        body += row("Took", number(log.stats.durationSeconds, places: 3) + " s")
        body += row("Written by", log.eval.inspectRobotsVersion)
        body += "</dl>"
        if file.origin == .imported {
            body += note(EvalLogFile.importedSaid)
        }
        body += note(reproduceSaid(log))
        body += "</header>"

        // The sentences a reader must have before the tiles. Every one of them
        // is either the file's own or one this app is entitled to say about
        // this file, so a log that has none of them gets no empty block.
        var before = ""
        if let seed = seedSaid(log) { before += note(seed) }
        if let axis = log.eval.policyConfig[EvalMeta.epochAxis]?.stringValue {
            before += note(axis)
        }
        // QUOTED MEANS SOMEBODY SAID IT. The three bench readers default a
        // missing criterion to one word of this app's own, so a bench that
        // said nothing would otherwise have that word set as a quotation under
        // "what the bench said ending standing means".
        if let criterion = statedCriterion(log) {
            before += "<p class=\"quoted\">" + escaped(criterion) + "</p>"
        }
        if let seconds = log.eval.maxSeconds, let steps = log.eval.maxSteps {
            before += note(horizonSaid(seconds: seconds, steps: steps))
        }
        if !before.isEmpty {
            body += "<section><h2>Before the numbers</h2>" + before + "</section>"
        }

        // The tiles, success and evidence adjacent.
        body += "<section><h2>What it measured</h2>"
        let names = ordered(Array(log.results.metrics.keys))
        if names.isEmpty {
            body += note(EvalRun.erroredNotScoredSaid)
        } else {
            body += "<div class=\"tiles\">"
            for name in names {
                let value = log.results.metrics[name]
                body += "<div class=\"tile\"><p class=\"value\">"
                     + escaped(value.map { number($0) } ?? notFinite)
                     + "</p><p class=\"name\">" + escaped(name) + "</p>"
                if let said = scorer(named: name)?.said {
                    body += "<p class=\"said\">" + escaped(said) + "</p>"
                }
                body += "</div>"
            }
            body += "</div>"
        }
        body += note(meanOverScenesSaid)
        body += "</section>"

        // One row per scene.
        body += "<section><h2>Scene by scene</h2>"
        body += "<div class=\"scroll\"><table><thead><tr><th>Scene</th><th>State</th>"
        for name in names { body += "<th>" + escaped(name) + "</th>" }
        body += "</tr></thead><tbody>"
        for sample in log.samples {
            body += "<tr><td>" + escaped(sample.sceneID) + "</td><td>"
                 + escaped(statusShown(sample.status)) + "</td>"
            for name in names {
                let value = sample.reduced[name]
                body += "<td>" + escaped(value.map { number($0) } ?? "") + "</td>"
            }
            body += "</tr>"
        }
        body += "</tbody></table></div>"
        body += "</section>"

        // Every trial, with what it was and whether anybody could watch it.
        for sample in log.samples {
            body += "<section><h2>" + escaped(sample.sceneID) + "</h2>"
            if let instruction = sample.instruction {
                body += "<p class=\"quoted\">" + escaped(instruction) + "</p>"
            }
            if let error = sample.error {
                body += "<p class=\"refused\">" + escaped(error) + "</p>"
            }
            // The spread belongs to a scene with an axis. A grid cell is one
            // episode, and telling a reader that one number agrees with itself
            // fourteen times is noise standing where a fact should be.
            for name in names {
                if let spread = spreadSaid(sample, scorer: name) {
                    body += note("\(name): " + spread)
                }
            }
            body += "<div class=\"scroll\"><table><thead><tr><th>Epoch</th><th>Drop</th>"
                 + "<th>Ended</th><th>Ticks</th><th>Watched</th><th>Verdict</th>"
            for name in names { body += "<th>" + escaped(name) + "</th>" }
            body += "</tr></thead><tbody>"
            for index in sample.epochs.indices {
                let metadata = index < sample.trialMetadata.count
                    ? sample.trialMetadata[index] : [:]
                body += "<tr><td>" + String(index + 1) + "</td>"
                body += "<td>"
                     + escaped(metadata[EvalMeta.dropMetres]?.doubleValue
                                   .map { number($0) } ?? "") + "</td>"
                let reason = index < sample.terminationReasons.count
                    ? sample.terminationReasons[index] : nil
                body += "<td>" + escaped(reason ?? "") + "</td>"
                body += "<td>"
                     + escaped(metadata[EvalMeta.ticksReported]?.integerValue
                                   .map { String($0) } ?? "") + "</td>"
                let traced = metadata[EvalMeta.traced]?.boolValue ?? false
                body += "<td>" + (traced ? "yes" : "no") + "</td>"
                let judgement = index < sample.operatorJudgements.count
                    ? sample.operatorJudgements[index] : nil
                body += "<td>" + escaped(judgement ?? "") + "</td>"
                for name in names {
                    body += "<td>"
                         + escaped(sample.epochs[index][name].map { number($0) } ?? "")
                         + "</td>"
                }
                body += "</tr>"
            }
            body += "</tbody></table></div>"
            for index in sample.trialMetadata.indices {
                if let why = sample.trialMetadata[index][EvalMeta.why]?.stringValue {
                    body += "<p class=\"refused\">Epoch \(index + 1): " + escaped(why) + "</p>"
                }
            }
            for index in sample.operatorNotes.indices {
                if let text = sample.operatorNotes[index] {
                    body += "<p class=\"quoted\">Epoch \(index + 1): " + escaped(text) + "</p>"
                }
            }
            body += "</section>"
        }

        // What the file will not claim, which is the half their page has no
        // field for. For a log from somewhere else the list is empty and the
        // block carries the two fields this app never fills and that file
        // sometimes does, under the file's own name.
        var closing = ""
        for said in caveats(for: file) { closing += note(said) }
        if !wroteHere(log) {
            var stated = ""
            if let latency = log.stats.meanInferenceLatencySeconds {
                stated += row(latencyLabel, number(latency, places: 6) + " s")
            }
            if let frames = log.stats.framesDir {
                stated += row(framesLabel, frames)
            }
            if !stated.isEmpty {
                closing += note(EvalLogFile.fromTheFile)
                closing += "<dl class=\"identity\">" + stated + "</dl>"
            }
        }
        if isGrid(log) { closing += note(leaderboardIsTheChallengeScreen) }
        if let error = log.error {
            closing += "<p class=\"refused\">" + escaped(error) + "</p>"
        }
        if !closing.isEmpty {
            body += "<section><h2>What this does not claim</h2>" + closing + "</section>"
        }

        body += "<footer>"
        body += note(Provenance.independenceShort)
        body += note(EvalLogFile.howToRead)
        body += "<p class=\"last\">" + escaped(notTheirRender) + "</p>"
        body += "</footer>"

        return page(title: log.eval.task, body: body)
    }

    static func row(_ label: String, _ value: String) -> String {
        "<dt>" + escaped(label) + "</dt><dd>" + escaped(value) + "</dd>"
    }

    static func note(_ text: String) -> String {
        "<p class=\"note\">" + escaped(text) + "</p>"
    }

    /// Their four words, capitalised the way their own viewer capitalises them.
    public static func statusShown(_ status: EvalLog.Status) -> String {
        switch status {
        case .started: return "Started"
        case .success: return "Success"
        case .error: return "Error"
        case .cancelled: return "Cancelled"
        }
    }

    static func page(title: String, body: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escaped(title))</title>
        <style>
        \(style)
        </style>
        </head>
        <body>
        <main>
        \(body)
        </main>
        </body>
        </html>
        """
    }

    /// The whole stylesheet, from `Palette` in both schemes, so the page a
    /// person keeps looks like the app it came out of and its contrast is
    /// already under test in `PaletteTests`.
    static var style: String {
        func block(_ scheme: Palette.Scheme) -> String {
            """
            --ground: \(hex(.backgroundPrimary, scheme));
            --sunk: \(hex(.backgroundSecondary, scheme));
            --card: \(hex(.surfacePrimary, scheme));
            --ink: \(hex(.textPrimary, scheme));
            --quiet: \(hex(.textSecondary, scheme));
            --faint: \(hex(.textTertiary, scheme));
            --brand: \(hex(.brandPrimary, scheme));
            --rule: \(hex(.separator, scheme));
            --bad: \(hex(.critical, scheme));
            --good: \(hex(.success, scheme));
            """
        }
        return """
        :root { \(block(.light)) }
        @media (prefers-color-scheme: dark) { :root { \(block(.dark)) } }
        * { box-sizing: border-box; }
        body { margin: 0; background: var(--sunk); color: var(--ink);
               font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
        main { max-width: 46rem; margin: 0 auto; padding: 1.5rem 1rem 4rem; }
        h1 { font-size: 1.6rem; margin: 0.2rem 0 1rem; }
        h2 { font-size: 1.1rem; margin: 0 0 0.6rem; letter-spacing: 0.02em;
             text-transform: uppercase; color: var(--quiet); }
        header, section, footer { background: var(--card); border: 1px solid var(--rule);
             border-radius: 14px; padding: 1rem 1.1rem; margin-bottom: 1rem; }
        p { margin: 0 0 0.7rem; }
        p:last-child { margin-bottom: 0; }
        .status { font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase;
                  font-size: 0.8rem; color: var(--brand); margin-bottom: 0; }
        .status.error, .status.cancelled { color: var(--bad); }
        .status.success { color: var(--good); }
        .note { color: var(--quiet); font-size: 0.92rem; }
        .quoted { color: var(--ink); border-left: 3px solid var(--rule);
                  padding-left: 0.7rem; font-size: 0.92rem; }
        .refused { color: var(--bad); font-size: 0.92rem; }
        .last { color: var(--faint); font-size: 0.85rem; }
        dl.identity { display: grid; grid-template-columns: max-content 1fr;
                      gap: 0.2rem 0.9rem; margin: 0 0 0.9rem; font-size: 0.92rem; }
        dt { color: var(--quiet); }
        dd { margin: 0; word-break: break-word; }
        .tiles { display: flex; flex-wrap: wrap; gap: 0.6rem; margin-bottom: 0.8rem; }
        .tile { flex: 1 1 9rem; background: var(--ground); border: 1px solid var(--rule);
                border-radius: 10px; padding: 0.7rem 0.8rem; }
        .tile .value { font-size: 1.4rem; font-weight: 700; margin: 0; }
        .tile .name { font-size: 0.8rem; color: var(--quiet); margin: 0.1rem 0 0; }
        .tile .said { font-size: 0.78rem; color: var(--faint); margin: 0.4rem 0 0; }
        .scroll { overflow-x: auto; }
        table { border-collapse: collapse; width: 100%; font-size: 0.88rem; }
        th, td { text-align: left; padding: 0.35rem 0.6rem 0.35rem 0;
                 border-bottom: 1px solid var(--rule); white-space: nowrap; }
        th { color: var(--quiet); font-weight: 600; }
        """
    }
}

/// One recorded episode, ready for the stage the app already draws.
///
/// F3, AND THE REASON IT IS IN THE KIT. `DuckStage` takes a pose, an
/// environment and a trail; a trace is forty-seven numbers a tick. Turning one
/// into the other is arithmetic, the app target does no arithmetic
/// (`scripts/check_no_studio_math.sh`), and the two pieces of robot knowledge
/// involved are both easy to get wrong in a view: the fourteen policy joints
/// have to be scattered over fifteen model joints around the mouth, and the
/// root's quaternion is (w, x, y, z) rather than a yaw.
///
/// THE ENVIRONMENT IS BARE FLOOR AND IT IS NOT NEGOTIABLE. `/tune` answers with
/// a plant name and a digest and NO scene geometry. Drawing the world the app
/// happens to have selected under a recorded episode would put a staircase
/// under a duck that never saw one, which is the exact falsehood
/// `check_phonebench_fresh.sh` exists to prevent one layer down.
public struct EvalStageClip: Equatable, Sendable {

    public let poses: [DuckStance]
    /// Where the trunk went, in the frame the stage draws, so the trail and the
    /// duck are the same recording.
    public let trail: [DuckIntentClip.Root]
    /// Always bare floor. Stored rather than computed so a caller reads it off
    /// the clip and cannot substitute one.
    public let environment: DuckIntentClip.Environment
    /// The drop height this recording belongs to, so it cannot be shown against
    /// another trial.
    public let dropHeight: Double
    /// True when the recording ran into the bench's cap, which is what a person
    /// has to know before judging the ending.
    public let wasCapped: Bool
    /// The bench's own caption for this recording, when it sent one.
    ///
    /// `/tune` answers a traced call with `traceWhy`, which says which drop the
    /// ticks are and where the cap falls. It is carried rather than reworded
    /// because it describes somebody else's measurement, and it is drawn
    /// through `EvalText.foreign` like every other string nobody here wrote.
    public let why: String?

    public var isEmpty: Bool { poses.isEmpty }
    public var ticks: Int { poses.count }

    /// The pose at a tick, clamped at both ends, because a playhead is a
    /// render loop and an index out of a slider's range has trapped in this app
    /// before.
    public func pose(at index: Int) -> DuckStance {
        guard !poses.isEmpty else { return .home }
        return poses[Swift.min(Swift.max(index, 0), poses.count - 1)]
    }

    /// Seconds, at the bench's own control rate.
    public var duration: TimeInterval {
        Double(Swift.max(poses.count - 1, 0)) / DuckModel.tickHz
    }

    public static func of(_ trace: EvalTrace) -> EvalStageClip {
        var poses: [DuckStance] = []
        var trail: [DuckIntentClip.Root] = []
        poses.reserveCapacity(trace.ticks.count)
        trail.reserveCapacity(trace.ticks.count)
        let mouth = DuckModel.homePose[DuckModel.mouthIndex]
        for tick in trace.ticks {
            var angles = [Double](repeating: 0, count: DuckModel.jointCount)
            for slot in 0..<Swift.min(tick.joints.count, DuckModel.policyJointCount) {
                angles[DuckModel.jointOfPolicySlot(slot)] = tick.joints[slot]
            }
            // The mouth is outside every policy's action space, so a recording
            // carries nothing for it and home is the honest default. This is
            // the same choice `DuckIntentClip.sample` makes, on purpose.
            angles[DuckModel.mouthIndex] = mouth
            let root = Self.root(tick.root)
            poses.append(DuckStance(jointAngles: angles, root: root))
            trail.append(root)
        }
        return EvalStageClip(poses: poses, trail: trail,
                             environment: .bareFloor,
                             dropHeight: trace.dropHeight,
                             wasCapped: trace.wasCapped,
                             why: trace.why)
    }

    /// x, y, z, qw, qx, qy, qz, in the order the bench sends them. A short
    /// array is the identity orientation at the origin rather than a crash: a
    /// trace is somebody else's JSON and a render loop is the worst place to
    /// find that out.
    static func root(_ values: [Double]) -> DuckIntentClip.Root {
        func at(_ index: Int, _ fallback: Double) -> Double {
            index < values.count && values[index].isFinite ? values[index] : fallback
        }
        return DuckIntentClip.Root(x: at(0, 0), y: at(1, 0), z: at(2, DuckStance.standingHeight),
                                   quaternion: (at(3, 1), at(4, 0), at(5, 0), at(6, 0)))
    }
}
