import Foundation

/// The chrome of the six evaluation screens: every heading, every button and
/// every field label a person reads there.
///
/// WHY THESE ARE HERE AND NOT IN THE VIEW. `scripts/check_stage_sentences.sh`
/// holds the six evaluation files to the rule the rest of this app already
/// lives by: a screen draws no string of its own, so every word on it is a
/// constant a test can read letter by letter. A heading typed into a `Section`
/// is a word nobody can check, and the ones that go stale first are exactly
/// these: the verb on a button after the button starts doing something else.
///
/// WHY A TYPE OF THEIR OWN, when the sentences that carry a claim live on the
/// type that owns the claim. `EvalEpochs.noSeedSaid` belongs to epochs because
/// it is an argument about seeds; "Saved" belongs to no argument. Splitting a
/// section heading across nine files by subject would put a word like "Metrics"
/// somewhere a reader has to guess at, and the point of the exercise is that
/// the words are all in one place where they can be read as a whole and heard
/// as one voice.
///
/// EVERY ONE IS PINNED, character for character, by `EvalScreenTests`, and
/// every one is swept by `EvalStringsTests` for the em dash, the doubled space,
/// the banned word and the second wording.
public enum EvalScreen {

    // MARK: - the shelf, EvalListView

    /// The door into a run, on the shelf. A verb rather than a noun: the row
    /// above it lists what has already been measured.
    public static let newEvaluationSaid = "New evaluation"
    public static let runOneHeading = "Run one"

    /// The swipe action. Destructive, and the word is the platform's own, so a
    /// person who has deleted anything else on this phone knows what it does.
    public static let deleteSaid = "Delete"
    public static let savedHeading = "Saved"

    public static let putTwoSideBySideSaid = "Put two side by side"
    public static let compareHeading = "Compare"

    /// The import door. "A log" and not "a file", because what this opens is a
    /// log written by inspect-robots or by another copy of this app, and a
    /// picker offered for any JSON at all would be a picker that fails after
    /// the tap rather than before it.
    public static let openALogFromElsewhereSaid = "Open a log from elsewhere"
    public static let openOneFromElsewhereHeading = "Open one from elsewhere"

    // MARK: - setting one up, EvalSetupView

    public static let whatToEvaluateHeading = "What to evaluate"

    /// The policy, or the challenge entrant. One heading for both, because
    /// which of the two it is is the thing under it.
    public static let whatIsBeingEvaluatedHeading = "What is being evaluated"

    public static let whereItRunsHeading = "Where it runs"

    /// The epoch axis and its reducer, named as what they do rather than as
    /// what upstream calls them. Their vocabulary is in the log and in the row
    /// beneath this heading; a heading in it would be a heading a person skips.
    public static let whatVariesHeading = "What varies, and how it is collapsed"

    public static let howItIsScoredHeading = "How it is scored"

    /// The toggle that turns the verdict path on. It asks rather than promises,
    /// because the bench returns a trajectory for one drop of each scene and
    /// there is nothing to watch on the others.
    public static let askMeAboutTheTrialSaid = "Ask me about the trial it recorded"
    public static let watchAndJudgeHeading = "Watch and judge it"

    /// Beside the spinner, before the probe answers. A spinner with no words is
    /// a spinner VoiceOver reads as nothing at all.
    public static let askingThisBenchSaid = "Asking this bench what it can do"

    public static let startSaid = "Start"

    // MARK: - while it runs, EvalRunView

    public static let runningHeading = "Running"
    public static let scenesSaid = "Scenes"
    public static let benchSaid = "Bench"
    public static let whereItRanHeading = "Where it ran"

    /// Never disabled, and the word changes for one reason only: the tap
    /// landed. A Stop that said "Stopping" because a request happened to be in
    /// flight would be a label describing the app's state rather than the
    /// button's; a Stop that says nothing at all after somebody presses it
    /// leaves the progress row claiming the run is going for up to a whole
    /// scene, which is the fifty seconds a scene takes.
    public static let stopSaid = "Stop"

    /// What the button says once it has been pressed, which is the promise
    /// `EvalEpochs.wholeSceneAtOnceSaid` explains underneath it: a scene is
    /// asked for in one request and stopping takes effect at the end of it.
    public static let stoppingAfterThisSceneSaid = "Stopping after this scene"

    public static let openTheLogSaid = "Open the log"

