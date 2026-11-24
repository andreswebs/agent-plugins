---
name: agent-introspection
description: >
  Introspect the harness you are running inside: what tools, storage, sessions,
  history and configuration are actually present, established by looking rather
  than by recalling. Use when asked what you can see or do, where your
  transcripts, memory, settings or skills live, what other sessions are doing,
  or why a skill, permission or tool behaved as it did; and when a claim about
  the harness needs checking before it is acted on.
metadata:
  argument-hint: "the question about the harness to answer"
---

# Agent Introspection

A harness describes itself in prose, and prose is lossy. It names tools without
their storage, skills without their resolution order, and says nothing about
what other sessions are doing. Most of the rest is on disk, readable with the
same tools any file needs.

Recall is the failure mode here. Harness details drift between versions, and a
remembered detail carries no timestamp, so it cannot be distinguished from a
current one. Every claim this skill produces costs one command.

## Steps

### 1. Name the question as a surface

Introspection questions land on one of four **surfaces**, listed in cost order.
Start at the cheapest that can answer the question:

| Surface | Answers | Cost |
| --- | --- | --- |
| Environment variables | Which session, which process, which effort, which host | Free |
| Harness storage on disk | History, memory, config, other sessions | Cheap |
| The harness CLI's own help | What this build can do | Cheap |
| The loaded context | Tool, skill, agent and server rosters | Already paid |

Walk down, rather than starting at the bottom. The first two answer most
questions, and the fourth is the least reliable despite being free: it
describes capability without location, and it understates what is available
whenever tools are deferred.

**Done when:** the question is assigned to a surface, and to the specific
command or path on it that would answer it.

### 2. Establish self-location

Before reading anything, fix who and where you are. Most storage paths are
derived from these two values:

```sh
env | grep -iE '^(CLAUDE|ANTHROPIC|PI_|KIRO|TERM_PROGRAM)'
```

The session id and the working directory together locate this session's own
records. For Claude Code specifically, the derivation, the directory layout,
and the record schema are in
[references/claude.md](references/claude.md); read it before hand-rolling a
path. For pi (`@earendil-works/pi-coding-agent`), the equivalent is
[references/pi.md](references/pi.md) — including the `PI_*` variables that
remove the need to derive the transcript path at all. For Kiro, it is
[references/kiro.md](references/kiro.md) — including why the storage bucket
must be found rather than derived, and how policy can deny a read. For
Hermes, it is [references/hermes.md](references/hermes.md) — including the
interpreter split that makes `pip show` unreliable there (`$HERMES_PYTHON` is
the runtime, the `python3` on `PATH` may not be), the storage map under
`${HERMES_HOME}`, and a one-pass probe script that prints the whole
environment with guarded commands.

When the harness has no reference here, derive one in three moves, and write
it up per step 6 so the next agent inherits it. Identify the vendor from the
environment and the running executable, then find the state directory it
keys on (conventionally under the home directory, named for the vendor), then
locate this session's record inside it by searching for the session id rather
than reconstructing a path. Each move is one command, and the third is the one
that matters: a found path beats a derived path, which is why searching for
the id is the move even where a derivation is documented.

The working directory is load-bearing, because project-scoped storage keys on
the launch directory rather than the repository root. A session started one
level down is a different project as far as the harness is concerned, and sees
different memory.

**Done when:** the session id and project storage path are known and confirmed
to exist, and the process id is known or recorded as unavailable from the
environment.

### 3. Read, with two witnesses

Take no single reading as fact. **Two witnesses** is the working rule: every
claim about the harness gets corroborated from an independent surface before
it is stated.

Pairings that have each caught a real error:

- A registry of sessions, against the process table. Registry entries go stale.
- A CLI's reported version, against the executable actually running. The name
  on `PATH` is frequently a wrapper lagging the real binary.
- A conclusion drawn from a sample, against metadata the harness generated
  independently.

Where a second witness is unavailable, say so in the answer rather than
promoting a single reading to fact.

Where the question is decidable by calling the code rather than reading it,
call it. A code read infers what a function should do; executing it decides
what it does. Probe the public entry point with a synthetic input — a private
helper can satisfy a code read while the serving path diverges from it — and
let an executed probe, not a read, upgrade an answer from "should work" to
"works".

**Done when:** every claim to be stated has either a second witness or an
explicit note that it has one source.

### 4. Sample what is large

Harness storage runs to hundreds of megabytes. Transcripts of a hundred
thousand records are ordinary, so reading one whole is never the move.

Draw a uniform random sample and read that.
[scripts/sample-agent-log.bash](scripts/sample-agent-log.bash) does this for
JSONL: it rejection-samples indices from the OS randomness source, so no
record is likelier than another, and pulls them in a single pass.

```sh
scripts/sample-agent-log.bash --dir "${TRANSCRIPT_DIR}" --count 12
```

A dozen records out of tens of thousands is routinely enough to identify what a
session was about. Corroborate the result per step 3 before believing it.

For a targeted question, a single filtering pass beats sampling. Reach for
sampling when the question is "what is this", and for a filter when the
question names what it wants.

**Done when:** every artifact over a few megabytes was sampled or filtered
rather than read whole.

### 5. State absences as findings

An absence is a result. "No cross-session messaging tool is exposed, though the
transport appears to exist" is worth as much as a positive finding, and it
stops the next agent repeating the search.

Absolute negatives earn the most scrutiny, because they are the easiest to
state and the hardest to support. A claim that something cannot be seen needs
the same second witness as a claim that it can.

**Done when:** the answer distinguishes what was found, what was searched for
and absent, and what was not searched.

### 6. Write findings where they outlive the session

A finding that stays in the conversation is spent. Route each one:

- Durable harness facts belong in a reference document.
- Facts about how this user or project works belong in memory.
- Facts that change per version belong nowhere, and should be re-derived on
  demand rather than stored stale.

Routing has a gate: re-derive the finding in the turn that writes it. A wrong
statement in conversation costs one correction; persisted, it is re-read and
trusted for months, and the witness that would have caught it is gone. When a
claim cannot be re-derived now, record when it was last verified, or write
nothing.

Confirm the destination reads back. A harness may mediate file access through
policy, and a writable path is not always a readable one: an ignored scratch
or log directory will accept every write and refuse every read, which loses
the findings exactly when they were supposed to outlive the session. Read the
first line back before trusting a location, and keep a record whose path you
cannot re-read in the answer as well.

**Done when:** every finding has a destination, including the ones whose
destination is "nowhere, re-derive it", and each written destination has been
read back.

## Handling credentials

Harness storage holds authentication material, readable by the owning user.
Introspection stops at its existence: note that a credentials file is present
and move on. Nothing about understanding a harness requires its contents.

## Known limits

- Another session's in-memory context is unreachable. Its transcript on disk is
  readable and lags by seconds, which is a different thing and worth stating
  precisely.
- Deferred tools are listed by name, and their schemas load only on request, so
  the visible roster understates real capability.
- A skill's body loads only on invocation. Read the file directly to inspect
  one without triggering it.
- Interactively-authenticated servers may be absent in headless runs, so a
  roster read in one session does not describe another.
- Access policy is part of the harness, so some of it may be unreadable from
  inside: a refusal names the rule that produced it, which makes the refusal
  itself a finding worth reporting rather than an error to route around.
