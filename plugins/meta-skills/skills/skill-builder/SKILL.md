---
name: skill-builder
description: Reference for authoring and editing agent skills. Use when creating new skills, auditing or editing existing ones.
---

# Skill Builder

```sh
AGENT_ARTIFACTS_DIR="${AGENT_ARTIFACTS_DIR:-$(pwd)/.local/data/agentartifacts}"
mkdir -p "${AGENT_ARTIFACTS_DIR}/skill-builder" && echo "${AGENT_ARTIFACTS_DIR}/skill-builder"
date -u +%Y%m%dT%H%M%SZ
```

Run this once when the run opens, and use the two printed values, the directory and the run's `<UTC>` stamp, for every path below.

**Bold terms** are defined in [the glossary](references/glossary.md); look them up there for the full meaning.

A skill exists to wrangle determinism out of a stochastic system. **Predictability**, the agent taking the same _process_ every run rather than producing the same output, is the root virtue; every lever below serves it.

## Authoring a skill

Work these steps for a new skill or an audit of an existing one; each draws on the reference sections below.

1. **Write the description.** Done when every trigger names a **branch** no other trigger names.
2. **Place the content on the information hierarchy**, giving each step a **completion criterion**. Done when nothing left in `SKILL.md` is read by only some branches.
3. **Lay out the files** as the spec layout requires, and, when the skill saves anything to disk, as [the artifacts convention](references/artifacts.md) requires. Done when the skill root holds `SKILL.md` and directories, nothing else, and every item of the convention's audit checklist holds or the skill writes nothing.
4. **Prune**: single source of truth, relevance, no-ops, and restatements a **leading word** retires. Done when no surviving sentence would be obeyed by default.
5. **Validate** with `scripts/skill_ref.py`, and read the description back with `to-prompt`. Done when `validate` exits `0`.
6. **Record the run** in `${AGENT_ARTIFACTS_DIR}/skill-builder/<skill>.<UTC>.audit.md`, `<skill>` being the skill worked on: one entry per finding, giving where in the skill, the failure mode or rule it breaks, and the fix applied or proposed. The reply still carries the findings. Done when every finding in the reply has an entry and the path is printed.

## Writing the description

A skill **description** does two jobs: state what the skill is, and list the **branches** that should trigger it. Every word increases **context load**, so a description earns even harder pruning than the body:

- **Front-load the skill's leading word.** The description is where it does its invocation work.
- **One trigger per branch.** Synonyms that rename a single branch are **duplication**: "build features using TDD … asks for test-first development" is one branch written twice. Collapse them; keep only genuinely distinct branches.
- **Cut identity that's already in the body.** Keep the description to triggers, plus any "when another skill needs…" reach clause.

## Information hierarchy

A skill is built from two content types, **steps** and **reference**, that mix freely: a skill can be all steps, all reference, or both. The core decision is which to use and where each sits on the **information hierarchy**, a ladder ranked by how immediately the agent needs the material:

1. **In-skill step**: an ordered action in `SKILL.md`, the primary tier, what the agent does, in order. Each step ends on a **completion criterion**, the condition that tells the agent the work is done. Make it _checkable_ (can the agent tell done from not-done?) and, where it matters, _exhaustive_ ("every modified model accounted for", not "produce a change list"); a vague criterion invites **premature completion**.
2. **In-skill reference**: a definition, rule, or fact in `SKILL.md`, consulted on demand. Often a legitimately flat peer-set (every rule of a review on one rung), a fine arrangement rather than a smell. _This skill is one short run of steps over flat reference._
3. **External reference**: reference pushed out of `SKILL.md` into a separate file, reached by a **context pointer**, loaded only when the pointer fires. (Spans _disclosed_ reference, a sibling file like `references/glossary.md` that is still part of the skill, through to fully **external reference** that lives outside the skill system and any skill can point at.)

A demanding completion criterion drives thorough **legwork** (the digging the agent does within the work) whether the skill has steps or not, since "every rule applied" binds flat reference just as "every step done" binds a sequence.

Push too little down and the top bloats; push too much and you hide material the agent actually needs. That tension is the whole decision.

**Progressive disclosure** is the move down the ladder, out of `SKILL.md` into a linked file, so the top stays legible. Mechanics: a linked `.md` file under `references/`, named for what it holds (this skill discloses its full definitions to `references/glossary.md`). Some skills are used in more than one way, and each distinct way is a **branch**: different runs taking different paths through the skill. Branching is the cleanest disclosure test: inline what every branch needs, and push behind a pointer what only some branches reach. A **context pointer**'s _wording_, not its target, decides when and how reliably the agent reaches the material.

Where the ladder decides _how far down_ a piece sits, **co-location** decides _what sits beside it_ once there: keep a concept's definition, rules, and caveats under one heading rather than scattered, so reading one part brings its neighbours with it.

## When to split

**Granularity** is how finely you divide skills, and each cut spends one of the two loads, so split only when the cut earns it. Two cuts:

