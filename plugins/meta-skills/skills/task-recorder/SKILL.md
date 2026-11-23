---
name: task-recorder
description: >
  Record a task while it is done, to grow a seed for a future skill that
  repeats it: the task's phases, the forks taken, the pitfalls hit, the user's
  interventions, and the command sequences worth pinning as scripts. Use when
  asked to record, capture or learn from a task so it can be repeated or turned
  into a skill, whether before starting it or partway through.
metadata:
  argument-hint: "the task to record, e.g. 'prepare a scanned volume for OCR'"
---

# Task Recorder

```sh
AGENT_ARTIFACTS_DIR="${AGENT_ARTIFACTS_DIR:-$(pwd)/.local/data/agentartifacts}"
mkdir -p "${AGENT_ARTIFACTS_DIR}/task-recorder" && echo "${AGENT_ARTIFACTS_DIR}/task-recorder"
date -u +%Y%m%dT%H%M%SZ
```

Run this once when the run opens, and use the two printed values, the
directory and the run's `<UTC>` stamp, for every path below.

A session leaves a **black box** behind it. Every tool call, argument,
timestamp and result is written to the transcript as it happens, and it can be
read back exactly.

The black box records what was done. It cannot record what was chosen between.
So this skill has two capture modes, and the split between them is the whole
design:

- **Retrace** reconstructs actions from the black box, afterwards, verbatim.
- **Callouts** capture decisions in the moment, because nothing on disk holds
  the alternative that was rejected.

Both feed one **seed**: a document, grown over several **runs** of the same
task, from which a skill that repeats the task can later be written. A run is
one session's pass at the task. What one run shows may be incidental; what
several runs agree on is the procedure. The seed exists to tell the two apart.

## Steps

### 1. Open the run

Open the run as soon as the skill is invoked, even when the task itself is
still waiting, for an input or for the user to say go. Planning turns before
the task begins are where interventions pile up, and they belong to the run.

Name the task and derive its **slug**, lowercase and hyphenated, from the
argument. Each run writes its own seed,
`${AGENT_ARTIFACTS_DIR}/task-recorder/<slug>.<UTC>.seed.md`, and earlier
seeds stay as the task's history.

When earlier seeds exist, the newest `<slug>.*.seed.md` is the starting point:
write this run's seed as a copy of it, then read the copy: its runs, its
highest phase, learning and run numbers, and any unmerged section left by a
run whose session ended before step 4. Merge such a section now, as step 4
describes, against its own run, before opening this one.

