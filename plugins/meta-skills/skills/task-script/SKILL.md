---
name: task-script
description: Hand a task over as an executable runbook, one idempotent Bash script the user reviews and runs themselves. Use when asked for a script to review and run, to batch a task into one reviewable artifact, or to make a procedure repeatable and ready to automate; and when the user objects to approval prompts or step-by-step execution. Also use when another skill needs its work delivered as a reusable script.
metadata:
  argument-hint: "the task to turn into a runbook"
---

# Task Script

```sh
AGENT_ARTIFACTS_DIR="${AGENT_ARTIFACTS_DIR:-$(pwd)/.local/data/agentartifacts}"
mkdir -p "${AGENT_ARTIFACTS_DIR}/task-script" && echo "${AGENT_ARTIFACTS_DIR}/task-script"
date -u +%Y%m%dT%H%M%SZ
```

Run this when the run opens, and again before each rewrite of the runbook,
and use the printed values, the directory and the `<UTC>` stamp, for the
runbook's path. It is one of only two shell commands this skill runs itself;
the other is the format-and-lint pass of step 3. The rules of steps 1 and 4
exclude both.

Deliver the task as a **runbook**: the whole procedure, planned up front and
written down as one Bash script that the user reads, runs, and keeps. The user
reviews everything in one batch instead of approving a stream of commands, and
because every step is idempotent, the runbook is also the first draft of the
task's automation.

The agent plans and writes. The user runs. The runbook is the single record of
how the task gets done, before it runs and after.

## Steps

### 1. Investigate without touching anything

Gather the facts the plan rests on with read-only, non-shell tools: read files,
search, list directories. A fact only a shell could reveal, such as a tool's version, whether a binary exists, or a
service's state, becomes a preflight check in the runbook rather than a guess.

**Done when:** every fact the plan relies on is either read from the workspace
or listed as a preflight check.

### 2. Draft the plan

Think the task through end to end and write a short numbered plan. Each step
names an **end state** a predicate can test (this file holds this content, this
package is installed, this branch exists), not an action. Mark each step
`[reversible]`, or `[risky: <what it touches>]` when it is hard to undo or
reaches shared systems (deletes, pushes, deploys, infrastructure, production
data). Name any step that cannot be made idempotent and how it is guarded.

Leave out long-running and interactive commands, such as dev servers, watchers,
and login flows: the runbook prints them as the final hand-off instead.

**Done when:** every step has a testable end state and a reversibility mark.

### 3. Write the runbook

Start from [`assets/runbook-template.bash`](assets/runbook-template.bash) and
follow the **/bash** skill for conventions and triage. The template fixes the
shape every runbook keeps:

- **The plan in the header**, numbered exactly as in step 2, with each step's
  mark, so the plan cannot drift from what runs.
- **One check and one act function per step**, `step_<n>_check` and
  `step_<n>_act`, run in plan order through `run_step`.
- **Check, then act.** `run_step` reports `skip` when the end state already
  holds, `would` in a dry run, and `done` or `FAIL` under `--apply`, then
  re-checks the end state after acting.
- **Dry run by default.** Nothing changes without `--apply`.
- **Preflight first**, collecting every unmet precondition before failing.
- **Self-contained.** File contents go inline as quoted heredocs; secrets are
  read from the environment and checked in preflight, never written into the
  script.

Write it with a file-writing tool as
`${AGENT_ARTIFACTS_DIR}/task-script/<task-slug>.<UTC>.bash`. Re-planning or
fixing the task writes a new stamped runbook, starting from the newest one;
earlier runbooks stay as its history.

Then format and lint the file you wrote, the **/bash** skill's two required
tools, and fix what they report before handing over:

```sh
shfmt --indent 4 --write "${RUNBOOK}"
shellcheck "${RUNBOOK}"
```

This reads and rewrites the runbook's text only; it never executes the
runbook, so the rule of step 4 holds. A finding is fixed in the source, not
silenced; `# shellcheck disable=SCxxxx` goes on the one line it is about,
never file-wide, and only for a genuine false positive (a deliberately
unexpanded single-quoted string, say). If either tool is missing, say so in
the hand-over and leave the user's own `shellcheck` run to catch it.

**Done when:** every plan step has its check and act functions, every shell
command the task needs is inside the runbook, the header plan matches
`run_steps` line for line, `shfmt --indent 4` changes nothing, and
`shellcheck` reports nothing.

### 4. Hand it over, then stop

Reply with the plan in a few lines, the runbook's path, and the review sequence:

1. `shellcheck <runbook>`
2. `bash <runbook>`, the dry run, which executes every check and lists what
   would change
3. `bash <runbook> --apply`

Then wait. Running the runbook, or any part of it, is the user's move.

**Done when:** the user has the path and the three commands, and no shell
command but the artifacts block and the format-and-lint pass has run.

### 5. Fix the runbook, not the system

When the user reports output or a failure, make the fix in a new stamped
runbook, run the format-and-lint pass of step 3 on it, and hand back its path,
since a fix applied outside it is lost the next time it runs. Because finished
steps report `skip`, a run of the new runbook resumes at the step that failed.

**Done when:** a run with `--apply` exits `0`, and the user knows that one more
run should report every step as `skip`.
