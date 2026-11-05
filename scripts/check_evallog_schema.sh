#!/usr/bin/env bash
# Is every wire key of an inspect-robots EvalLog spelled in exactly one place?
#
# THE FAILURE THIS EXISTS TO CATCH IS A SECOND SPELLING OF A SCHEMA KEY.
# The app writes a file another project's library reads. `read_eval_log`
# rejects a log whose keys are not its keys, and the way that goes wrong is
# never a typo in the one place a reader would look: it is a second place that
# builds a dictionary by hand with "total_steps" typed into it, drifting from
# the enum that everything else uses until the two disagree about one field and
# nobody can say which is the schema. So the rule is that
# StudioKit/Sources/StudioKit/EvalLog.swift owns the forty strings, every other
# file spells them by their constant, and the app target never spells one at
# all, because the app target draws and does not serialise.
#
# WHY THE LIST IS TYPED OUT HERE RATHER THAN READ OUT OF EvalLog.swift.
# A guard that reads its expectation from the file it is guarding cannot fail:
# rename a key in both halves and the check still passes. These forty are
# transcribed from the plan's key table, which was measured against a real
# inspect-robots 0.58.0 log. Two independent statements of the same fact is the
# point, and the count assertion below is what makes adding a field deliberate.
#
# HOW A KEY IS MATCHED, AND WHY IT IS grep -F ON THE QUOTED LITERAL.
# The obvious form, a word-boundary match on the bare token, is red on arrival:
# `status` appears 90 times in DuckStudio/Sources today, `policy` 290, `error`
# 250, none of them schema keys, all of them ordinary Swift identifiers. A
# guard that is red for reasons nobody can fix gets weakened until it is green,
# which is the vacuous-gate failure check_no_studio_math.sh:44-52 already
# records having shipped once. What actually matters is the JSON literal, so
# what is matched is the fixed string "KEY" with its quotes, found with
# grep -F. Substring is exactly right here and the trap that usually comes with
# it does not apply: `"status"` cannot match `scene_status` or `TrialStatus`,
# because those carry no quote before the s.
#
# THE FOUR EXEMPTIONS, AND WHOSE PROTOCOL EACH ONE IS.
# Four of the forty are also wire keys of OTHER protocols this app already
# speaks, so the quoted literal is legitimately in more than one file:
#   "error"       the bench's own failure shape, read by DuckBench, DuckLink,
#                 DuckPeer, DuckDrive, ChatWire, BridgeHandshake, BenchSetup
#                 and the climb and chase readers, and written by the phone
#                 bench's shell in DuckStudio/Sources/PhoneBench.swift.
#   "policy"      duck-bench request and answer bodies, the challenge entrant
#                 files and duck-intent/2 all carry a `policy` key.
#   "eval"        PolicyManifest reads an `eval` block out of a policy's
#                 manifest, and EvalLogWriter uses the same four letters as the
#                 fallback filename stem, which is not a key at all.
#   "duration_s"  MotionPublication and PolicyManifest both publish a duration
#                 under that name, and have since before this feature existed.
# They are exempt from the one-file rule and from the app-target ban, and
# nothing else is. EvalLog.swift is still required to spell all four, so the
# exemption cannot hide the schema itself going missing.
#
# FIVE MORE WORDS ARE TAKEN BY OTHER FORMATS IN NAMED FILES, AND ONLY THERE.
# `created`, `embodiment`, `seed`, `status` and `task` are ordinary words later
# wire formats also use. Typing EvalLog.Key.seed into a LeRobot writer would be the
# wrong fix: it would tie that format to a schema it has nothing to do with, and
# a rename here would silently change a file another tool reads. But these five
# get no key-wide exemption either, since a hand-built log could then spell
# "seed" anywhere. So ELSEWHERE allows one key in one file, each pair naming its
# format below; every other file, and the app target, is held to the rules. A
# pair whose file stops spelling the key is red too, so the list cannot go stale.
#
# PROVED ABLE TO FAIL. On 2026-09-05, with the tree otherwise green, the line
#   let scratch = "total_scenes"
# was added to DuckStudio/Sources/EvalStore.swift and this script exited 1
# saying `"total_scenes" is spelled in the app target: DuckStudio/Sources/
# EvalStore.swift`. The same literal added to StudioKit/Sources/StudioKit/
# EvalRun.swift made it exit 1 on the one-file rule instead, naming both files.
# Both lines were removed and the script returned to exit 0. A gate nobody has
# watched go red is a comment.
# On 2026-11-05 ELSEWHERE went red the same way: "seed" in EvalRun.swift, in a
# file the list does not name, exit 1 naming the file; "task" in the app target,
# exit 1; "seed" taken out of Shoot.swift, exit 1 calling that pair stale.
#
# Usage:  scripts/check_evallog_schema.sh
# Run from anywhere. Exit 0 = one spelling per key, none in the app target.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT="$HERE/StudioKit/Sources"
APP="$HERE/DuckStudio/Sources"
OWNER="StudioKit/Sources/StudioKit/EvalLog.swift"

if [ ! -f "$HERE/$OWNER" ]; then
  echo "check_evallog_schema: no $OWNER" >&2
  echo "  This guard is about that file. Without it there is nothing to guard." >&2
  exit 2
fi