When none exists, create this run's seed with the header from
[Seed layout](#seed-layout).

Read the seed path back after the first write. A harness may mediate file
access through policy, and an ignored directory is a common thing to deny
reads on, so a seed can be written and then be unreadable, which loses every
later run's merge. When the path will not read back, stop the run and tell the
user: the fix is to relaunch with `AGENT_ARTIFACTS_DIR` set to a readable
directory the project does not track as source.

Then append this run's unmerged section, `## R<n> unmerged`, and add the run to
the header: its number, date, session id, and whether it opened **live**, before
the task began, or **late**, with work already done. A late run's earlier
actions are recoverable and their reasons are not; the header says so, so that
a reader weighs its learnings accordingly.

Locate the **black box**: this session's transcript on disk. Where it lives and
what shape its records take are harness-specific, so read the reference for
yours before deriving anything: [Claude Code](references/claude.md),
[Kiro](references/kiro.md).

When the harness has no reference here, discover it in three moves, and write
one up afterwards so the next run inherits it. Identify the harness from its
environment variables and the running executable; find the state directory it
keys on, conventionally under the home directory and named for the vendor; then
locate this session's record inside it by **searching for the session id**
rather than reconstructing a path:

```sh
find "${STATE_DIR}" -name "*${SESSION_ID}*" 2>/dev/null
```

A found path beats a derived path. Every derivation is a chance to build a path
that does not exist, which reads as an unrecorded session and silently skips
the whole retrace, so search by id even where a derivation is documented.

Confirm the black box exists and is non-empty. When it is missing, treat a
wrong derivation as likelier than an unrecorded session and search again by id
before concluding. Only once no record for this session exists anywhere under
the state directory is the session genuinely unrecorded.

An unrecorded session runs **callout-only**: say so now rather than discovering
it at step 3, record the limit in the header, skip step 3, and let steps 2, 4
and 5 proceed unchanged. Call counts then come from the agent's own account of
the run, and are marked as estimates wherever they appear. Callout-only is a
degraded run, not a failed one: callouts carry what the black box never held
anyway, which is the whole of what a future skill most needs.

Set the run's **watermark**, the timestamp its retrace starts from: the
session's first event when opened late, since the task's earlier work must be
recovered, or the timestamp of the user turn that invoked this skill when
opened live.

**Done when:** the seed exists at a path that reads back, with this run in its
header and an unmerged section of its own, any earlier unmerged section has
been merged, the black box is confirmed or the run is declared callout-only,
and the watermark is recorded.

### 2. Call out at every fork

While doing the task, append to the run's unmerged section before acting on
what was found. A **callout** is three lines, numbered `R<n>.C<m>`, written
before the next action that relies on it, so that its outcome cannot shape it.
Several findings from one observation may share one append. Three forms,
because each becomes a different part of the future skill and forcing one into
another loses the part that matters.

A **fork**, written before the chosen path is executed. It becomes a branch or a
rule, and its third line carries the observation that decided it:

```markdown
### R2.C3

Chose: widen the parameter to `ArrayLike`.
Over: narrowing the call site with a cast, which hides that older stubs return a scalar.
Because: pyright reports `.any(axis=0)` may return `bool`, not an array, under the locked NumPy.
```

A **pitfall**, written at the moment of discovery. It has no road not taken, so
the third line carries the **discriminator**, the check that told wrong from
right. It becomes a completion criterion, since the discriminator is the check a
future run should make before believing it is done:

```markdown
### R2.C4

Wrong: the module type-checks clean, since strict pyright reports 0 errors.
Right: the editor still shows errors, because the project has no `.venv` to resolve imports from.
Separated by: the checker ran against a scratch venv; the editor's interpreter had none.
```

A **script candidate**, written when a command sequence is run that a future run
should run identically. It becomes a script:

```markdown
### R2.C5

Script: run ruff, then ty, then strict pyright against the project `.venv`.
Pins: the checker order, strict mode, and a config that includes dot-directories.
```

A callout that responds to an earlier one, such as a fix for a pitfall, or a
fix that failed and the one tried next, adds a fourth line, `Follows:
R<n>.C<m>`. The chain is what tells a future skill which attempts failed, and
the transcript holds only their order, not which one answered which.

What needs no callout: anything whose command and output the transcript already
holds, including what the user said. Retrace recovers those for free. A callout
is spent only on what the transcript lacks: the road not taken, the belief that
was wrong, or the judgement that a sequence must not vary.

**Done when:** every fork, pitfall and script candidate met so far has a
callout, including those that in hindsight look obvious.

### 3. Retrace the black box

At the end of the task, project the run's actions out of the transcript,
bounded by the watermark. Take the queries from your harness's reference
([Claude Code](references/claude.md), [Kiro](references/kiro.md)); whatever
their syntax, they project the same three things, and the reasons below hold
for all of them.

Timestamps come back exact. Use them rather than estimating, and rather than
narrating from memory of what happened.

**The tool calls after the watermark.** This projection is an **index, not
evidence**. A row carries a truncated or summarised form of the call, often the
agent's own description of what it was doing rather than a record of what ran,
and truncation cuts a file edit off before either of its strings. Quoting from
a row produces evidence that is merely plausible. Pull the full record whenever
a discriminator needs quoting; every harness keys its records by an id for
exactly that purpose, so carry the id in the index.

**The user's messages after the watermark.** This is the half most easily lost,
because a projection over typed turns alone misses two shapes. Account for all
three: the turns the user typed; the messages sent while a turn was already
running, which the harness stores separately and which are the likeliest of all
to be a correction; and the answers typed in place of picking an offered
option, where an answer made only of offered labels is a choice and anything
else is the user's own words. Harness context injected into a human turn, such
as a note of which file is open in the editor, is not something the user said:
drop those blocks rather than the turn that carries them.

Assign each tool call to a phase of the task, or drop it as **overhead**: the
recording itself, and anything else not serving the task. Count the calls per
phase, and the task and overhead totals; the counts go into the seed, and the
per-call assignment does not, since the transcript regenerates it. Classify
each user message as the task's instruction, an intervention (the user
redirected, corrected, or supplied what the agent should have known), or
unrelated.

**Done when:** every tool call after the watermark is assigned to a phase or
deliberately dropped as overhead, the counts add up to the index's length, and
every user message after it is classified — or, on a callout-only run, this
step is recorded as skipped and the counts are marked as estimates.

### 4. Merge into the seed

