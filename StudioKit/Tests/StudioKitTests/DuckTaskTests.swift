import XCTest
import DuckKit
@testable import StudioKit

/// quackd's `.duck` task format, pinned against REAL published files.
///
/// The two fixtures below are `ducks/find-and-kick.duck` and `ducks/fetch.duck` from
/// `rokbenko/quackd`, byte for byte as GitHub served them at commit 56d752a on 2026-08-29.
/// A hand-written approximation would prove only that this reader agrees with itself, and
/// the entire value of this reader is that a file it accepts is a file quackd will run.
///
/// `fetch.duck` earns its place by carrying the two awkward shapes the starter set contains:
/// three `#` comment lines above the opening fence, and a success criterion wrapped across
/// two source lines as a folded plain scalar.
final class DuckTaskTests: XCTestCase {

    private let findAndKick = #"""
---
duck: 0
name: find-and-kick
description: Search the area for a ball, walk to it, kick it.
author: rok
verbs:
  allow: [search_scan, walk_to, kick, quack, get_frame, stop]
  confirm: []
budgets:
  max_steps: 40
  max_minutes: 5
  max_llm_calls: 40
success:
  - Ball displaced more than 0.3 m in sim, or human confirms the kick landed.
abort_when:
  - Battery below 15%
  - Same verb fails 3 times in a row
persona: Determined and cheerful. Quack once when you succeed.
providers: [fake, anthropic, openai, gemini, grok]
learned_verbs: []
---

# Task

You are piloting a small biped duck robot. Find the ball and kick it.

## Strategy

1. `search_scan` to locate the ball. It rotates in steps and reports detections.
2. `walk_to` the ball and stop about 0.25 m away. `walk_to` closes the approach loop
   itself using the camera — you do not need to micro-manage it.
3. `kick`. The result tells you whether the ball moved and by how much.
4. Verify with a fresh frame or the kick result. If the ball has not moved at least
   0.3 m, `walk_to` it again and retry the kick.
5. When the ball has moved ≥ 0.3 m, `quack` once and declare success.

## Notes

- A kick only connects if the ball is close (< 0.3 m) and roughly in front of you.
  If the kick reports "missed", reposition with `walk_to` before kicking again.
- If `search_scan` finds nothing twice in a row, declare failure rather than looping.
"""#

    private let fetch = #"""
# EXPERIMENTAL: `grab` is an open-loop beak scoop to the floor on the real robot
# (upstream `ground_pick`), so success rates are low. The instructions below insist on
# verify-and-retry rather than trusting a single attempt.
---
duck: 0
name: fetch
description: Find the ball, walk to it, scoop it up with the beak, and bring it back.
author: rok
verbs:
  allow: [search_scan, walk_to, grab, walk, quack, get_frame, stop]
  confirm: []
budgets:
  max_steps: 50
  max_minutes: 6
  max_llm_calls: 50
success:
  - The ball is no longer visible in front of the duck after a grab (it is in the beak),
    and the duck has walked back at least 0.5 m toward where it started.
abort_when:
  - Battery below 15%
  - Same verb fails 3 times in a row
persona: Eager. This is hard for a duck, so be patient with yourself.
providers: [fake, anthropic, openai, gemini, grok]
learned_verbs: []
---

# Task

You are piloting a small biped duck robot. Fetch the ball.

## Strategy

1. `search_scan` to locate the ball.
2. `walk_to` it with `stop_distance` 0.15 — the scoop only works when the ball is right
   under the beak.
3. `grab`. This is open-loop: the duck scoops at the floor and hopes.
4. **Verify.** `get_frame`. If the ball is still visible in front of you, the grab missed:
   `walk_to` again (maybe from a slightly different angle) and retry `grab`. Do not retry
   more than three times.
5. Once the ball is gone from view, `walk` backward (`vx` -0.1) for about 3 seconds,
   quack, and declare success.
"""#

    /// A Swift multi-line literal cannot carry a file's final newline, and both files on
    /// disk end with one. Adding it back here is what makes the byte comparison a
    /// comparison against the real file rather than against a truncation of it.
    private var findAndKickFile: String { findAndKick + "\n" }
    private var fetchFile: String { fetch + "\n" }

    // MARK: - reading a real starter duck

    func testItReadsTheRealFindAndKickStarterDuck() throws {
        let task = try DuckTask.decode(Data(findAndKickFile.utf8))
        XCTAssertEqual(task.name, "find-and-kick")
        XCTAssertEqual(task.summary, "Search the area for a ball, walk to it, kick it.")
        XCTAssertEqual(task.author, "rok")
        XCTAssertEqual(task.verbs.allow,
                       ["search_scan", "walk_to", "kick", "quack", "get_frame", "stop"])
        XCTAssertEqual(task.verbs.confirm, [])
        XCTAssertEqual(task.budgets.maxSteps, 40)
        XCTAssertEqual(task.budgets.maxMinutes, 5)
        XCTAssertEqual(task.budgets.maxLLMCalls, 40)
        XCTAssertEqual(task.success, [
            "Ball displaced more than 0.3 m in sim, or human confirms the kick landed."
        ])
        XCTAssertEqual(task.abortWhen, ["Battery below 15%", "Same verb fails 3 times in a row"])
        XCTAssertEqual(task.persona, "Determined and cheerful. Quack once when you succeed.")
        XCTAssertEqual(task.providers, ["fake", "anthropic", "openai", "gemini", "grok"])
        XCTAssertEqual(task.learnedVerbs, [])
    }

    /// The body is everything after the closing fence, and it is the LLM's whole plan.
    func testTheBodyIsEverythingAfterTheClosingFence() throws {
        let task = try DuckTask.decode(Data(findAndKickFile.utf8))
        XCTAssertTrue(task.body.hasPrefix("# Task\n"), String(task.body.prefix(40)))
        XCTAssertTrue(task.body.hasSuffix("declare failure rather than looping."), task.body)
        XCTAssertTrue(task.body.contains("`search_scan` to locate the ball."))
        XCTAssertFalse(task.body.contains("duck: 0"), "the frontmatter must not leak into the body")
    }

    /// The one test that keeps the writer honest about the format rather than merely
    /// self-consistent: a real file goes out exactly as it came in.
    func testARealStarterDuckComesBackOutByteForByte() throws {
        let task = try DuckTask.decode(Data(findAndKickFile.utf8))
        XCTAssertEqual(String(decoding: task.encode(), as: UTF8.self), findAndKickFile)
    }

    /// Comment lines above the fence are how `fetch.duck` warns that `grab` is open-loop,
    /// so a reader that choked on them would refuse a file quackd ships.
    func testCommentsAboveTheOpeningFenceAreSkipped() throws {
        XCTAssertTrue(fetchFile.hasPrefix("# EXPERIMENTAL:"), "the fixture must still lead with them")
        let task = try DuckTask.decode(Data(fetchFile.utf8))
        XCTAssertEqual(task.name, "fetch")
        XCTAssertEqual(task.budgets.maxSteps, 50)
        XCTAssertEqual(task.budgets.maxMinutes, 6)
        XCTAssertFalse(task.body.contains("EXPERIMENTAL"),
                       "a comment above the fence is not part of the task instructions")
    }

    /// `fetch.duck` wraps one success criterion over two lines. YAML folds it into a single
    /// sentence, and so does this — a reader that kept the newline would hand the LLM half
    /// a criterion.
    func testAPlainScalarWrappedOverTwoLinesFoldsIntoOneSentence() throws {
        let task = try DuckTask.decode(Data(fetchFile.utf8))
        XCTAssertEqual(task.success, [
            "The ball is no longer visible in front of the duck after a grab (it is in the "
          + "beak), and the duck has walked back at least 0.5 m toward where it started."
        ])
    }

    /// Folding loses the author's line breaks, so `fetch.duck` cannot come back byte for
    /// byte — but it must come back as the same task, which is the claim that matters.
    func testAFoldedFileStillRoundTripsToTheSameTask() throws {
        let task = try DuckTask.decode(Data(fetchFile.utf8))
        XCTAssertEqual(try DuckTask.decode(task.encode()), task)
    }

    /// An apostrophe in the middle of a plain scalar is an apostrophe, not an opening quote.
    ///
    /// Found the hard way, and cheaply: the caution this app writes for an unmerged policy
    /// ends "reproduced from the project's main line", and reading that apostrophe as a
    /// quote swallowed every later item in the flow list it sat in.
    func testAnApostropheInsideAPlainScalarIsNotAnOpeningQuote() throws {
        let task = try DuckTask(name: "apostrophes", summary: "The author's own words.",
                                verbs: .init(allow: ["stop"]),
                                success: ["The duck's beak is empty."],
                                providers: ["rok's fork", "fake"],
                                body: "# Task\nStand still.")
        let reread = try DuckTask.decode(task.encode())
        XCTAssertEqual(reread.providers, ["rok's fork", "fake"])
        XCTAssertEqual(reread, task)
    }

    // MARK: - the two abort phrasings the executor actually enforces

    private func task(abortWhen: [String]) throws -> DuckTask {
        try DuckTask(name: "probe", summary: "One abort condition under test.",
                     verbs: .init(allow: ["stop"]), success: ["Nothing happens."],
                     abortWhen: abortWhen, body: "# Task\nStand still.")
    }

    /// The battery pattern is a grep, not an understanding, and these are the exact
    /// sentences it does and does not catch.
    func testOnlyTheBatteryPhrasingQuackdGrepsForIsEnforced() throws {
        XCTAssertEqual(try task(abortWhen: ["Battery below 15%"]).batteryAbortPercent, 15.0)
        XCTAssertEqual(try task(abortWhen: ["BATTERY < 7.5%"]).batteryAbortPercent, 7.5,
                       "the pattern is case-insensitive and < is one of its three verbs")
        XCTAssertEqual(try task(abortWhen: ["Battery under 20%"]).batteryAbortPercent, 20.0)
    }

    /// The traps. Both of these READ like a battery floor and neither one arms anything, so
    /// an author who writes them gets no protection at all — which is why this reader
    /// reports them as advisory rather than quietly enforcing something it invented.
    func testABatteryFloorTheExecutorWillMissIsReportedAsAdvisory() throws {
        let noPercentSign = try task(abortWhen: ["Battery below 15 percent"])
        XCTAssertNil(noPercentSign.batteryAbortPercent, "the pattern needs a % sign")
        XCTAssertEqual(noPercentSign.advisoryAbortConditions, ["Battery below 15 percent"])

        let politelyWorded = try task(abortWhen: ["Stop if the battery goes below 20% please"])
        XCTAssertNil(politelyWorded.batteryAbortPercent,
                     "words between 'battery' and 'below' defeat the pattern")
        XCTAssertEqual(politelyWorded.advisoryAbortConditions,
                       ["Stop if the battery goes below 20% please"])
    }

    func testOnlyTheRepeatFailurePhrasingQuackdGrepsForIsEnforced() throws {
        XCTAssertEqual(try task(abortWhen: ["Same verb fails 3 times in a row"])
                        .repeatFailureAbort, 3)
        XCTAssertEqual(try task(abortWhen: ["same verb fails 1 time in a row"])
                        .repeatFailureAbort, 1,
                       "one failure is singular, and the pattern allows it")
    }

    func testARepeatFailureRuleWithoutTheWordSameIsAdvisory() throws {
        let vague = try task(abortWhen: ["A verb fails 3 times in a row"])
        XCTAssertNil(vague.repeatFailureAbort)
        XCTAssertEqual(vague.advisoryAbortConditions, ["A verb fails 3 times in a row"])
    }

    /// Two floors in one file is a contradiction, and quackd resolves it by reading order.
    func testTheFirstMatchingEntryWins() throws {
        let both = try task(abortWhen: ["Battery below 30%", "Battery below 10%"])
        XCTAssertEqual(both.batteryAbortPercent, 30.0)
    }

    /// Everything the executor cannot police is handed to the LLM, and a screen has to be
    /// able to say which half is which.
    func testTheEnforcedAndAdvisoryHalvesAreReportedSeparately() throws {
        let mixed = try task(abortWhen: [
            "Battery below 15%",
            "Same verb fails 3 times in a row",
            "The ball rolls off the table.",
        ])
        XCTAssertEqual(mixed.batteryAbortPercent, 15.0)
        XCTAssertEqual(mixed.repeatFailureAbort, 3)
        XCTAssertEqual(mixed.advisoryAbortConditions, ["The ball rolls off the table."])
    }

    func testTheRealStarterDucksAbortRulesAreBothEnforced() throws {
        let task = try DuckTask.decode(Data(findAndKickFile.utf8))
        XCTAssertEqual(task.batteryAbortPercent, 15.0)
        XCTAssertEqual(task.repeatFailureAbort, 3)
        XCTAssertEqual(task.advisoryAbortConditions, [])
    }

    // MARK: - what a file has to get right

    /// `duck: 0` is the integer zero. The quoted string is a different value and quackd's
    /// `Literal[0]` refuses it, so refusing it here is the point.
    func testTheSpecVersionHasToBeTheNumberZero() {
        for (replacement, expectedInMessage) in [("\"0\"", "the text \"0\""), ("1", "1")] {
            let altered = findAndKickFile.replacingOccurrences(of: "duck: 0",
                                                               with: "duck: \(replacement)")
            XCTAssertNotEqual(altered, findAndKickFile, "the fixture must still say duck: 0")
            XCTAssertThrowsError(try DuckTask.decode(Data(altered.utf8)), replacement) {
                XCTAssertEqual($0 as? DuckTask.ReadError,
                               .notSpecVersionZero(expectedInMessage), replacement)
            }
        }
    }

    /// A misspelled key that was merely ignored would silently do nothing, which is the
    /// worst way for a safety setting to fail.
    func testUnknownFrontmatterKeysAreRefusedRatherThanIgnored() {
        let altered = findAndKickFile.replacingOccurrences(of: "persona:", with: "personna:")
        XCTAssertThrowsError(try DuckTask.decode(Data(altered.utf8))) {
            XCTAssertEqual($0 as? DuckTask.ReadError, .unknownKeys(["personna"]))
            XCTAssertTrue(($0 as? DuckTask.ReadError)?.message.contains("personna") == true)
        }
    }

    /// Underscores are legal in a verb name and illegal in a duck's name, because the verb
    /// rule replaces `_` with `-` before matching and the name rule does not.
    func testUnderscoresAreLegalInVerbNamesAndNotInADucksName() throws {
        XCTAssertTrue(DuckTask.isVerbName("walk_to"))
        XCTAssertTrue(DuckTask.isVerbName("get_frame"))
        XCTAssertTrue(DuckTask.isVerbName("search-scan"))
        XCTAssertFalse(DuckTask.isVerbName("WalkTo"), "capitals are out")
        XCTAssertFalse(DuckTask.isVerbName("_walk"), "it still has to start with a letter or digit")
        XCTAssertFalse(DuckTask.isVerbName(""))

        XCTAssertTrue(DuckTask.isSlug("find-and-kick"))
        XCTAssertFalse(DuckTask.isSlug("find_and_kick"), "a name has no underscore escape hatch")
        XCTAssertFalse(DuckTask.isSlug("Find-And-Kick"))
        XCTAssertFalse(DuckTask.isSlug(String(repeating: "a", count: 65)), "64 characters, no more")

        let altered = findAndKickFile.replacingOccurrences(of: "name: find-and-kick",
                                                           with: "name: find_and_kick")
        XCTAssertThrowsError(try DuckTask.decode(Data(altered.utf8))) {
            XCTAssertEqual($0 as? DuckTask.ReadError, .invalidName("find_and_kick"))
        }
    }

    /// A verb somebody has to approve still has to be one the LLM may call.
    func testConfirmHasToBeASubsetOfAllow() {
        XCTAssertThrowsError(try DuckTask(name: "probe", summary: "Confirm names a stranger.",
                                          verbs: .init(allow: ["kick"], confirm: ["walk_to"]),
                                          success: ["Nothing."], body: "# Task\nStand still.")) {
            XCTAssertEqual($0 as? DuckTask.ReadError, .confirmNotAllowed(["walk_to"]))
            XCTAssertTrue(($0 as? DuckTask.ReadError)?.message.contains("walk_to") == true)
        }
    }

    /// The subset test is by exact string. `walk-to` and `walk_to` are both legal names and
    /// normalise to the same slug, but the executor looks a verb up by the name it was
    /// written with, so they are not the same verb.
    func testTheSubsetTestComparesTheNamesAsWritten() {
        XCTAssertThrowsError(try DuckTask(name: "probe", summary: "Spelled two ways.",
                                          verbs: .init(allow: ["walk_to"], confirm: ["walk-to"]),
                                          success: ["Nothing."], body: "# Task\nStand still.")) {
            XCTAssertEqual($0 as? DuckTask.ReadError, .confirmNotAllowed(["walk-to"]))
        }
    }

    func testADuplicateVerbIsRefused() {
        XCTAssertThrowsError(try DuckTask(name: "probe", summary: "Listed twice.",
                                          verbs: .init(allow: ["kick", "kick"]),
                                          success: ["Nothing."], body: "# Task\nStand still.")) {
            XCTAssertEqual($0 as? DuckTask.ReadError, .duplicateVerb("kick"))
        }
    }

    func testAnEmptyAllowListOrEmptySuccessListIsRefused() {
        XCTAssertThrowsError(try DuckTask(name: "probe", summary: "No verbs.",
                                          verbs: .init(allow: []), success: ["Nothing."],
                                          body: "# Task\nStand still.")) {
            XCTAssertEqual($0 as? DuckTask.ReadError, .noAllowedVerbs)
        }
        XCTAssertThrowsError(try DuckTask(name: "probe", summary: "No criteria.",
                                          verbs: .init(allow: ["stop"]), success: [],
                                          body: "# Task\nStand still.")) {
            XCTAssertEqual($0 as? DuckTask.ReadError, .noSuccessCriteria)
        }
    }

    /// The budgets are hard stops, so their bounds are quackd's and not this app's.
    func testTheBudgetBoundsAreQuackdsOwn() {
        XCTAssertEqual(DuckTask.Budgets.quackdDefaults.maxSteps, 40)
        XCTAssertEqual(DuckTask.Budgets.quackdDefaults.maxMinutes, 5.0)
        XCTAssertEqual(DuckTask.Budgets.quackdDefaults.maxLLMCalls, 40)

        let cases: [(DuckTask.Budgets, String, String)] = [
            (.init(maxSteps: 0), "max_steps", "0"),
            (.init(maxSteps: 1001), "max_steps", "1001"),
            (.init(maxMinutes: 0), "max_minutes", "0"),
            (.init(maxMinutes: 180.5), "max_minutes", "180.5"),
            (.init(maxLLMCalls: 2001), "max_llm_calls", "2001"),
        ]
        for (budgets, key, value) in cases {
            XCTAssertThrowsError(try DuckTask(name: "probe", summary: "Out of range.",
                                              verbs: .init(allow: ["stop"]), budgets: budgets,
                                              success: ["Nothing."],
                                              body: "# Task\nStand still."), key) { error in
                guard case .budgetOutOfRange(let refusedKey, let refusedValue, _)?
                        = error as? DuckTask.ReadError else {
                    return XCTFail("expected a budget refusal for \(key), got \(error)")
                }
                XCTAssertEqual(refusedKey, key)
                XCTAssertEqual(refusedValue, value)
            }
        }
        XCTAssertNoThrow(try DuckTask(name: "probe", summary: "At the edges.",
                                      verbs: .init(allow: ["stop"]),
                                      budgets: .init(maxSteps: 1000, maxMinutes: 180,
                                                     maxLLMCalls: 1),
                                      success: ["Nothing."], body: "# Task\nStand still."))
    }

    /// `providers: openai` is not a one-element list. quackd refuses it, so a file that
    /// loads here and fails there must not exist.
    func testABareStringIsNotAOneElementList() {
        let altered = findAndKickFile.replacingOccurrences(
            of: "providers: [fake, anthropic, openai, gemini, grok]", with: "providers: openai")
        XCTAssertNotEqual(altered, findAndKickFile)
        XCTAssertThrowsError(try DuckTask.decode(Data(altered.utf8))) {
            guard case .wrongType(let key, _)? = $0 as? DuckTask.ReadError else {
                return XCTFail("expected a type refusal, got \($0)")
            }
            XCTAssertEqual(key, "providers")
        }
    }

    // MARK: - the file's shape

    func testAFileWithoutFencesIsNotADuckFile() {
        XCTAssertThrowsError(try DuckTask.decode(Data("just some notes\n".utf8))) {
            XCTAssertEqual($0 as? DuckTask.ReadError, .missingFence)
        }
        XCTAssertThrowsError(try DuckTask.decode(Data("---\nduck: 0\nname: x\n".utf8))) {
            XCTAssertEqual($0 as? DuckTask.ReadError, .unterminatedFrontmatter)
        }
    }

    /// An LLM handed no instructions has no task, so quackd refuses the file and so does
    /// this.
    func testAFileWithNoInstructionsIsRefused() {
        let source = """
        ---
        duck: 0
        name: empty
        description: A duck with nothing to say.
        verbs:
          allow: [stop]
        success:
          - Nothing happens.
        ---
        """ + "\n\n   \n"
        XCTAssertThrowsError(try DuckTask.decode(Data(source.utf8))) {
            XCTAssertEqual($0 as? DuckTask.ReadError, .emptyBody)
        }
    }

    /// A `---` inside the body is a horizontal rule, not a fence — but the CLOSING fence is
    /// the first one after the opening, so the body keeps its rule and the frontmatter stops
    /// where it should.
    func testTheClosingFenceIsTheFirstOneAndTheBodyMayContainMore() throws {
        let source = """
        ---
        duck: 0
        name: ruled
        description: A body with a horizontal rule in it.
        verbs:
          allow: [stop]
          confirm: []
        success:
          - Nothing happens.
        ---

