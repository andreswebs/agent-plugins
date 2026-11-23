# Evals

Reference for a skill's `evals/` directory. Loaded from [SKILL.md](../SKILL.md) when the user asks for evals.

An eval settles by running what pruning settles by reading. The **no-op** test asks whether a line changes behaviour against the default; a **baseline** run answers it: the same prompt with and without the skill, graded the same way. A skill earns its **context load** when the two arms differ on the assertions that matter. Everything here is client-agnostic; the only client-specific piece is the runner, and its contract is fixed at the end.

## Layout

Test cases are part of the skill; run artifacts are not.

```text
my-skill/
  SKILL.md
  evals/
    evals.json        cases: prompt, expected output, files, assertions
    files/            inputs the cases refer to
    run.*             the runner, the one client-specific file
my-skill-workspace/
  iteration-1/
    eval-<id>/
      with_skill/     outputs/, timing.json, grading.json
      without_skill/  the baseline arm, same shape
    benchmark.json    aggregate per arm, and the delta
    feedback.json     human review, one actionable sentence per case
```

`evals.json` follows the Agent Skills spec:

```json
{
  "skill_name": "my-skill",
  "evals": [
    {
      "id": 1,
      "prompt": "a realistic user message, with the paths and details a real user gives",
      "expected_output": "what success looks like, in a sentence or two",
      "files": ["evals/files/input.csv"],
      "assertions": ["The output file is valid JSON", "Both chart axes are labeled"]
    }
  ]
}
```

`skill_ref.py validate` checks the file's shape when it is present. Extra fields per case are allowed, so a runner can carry machine-checkable expectations (a should-trigger flag, an expected reference file, an expected finding) beside the prose assertions.

## What an eval tests

Choose by the failure being hunted. A skill usually needs two or three of these, rarely all five.

### Triggering

Tests the **description** alone: the skill loads when it should and stays out when it should not. About twenty realistic queries labeled `should_trigger`, half positive and half negative, varied in phrasing, explicitness, and detail. The negatives that earn their place are **near-misses**: queries that share the skill's vocabulary but need something else. Run each query three times and record its **trigger rate**; a positive passes above 0.5, a negative below. Hold back about 40% of the queries as a validation set, revise the description against the rest only, and pick the iteration with the best validation rate, which is often not the last one. The description's ceiling is 1024 characters, and it grows under optimization. Done when every training query passes and the validation rate has stopped moving.

### Routing

For a skill with **branches**: which disclosed reference the agent reads for a given input. One prompt per branch, plus inputs that sit between branches, where the pass condition is that the agent asks rather than guesses. Grade on the first reference read; an agent that reads them all would otherwise pass. Done when each branch has a prompt that lands on it and each ambiguous prompt ends in a question.

### Output quality

The spec's core loop. Two or three cases to start, varied in phrasing and detail, at least one edge case. Run each with the skill and without, or against a snapshot of the previous version, each run from a clean context. Write **assertions** after the first run, once good has a visible shape: observable and countable ("at least three recommendations"), never a fixed phrasing. Grade each assertion PASS or FAIL with quoted evidence: a script for anything mechanical, a judge model for the rest, a human pass for what neither catches. Record tokens and time per arm, so the delta shows what the skill costs as well as what it buys. Done when every case has a graded pair of arms and `benchmark.json` carries the delta.

### Seeded defects

For a skill whose job is reviewing, validating, or auditing. Each item carries exactly one planted defect that mechanical checks cannot see; pass when the review names that item and stops there. Recall is cheap to buy with a noisy reviewer, so the ceiling on extra findings is the half of the assertion that matters. Done when every invariant the skill claims to enforce has an item that violates only it.

### Goldens

For `scripts/`. Fixtures and their captured output, compared byte for byte on every run, regenerated only after the diff has been read against the change that predicted it. Done when every command and every documented warning has a fixture that exercises it.

## Reading results

- An assertion that passes in both arms is a **no-op** measured: delete it, or the instruction it was written for.
- An assertion that fails in both arms is broken, impossible, or aimed at the wrong thing; fix it before the next iteration.
- An assertion that passes only with the skill is the skill's value; know which line earned it.
- A case that passes on some runs and fails on others is **flaky**, and flakiness is ambiguity read back: add the example or the sharper **completion criterion** the runs disagreed about.
- A run three times longer than its neighbours has a transcript worth reading.
- Human feedback is one actionable sentence per case; an empty entry is a pass.

## Iterating

Give the failed assertions, the feedback, the transcripts, and the current `SKILL.md` to a model and ask for changes that generalize: the fix addresses the class a failing prompt belongs to, not its wording. Each pass gets a new `iteration-N/`. Stop when feedback runs empty or the delta stops moving. Five iterations is usually enough, and a plateau under more rules means the skill is over-constrained: remove some and see whether results hold.

## The runner

The one file that knows the client. Its contract is small: start a clean run from a prompt, a set of files, and a working directory; return the final reply, the files written, and enough of the transcript to tell whether the skill loaded and which files it read. Where the client ships an eval command, prefer it; where it does not, a short script over the client's non-interactive mode does. Keep it under `evals/`, **self-contained** like any script, printing one PASS or FAIL line per case with the reason and exiting non-zero on any failure.

**Grade only a run that provably happened.** Every grader here reads absence as evidence: no reference file read, no skill loaded, no findings line. A client that crashed, was rate-limited, or exited on a bad flag produces exactly that same absence, so an unguarded runner scores a dead run as a should-not-trigger pass and reports green having tested nothing. Require positive proof in the transcript, at least one assistant turn or a non-error result, and give the runner a third outcome beside pass and fail: ERROR, which never counts as a pass and is worth retrying, unlike a graded failure. Two shapes to test deliberately, by pointing the runner at a binary that does not exist and at one that exits silently. Cost and duration are the field evidence: a run that took a second and cost nothing did not happen.