Fold the run into the seed's phases, then empty its unmerged section.

- **Phases.** Match the run's phases to the seed's by what they accomplish, not
  by their commands. A matched phase gains this run's number; an unmatched one
  is added in order and marked as seen once. A phase the seed has that this run
  skipped is noted as skipped, which is how an optional phase shows itself.
  Record, per phase, the check that actually ended it this run and the number
  of tool calls step 3 assigned to it, as `R<n> (<count> calls)`.
- **Learnings.** Each callout, and each intervention, becomes one learning
  `L<n>` under the phase it belongs to, carrying its kind, the rule stated as
  the behaviour a future run should show, its discriminator, and the runs that
  saw it. The discriminator is quoted verbatim: a fork's `Because:` line, a
  pitfall's `Separated by:` line, the output that showed a script's sequence
  working, or, for an intervention, the user's own words. A callout id is never
  a discriminator, since this step deletes what it names. A learning an earlier
  run already holds gains this run's number instead of being repeated.
- **Chains.** Callouts linked by `Follows:` merge into one learning for the
  path finally taken, plus one learning for each attempt that failed on the way,
  marked superseded by it, each with its own discriminator.
- **Conflicts.** When a later callout or a later run contradicts a learning,
  keep the old one, mark it superseded by the new one, and quote the
  discriminator that separated them. A conflict usually means the future skill
  needs a condition or a branch, which deleting the old learning would hide.

Write learnings so a future skill can carry them: paths relative to the project
and only to files the project tracks. Name a generated or ignored artifact by
its role (the page's raw image, the bundle's master) or by its pattern in the
project's layout (`work/<volume>/raw/`), never by a concrete instance, which
will not exist when the skill runs. No home directories, and no citation of the
seed or anything else under `${AGENT_ARTIFACTS_DIR}` or `.local/`. The run ids and session ids stay in the seed, since they are what
lets a learning be re-derived from its transcript.

**Done when:** the run's unmerged section is empty and removed, every callout
and every intervention appears in exactly one learning, and every phase the run
touched carries its number.

### 5. Report readiness

End the run with a readiness verdict in the reply, not in the seed:

- how many runs the seed holds, and how many opened live;
- phases seen in only one run;
- learnings resting on a single run, and learnings superseded;
- script candidates, and whether their sequences matched across runs.

Say whether the seed looks stable enough to write a skill from, and leave that
decision to the user.

**Done when:** the verdict names every single-run phase and every single-run
learning, or says there are none.

## Seed layout

One file per run, `${AGENT_ARTIFACTS_DIR}/task-recorder/<slug>.<UTC>.seed.md`,
each holding every run up to its own:

1. **Header**: the task in one line, then a runs table of run number, date,
   session id, live or late, watermark, task calls, and overhead calls.
2. **Phases**, one section per phase `P<n>` in task order, each opening with
   what the phase accomplishes, the runs that saw it with their call counts, and
   the check that ended it, then its learnings.
3. **Learnings**, under their phase, each as `L<n>`, one of `fork`, `pitfall`,
   `intervention` or `script`, with the rule, the discriminator, and the runs,
   plus `superseded by L<m>` where a later callout or run overturned it.
4. **Unmerged sections**, `R<n> unmerged`, at the end, present only while a run
   is in progress or ended before step 4.

## Reconstruction limits

State these in the seed's header whenever they bite, rather than letting a
reader assume the record is complete:

- Counterfactuals are gone unless a callout caught them. The transcript holds
  the path taken and nothing about the paths considered.
- Reasoning between tool calls is only partly recoverable, and only where the
  harness records it at all. What it records is reasoning as narrated, not as
  weighed.
- A compacted session loses detail in the compacted region. Whether compaction
  leaves a record, and how to test for one, is harness-specific; the references
  carry the test. Two cautions hold whichever harness it is. Test the marker
  **structurally**, as a record's own content, rather than by grepping for its
  text: the text appears in documents like this one, so loading or reading them
  plants a match, and each grep for it plants another. And since a structural
  test has no positive control, report what it establishes — "no compaction
  record found" — rather than "not compacted".
- Subagent work may be recorded apart from the main thread, in its own files or
  behind a flag, and needs pulling in separately. The references say which.
- A late run's early phases record what the transcript proves and what the
  writer recalls, and only the first half is evidence.
- Policy may deny reads the harness itself permits, so part of the record can
  be unreachable from inside the session. A refusal names the rule that
  produced it; report that as a limit rather than routing around it.