        # Task

        Above the rule.

        ---

        Below the rule.
        """
        let task = try DuckTask.decode(Data(source.utf8))
        XCTAssertEqual(task.name, "ruled")
        XCTAssertTrue(task.body.contains("\n---\n"), task.body)
        XCTAssertTrue(task.body.hasSuffix("Below the rule."))
    }

    /// Everything with a default may be left out, and the defaults are quackd's.
    func testTheOptionalHalfOfTheFrontmatterMayBeOmitted() throws {
        let source = """
        ---
        duck: 0
        name: minimal
        description: The smallest legal duck.
        verbs:
          allow: [stop]
        success:
          - Nothing happens.
        ---

        # Task

        Stand still.
        """
        let task = try DuckTask.decode(Data(source.utf8))
        XCTAssertNil(task.author)
        XCTAssertNil(task.persona)
        XCTAssertEqual(task.verbs.confirm, [])
        XCTAssertEqual(task.budgets, .quackdDefaults)
        XCTAssertEqual(task.abortWhen, [])
        XCTAssertEqual(task.providers, [])
        XCTAssertEqual(task.learnedVerbs, [])
        XCTAssertEqual(try DuckTask.decode(task.encode()), task, "and it still round-trips")
    }

    /// Refusals name the thing that is wrong, in words somebody can act on.
    func testRefusalsSayWhatToFix() {
        XCTAssertTrue(DuckTask.ReadError.emptyBody.message.contains("instructions"))
        XCTAssertTrue(DuckTask.ReadError.invalidVerbName("WalkTo").message.contains("WalkTo"))
        XCTAssertTrue(DuckTask.ReadError.invalidVerbName("WalkTo").message.contains("walk_to"),
                      "it should show a name that would work")
        XCTAssertTrue(DuckTask.ReadError.notSpecVersionZero("the text \"0\"")
                        .message.contains("not the number"))
        XCTAssertTrue(DuckTask.ReadError
                        .budgetOutOfRange(key: "max_minutes", value: "600",
                                          allowed: "more than 0 and at most 180")
                        .message.contains("600"))
    }

    // MARK: - exporting a policy as a learned verb

    private let flamingo = #"""
{
  "schema_version": 2,
  "model_api": 1,
  "name": "flamingo-cycle",
  "kind": "perpetual",
  "obs_len": 61,
  "action_len": 14,
  "action_scale": 1.0,
  "entry_pose": "standing",
  "duration_s": null,
  "description": "Stand on one foot, either side, on command, and come back to a two-foot stand: twist = [flag, side, 0].",
  "command": {
    "twist": [
      "flag: 0 = stand on two feet (HOME), 1 = stand on one foot",
      "side: +1 = right foot down / left leg lifted, -1 = left foot down / right leg lifted; 0 allowed while flag = 0",
      "unused (0)"
    ],
    "head": "unused (zeros)",
    "body": "unused (zeros)",
    "idle": [
      0,
      0,
      0
    ]
  },
  "robot": {
    "model": "microduck",
    "hw_rev": 1,
    "servos": "xl330",
    "control_hz": 50
  },
  "training": {
    "task_id": "Mjlab-FlamingoCycleHard-Flat-MicroDuck",
    "repo": "pollen-robotics/microduck_rl",
    "commit": "0bf9897 on branch flamingo (https://github.com/pollen-robotics/microduck_rl/commit/0bf9897), not merged yet",
    "run": "pollen-robotics/flamingo-cycle-r2-hard-20260829-0245"
  },
  "eval": {
    "sim_proxy": "CPU MuJoCo with the BAM XL330 servo model, allcollisions model",
    "battery": "10/10: right and left cycles, 0.1 m/s pushes toward either side, 0.15 m/s forward, a 0.3 m/s push toward the lifted side (brief touch-down, re-lift), lowering from a static hold, 10 s hold",
    "stress_24_random_trials": {
      "held": 20,
      "recovered_stepped_down": 2,
      "fell": 2,
      "push_range_m_s": [
        0.05,
        0.25
      ]
    },
    "known_limits": "falls on backward pushes >= 0.18 m/s; pushes toward the standing-foot side above ~0.15 m/s end in a step-down; never tested on hardware",
    "transition_time_s": 1.5,
    "lifted_foot_height_m": 0.09
  }
}
"""#

    private func flamingoManifest() throws -> PolicyManifest {
        try PolicyManifest.decode(Data(flamingo.utf8))
    }

    /// quackd's contract and this robot's contract are the same three numbers. If they ever
    /// drift, a policy this app can drive is not one quackd can register, and that deserves
    /// a red test rather than a surprise on a robot.
    func testTheLearnedVerbContractIsThisRobotsContract() {
        XCTAssertEqual(LearnedVerbSpec.upstreamObservationDimension, 61)
        XCTAssertEqual(LearnedVerbSpec.upstreamActionDimension, 14)
        XCTAssertEqual(LearnedVerbSpec.upstreamControlHz, 50)
        XCTAssertEqual(LearnedVerbSpec.upstreamObservationDimension, DuckObservation.length)
        XCTAssertEqual(LearnedVerbSpec.upstreamActionDimension, DuckModel.policyJointCount)
        XCTAssertEqual(LearnedVerbSpec.upstreamControlHz, DuckModel.tickHz)
    }

    /// `register_learned_verb` writes `safety_class="confirm"` as a literal. There is no
    /// argument for it and no way to raise it from a `.duck`, so an unproven policy asks a
    /// human first, always.
    func testALearnedVerbAlwaysAsksAHumanFirst() throws {
        XCTAssertEqual(LearnedVerbSpec.safetyClass, "confirm")
        let spec = try LearnedVerbSpec.export(flamingoManifest(),
                                              policyPath: "policies/flamingo-cycle.onnx")
        XCTAssertEqual(spec.metadata["safety_class"]?.stringValue, "confirm",
                       "and the .duck author reads it in the metadata, not in quackd's source")
    }

    /// Every provenance field is the author's own, mapped across one for one.
    func testTheManifestsProvenanceIsCarriedIntoTheVerbsMetadata() throws {
        let spec = try LearnedVerbSpec.export(flamingoManifest(),
                                              policyPath: "policies/flamingo-cycle.onnx")
        XCTAssertEqual(spec.name, "flamingo-cycle")
        XCTAssertEqual(spec.policyPath, "policies/flamingo-cycle.onnx")
        XCTAssertEqual(spec.observationDimension, 61)
        XCTAssertEqual(spec.actionDimension, 14)
        XCTAssertEqual(spec.controlHz, 50)

        XCTAssertEqual(spec.metadata["training_task_id"]?.stringValue,
                       "Mjlab-FlamingoCycleHard-Flat-MicroDuck")
        XCTAssertEqual(spec.metadata["training_repo"]?.stringValue,
                       "pollen-robotics/microduck_rl")
        XCTAssertEqual(spec.metadata["training_run"]?.stringValue,
                       "pollen-robotics/flamingo-cycle-r2-hard-20260829-0245")
        XCTAssertEqual(spec.metadata["training_unmerged"]?.booleanValue, true)
        XCTAssertEqual(spec.metadata["eval_stress_held"]?.integerValue, 20)
        XCTAssertEqual(spec.metadata["eval_stress_fell"]?.integerValue, 2)
        XCTAssertEqual(spec.metadata["eval_stress_trials"]?.integerValue, 24)
        XCTAssertTrue(spec.metadata["eval_battery"]?.stringValue?.contains("0.3 m/s push") == true,
                      "the eval battery is the numbers a .duck author is being asked to trust")
        XCTAssertTrue(spec.metadata["eval_known_limits"]?.stringValue?.contains("0.18") == true)
    }

    /// The reward text quackd's doc asks for does not exist in Pollen's manifest format.
    /// Leaving the key out is the honest answer; inventing one would put a fabricated
    /// provenance line in front of the person the metadata exists to inform.
    func testNoRewardTextIsInventedBecauseTheManifestHasNone() throws {
        let spec = try LearnedVerbSpec.export(flamingoManifest(),
                                              policyPath: "policies/flamingo-cycle.onnx")
        XCTAssertNil(spec.metadata["reward"])
        XCTAssertNil(spec.metadata["reward_text"])
    }

    /// THE LIMIT THAT BITES. `register_learned_verb` binds `NoParams`, so the LLM calls the
    /// verb with nothing — and flamingo-cycle's whole behaviour is selected by a command it
    /// therefore cannot send.
    func testALearnedVerbTakesNoArgumentsSoTheCommandCannotBeChosen() throws {
        XCTAssertFalse(LearnedVerbSpec.acceptsCallTimeArguments)
        let spec = try LearnedVerbSpec.export(flamingoManifest(),
                                              policyPath: "policies/flamingo-cycle.onnx")
        let caution = try XCTUnwrap(spec.cautions.first { $0.contains("no arguments") },
                                    "\(spec.cautions)")
        XCTAssertTrue(caution.contains("flag"), caution)
        XCTAssertTrue(caution.contains("side"), caution)
        XCTAssertFalse(caution.contains("unused (0)"),
                       "an unused slot is not something the author is losing")
        XCTAssertTrue(spec.metadata["command_at_call_time"]?.stringValue?
                        .contains("NoParams") == true)
        XCTAssertEqual(spec.metadata["command_twist"]?.listValue?.count, 3,
                       "the slot meanings are still carried, as documentation")
    }

    /// The author's own admissions travel with the verb, because a `.duck` author allowing
    /// it is the person who needs them.
    func testTheAuthorsCautionsTravelWithTheVerb() throws {
        let spec = try LearnedVerbSpec.export(flamingoManifest(),
                                              policyPath: "policies/flamingo-cycle.onnx")
        XCTAssertTrue(spec.cautions.contains { $0.contains("never tested on hardware") },
                      "\(spec.cautions)")
        XCTAssertTrue(spec.cautions.contains { $0.contains("held 20 of 24") })
        XCTAssertTrue(spec.cautions.contains { $0.contains("not merged") })
        XCTAssertEqual(spec.metadata["cautions"]?.listValue?.count, spec.cautions.count)
    }

    /// A no-argument verb can only ever send a fixed command, and zeros is the only fixed
    /// command it can defend. A policy that reads zeros as an instruction cannot be driven
    /// that way, so it is refused rather than exported and hoped over.
    func testAPolicyWhoseIdleCommandIsNotZeroIsRefused() throws {
        let altered = flamingo.replacingOccurrences(
            of: "\"idle\": [\n      0,\n      0,\n      0\n    ]",
            with: "\"idle\": [0, 1, 0]")
        XCTAssertNotEqual(altered, flamingo, "the fixture's idle block must still be there")
        let manifest = try PolicyManifest.decode(Data(altered.utf8))
        XCTAssertEqual(manifest.command?.idle, [0, 1, 0])
        XCTAssertThrowsError(try LearnedVerbSpec.export(manifest, policyPath: "p.onnx")) {
            XCTAssertEqual($0 as? LearnedVerbSpec.ExportRefusal,
                           .idleCommandIsNotNeutral([0, 1, 0]))
            let message = ($0 as? LearnedVerbSpec.ExportRefusal)?.message ?? ""
            XCTAssertTrue(message.contains("NoParams"), message)
            XCTAssertTrue(message.contains("[0, 1, 0]"), message)
        }
    }

    /// An idle command the author never wrote down cannot be trusted to be neutral.
    func testAnUnstatedIdleCommandIsRefused() throws {
        let altered = flamingo.replacingOccurrences(
            of: "\"idle\": [\n      0,\n      0,\n      0\n    ]", with: "\"idle\": []")
        XCTAssertNotEqual(altered, flamingo)
        XCTAssertThrowsError(try LearnedVerbSpec.export(
            PolicyManifest.decode(Data(altered.utf8)), policyPath: "p.onnx")) {
            XCTAssertEqual($0 as? LearnedVerbSpec.ExportRefusal, .idleCommandNotStated)
        }
    }

    func testAPolicyForAnotherRobotCannotBeALearnedVerb() throws {
        let altered = flamingo.replacingOccurrences(of: "\"obs_len\": 61", with: "\"obs_len\": 48")
        XCTAssertNotEqual(altered, flamingo)
        XCTAssertThrowsError(try LearnedVerbSpec.export(
            PolicyManifest.decode(Data(altered.utf8)), policyPath: "p.onnx")) {
            XCTAssertEqual($0 as? LearnedVerbSpec.ExportRefusal,
                           .wrongContract([.observationLength(48)]))
            XCTAssertTrue(($0 as? LearnedVerbSpec.ExportRefusal)?.message.contains("48") == true)
        }
    }

    /// The policy's own name becomes the verb name, so a name no verb could have is a
    /// refusal rather than a silent rewrite.
    func testAPolicyNameThatCannotBeAVerbNameIsRefused() throws {
        let altered = flamingo.replacingOccurrences(of: "\"name\": \"flamingo-cycle\"",
                                                    with: "\"name\": \"Flamingo_Cycle\"")
        XCTAssertNotEqual(altered, flamingo)
        XCTAssertThrowsError(try LearnedVerbSpec.export(
            PolicyManifest.decode(Data(altered.utf8)), policyPath: "p.onnx")) {
            XCTAssertEqual($0 as? LearnedVerbSpec.ExportRefusal,
                           .unusableVerbName("Flamingo_Cycle"))
        }
    }

    /// The manifest carries no timeout, so quackd's own 10 s stands — widened only when the
    /// author's stated duration would not fit inside it.
    func testTheTimeoutIsQuackdsDefaultUnlessThePolicyRunsLonger() throws {
        XCTAssertEqual(LearnedVerbSpec.defaultTimeoutSeconds, 10.0)
        let perpetual = try LearnedVerbSpec.export(flamingoManifest(), policyPath: "p.onnx")
        XCTAssertEqual(perpetual.timeoutSeconds, 10.0)

        let altered = flamingo.replacingOccurrences(of: "\"duration_s\": null",
                                                    with: "\"duration_s\": 12.5")
        XCTAssertNotEqual(altered, flamingo)
        let oneShot = try LearnedVerbSpec.export(PolicyManifest.decode(Data(altered.utf8)),
                                                 policyPath: "p.onnx")
        XCTAssertEqual(oneShot.timeoutSeconds, 12.5,
                       "a 12.5 s motion cannot be given 10 s to finish")
        XCTAssertEqual(try LearnedVerbSpec.export(flamingoManifest(), policyPath: "p.onnx",
                                                  timeoutSeconds: 3).timeoutSeconds, 3)
    }

    /// The whole point: a policy this app inspected becomes a line in a task file somebody
    /// else can run — and survives being written and read back.
    func testAnExportedVerbCanBeWrittenIntoADuckFileAndReadBack() throws {
        let spec = try LearnedVerbSpec.export(flamingoManifest(),
                                              policyPath: "policies/flamingo-cycle.onnx")
        let task = try DuckTask(
            name: "one-foot-demo",
            summary: "Stand on one foot on command, then come back to two.",
            author: "duck studio",
            verbs: .init(allow: ["flamingo-cycle", "stop"], confirm: ["flamingo-cycle"]),
            success: ["The duck stood on one foot and came back down without falling."],
            abortWhen: ["Battery below 20%", "Same verb fails 2 times in a row"],
            learnedVerbs: [spec.duckDeclaration],
            body: "# Task\n\nAsk for the flamingo, then stop.")

        let written = String(decoding: task.encode(), as: UTF8.self)
        XCTAssertTrue(written.contains("  - name: flamingo-cycle\n"), written)
        XCTAssertTrue(written.contains("    policy: policies/flamingo-cycle.onnx\n"), written)
        XCTAssertTrue(written.contains("      safety_class: confirm\n"), written)

        let reread = try DuckTask.decode(task.encode())
        XCTAssertEqual(reread, task, "a learned verb has to survive the round trip intact")
        XCTAssertEqual(reread.learnedVerbs.first?.metadata["training_run"]?.stringValue,
                       "pollen-robotics/flamingo-cycle-r2-hard-20260829-0245")
        XCTAssertEqual(reread.learnedVerbs.first?.metadata["command_idle"]?.listValue,
                       [.double(0), .double(0), .double(0)])
        XCTAssertEqual(reread.batteryAbortPercent, 20.0)
        XCTAssertEqual(reread.repeatFailureAbort, 2)
    }

    /// The timeout has nowhere to live in a `.duck` — quackd's `LearnedVerbRef` has no
    /// `timeout_s` field — so it is written into the metadata rather than dropped.
    func testTheTimeoutSurvivesOnlyAsMetadataBecauseTheDuckShapeHasNoFieldForIt() throws {
        let spec = try LearnedVerbSpec.export(flamingoManifest(), policyPath: "p.onnx",
                                              timeoutSeconds: 7.5)
        let declaration = spec.duckDeclaration
        XCTAssertEqual(declaration.name, "flamingo-cycle")
        XCTAssertEqual(declaration.policy, "p.onnx")
        XCTAssertEqual(declaration.metadata["timeout_s"]?.numberValue, 7.5)
    }

    // MARK: - a criterion with a colon in it, which the writer quotes and the reader must
    //         not then read as a mapping

    /// THE ONE THAT GOT THROUGH. `quoteIfNeeded` quotes any criterion containing `: `, so
    /// the writer emitted `  - "ball moved: at least 0.3 m"` — and `parseSequence` asked
    /// `splitKey` about the raw item text, `splitKey` cannot see quotes, and the item came
    /// back a mapping. The author was then told "success has to be text" about a file this
    /// app had written thirty milliseconds earlier.
    func testACriterionContainingAColonSurvivesItsOwnExport() throws {
        let task = try DuckTask(name: "colon-criterion",
                                summary: "A success criterion with a colon in it.",
                                verbs: .init(allow: ["kick"]),
                                success: ["ball moved: at least 0.3 m"],
                                abortWhen: ["battery: below 15%"],
                                body: "# Task\nKick it.")
        let written = String(decoding: task.encode(), as: UTF8.self)
        XCTAssertTrue(written.contains("  - \"ball moved: at least 0.3 m\"\n"),
                      "the writer is expected to quote it — that is not the bug:\n\(written)")
        let reread = try DuckTask.decode(task.encode())
        XCTAssertEqual(reread.success, ["ball moved: at least 0.3 m"])
        XCTAssertEqual(reread.abortWhen, ["battery: below 15%"])
        XCTAssertEqual(reread, task)
    }

    /// The mirror half, and the one that matters more: a HAND-WRITTEN file. PyYAML reads
    /// both of these as a plain string, so quackd runs them, so this reader accepting them
    /// is the whole justification for the reader existing.
    func testAQuotedCriterionInAHandWrittenFileIsAccepted() throws {
        for quote in ["\"", "'"] {
            let source = """
            ---
            duck: 0
            name: hand-written
            description: A criterion with a colon in it.
            verbs:
              allow: [kick]
            success:
              - \(quote)ball moved: at least 0.3 m\(quote)
            ---