    /// TWO FILES, SAID AS TWO. The share sheet hands over the JSON and the
    /// HTML report together, and a button that said "Share" would leave a
    /// person wondering which one went.
    public static let shareTheLogAndTheReportSaid = "Share the log and the report"
    public static let whatItWroteHeading = "What it wrote"

    // MARK: - the verdict sheet

    public static let watchItHeading = "Watch it"
    public static let whatItWasAskedToDoHeading = "What it was asked to do"

    /// The operator's own words. The field says what it is rather than
    /// prompting for anything in particular, because a note that was answered
    /// against a leading question would be a leading question in the log.
    public static let noteSaid = "Note"
    public static let yourVerdictHeading = "Your verdict"

    /// The two escapes. One trial, or the whole queue.
    public static let skipThisOneSaid = "Skip this one"
    public static let stopWatchingSaid = "Stop watching"

    // MARK: - the lab notebook, EvalLogDetailView

    public static let whatRanHeading = "What ran"
    public static let metricsHeading = "Metrics"
    public static let errorsHeading = "Errors"
    public static let whatThisIsNotHeading = "What this is not"
    public static let shareHeading = "Share"
    public static let sendItSomewhereSaid = "Send it somewhere"
    public static let publishItHeading = "Publish it"

    // MARK: - the publish form, EvalLogDetailView

    /// The five words of the publish form, which are the same five words the
    /// other four publish screens in this app use.
    ///
    /// THEY ARE HERE BECAUSE THEY ARE THE ONES THAT GO STALE FIRST. A verb on a
    /// button that has started doing something else is the failure this file
    /// exists to prevent, and a publish form is where a wrong verb costs the
    /// most: "Commit to a public dataset" is the one control in this feature
    /// that cannot be undone. The placeholder carries its ellipsis for the same
    /// reason the other four do, which is that `hf_` on its own reads as a
    /// field that has already been half filled in.
    public static let checkThisTokenSaid = "Check this token"
    public static let tokenFieldSaid = "hf_\u{2026}"
    /// A `SecureField`'s placeholder is not its label: VoiceOver reads the
    /// placeholder and a person hears "hf", which names nothing.
    public static let tokenLabelSaid = "Hugging Face token"
    public static let privateRepositorySaid = "Private repository"
    public static let commitPrivateSaid = "Commit to a private dataset"
    public static let commitPublicSaid = "Commit to a public dataset"

    // MARK: - two at once, EvalCompareView

    public static let sideBySideTitle = "Side by side"
    public static let leftSaid = "Left"
    public static let rightSaid = "Right"
    public static let whichTwoHeading = "Which two"

    /// The heading over the refusals, which is the finding when there is one.
    /// It says what did not happen and the rows under it say why.
    public static let notSideBySideHeading = "Not side by side"

    /// Over the rows: both numbers, one scorer at a time, and never a third
    /// number made out of the two.
    public static let bothScorerByScorerHeading = "Both, scorer by scorer"

    /// Everything here, so a screen can be checked against it and so nothing
    /// joins this file without joining the sweep.
    public static let everyWord: [String] = [
        newEvaluationSaid, runOneHeading, deleteSaid, savedHeading,
        putTwoSideBySideSaid, compareHeading, openALogFromElsewhereSaid,
        openOneFromElsewhereHeading,
        whatToEvaluateHeading, whatIsBeingEvaluatedHeading, whereItRunsHeading,
        whatVariesHeading, howItIsScoredHeading, askMeAboutTheTrialSaid,
        watchAndJudgeHeading, askingThisBenchSaid, startSaid,
        runningHeading, scenesSaid, benchSaid, whereItRanHeading, stopSaid,
        stoppingAfterThisSceneSaid,
        openTheLogSaid, shareTheLogAndTheReportSaid, whatItWroteHeading,
        watchItHeading, whatItWasAskedToDoHeading, noteSaid, yourVerdictHeading,
        skipThisOneSaid, stopWatchingSaid,
        whatRanHeading, metricsHeading, errorsHeading, whatThisIsNotHeading,
        shareHeading, sendItSomewhereSaid, publishItHeading,
        checkThisTokenSaid, tokenFieldSaid, tokenLabelSaid, privateRepositorySaid,
        commitPrivateSaid, commitPublicSaid,
        sideBySideTitle, leftSaid, rightSaid, whichTwoHeading,
        notSideBySideHeading, bothScorerByScorerHeading,
    ]
}
