---
name: plan-to-tickets
description: Decompose a finalized plan, spec, or phase document into self-contained, dependency-mapped tickets that an independent agent can implement cold, without the plan open. Use when splitting a plan or phase into tickets, tasks, or issues; when filing a spec's commit sequence into a tracker as a work queue; or when a plan's ordering constraints need to become dependency edges.
metadata:
  argument-hint: "path to the plan document, and the tracker if not obvious"
---

# Plan to tickets

The bar for every ticket: an implementer who has never seen the plan picks
it up cold and can finish it. The tracker's mechanics (commands, file
formats) belong to that tracker's own skill; this one owns the
decomposition.

## 1. Learn the house conventions

Locate the tracker in use and read recent tickets **by role, not by count**:
an umbrella, at least one child, and a manual gate if the plan needs one.
The umbrella is the densest and least guessable of the three, and inventing
its format is the easiest way to miss house style.

Extract what you will replicate: body sections, metadata (type, priority,
tags, parent), the language tickets are written in, and what gets written
back into a ticket after it closes. Done when you can name the conventions
and the ID scheme you are extending.

## 2. Re-verify the plan against the source

Plans drift: line numbers move, versions bump, code turns out shaped
differently than described. Open every file the plan cites and check each
claim you intend to quote (paths, line numbers, "zero call sites",
versions). A discrepancy is evidence the ticket must carry, dated, not a
blocker.

**A count is only meaningful beside the unit of work it sizes.** Most wrong
numbers in a plan are accurate measurements of the wrong population: a total
presented as a workload, a subtree another section excludes, a filter that
answers the neighbouring question. Re-derive each count against the scope
the ticket will actually carry.

**Verifying the plan is not verifying the tickets, and the gap is widest when
you wrote the plan yourself.** Your own pass covered the plan's scope and left
you feeling done; each ticket carries a narrower scope, which is exactly where
an accurate measurement of the wrong population survives.

Anything that reads as a conflict inside the plan, rather than a mismatch
with the tree, goes to step 3 instead of into a ticket.

Done when every code reference in your draft bodies matches the working tree
today, every count matches the scope of the ticket that will quote it, and
every drift found is written down.

## 3. Sweep for stranded work, then ask the plan owner

Decomposition surfaces what writing the plan did not. Sweep for all four
before filing anything:

- **Stranded deliverables**: work the plan's own deferrals make impossible.
  "Convert the call sites and remove the package" cannot ship when two other
  sections defer the last consumers to later phases. The counts under a
  stranded deliverable are often perfectly accurate, which is why reading
  cannot find it: check that each deliverable is still _reachable_ given
  every scope decision elsewhere in the document.
- **Contradictions between sections**, including a definition of done that
  the code, or another section, cannot satisfy.
- **Scope edges**: removing X's last consumer leaves X dead; does X go too?
- **Mechanisms the plan prescribes but the medium cannot deliver**,
  including a ticket state the tracker does not model.

Batch what you have to the plan owner. Expect a second round: writing a
definition of done in step 5 surfaces questions that reading the plan does
not, and asking late beats filing a decision nobody made.

Done when no ticket carries a decision that neither the plan records nor the
owner made, and each ruling is cited in the ticket that applies it ("decided
with the plan owner on DATE").

## 4. Cut the tickets

One ticket per independently closable unit. The plan's own step and commit
boundaries are a first guess, not the answer: they were written to describe a
sequence, not to bound work. **A plan step is one ticket only when its findings
are one shape and one risk level.** Split it where it mixes shapes (safe local
deletions beside imports that may carry load-time effects), where it mixes risk
(a live defect inside a cosmetic sweep), or where part of it depends on
something the rest does not. A required human verification becomes its own gate
ticket, sequenced so the queue blocks on it.

One umbrella ticket holds the cross-cutting material: the ordered map of
children, phase-wide policies, and handoffs to later phases. Deferred work
splits by whether anyone will ever do it: work handed to a real later phase
gets **its own ticket outside the umbrella, depending on it**, so it reaches
a queue on its own; only genuinely never-doing-this items stay as prose in
the out-of-scope list.

**Read the definition of done before pointing a handoff ticket at the
umbrella.** Where the plan owes the later phase an artifact its own definition
of done names, a stub or spec or filed follow-up, that edge inverts: the
umbrella cannot close until the artifact exists, so the ticket writing it is a
child of _this_ plan, and the later-phase ticket depends on that child. The
real ordering survives as prose in the umbrella. Filed the other way the two
**deadlock**, and the tracker will not tell you, because one arc of the cycle
is a sentence in the plan rather than an edge. An owed artifact also wants a
home the repository keeps: a tracker directory is often untracked, so a finding
held only in a ticket body is absent from history and from a fresh clone.

Where the owner asks for a ticket state the tracker does not model, encode
it in tags and say so in the body's first line.

Done when every plan item maps to exactly one ticket, and every deferral is
either a ticket with an edge or a line in the umbrella.

## 5. Write self-contained bodies

Each body answers, with the plan closed: what, why it is safe, how, and how
the implementer knows they are done.

- Context: one line placing the ticket in the plan (section, commit
  number).
- Evidence, dated: the verified claims, quoting code where it decides.
- Warnings: the near-misses; what sits beside the target, looks equally
  removable, and must survive, with the reason.
- Steps, opening with re-verification: "re-run the greps; stop and report
  if anything changed since DATE".
- Definition of done: checkable, including the project's standing gates
  (tests, lint, boot). Where the body quotes a count that will drift, require
  the close note to record what it turned out to be and which other ticket
  inherits the correction.
- References: repo-relative doc paths; handoff notes to later phases.

Wrap every symbol, path, and command in backticks. Done when a body reads
complete to someone who has only the repository.

## 6. Wire and verify the graph

Record every ordering constraint as a dependency edge, never prose. **Every
edge names a constraint you can state in one clause**; where you cannot, the
two tickets are independent and the edge serializes work for nothing. Where
the house style is a strict chain regardless, say in the umbrella that the
chain is a style choice, so a later reader can parallelize safely.

Then verify from the tool, not from memory: the ready queue shows exactly
the intended entry points, everything else is blocked, no cycles, and the
dependency tree read from the final ticket walks the whole chain.

**A clean cycle check is not proof the plan can finish.** It reads edges, and
the deadlock in step 4 hides in prose. Re-read the definition of done and name
the ticket that produces each artifact it requires; an artifact with no owner,
or one owned by a ticket the umbrella blocks, is the same stall the tool just
called clean.

Done when the queue output matches the plan's sequence and every
definition-of-done artifact has a ticket that can reach the queue.

## 7. Lint and report

If the project already lints its tickets, run its linter over **the ticket
files you created** and fix to zero findings. Do not impose a convention the
tracker does not have, and do not widen the glob: a tracker directory is often
untracked, so an autofix across it has no revert and quietly reformats closed
tickets that were nobody's business but their author's.

**Re-read each title against its own body.** Titles come from the plan's
framing in step 4, and step 5's evidence can invalidate them. A title
carrying a number its own body corrects is the one error every reader of the
queue sees and nobody opens the ticket to catch.

Report the filed IDs and the queue state from command output. Done when the
linter exits clean, every title matches its body's evidence, and the report
shows tool output, not intention.
