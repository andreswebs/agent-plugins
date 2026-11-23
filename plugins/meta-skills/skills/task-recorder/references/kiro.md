# Retracing a Kiro black box

The harness-specific half of [task-recorder](../SKILL.md): where the transcript
lives, and the queries that project a run out of it. The skill's steps carry
the reasons; this file carries the syntax.

For the wider harness layout — the storage tree, policy, snapshots, the session
roster — the authority is the `agent-introspection` skill's Kiro reference.
This file stays on what a retrace needs.

Verified against Kiro 1.2.4. Re-derive rather than trust: harness facts drift.

## Locating the black box

Sessions live under a workspace bucket whose name is an **opaque hash**, so
there is nothing to derive and no slug rule to get wrong. Search by session id:

```sh
SELF="$(find ~/.kiro/sessions -maxdepth 2 -name "${KIRO_SESSION_ID}")"
BLACKBOX="${SELF}/messages.jsonl"
```

`KIRO_SESSION_ID` is exported into the agent's shell, so this is a single
command with no fallbacks. Sessions belonging to no workspace sit under a
`_global` bucket, which the same search covers.

`${SELF}/session.json` is worth reading at step 1: its `title` is a
harness-generated one-line summary of the session, and `agentMode` says whether
this was a conversational or a spec-driven run.

## The record envelope

Every record is the same wrapper, and this is the one thing that breaks ported
queries:

```json
{
  "id": "<record-id>",
  "payload": { "type": "tool_call", "…": "…" },
  "timestamp": "…"
}
```

**The type lives inside `.payload`, not at the top level.** A Claude Code
filter such as `select(.type=="assistant")` matches nothing here and fails
silently, which looks exactly like a session with no activity. Unwrap
`.payload` first, every time.

The `.timestamp` stays at the top level, so watermark bounding is unchanged.

Record types a retrace cares about:

| `payload.type`                          | Use                                 |
| --------------------------------------- | ----------------------------------- |
| `tool_call`, `tool_result`              | The actions and their outcomes      |
| `user`, `assistant`                     | The conversation                    |
| `turn_start`, `turn_end`                | Turn boundaries; `stopReason`       |
| `pending_interaction`                   | A question put to the user          |
| `interaction_resolved`                  | Its answer                          |
| `usage_summary`                         | Per-turn accounting                 |
| `sub_agent_start`, `sub_agent_complete` | Delegation boundaries               |
| `agent_note`                            | A note the agent recorded           |
| `session_metadata`                      | Key/value state, e.g. context usage |

## Projecting the tool calls

```sh
jq -r --arg since "${WATERMARK}" 'select(.timestamp > $since)
       | select(.payload.type=="tool_call")
       | .timestamp as $t | .id as $u
       | .payload.toolName as $n
       | ((.payload.title // (.payload.args|tostring)) | gsub("\\s+";" "))
       | "\($t)  \($u)  \($n)  \(.[0:120])"' \
    "${BLACKBOX}" | nl -ba
```

`payload.title` is the harness's own short label for the call where it has one,
and the serialised `args` otherwise — so the same index-not-evidence caution
applies: it is a summary, truncated, and not a record of what ran.

Pull the full record by the envelope `id` carried in each row:

```sh
jq --arg u "${UUID}" 'select(.id==$u)' "${BLACKBOX}"
```

A second histogram is available here that other harnesses lack, and it is
better for phase assignment than tool names, because it survives tool renames:

```sh
jq -r 'select(.payload.type=="tool_call")
       | (.payload.kind // "-") + "/" + (.payload.actionType // "-")' \
  "${BLACKBOX}" | sort | uniq -c | sort -rn
```

Values seen: `read/read_files`, `edit/create`, `edit/write`, `edit/replace`,
`edit/append`, `execute/run_command`, and `other/*` for the rest.

## Projecting what the user said

```sh
# typed turns
jq -r --arg since "${WATERMARK}" 'select(.timestamp > $since)
       | select(.payload.type=="user")
       | .timestamp as $t
       | (.payload.content | if type=="array"
            then (map(select(.type=="text") | .text) | join(" "))
            else tostring end)
       | "\($t)  turn      \(gsub("\\s+";" "))"' "${BLACKBOX}"

# answers to questions the agent asked
jq -r --arg since "${WATERMARK}" 'select(.timestamp > $since)
       | select(.payload.type=="interaction_resolved")
       | .timestamp as $t
       | "\($t)  answer    \(.payload.selectedOption // .payload.outcome)"' \
  "${BLACKBOX}"
```

