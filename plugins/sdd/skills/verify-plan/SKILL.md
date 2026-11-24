---
name: verify-plan
description: Fact-check a plan, spec, or assessment against the code it describes, before acting on it. Use when finalizing a draft plan for implementation, when picking up a plan written in an earlier session or by someone else, when a document's evidence is tool output rather than a read of the source, or when a status table claims work is already done.
metadata:
  argument-hint: "path to the plan, spec, or assessment"
---

# Verify a plan against the code

A plan is a **secondary source**. The code is the **primary source**. Every
claim in the plan was true about some version of the system, believed by someone
holding partial information, and has been drifting since it was written.

Re-reading the plan cannot detect that drift, because the plan is internally
consistent. Only the primary source can. So the governing move is: **for each
claim, go to the code and re-derive it, without looking at what the plan
concluded.**

What this prevents is not a wrong plan. It is a **confident** wrong plan, whose
errors survive careful reading because the reasoning is sound and only the
premise is stale. Those are the ones that get implemented.

**Who wrote the plan is irrelevant, and your own plans are the hard case.** A
plan you wrote an hour ago is still a secondary source. Re-reading it, you
recognise your own reasoning as familiar and score it as verified, which is the
one thing reading cannot establish. Verify your own drafts before handing them
over, at the same depth you would verify someone else's.

## Steps

### 1. Inventory the claims

Extract every falsifiable assertion the document makes about the system: counts,
causes, "X is dead", "Y crashes", "Z is fixed", file and line references.

Ignore the document's own structure. A claim buried in a parenthetical carries
the same weight as one in a heading, and section headings often assert more than
the section proves.

**Done when** every claim names a place in the system where it can be checked.
Claims with no checkable location are labeled as judgment, and judgment is out of
scope: verify facts, and let the author keep their opinions.

### 2. Re-derive each claim from the primary source

Read the code the claim is about. Reach for the claim's own wording only after
forming your own reading, so the document's framing does not become the question
you ask.

**History is primary source too, and it is the cheapest one.** Current code says
what the system does; the commit that introduced a line says *why it exists*,
which is exactly what a claim like "this is vestigial" asserts. Reach for
`git log -S'<symbol>'` or `git log -- <path>` whenever the claim is about intent
rather than behavior, and read two things: the commit message, and **what else
changed in the same commit**. A dependency added alongside a platform-version
bump is a compatibility pin, and the diff says so in a way the code never will.

**Done when** every claim is marked confirmed, wrong, or imprecise, each with the
`file:line` or commit that decided it. "Imprecise" is the most valuable verdict
and the easiest to skip: the claim is true as stated and misleading as used.

### 3. Separate the symptom from the mechanism

Wherever the evidence is tool output (a linter finding, a grep count, a scanner
report), the tool reported a **symptom**. The document then supplied a
**mechanism** to explain it. Tools are reliable about symptoms and silent about
mechanisms, so the mechanism is the author's inference and is where the error
lives.

Claims come in two directions and each fails differently:

- **"X fails"** (it crashes, it leaks, it throws). Trace the path. Is the line
  **reachable**, does the branch execute, does the value flow where the claim
  says it flows.
- **"X is unused"** (dead, vestigial, safe to delete). This is a claim that
  something is *absent*, and a search proves absence only within what it can
  see. Ask what the search missed: build-time compilers, peer dependencies,
  resolution pins, config-file references, CSS and asset imports, dynamic or
  string-keyed dispatch, and callers outside the repository.

The second direction is the more dangerous one, because a removal looks like the
safest possible change and the evidence for it is an empty result. Empty results
are indistinguishable from wrong questions.

**Done when** no claim of the form "therefore it crashes" survives without a path
you traced, and no claim of the form "therefore it is safe to delete" survives
without naming what would break if you were wrong.

### 4. Read the negative space

The document's silences are invisible on re-reading, so hunt them deliberately.
At minimum:

- **A severity class nobody recorded.** The plan sorts findings by the harm it
  already noticed. Ask what other kinds of harm the same defect produces, and
  check for those directly.
- **An aggregate that hides shapes.** A count of N call sites, findings, or
  occurrences invites one uniform fix. Sample them and confirm they are one
  shape. Different shapes usually mean different failure semantics and different
  fixes.
- **What the measurement cannot see.** Every count is produced by a technique,
  and the technique defines a blind spot the number never mentions. "Zero import
  sites" measures imports, and answers "is this imported", not "is this used".
  Name the question the plan is actually asking, then ask whether the
  measurement can answer it. This subsumes the unit problem: "this file is
  fixed" and "this feature is secured" are different claims, and only one of
  them is about whether a user is affected.
- **Whether the gate would catch it.** For each change the plan proposes, ask
  which check would fail if it went wrong, then confirm that check exercises the
  thing. A suite that runs without a client does not catch a rendering break; a
  boot check that asserts the process started does not catch a broken page. A
  change whose failure mode no gate covers needs a human step written into the
  plan, not a hope.
- **What already shipped.** A plan that partitions work by risk assumes none of
  it has landed. Check history for the parts already committed or deployed; they
  are the ones no longer under the plan's control.

**Done when** each of the five has been checked against the system, not
considered and dismissed from the document.

### 5. Fold the corrections back

Rewrite the affected sections. Where a claim was wrong, **keep the wrong version
visible** with the reason it was believable, so the next reader does not re-derive
it from the same evidence and reach the same conclusion.

State the correction as a finding about the system, not as an apology about the
document.

**Done when** every verdict from step 2 is reflected in the document, and every
downstream section that depended on a corrected claim has been re-checked. A
correction usually invalidates a sequencing or scoping decision somewhere else,
and that decision will not announce itself.

## Reference

- [Worked example](references/worked-example.md), each pattern above as it
  appeared in a real migration plan.

## Judging your own work

The output is worthless if it says everything checks out. That result is
possible, and it is rare enough that it should prompt a second look at step 4
rather than relief: a plan of any size, written before the work started, is
almost always precise about what its author looked at and vague about what they
did not.

For calibration: on the real plans behind the worked example, roughly one claim
in seven was wrong or imprecise, and the wrong ones clustered. Two plans each
carried multiple errors **in the same direction**, because a single mistaken
habit of evidence produced all of them. When you find one, do not move on
satisfied; ask what else the author established the same way.

Report findings to the author rather than silently repairing them. A wrong claim
in a plan usually means someone holds a wrong belief about the system, and the
belief outlives the document.