            # Task

            Kick it.
            """
            let task = try DuckTask.decode(Data(source.utf8))
            XCTAssertEqual(task.success, ["ball moved: at least 0.3 m"],
                           "a \(quote)-quoted criterion is a string, not a mapping")
        }
    }

    /// A quoted item that is genuinely a mapping is still a mapping, so the fix above did
    /// not simply switch the parser off: `learned_verbs` is a block sequence of mappings and
    /// has to keep parsing as one.
    func testABlockSequenceOfMappingsIsStillReadAsMappings() throws {
        let task = try DuckTask(name: "verbs",
                                summary: "One learned verb.",
                                verbs: .init(allow: ["flamingo_cycle"],
                                             confirm: ["flamingo_cycle"]),
                                success: ["The duck is standing."],
                                learnedVerbs: [.init(name: "flamingo_cycle",
                                                     policy: "p.onnx",
                                                     description: "Stand on one foot.")],
                                body: "# Task\nStand on one foot.")
        let reread = try DuckTask.decode(task.encode())
        XCTAssertEqual(reread.learnedVerbs.count, 1)
        XCTAssertEqual(reread.learnedVerbs.first?.policy, "p.onnx")
        XCTAssertEqual(reread, task)
    }

    /// A quoted scalar may carry a `#` comment after it, and the comment has to come off
    /// BEFORE the quotes do. It used to come off after, which meant `unquote` had already
    /// failed on a value that no longer ended in a quote — and the criterion came back
    /// wearing its own quote characters, silently, with no refusal anybody could act on.
    func testAQuotedValueMayCarryATrailingComment() throws {
        let source = """
        ---
        duck: 0
        name: commented
        description: "one line: with a comment"   # the description's own note
        verbs:
          allow: [kick]
        success:
          - "ball moved: 0.3 m" # measured in sim
          - 'the human said "it landed"' # quoted the other way
        ---

