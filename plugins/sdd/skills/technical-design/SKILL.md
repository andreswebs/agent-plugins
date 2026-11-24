---
name: technical-design
description: "Write or revise a technical-design.md from an EARS requirements.md, in the shape of a Kiro spec design document: architecture, components and interfaces, data models, gated correctness properties, error handling, testing strategy, with every acceptance criterion traced. Use when asked for a technical design or design phase from requirements, or to re-sync an existing technical-design.md after the requirements changed."
metadata:
  argument-hint: "path to requirements.md (optional when the repo holds exactly one)"
---

# Technical design from requirements

The design is a checkpoint, not a plan of record: a paragraph describing the
wrong component boundary costs a sentence to fix, the same boundary spread
across nine files costs an afternoon. Write the document so a reviewer can
disagree with it cheaply, and stop when it is written.

Draft first. The requirements author will react to a concrete design faster
than they will answer a blank-page interview, so ask only when the answer
changes the architecture, and record everything else as an assumption.

## Steps

1. **Locate the inputs.** The requirements file is the argument, or the single
   `requirements.md` in the repo when no argument is given; stop and ask when
   there are several. The output is `technical-design.md` beside it. When that
   file already exists, this run is a _revision_: read it first, keep its
   structure, and change only what the request or the changed requirements
   demand. Any other design document beside the requirements is prior art
   for step 2, read for decisions to keep or reject, never the revision
   target. Done when the requirements path, the output path and the branch
   (new or revision) are stated in the conversation.

2. **Research in the conversation.** Read the requirements' Introduction and
   Glossary, every file they reference (a referenced file that is not beside
   the requirements is found by name across the repo, and its location is
   recorded under Dependencies), sibling notes beside them, the project's
   instruction and steering files, and any existing code or prototypes the
   design must fit. Settle the notation for interfaces and data models:
   settled means a language chosen for the components being designed; code
   in another layer, a prototype or a demo is evidence to cite in the
   question, not a decision. When none is settled, ask once whether to use a
   named language or structured pseudocode. Keep the findings in the
   conversation; a separate research file is a second source of truth that
   drifts. Done when the notation is settled and each glossary term that
   names a component or record has a home in the design.

3. **Write Overview through Data Models** following
   [the design template](references/design-template.md), using the glossary's
   names for components, records and channels. Highlight each design decision
   with its rationale where it is made. Ask the user, with options, only about
   decisions that change the architecture; write every other open item as an
   assumption at the point of use. Done when every component and record in
   the glossary appears under Components and Interfaces or Data Models, or is
   explicitly out of scope, and every criterion whose actor is THE Service
   is assigned to a named component.

4. **Run the property-based testing gate.** Judge the feature against the
   applicability table in the template. When it qualifies, analyse the
   acceptance criteria before writing: list in the conversation the
   universally quantified clauses, grouped into the candidate properties
   that consolidate them, so the reviewer can see what was merged and what
   was left to example tests. Then write Correctness Properties in the
   template's format, each with an explicit "for all" and a `Validates` line
   naming the clauses it derives from. When it does not qualify, omit the
   section and state the reason under Testing Strategy. Done when the clause
   list is in the conversation and either every property traces to a
   clause, or the omission is explained.

5. **Write Error Handling and Testing Strategy**, then any of Performance
   Considerations, Security Considerations or Dependencies that the
   requirements actually raise, and finally Open Questions and Assumptions,
   collecting every assumption made in steps 3 and 4. Done when no section
   exists only to satisfy the template.

6. **Check traceability.** Run the checker from the skill's base directory
   (the loader prints it) with absolute paths to both files, and fix the
   design until it passes. Each referenced clause sits next to the mechanism
   that satisfies it; the checker's "tested but not designed" warnings list
   the clauses whose only mention is under Testing Strategy, and each one
   gets a home in Components, Data Models or Error Handling.

   ```sh
   cd "${SKILL_BASE_DIR}" && uv run scripts/check_design.py "${REQUIREMENTS}" "${DESIGN}"
   ```

   Exit `0` means every mandated section is present, every acceptance
   criterion is referenced, and every property carries a valid `Validates`
   line and a "for all". Then lint: `markdownlint-cli2 --fix "${DESIGN}"`
   when the command is available. Done when both exit `0` and the warning
   list is empty.

7. **Present and stop.** Summarise the key design decisions, the open
   questions that need the author's answer, and the assumptions made. The
   workflow ends here: no task list and no implementation until the design is
   approved. Done when the summary is in the conversation and the user has
   been asked to review.