Kiro pairs `pending_interaction` (carrying `question` and `options`) with
`interaction_resolved` (carrying `outcome` and `selectedOption`). To separate a
choice from the user's own words, join the two on `executionId` and compare the
resolved value against the offered `options`: an answer made only of offered
labels is a choice, anything else was typed.

**Harness context arrives inside user turns.** Kiro injects blocks naming the
open and active editor files, and these are not something the user said. Drop
them rather than the turn, as the skill's step 3 requires.

**Not verified:** whether a message sent while a turn is running is stored
distinctly, as Claude Code's `queued_command` attachment is. Until it is
established, treat mid-turn corrections as possibly indistinguishable from
ordinary turns here, and lean on callouts to catch them.

## Subagent and workflow work

Better separated than in other harnesses: each delegated execution gets **its
own file**, in the same envelope, so no flag-filtering is needed.

```sh
ls "${SELF}/sub-executions/"
jq -r 'select(.payload.type=="tool_call") | .payload.toolName' \
  "${SELF}/sub-executions/<execution-id>.jsonl" | sort | uniq -c | sort -rn
```

The parent transcript brackets each with `sub_agent_start` and
`sub_agent_complete`, and `payload.executionId` links the two. Count a
delegated run's calls from its own file; do not expect them in the parent.

## Accounting, for free

```sh
# per-turn usage
jq -r 'select(.payload.type=="usage_summary")
       | .payload.promptTurnSummaries[]? | "\(.usage) \(.unitPlural)"' \
  "${BLACKBOX}"

# context pressure, most recent reading
jq -r 'select(.payload.key=="contextUsage") | .payload.value.usagePercentage' \
  "${BLACKBOX}" | tail -1

# which model actually served the turns
jq -r 'select(.payload.reasoningModelId) | .payload.reasoningModelId' \
  "${BLACKBOX}" | sort | uniq -c
```

The model matters for a seed's header: Kiro may be configured to `auto`, so the
model is server-selected and only the transcript records what actually ran.

## A second witness on what changed

`${SELF}/snapshots/` holds pre-edit copies of the files the session modified,
under their workspace-relative paths. That makes it an independent check on the
phase assignment — a file in snapshots whose edit you did not assign to a
phase means the index was read wrong:

```sh
find "${SELF}/snapshots" -mindepth 2 -not -name .hash
```

## The seed location pitfall

**The skill's default seed path can be unreadable on Kiro.** Policy derives
`fs_read` deny rules from the user's ignore patterns, and `.local` is a common
ignore entry, so a seed under the default `${AGENT_ARTIFACTS_DIR}` is
frequently writable and not readable. Every write succeeds and every read fails, so the failure surfaces at
the _next_ run's merge rather than when the seed is created.

Three facts that decide what to do about it:

- An `allow` rule does **not** override the deny, even after a session reload.
- Paths are canonicalised before matching, so a symlink to the directory is
  denied too.
- The refusal message names the ignore file that sourced the rule.

So the fix is not a policy edit from inside the session. Read the seed path
back once at step 1; if it refuses, stop and ask the user to relaunch Kiro with
`AGENT_ARTIFACTS_DIR` set to a readable directory that the project does not
track as source and that no ignore pattern covers.

## Reconstruction limits, specific to this harness

- **Compaction is unresolved.** `session.json` carries
  `disableAutoCompaction`, so the feature exists, but no compaction record type
  appeared in the transcripts examined. Report "no compaction record found, and
  the marker for this harness is not established" rather than "not compacted".
- **Thinking blocks are not established.** `reasoningModelId` and
  `reasoningSignature` are recorded per turn, but whether reasoning _text_ is
  retained was not confirmed. Treat narrated reasoning as unavailable until it
  is.
- **Policy can hide part of the record**, including the seed itself, as above.
- Everything here is stamped to Kiro 1.2.4.
