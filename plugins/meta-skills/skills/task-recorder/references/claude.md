# Retracing a Claude Code black box

The harness-specific half of [task-recorder](../SKILL.md): where the transcript
lives, and the queries that project a run out of it. The skill's steps carry
the reasons; this file carries the syntax.

For the wider harness layout — the project directory, memory, the live-session
registry — the authority is the `agent-introspection` skill's Claude Code
reference. This file stays on what a retrace needs.

## Locating the black box

A session's transcript is one JSONL file per session, under a per-project
directory whose name is the **slug**: the working directory with every slash
and dot replaced by a dash.

Search by session id first, which skips the derivation entirely:

```sh
find "${HOME}/.claude/projects" -name "${CLAUDE_CODE_SESSION_ID}.jsonl"
```

When you must derive it, two directories the harness names already carry the
slug and survive any `cd` the session has done. Prefer them over `${PWD}`:

```sh
# scratchpad: .../<slug>/<session id>/scratchpad
SLUG="$(basename "$(dirname "$(dirname "${SCRATCHPAD}")")")"
# memory directory: .../projects/<slug>/memory
SLUG="$(basename "$(dirname "${MEMORY_DIR}")")"
# fallback, wrong after any cd in the session
SLUG="$(echo "${PWD}" | sed 's|[/.]|-|g')"
BLACKBOX="${HOME}/.claude/projects/${SLUG}/${CLAUDE_CODE_SESSION_ID}.jsonl"
```

**The slug replaces dots as well as slashes**, so a working directory such as
`~/.work/finder` lands at `-Users-you--work-finder`, with a doubled dash.
Replacing only slashes builds a path that does not exist, which reads as an
unrecorded session and silently skips the whole retrace. This is the single
most common way a Claude Code retrace fails.

## Projecting the tool calls

```sh
jq -r --arg since "${WATERMARK}" 'select(.timestamp > $since)
       | select(.type=="assistant") | .timestamp as $t | .uuid as $u
       | .message.content[]? | select(.type=="tool_use") | .name as $n
       | (.input.description // ((.input|tostring)
            | sub("^\\{\"command\":\"cd [^;&]*(;|&&) *"; "{\"command\":\"")))
       | "\($t)  \($u)  \($n)  \(gsub("\\s+";" ")|.[0:120])"' \
    "${BLACKBOX}" | nl -ba
```

A row shows the call's `description` where the agent gave one, which is the
agent's claim about the call rather than a record of what ran; otherwise it
shows the input with any leading `cd` removed, cut at 120 characters, which
cuts an `Edit` off before either of its strings.

The `uuid` in each row is what pulls the full record when a discriminator needs
quoting:

```sh
jq --arg u "${UUID}" 'select(.uuid==$u)' "${BLACKBOX}"
```

## Projecting what the user said

Interventions live in three record shapes. The first query covers two of them,
the second covers the third.

```sh
# typed turns, and messages sent while a turn was running
jq -r --arg since "${WATERMARK}" '
  def texts: if type=="array" then map(select(.type=="text") | .text)
             elif type=="string" then [.] else [] end;
  select(.timestamp > $since)
  | if .type=="user" and .origin.kind=="human" then
      .timestamp as $t | .message.content | texts[]
      | select(startswith("<") | not) | "\($t)  turn      \(.)"
    elif .type=="attachment" and .attachment.type=="queued_command" then
      .timestamp as $t | .attachment.prompt | texts[] | "\($t)  mid-turn  \(.)"
    else empty end' "${BLACKBOX}"

# answers the user typed instead of picking an offered option
jq -r --arg since "${WATERMARK}" 'select(.timestamp > $since)
       | select(.type=="user" and (.toolUseResult|type)=="object")
       | select(.toolUseResult.answers? != null)
       | .timestamp as $t
       | [.toolUseResult.questions[]?.options[]?.label] as $offered
       | .toolUseResult.answers | to_entries[]
       | select(.value as $v | ($offered | index($v))
                or ($v | split(", ") | all(. as $a | $offered | index($a))) | not)
       | "\($t)  answer    \(.value)"' "${BLACKBOX}"
```

Three details each query depends on:

- A multi-select answer is stored as its labels joined by `", "`, so the filter
  tries the whole answer as one label first, since labels contain commas too,
  and only then splits it.
- A human turn's first content block is often harness context, such as a note
  of the file open in the editor, rather than what the user typed. The
  `startswith("<")` filter drops those blocks rather than the turn.
- A message the user sent while the agent was working is stored as a
  `queued_command` attachment, not as a turn.

## Reconstruction limits, specific to this harness

**Reasoning** between tool calls is partly recoverable from `thinking` blocks
on `assistant` records.

**Compaction** is marked with a `<local-command-stdout>Compacted</local-command-stdout>`
record. Test whether the marker is a record's **own** content rather than
something quoted inside one:

```sh
jq -r 'select(.type=="user" and .toolUseResult==null)
       | (.message.content | if type=="array" then (.[0].text // "") else . end)
       | select(test("^<local-command-stdout>Compacted"))' "${BLACKBOX}"
```

**Subagent work** sits behind `isSidechain: true` in the same file, so it is
excluded from the projections above unless you ask for it:

```sh
jq -r 'select(.isSidechain==true) | .timestamp' "${BLACKBOX}" | head
```

**Attribution**: `attributionSkill` records which skill an action is attributed
to, which makes skill usage auditable after the fact — useful for separating a
recording run's overhead from the task itself.