# The forty, in the order the plan's table lists them: seven at the top level,
# eleven under eval, four under results, six under stats, twelve more on a
# sample. `error` and `status` sit at two levels each, which is why twelve
# sample keys make forty and not forty-two.
KEYS=(
  error eval results samples stats status version
  created embodiment embodiment_info git_commit inspect_robots_version
  max_seconds max_steps policy policy_config seed task
  errored_trials metrics total_scenes total_trials
  completed_at duration_s frames_dir mean_inference_latency_s
  started_at total_steps
  epochs instruction judgement_sources operator_judgements operator_messages
  operator_notes policy_transcripts reduced scene_id scene_metadata
  termination_reasons trial_metadata
)

EXEMPT=(error policy eval duration_s)

# One key in one file under StudioKit/Sources/StudioKit, each another format's.
ELSEWHERE=(
  "created DuckFeedback.swift"     # a feedback card's own JSONL line
  "embodiment DuckDream.swift"     # dream.* request params, Dream Labs' wire
  "seed BallTakes.swift"           # a line of the driver's ball-takes file
  "seed DuckFeedback.swift"        # the `shown` block of a feedback card
  "seed RolloutPairs.swift"        # duckbench's rollout-pairs source block
  "seed Shoot.swift"               # duckbench's POST /shoot body
  "status DreamDirect.swift"       # Dream Labs' error body, read not written
  "status HubTraining.swift"       # the Hugging Face Jobs API, read not written
  "task BallTakes.swift"           # a line of the driver's ball-takes file
  "task DreamDataset.swift"        # LeRobot's meta/tasks.jsonl
)

fail=0

# RULE 3 FIRST, because the other two are meaningless over the wrong list.
# Forty is the schema's size, and a field arriving or leaving has to be a
# deliberate edit here rather than something a merge does quietly.
distinct=$(printf '%s\n' "${KEYS[@]}" | sort -u | wc -l)
if [ "$distinct" -ne 40 ] || [ "${#KEYS[@]}" -ne 40 ]; then
  echo "check_evallog_schema: the key list is ${#KEYS[@]} entries, $distinct distinct, not 40" >&2
  echo "  If inspect-robots' EvalLog gained or lost a field, say so here and in" >&2
  echo "  $OWNER, and check read_eval_log still opens what this app writes." >&2
  exit 1
fi

is_exempt() {
  local key="$1" e
  for e in "${EXEMPT[@]}"; do
    [ "$e" = "$key" ] && return 0
  done
  return 1
}

# grep -F on the quoted literal. --include keeps this off the test tree, which
# is allowed to quote anything it likes, and off Resources, where the vendored
# bench is JavaScript nobody here wrote.
kit_files() { grep -rlF "\"$1\"" "$KIT" --include='*.swift' 2>/dev/null | sort || true; }
app_files() { grep -rlF "\"$1\"" "$APP" --include='*.swift' 2>/dev/null | sort || true; }

# The kit's files for a key, less the ones ELSEWHERE gives to another format.
schema_files() {
  local key="$1" pair
  local files
  files=$(kit_files "$key")
  for pair in "${ELSEWHERE[@]}"; do
    if [ "${pair%% *}" = "$key" ]; then
      files=$(printf '%s\n' "$files" | grep -vxF "$KIT/StudioKit/${pair##* }" || true)
    fi
  done
  printf '%s' "$files"
}

for pair in "${ELSEWHERE[@]}"; do
  if ! grep -qF "\"${pair%% *}\"" "$KIT/StudioKit/${pair##* }" 2>/dev/null; then
    echo "check_evallog_schema: ELSEWHERE allows \"${pair%% *}\" in ${pair##* }, which no longer spells it" >&2
    echo "    Take the pair out of the list, so the allowance cannot outlive its reason." >&2
    fail=1
  fi
done

for key in "${KEYS[@]}"; do
  kit=$(schema_files "$key")
  app=$(app_files "$key")
  count=$(printf '%s' "$kit" | grep -c . || true)

  if is_exempt "$key"; then
    # The exemption is from the counting rules only. The schema must still be
    # written down somewhere, and that somewhere is EvalLog.swift.
    if ! printf '%s\n' "$kit" | grep -qx "$KIT/StudioKit/EvalLog.swift"; then
      echo "check_evallog_schema: \"$key\" is exempt but $OWNER does not spell it" >&2
      fail=1
    fi
    continue
  fi

  if [ "$count" -ne 1 ]; then
    echo "check_evallog_schema: \"$key\" is spelled in $count kit files, not 1:" >&2
    printf '%s\n' "$kit" | sed "s|^$HERE/|    |" >&2
    echo "    Spell it once, in $OWNER, and use EvalLog.Key from everywhere else." >&2
    fail=1
  elif [ "$kit" != "$KIT/StudioKit/EvalLog.swift" ]; then
    echo "check_evallog_schema: \"$key\" is spelled in ${kit#$HERE/}, not in $OWNER" >&2
    fail=1
  fi

  if [ -n "$app" ]; then
    echo "check_evallog_schema: \"$key\" is spelled in the app target:" >&2
    printf '%s\n' "$app" | sed "s|^$HERE/|    |" >&2
    echo "    The app draws a log; the kit writes one. A view that spells a wire" >&2
    echo "    key is a second serialiser nobody is testing." >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "check_evallog_schema: 40 keys, ${#EXEMPT[@]} exempt by another protocol, ${#ELSEWHERE[@]} pairs named elsewhere, one spelling each."