        # Task

        Kick it.
        """
        let task = try DuckTask.decode(Data(source.utf8))
        XCTAssertEqual(task.summary, "one line: with a comment")
        XCTAssertEqual(task.success, ["ball moved: 0.3 m", "the human said \"it landed\""])
    }

    /// The trap the same fix has to avoid: a `#` INSIDE the quotes is part of the value, and
    /// truncating there was the older, louder half of the same bug.
    func testAHashInsideQuotesIsPartOfTheValueAndNotAComment() throws {
        let source = """
        ---
        duck: 0
        name: hashed
        description: A hash inside quotes.
        verbs:
          allow: [kick]
        success:
          - "the ball is #1 # and this part is a comment"
          - "trailing hash only # here"
        ---

        # Task

        Kick it.
        """
        let task = try DuckTask.decode(Data(source.utf8))
        XCTAssertEqual(task.success, ["the ball is #1 # and this part is a comment",
                                      "trailing hash only # here"])
    }

    // MARK: - every character YAML cares about, through the writer and back

    /// Each value below contains something YAML reads as punctuation rather than prose, and
    /// each is a shape a person really types into a criterion. The table exists because
    /// discovering these one at a time is exactly how a writer that emitted a file its own
    /// reader refused survived four hundred tests.
    private static let awkwardValues: [(what: String, value: String)] = [
        ("a colon and a space", "ball moved: at least 0.3 m"),
        ("a trailing colon", "check the beak:"),
        ("a colon with no space after it", "c:\\balls\\moved"),
        ("a hash after a space", "quack once # then stop"),
        ("a leading hash", "#1 priority is the ball"),
        ("a leading dash", "- kick, then look"),
        ("a leading pipe", "| is not a block scalar here"),
        ("a leading angle bracket", "> 0.3 m of travel"),
        ("a leading ampersand", "&anchor is not an anchor"),
        ("a leading star", "*alias is not an alias"),
        ("a leading question mark", "? unsure whether the ball moved"),
        ("a leading bang", "!tag is not a tag"),
        ("a leading percent", "%directive is not a directive"),
        ("a leading backtick", "`kick` reports the distance"),
        ("a leading brace", "{not a flow mapping}"),
        ("a leading bracket", "[not a flow list]"),
        ("double quotes around the whole value", "\"the kick landed\""),
        ("double quotes in the middle", "the human said \"it landed\""),
        ("single quotes around the whole value", "'the kick landed'"),
        ("an apostrophe in the middle", "the project's main line"),
        ("a leading space", " leading space is part of it"),
        ("a trailing space", "trailing space is part of it "),
        ("commas", "search, walk, kick"),
        ("a backslash", "escape \\n is two characters here"),
        ("a value that reads as a number", "0.3"),
        ("a value that reads as true", "true"),
        ("a value that reads as null", "null"),
        ("unicode", "the ball moved ≥ 0.3 m — quack 🦆"),
        ("the empty value", ""),
        ("a very long line",
         String(repeating: "the ball moved far enough to count. ", count: 60) + "done."),
    ]

    /// One task carrying the value in every free-text field the frontmatter has — block
    /// scalar, block list, flow list and metadata all at once, because each of the four has
    /// its own quoting rule and its own reader.
    private func taskCarrying(_ value: String) throws -> DuckTask {
        let summary = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "A task carrying an awkward value." : value
        return try DuckTask(
            name: "round-trip",
            summary: summary,
            author: value,
            verbs: .init(allow: ["kick", "stop"], confirm: ["stop"]),
            success: [value, "the duck is standing"],
            abortWhen: [value, "Battery below 15%"],
            persona: value,
            providers: [value, "fake"],
            learnedVerbs: [.init(name: "flamingo_cycle", policy: "p.onnx", description: value,
                                 metadata: ["note": .string(value),
                                            "nested": .mapping(["note": .string(value)]),
                                            "listed": .list([.string(value), .string("fake")])])],
            body: "# Task\nStand still and report.")
    }

    /// THE TEST THAT WOULD HAVE CAUGHT IT. A file this writer produces must be a file this
    /// reader reads back as the same task — the promise made twice at the top of
    /// `DuckTask.swift`, and the one a quoted criterion broke.
    func testEveryAwkwardValueSurvivesTheRoundTrip() throws {
        for (what, value) in Self.awkwardValues {
            let task = try taskCarrying(value)
            let written = task.encode()
            let reread = try DuckTask.decode(written)
            XCTAssertEqual(reread, task,
                           "a value containing \(what) did not survive:\n"
                         + String(decoding: written, as: UTF8.self))
            // A SECOND WRITE HAS TO AGREE WITH THE FIRST. Quoting a value that was already
            // quoted accretes a layer on every save, and the equality above cannot see it
            // because the value it compares is correct at each step.
            XCTAssertEqual(reread.encode(), written,
                           "\(what): writing it a second time produced a different file")
        }
    }

    // MARK: - a metadata name this writer cannot write down

    /// THE TRUE SET, AS A TABLE, because the last two sentences written here were wrong.
    /// This test replaces one that listed `a: b`, `a:b`, `trailing:` and `{a: b}` as
    /// unwritable and a class comment that said the refused set "in practice means one
    /// holding a colon". Every one of those is written and read back now: the colons were
    /// never the writer's problem, they were `flowKeyColon` cutting a quoted key before
    /// `unquote` ran.
    ///
    /// EVERY ROW IS MEASURED IN ALL THREE PLACES A NAME CAN SIT, because the answer differs
    /// between them and a table that only asked about one would go on being tidy and false.
    /// `a}b` at the top of a metadata mapping is fine; the same name inside a `[ ]` is not,
    /// and saying "`a}b` is unwritable" would send an author renaming a key that works.
    ///
    /// THE RESIDUE IS TWO NAMED TRAITS AND ONE UNNAMED FAMILY. A carriage return, which
    /// nothing in the reader can hand back out of a file; brackets that do not close each
    /// other, which only bites where the name is nested; and — also only nested — a name
    /// whose brackets balance by COUNT but whose running depth returns to zero at a comma,
    /// so `splitTopLevel` cuts the entry there. `},{` is the shape, and it gets the fallback
    /// sentence rather than a named character, because there is no single character to name.
    /// `testTheMetadataRefusalNeverTurnsAwayAFileThisReaderCanRead` is the other half of the
    /// claim: none of the three can arrive from a `.duck`.
    func testTheTrueSetOfMetadataNamesThisWriterRefuses() {
        /// name -> refused at the top of metadata / nested in a mapping / nested in a list.
        let table: [(String, Bool, Bool, Bool)] = [
            // A carriage return has no place to go at all. It is the only name in this
            // table refused at the top level.
            ("a\rb", true, true, true),
            // Brackets that do not close each other survive everywhere a quote can open for
            // them, and only fail one level down, inside a `[ ]` or a `{ }`.
            ("a}b", false, false, true),
            ("a{b", false, false, true),
            ("a[b", false, false, true),
            ("a]b", false, false, true),
            ("a, }", false, false, true),
            ("a: }", false, false, true),
            // BALANCED BY COUNT AND STILL UNWRITABLE, which is the third family and the
            // reason the comment above says "residue" rather than "exactly two". The running
            // depth returns to zero at the comma, so `splitTopLevel` cuts the entry in half
            // there. No single character is at fault, so these get the fallback sentence.
            ("},{", false, false, true),
            ("}a,{", false, false, true),
            ("a},{", false, false, true),
            // Counted, not looked for: these hold brackets that DO close each other, in the
            // one running count `splitTopLevel` keeps, so they go everywhere.
            ("a}b{c", false, false, false),
            ("a{b}c", false, false, false),
            ("a[b]c", false, false, false),
            ("}{", false, false, false),
            // The names the old table called unwritable. All of them are written now.
            ("a: b", false, false, false),
            ("a:b", false, false, false),
            ("trailing:", false, false, false),
            ("{a: b}", false, false, false),
            ("[a: b]", false, false, false),
            ("x, y: z", false, false, false),
            ("he said \"hi\", ok", false, false, false),
            ("he said 'hi', ok", false, false, false),
        ]
        for (name, atTop, whenNested, whenInAList) in table {
            let shapes: [(String, [String: DuckValue], Bool)] = [
                ("at the top of metadata", [name: .integer(1)], atTop),
                ("nested in a mapping", ["outer": .mapping([name: .integer(1)])], whenNested),
                ("nested in a list",
                 ["outer": .list([.mapping([name: .integer(1)])])], whenInAList),
            ]
            for (where_, metadata, shouldRefuse) in shapes {
                let task = Result { try metadataTask(metadata) }
                if shouldRefuse {
                    XCTAssertThrowsError(try task.get(),
                                         "\"\(name)\" \(where_) should have been refused") {
                        XCTAssertEqual($0 as? DuckTask.ReadError,
                                       .metadataNameIsNotWritable(verb: "flamingo_cycle",
                                                                  name: name))
                    }
                } else {
                    // Not refused is not enough — the point of not refusing it is that the
                    // file comes back holding the same name.
                    guard let built = try? task.get() else {
                        XCTFail("\"\(name)\" \(where_) was refused"); continue
                    }
                    XCTAssertEqual(try? DuckTask.decode(built.encode()), built,
                                   "\"\(name)\" \(where_) did not survive the round trip:\n"
                                 + String(decoding: built.encode(), as: UTF8.self))
                }
            }
        }
    }

    /// And the refusal says which verb and which name, because "invalid metadata" sends an
    /// author looking through a whole file.
    func testTheMetadataRefusalNamesTheVerbAndTheName() {
        let message = DuckTask.ReadError
            .metadataNameIsNotWritable(verb: "flamingo_cycle", name: "a: b").message
        XCTAssertTrue(message.contains("flamingo_cycle"), message)
        XCTAssertTrue(message.contains("\"a: b\""), message)
        XCTAssertTrue(message.contains("Rename it."), message)
    }

    /// AND IT NAMES THE CHARACTER, not the rule. An author who has just been told their
    /// name is unusable has to be able to look at it and see which key to press; a sentence
    /// that lists every rule and leaves them to work out which one they broke is the bug,
    /// not a wording preference. An earlier version listed rules — and left the tab it
    /// refused off the list entirely.
    ///
    /// A REASON THAT IS NOT THE REASON IS THE SAME BUG WEARING A CHARACTER. The version
    /// before this one answered `a: }` with "it contains a colon" — a colon this writer
    /// places without trouble — leaving an author to delete the wrong character and watch
    /// the refusal come back. Both surviving branches are asserted against the name that
    /// tests them, and the sentence says WHERE the name cannot go rather than claiming it
    /// can go nowhere, because `a}b` one level up is written and read back perfectly.
    func testTheMetadataRefusalNamesTheCharacterThatCausedIt() {
        func why(_ name: String) -> String {
            DuckTask.ReadError.metadataNameIsNotWritable(verb: "v", name: name).message
        }
        XCTAssertEqual(why("a}b"),
                       "The learned verb \"v\" has a metadata setting named \"a}b\", and "
                     + "there is no way to write that name where it sits and read it back: "
                     + "its brackets do not close each other, and a name nested inside a "
                     + "[ ] or a { } has to close its own. Written out, \"a}b\" would come "
                     + "back as a different name holding a different value, and nothing "
                     + "would complain. Rename it.")
        XCTAssertTrue(why("a\rb").contains("it contains a carriage return"), why("a\rb"))
        for name in ["a{b", "a[b", "a]b", "a, }", "a: }"] {
            XCTAssertTrue(why(name).contains("its brackets do not close each other"),
                          why(name))
        }
        // The colon in `a: }` is not the trouble and the sentence must not say it is.
        XCTAssertFalse(why("a: }").contains("colon"), why("a: }"))
    }

    /// THE REFUSAL MUST NOT COST ANYBODY A FILE QUACKD RUNS. Every name below is one this
    /// reader can hand back from a real file — `12` and `true` are names here, not values,
    /// and `splitKey` does no type inference on a key — so every one of them has to stay
    /// legal and has to round-trip unchanged.
    ///
    /// MOST OF THIS LIST USED TO BE REFUSED. ` x`, `#x`, `-x`, a leading tab and `a, b` were
    /// all turned away on the grounds that no file could produce them, which was false: a
    /// quoted flow key hands every one of them back. They are written now instead, in flow
    /// form, and that is what this list is for. The colon-bearing tail joined them when
    /// `flowKeyColon` stopped cutting a quoted key in half.
    func testAMetadataNameThisFormatCanWriteDownIsKept() throws {
        let writable = ["timeout_s", "a b", "a#b", "a #b", "a, b", "12", "true", "[a]",
                        "{a}", "a's name", "a\"b", "ünïcode", "a\tb", "", " leading space",
                        "trailing space ", "-leading dash", "#leading hash", "\ttabbed",
                        "tabbed\t", "a\nb", "\"quoted", "'quoted", "a}b", "a b, c",
                        "a: b", "a:b", "trailing:", "{a: b}", "[a: b]", "x, y: z",
                        "a: b, c", "he said \"hi\", ok", "he said 'hi', ok", "a\"b,y",
                        "a'b,y", "a''b", "back\\slash", "a\"b\"c", "}{", "a}b{c"]
        for name in writable {
            let task = try metadataTask([name: .integer(1)])
            let reread = try DuckTask.decode(task.encode())
            XCTAssertEqual(reread.learnedVerbs.first?.metadata[name], .integer(1),
                           "\"\(name)\" stopped round-tripping:\n"
                         + String(decoding: task.encode(), as: UTF8.self))
            XCTAssertEqual(reread.encode(), task.encode(),
                           "\"\(name)\": writing it a second time produced a different file")
        }
    }

    /// A NAME A BLOCK LINE CANNOT CARRY SENDS ITS WHOLE MAPPING INTO FLOW FORM, quoted, and
    /// the bytes are asserted here because that form choice is the entire reason the names
    /// above survive. It has to be the whole mapping: a block line writes its name raw, so
    /// there is no way to quote one entry and leave its neighbours in place.
    func testANameBlockFormCannotCarryIsWrittenInFlowInstead() throws {
        let plain = try metadataTask(["timeout_s": .integer(30), "kind": .string("walk")])
        XCTAssertTrue(String(decoding: plain.encode(), as: UTF8.self)
                        .contains("    metadata:\n      kind: walk\n      timeout_s: 30\n"),
                      String(decoding: plain.encode(), as: UTF8.self))

        let awkward = try metadataTask(["#note": .integer(1), "timeout_s": .integer(30)])
        XCTAssertTrue(String(decoding: awkward.encode(), as: UTF8.self)
                        .contains("    metadata: {\"#note\": 1, timeout_s: 30}\n"),
                      String(decoding: awkward.encode(), as: UTF8.self))

        // A ` #` GOES TO FLOW FORM FOR QUACKD'S SAKE, NOT THIS READER'S. This reader's block
        // branch hands `a #b: 1` back as the whole name `a #b`, so a round-trip test cannot
        // see the problem — but PyYAML starts a comment at the ` #`, leaving `a` with no
        // colon, and a writer that can hand quackd a file quackd refuses is the one thing
        // this type promises not to be. Asserted as bytes because nothing else can see it.
        let commented = try metadataTask(["a #b": .integer(1)])
        XCTAssertTrue(String(decoding: commented.encode(), as: UTF8.self)
                        .contains("    metadata: {\"a #b\": 1}\n"),
                      String(decoding: commented.encode(), as: UTF8.self))
    }

    /// A name nested inside metadata is written by the same writer and read by the same
    /// reader, so it is checked on the same terms — but the terms are not the same
    /// everywhere, and that is the point. Inside a `[ ]`, `splitTopLevel` has already seen
    /// the enclosing `{` by the time it reaches a key's quote, so a quote cannot open there
    /// and a name's own brackets have to balance on their own. A comma is fine, a colon is
    /// fine, and a `\"` inside the name is fine — the quotes hold for all three — which is
    /// why they are written rather than refused.
    func testANestedMetadataNameIsCheckedToo() throws {
        XCTAssertThrowsError(try metadataTask(["outer": .list([.mapping(["a}b": .integer(1)])])])) {
            XCTAssertEqual($0 as? DuckTask.ReadError,
                           .metadataNameIsNotWritable(verb: "flamingo_cycle", name: "a}b"))
        }
        // The same name one level up, where a quote CAN open, is written and read back.
        let nested = try metadataTask(["outer": .mapping(["a}b": .integer(1)])])
        XCTAssertEqual(try DuckTask.decode(nested.encode()), nested)
        // A colon, a comma, and an escaped quote all survive the deepest placement there
        // is. Each of these was refused before the reader was fixed under it.
        for name in ["a, b", "a: b", "he said \"hi\", ok", "he said 'hi', ok", "{a: b}"] {
            let inAList = try metadataTask(["outer": .list([.mapping([name: .integer(1)])])])
            XCTAssertEqual(try DuckTask.decode(inAList.encode()), inAList,
                           "\"\(name)\" nested in a list did not survive:\n"
                         + String(decoding: inAList.encode(), as: UTF8.self))
        }
    }

    /// THE PROPERTY THE WHOLE REFUSAL RESTS ON. Refusing a name is only safe while no real
    /// file can produce one, because a `.duck` that quackd runs and this app refuses is the
    /// one failure this reader exists to prevent. Every name below is fed in as HAND-WRITTEN
    /// frontmatter, in all three shapes a real file can put a metadata name in — a block
    /// line, a quoted flow key, and a quoted flow key one level deeper inside a list.
    /// Whatever the reader makes of it — a name of its own, or a refusal for a different
    /// reason — it must never be the metadata refusal, and whatever it reads must go back
    /// out and come back in unchanged.
    ///
    /// THE FLOW ROWS ARE THE ONES THAT MATTER. An earlier version of this test fed every
    /// name in BLOCK FORM ONLY, where `splitKey` genuinely cannot hand back a bad name, so
    /// it passed by construction and could not see that the refusal it was named after was
    /// turning away `outer: {" x": 1}` — a file PyYAML, and so quackd, reads without
    /// complaint. Adding the flow rows is what made it able to fail.
    ///
    /// THE SINGLE-QUOTED ROWS ARE HERE BECAUSE THE DOUBLE-QUOTED ONES ALONE WERE NOT ENOUGH
    /// EITHER. With only `"…"` shapes on the table, `he said "hi", ok` written as `'he said
    /// "hi", ok'` was refused and this test could not see it — `splitTopLevel` ended the
    /// quoted run at the bare `"` and the comma after it cut the entry in half. Nine
    /// placements now: a block line, a block line quoted both ways, a flow key quoted both
    /// ways, the same one level down inside a `[ ]`, and both of those with the whole
    /// mapping written at the `metadata:` root. Each name and shape below was checked
    /// against PyYAML 6.0.2 before it was written down; 22 of these rows were refused
    /// before the reader was fixed under them, and the whole table passes now.
    ///
    /// WHAT THIS DOES NOT PROVE, said plainly: it proves no file THIS READER CAN READ is
    /// turned away by the metadata refusal, not that this reader reads every file PyYAML
    /// does. A quoted key on a BLOCK line is still read with its quotes on — the limitation
    /// the class comment names — and `outer: [{"a}b": 1}]` is still refused on the line, by
    /// `splitTopLevel`, before there is a name to refuse. Both are misreads or parse
    /// refusals with their own names; neither is this refusal, and neither is fixed by
    /// pretending otherwise here.
    func testTheMetadataRefusalNeverTurnsAwayAFileThisReaderCanRead() throws {
        for name in ["a: b", "a:b", "trailing:", "", " leading space", "trailing space ",
                     "-leading dash", "#leading hash", "\ttabbed", "tabbed\t", "a\tb",
                     "a b", "a#b", "a #b", "a, b", "12", "true", "[a]", "{a}", "a's name",
                     "a\"b", "ünïcode", "a}b", "a{b", "a[b", "a]b", "\"quoted", "'quoted",
                     "a\\nb", "a b, c", "{a: b}", "[a: b]", "x, y: z", "a: b, c",
                     "he said \"hi\", ok", "he said 'hi', ok", "a\"b,y", "say \"hi\",y",
                     "\",y", "x\",y", "q\"q,q", "a'b,y", "a''b", "back\\slash", "a\"b\"c",
                     "a}b{c"] {
            let double = Self.doubleQuoted(name), single = Self.singleQuoted(name)
            for block in ["    metadata:\n      \(name): 1",
                          "    metadata:\n      \(double): 1",
                          "    metadata:\n      \(single): 1",
                          "    metadata:\n      outer: {\(double): 1}",
                          "    metadata:\n      outer: {\(single): 1}",
                          "    metadata:\n      outer: [{\(double): 1}]",
                          "    metadata:\n      outer: [{\(single): 1}]",
                          "    metadata: {outer: [{\(double): 1}]}",
                          "    metadata: {outer: [{\(single): 1}]}"] {
                do {
                    let task = try DuckTask.decode(Data(Self.fileCarrying(block).utf8))
                    XCTAssertEqual(try DuckTask.decode(task.encode()), task,
                                   "\"\(name)\" came out of \(block) and would not go back in")
                } catch let error as DuckTask.ReadError {
                    if case .metadataNameIsNotWritable = error {
                        XCTFail("the reader read \"\(name)\" out of \(block) and then "
                              + "refused it: \(error.message)")
                    }
                }
            }
        }
    }

    /// WHAT THE READER STILL GETS WRONG, pinned so that the honest claim above stays honest.
    /// These are misreads, not refusals, and they are the reason the class comment says this
    /// subset is narrower than PyYAML rather than saying it is not.
    ///
    /// A QUOTED KEY ON A BLOCK LINE KEEPS ITS QUOTES. `splitKey` divides `key: value` before
    /// anything unquotes, so `"a b": 1` on a line of its own is the name `"a b"` here and
    /// the name `a b` to PyYAML. It is left alone deliberately: `nameFits(_:at: .block)`
    /// writes a block name RAW, so teaching the reader to unquote would make the writer have
    /// to quote, which changes the bytes of every metadata mapping in every file this app
    /// has ever written. The flow forms carry every awkward name already, so the cost buys
    /// nothing. It is a misread of a hand-written file and it is written down as one.
    func testAQuotedKeyOnABlockLineKeepsItsQuotes() throws {
        let task = try DuckTask.decode(
            Data(Self.fileCarrying("    metadata:\n      \"a b\": 1").utf8))
        XCTAssertEqual(task.learnedVerbs.first?.metadata, ["\"a b\"": .integer(1)],
                       "PyYAML reads this file as the name `a b`")
        // The same name in a FLOW key — the shape the writer actually uses — is read the way
        // PyYAML reads it. That is why the misread above costs nothing on a written file.
        let flow = try DuckTask.decode(
            Data(Self.fileCarrying("    metadata:\n      outer: {\"a b\": 1}").utf8))
        XCTAssertEqual(flow.learnedVerbs.first?.metadata,
                       ["outer": .mapping(["a b": .integer(1)])])
    }

    /// A name whose brackets do not close each other, nested inside a `[ ]`, is a file this
    /// reader cannot read AT ALL — `splitTopLevel` counts the enclosing `{` and the name's
    /// stray `}` together and reports the line. PyYAML reads it.
    ///
    /// IT IS PINNED HERE BECAUSE IT IS THE OTHER HALF OF THE REFUSAL'S ALIBI. The claim
    /// `validate()` rests on is that its refusal can never meet a name that came out of a
    /// file; this is the one trait where a file could in principle carry such a name, and
    /// the reason it cannot is that the file is turned away one layer earlier, by the
    /// parser, with a line number and a reason. A different wrong, honestly reported.
    func testANestedNameWithUnbalancedBracketsIsRefusedByTheParserNotByTheName() {
        let block = "    metadata:\n      outer: [{\"a}b\": 1}]"
        XCTAssertThrowsError(try DuckTask.decode(Data(Self.fileCarrying(block).utf8))) {
            guard case .malformedYAML(_, let reason) = ($0 as? DuckTask.ReadError) else {
                return XCTFail("expected a parse refusal, got \($0)")
            }
            XCTAssertEqual(reason, "unbalanced quotes or brackets")
        }
    }

    /// A YAML double-quoted scalar carrying exactly `name`, and a single-quoted one.
    ///
    /// HAND-ROLLED RATHER THAN BORROWED FROM `DuckYAML.quoteIfNeeded`, on purpose: a table
    /// that quoted its names with the writer's own escaping could only ever agree with the
    /// writer, and the point of the table is to hold a HAND-WRITTEN file against it. These
    /// two follow the YAML spec — `\\`, `\"`, `\n`, `\t` in a double-quoted scalar, `''` in
    /// a single-quoted one — and every row they produce was run through PyYAML 6.0.2.
    private static func doubleQuoted(_ name: String) -> String {
        var out = "\""
        for character in name {
            switch character {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default: out.append(character)
            }
        }
        return out + "\""
    }

    private static func singleQuoted(_ name: String) -> String {
        "'" + name.replacingOccurrences(of: "'", with: "''") + "'"
    }

    /// The whole `metadata:` block, indented as it sits under a learned verb — not just the
    /// name's line, because the mapping written at the `metadata:` root is one of the shapes
    /// a hand-written file uses and it has no line of its own.
    private static func fileCarrying(_ metadataBlock: String) -> String {
        """
        ---
        duck: 0
        name: from-a-file
        description: A hand-written metadata name.
        verbs:
          allow: [flamingo_cycle]
        success:
          - The duck is standing.
        learned_verbs:
          - name: flamingo_cycle
            policy: p.onnx
            description: ""
        \(metadataBlock)
        ---

        # Task

        Stand on one foot.
        """
    }

    private func metadataTask(_ metadata: [String: DuckValue]) throws -> DuckTask {
        try DuckTask(name: "metadata", summary: "One learned verb with metadata.",
                     verbs: .init(allow: ["flamingo_cycle"]),
                     success: ["The duck is standing."],
                     learnedVerbs: [.init(name: "flamingo_cycle", policy: "p.onnx",
                                          metadata: metadata)],
                     body: "# Task\nStand on one foot.")
    }
}

