---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
metadata:
  argument-hint: "What will the next session be used for?"
---

```sh
AGENT_ARTIFACTS_DIR="${AGENT_ARTIFACTS_DIR:-$(pwd)/.local/data/agentartifacts}"
mkdir -p "${AGENT_ARTIFACTS_DIR}/handoff" && echo "${AGENT_ARTIFACTS_DIR}/handoff"
date -u +%Y%m%dT%H%M%SZ
```

Run this once when the run opens, and use the two printed values, the directory and the run's `<UTC>` stamp, for the path below.

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save it as `${AGENT_ARTIFACTS_DIR}/handoff/<slug>.<UTC>.handoff.md`, `<slug>` naming the work in a few hyphenated words, and print the path.

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Characterize every artifact you describe from the primary source in hand (the fetched file, the live tree), never from the framing carried in conversation summaries or a previous handoff. Stale labels survive re-reads and the recipient inherits the error; a filename is not a format claim (a `testing.md` may hold a BATS table, not the framework the name suggests), so read the surrounding context before naming what a flagged line belongs to.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