- **Split off a model-invoked skill** when you have a distinct **leading word** that should trigger it on its own, or when another skill must reach it. You pay **context load** for the new always-loaded **description**, so that independent reach has to be worth it.
- **Split a run of steps** when the steps still ahead (a step's **post-completion steps**) tempt the agent to rush the one in front of it (**premature completion**). Keeping them out of view encourages the agent to do more **legwork** on the current task.

## Pruning

Keep each meaning in a **single source of truth**: one authoritative place, so changing the behaviour is a one-place edit.

Check every line for **relevance**: does it still bear on what the skill does?

Then hunt **no-ops** sentence by sentence, not just line by line: run the no-op test on each sentence in isolation, and when one fails, delete the whole sentence rather than trim words from it. Be aggressive: most prose that fails should go, not be rewritten.

## Leading words

A **leading word** is a compact concept already living in the model's pretraining that the agent thinks with while running the skill (e.g. _lesson_, _fog of war_, _tracer bullets_). Repeated through the text (a strong one may need only a single mention), it accumulates a distributed definition and anchors a whole region of behaviour in the fewest tokens, by recruiting priors the model already holds.

It serves predictability twice. In the body it anchors _execution_: the agent reaches for the same behaviour every time the word appears. In the description it anchors _invocation_: when the same word lives in your prompts, docs, and code, the agent links that shared language to the skill and fires it more reliably.

Hunt for opportunities to refactor skills to use leading words. A triad spelled out at three sites (**duplication**), or a description spending a sentence to gesture at one idea: each is a passage begging to **collapse** into a single token. Examples include:

- "fast, deterministic, low-overhead" -> _tight_: one quality restated across a phase, folded into a single pretrained word (a _tight_ loop).
- "a loop you believe in" -> _red_: converts a fuzzy gate into a binary observable state (the loop goes _red_ on the bug, or it doesn't).

You win twice over: fewer tokens, _and_ a sharper hook for the agent to hang its thinking on. Assume every skill is carrying restatements that leading words retire; go find them.

## Failure modes

Use these to diagnose issues the user may be having with the skill; the glossary carries each one's full definition and cure.

- **Premature completion**: the agent ends a step before it is genuinely done, attention slipping to _being done_.
- **Duplication**: the same meaning kept in more than one place.
- **Sediment**: stale layers that settled because adding felt safe and removing felt risky.
- **Sprawl**: a skill simply too long, even when every line is live and unique. Judge it by reach rather than size: a section only some branches read belongs behind a pointer.
- **No-op**: a line the model already obeys by default, so you pay load to say nothing.
- **Negation**: steering by prohibition, which drags the banned behaviour into view and makes it _more_ available, not less. Restate the ban as the behaviour you want instead: "do not assume the project uses npm" -> "name the toolchain the repo actually uses".

## Skill audit

Keep the standard layout the [Agent Skills spec](https://agentskills.io/llms-full.txt) defines: `SKILL.md` at the root, disclosed docs under `references/`, runnable code under `scripts/`, static resources under `assets/`, and test cases under `evals/` when the user asked for evals. A supporting file dropped at the skill root, even one that already works where it sits, belongs in its directory. `SKILL.md` opens with YAML frontmatter carrying the two required fields, plus optional `metadata`:

```yaml
---
name: my-skill
description: What it is, and the branches that trigger it.
metadata:
  argument-hint: "what the user should pass"
---
```

A `SKILL.md` body must never write a dollar sign directly followed by a digit. The loader substitutes that form from the invocation arguments before the agent reads the body, so an `awk`, `sed` or `jq` snippet written that way arrives rewritten while the file on disk still looks correct, and the agent has no signal that its instructions changed. Brace it as `${2}` where the syntax allows, or restructure to avoid the position entirely: `awk '{print $NF}'` and `sed -n 's/^key: *//p'` carry no digit. This applies only to `SKILL.md`, since `references/` files are loaded by Read and pass through unchanged. Note that a warning about this hazard is itself subject to it, so write the rule with braces too.

The bundled [`scripts/skill_ref.py`](scripts/skill_ref.py) is the conformance check, so run it rather than fetching the spec or reading by eye:

```sh
uv run scripts/skill_ref.py validate path/to/skill
```

It exits `0` when the skill is valid and `1` with the list of problems otherwise, checking the frontmatter fields, the name rules (lowercase, hyphen-separated, matching the directory, within the length limit), the description, and the shape of `evals/evals.json` when that file is present. Two companion commands help while authoring: `read-properties path/to/skill` prints the parsed frontmatter as JSON, and `to-prompt path/to/skill ...` emits the `<available_skills>` block so you can read the **description** exactly as the agent sees it.

## Deterministic behavior

A skill may carry a `scripts/` directory. Scripts pin the behaviour that must not vary, taking it out of the model's hands, so keep them **self-contained**: one file, dependencies declared inline, one command to run. The [scripting reference](references/scripting.md) sets out how.

## Evaluating a skill

Evals are opt-in: build them when the user asks for them, for a new skill or one being changed. Then read the [evals reference](references/evals.md): cases in `evals/evals.json`, a **baseline** arm without the skill, **assertions** graded with evidence, and the eval kind chosen by the failure being hunted (triggering, routing, output quality, seeded defects, goldens).
