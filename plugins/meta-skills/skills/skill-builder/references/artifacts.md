# Artifacts

A skill that saves anything to disk (a log, a report, a seed, a runbook, a
generated guide) writes it under one shared root, in a directory of its own.
One root makes every skill's output findable by listing a single directory,
and one override moves all of it at once.

## The block

Every such skill opens its body with this block, the skill's directory name
in place of `<skill>`, copied verbatim otherwise:

```sh
AGENT_ARTIFACTS_DIR="${AGENT_ARTIFACTS_DIR:-$(pwd)/.local/data/agentartifacts}"
mkdir -p "${AGENT_ARTIFACTS_DIR}/<skill>" && echo "${AGENT_ARTIFACTS_DIR}/<skill>"
date -u +%Y%m%dT%H%M%SZ
```

followed by one sentence telling the agent to run it once when the run opens
and to use the two printed values, the directory and the run's `<UTC>` stamp,
for every path the skill names. A skill whose output is not stamped (see
the exception below) drops the `date` line.

After the block, the skill names its paths only through the variable, as
`${AGENT_ARTIFACTS_DIR}/<skill>/...`, in `SKILL.md` and in every file under
`references/`, `assets/` and `scripts/`. A script resolves the same default
itself: the environment variable when set and non-empty, otherwise
`.local/data/agentartifacts` under the working directory, then the skill's
subdirectory.

## Rules

1. **The override is the environment.** A user who wants every skill to
   write elsewhere, a home-wide location for example, sets
   `AGENT_ARTIFACTS_DIR` in the shell before launching the agent. The
   default is project-local, with the working directory taken as the
   project root and no search for a marker file or a git root.
2. **One subdirectory per skill**, named exactly as the skill's directory.
   The root holds skill subdirectories and nothing else, so listing the
   root lists the skills that produced something. Each skill creates its
   own subdirectory; nothing creates the root alone.
3. **No fallbacks.** The working directory always exists, and the override
   covers the case where it is the wrong place. A skill that finds its
   directory unwritable or unreadable says so and names the override,
   rather than writing somewhere else that nothing else will look in.
4. **Every run is stamped, and nothing is overwritten.** Every file of one
   run shares a stem:

   ```text
   ${AGENT_ARTIFACTS_DIR}/<skill>/<slug>.<UTC>[.<type>].<ext>
   ```

   `<slug>` is the skill's own (the task, the skill under test, the
   platform), `<UTC>` is the one stamp the block printed, and `<type>`
   names the kind of file when a run writes several, or when the extension
   alone is ambiguous (`.audit.md`, `.seed.md`, `.atoms.json`). A run that
   revises an earlier one writes a new stamped file and reads the newest
   earlier one as its starting point.
5. **The exception is a file whose name something else fixes**, such as a
   loadable skill directory whose name must match its `name:` field. It
   keeps its required name, unstamped, and the skill says where its
   history lives instead.

## Why the block prints

Shell state does not persist between an agent's tool calls, and a
file-writing tool takes a literal path, not a shell expression. Printing
the resolved directory and the stamp once turns both into values the agent
can carry into every later write. A shell command that uses the variable
carries the assignment line itself, for the same reason.

Both lines are free of the dollar-digit form the skill loader substitutes,
so they arrive as written. The stamp command is fixed so that every skill
produces stamps that sort the same way.

## Shell notes

- In zsh an unquoted variable is not word-split, so a variable holding
  several paths passes them as one argument: list paths explicitly or use
  an array.
- In zsh `path` is tied to `PATH`; a variable or loop variable named `path`
  breaks every later command. Name it `file`, `dir` or `target`.

## Audit checklist

For a skill that saves anything to disk:

- the block opens the body, verbatim apart from `<skill>`, which matches
  the skill's directory;
- no other location survives anywhere in the skill: no `.local/tmp`, no
  `.logs/`, no home-directory path, no scratchpad or OS temporary
  directory, no fallback chain;
- every file name follows the stem pattern, or is the named exception;
- every script that writes or reads the skill's files resolves the same
  default as the block, honouring the override.
