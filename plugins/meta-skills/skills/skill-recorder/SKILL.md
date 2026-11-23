---
name: skill-recorder
description: Field-test a skill on a real task and record the action of running it. Use when the user asks to test, exercise, or dogfood a skill.
metadata:
  argument-hint: "/skill-under-test [its argument line]"
---

# Skill Recorder

```sh
AGENT_ARTIFACTS_DIR="${AGENT_ARTIFACTS_DIR:-$(pwd)/.local/data/agentartifacts}"
mkdir -p "${AGENT_ARTIFACTS_DIR}/skill-recorder" && echo "${AGENT_ARTIFACTS_DIR}/skill-recorder"
date -u +%Y%m%dT%H%M%SZ
```

Run this once when the run opens, and use the two printed values, the
directory and the run's `<UTC>` stamp, for every path below.

You are field-testing one skill. Follow its text literally and cold, using its
guidance in place of your own knowledge of the subject; where the skill is
silent, that silence is a finding. The skill under test stays unedited until
the test ends, since a fix applied halfway destroys the observation.

## Steps

1. **Fix the target.** The first `/name` token in the argument line is the
   skill under test; the rest of the line is that skill's argument line. When
   the skill under test is a loader, the test covers the loader's own steps,
   and the skill it loads is **downstream**: observed, but not owned by this
   test. A loader announces the hand-off as `LOADER: loaded NAME from PATH`,
   and that line marks where the downstream skill begins. When the test needs
   a real task and the line carries none, ask once for it. Done when you can name the skill under test, its argument line, the
   downstream skill if any, and the real task.
2. **Open the action log** at
   `${AGENT_ARTIFACTS_DIR}/skill-recorder/NAME.<UTC>.skill-test.md`, `NAME`
   being the skill under test, so a re-test never overwrites an earlier one.
   Print the path as the first line of output. Done when the file exists and
   the path has been printed.
3. **Run the skill and log as you go.** Append an entry `A<n>` the moment each
   observation happens rather than from memory afterwards. Each entry carries:
   where (skill step or section, or "gap: nothing covered this"); the decision
   faced and what you actually did; whether it is friction (ambiguous, missing,
   conflicting, wrong for this case, or guidance ignored to get a good result)
   or an opportunity (something that could be done differently and better);
   severity where it applies; and a proposed fix or "needs discussion". An
   observation about a downstream skill is tagged `downstream: NAME`. Done when
   the real task is complete and every observation has an entry.
4. **Report.** Give the work produced, the log path, and a ranked list of
   proposed changes, separating "the skill misled me" from "the skill was
   unclear" from "the skill was silent" from "the skill could be improved if
   it had steered differently" from "the skill was right, and the confirmation
   matters". The last group carries no proposed change and is not padding: the
   four before it all say what to edit, so a report without it tells an author
   what to touch and nothing about what to leave alone, and the load-bearing
   parts of a skill are invisible precisely because they worked. Name what each
   confirmed instruction prevented. Downstream observations go under their own
   heading, addressed to the skill they belong to. Done when every entry in
   the log appears in exactly one of those groups.
