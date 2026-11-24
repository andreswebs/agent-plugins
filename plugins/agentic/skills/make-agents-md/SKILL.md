---
name: make-agents-md
description: Restructure an agent instruction file (AGENTS.md, CLAUDE.md) into a minimal root file plus grouped, linked docs, applying progressive disclosure. Use when such a file has grown long, when its instructions contradict each other, or when asked to split, slim, or optimize it.
---

# Make AGENTS.md

Refactor the target instruction file so the root holds only what every task
needs and everything else sits one link away.

## 0. Pick the target and take inventory

Identify the file to refactor. If more than one candidate exists (a root
`AGENTS.md`, per-directory `CLAUDE.md` files, nested instruction files), list
them with a line on what each contains and ask which to refactor. Refactor one
file per run.

Establish the scope the file covers. A file describing one project can name
"the" toolchain and commands; a file describing a workspace of independent
projects cannot, and its root becomes an index whose job is to route the agent
to the right project first. Say which case you are in, because it changes what
belongs in the root.

Then build an **instruction inventory**: a numbered list of every distinct
instruction in the original, in file order. Keep it for step 6. Without it,
step 3's completeness criterion becomes unverifiable the moment you overwrite
the original.

Done when the target is agreed, the scope is stated, and the inventory exists.

## 1. Find contradictions

Read the whole file and list instructions that conflict **with each other or
with what the code and config actually do**. The second kind matters more: an
agent cannot detect it by reading the file, so it gets followed off a cliff.
Spot-check the file's factual claims against the repo, especially package
managers, lockfiles, script names, CI commands, and directory layout. A rule
saying "always use X" when the lockfile says Y is a contradiction, and often the
most damaging one in the file.

Ask the user how to resolve each. Do not resolve one silently. Offer the
resolutions that actually apply, which are usually more than "pick a version":

- keep one version and drop the other,
- scope one to a subset (this rule holds in these directories only),
- merge them into a single instruction,
- or correct the file to match reality.

Gather the step 4 deletion candidates now, in the same pass, and ask about both
together. Both are readable from the original, and splitting them across two
rounds costs the user an extra round-trip for nothing.

Done when every conflict is resolved by the user or confirmed as not a conflict,
including any the file already documents as superseded.

## 2. Keep only the essentials in the root

The root keeps four things:

- a one-sentence description of the project or workspace,
- **prohibitions and safety rails, always, whatever their subject.** Anything
  phrased "never", "do not", or "always ask first" stays in the root even when it
  belongs to a category from step 3. A prohibition behind a link is a
  prohibition an agent may never read. This overrides step 3.
- instructions that bear on every single task,
- the toolchain and commands the repo actually uses, where they are not
  discoverable from its own config **and only if they fit in about three
  lines**. Beyond that they go in a group file and the root links to it. Step 5
  wins over this bullet: a root buried in build commands is not a minimal root.

Enough orientation material to know where things are may stay in the root as a
compact summary, with the detail in a group file. See step 3.

Done when each retained line survives the question "would an agent need this
whatever the task is?", and every prohibition from the original is present.

## 3. Group the rest

Sort the remaining instructions into categories by subject. Derive the
categories from the file's actual content; do not force it into a fixed set.
Language conventions, testing, API design, deployment, and git workflow are
common, but a file with nothing to say about testing should not get a testing
file, and a file whose entire git section is prohibitions gets no git file at
all, because step 2 already claimed them.

Orientation material may be split: a summary in the root and the detail in a
group file. This is the one permitted exception to one-instruction-one-place,
and it applies to file maps, directory inventories, and repository tables, where
part is needed on every task and part only sometimes.

Aim for a handful of group files. One file per instruction is not grouping, and
a single file called "everything else" is not either.

Done when every instruction from the original is in exactly one group, split
under the exception above, or on the approved deletion list.

## 4. Flag for deletion

Propose removing instructions that are:

- redundant, because the agent already behaves this way,
- already covered by a higher-level instruction file the agent always loads,
- too vague to act on,
- restatements of another instruction,
- or time-stamped state that will rot, such as "there are currently N
  uncommitted changes", "dormant since 2022", or superlatives like "the most
  active repo". Anything the agent can observe directly by running a command
  does not belong in an instruction file.

Present the list for approval rather than deleting. Ask about it together with
the step 1 conflicts.

Done when the user has accepted or rejected each entry.

## 5. Write the structure

A minimal root file whose body is mostly markdown links to the group files, plus
each group file under a `docs/` directory beside the root file. If `docs/`
already exists, use it. If the root file sits above other projects that have
their own `docs/` directories, say inside each group file which scope it
governs, so a reader cannot mistake it for a project-level doc.

Give each link a phrase saying when to read that file, so the agent knows which
ones a given task needs. This is the highest-value line in the output: write
"read when installing dependencies or running a build", not "dependency
information".

Done when the root file links every group file that was created and nothing
else.

## 6. Verify

- Walk the step 0 inventory and confirm each numbered instruction now appears in
  exactly one new file or on the approved deletion list. Report anything that
  matches neither.
- Confirm every prohibition from the original survived into the root.
- Check that each link resolves to a file that exists.
- Lint the files with the project's markdown linter if it has one, and match the
  surrounding documentation's conventions for line width, heading style, and
  tone.

Done when the inventory is fully accounted for and the files lint clean.
