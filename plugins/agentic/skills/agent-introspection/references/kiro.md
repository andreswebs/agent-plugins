# Kiro self-introspection

What an agent running inside Kiro (the VS Code-derived IDE) can learn about its
own harness, by looking rather than by recalling. Companion to
[claude.md](claude.md) and [pi.md](pi.md); the method is shared, the surfaces
differ where Kiro differs.

Verified in a live session against Kiro 1.2.4 with the shipped `kiro.kiro-agent`
extension at 1.1.237. Two witnesses were taken wherever one was available, and
single-source claims are marked as such. Harness facts drift between versions —
re-derive rather than trust.

Paths below use placeholders: `<session-id>` for a `sess_<uuid>` identifier,
`<workspace-hash>` for the 16-hex workspace bucket, `<workspace>` for a project
root. Some locations are user-overridable; see [Overrides](#overrides).

## The four introspection surfaces

| Surface               | What it answers                                | Cost           |
| --------------------- | ---------------------------------------------- | -------------- |
| Environment variables | Which session, which host app                  | Free           |
| `~/.kiro/` on disk    | Sessions, transcripts, settings, agents, specs | Cheap          |
| The `kiro` CLI        | Window management only — **not** agent state   | Cheap          |
| The prompt itself     | Tool, skill, agent and steering rosters        | Already loaded |

Work down the list, but note the third rung is weaker here than in other
harnesses: Kiro's CLI is a window launcher, so capability questions that
`claude --help` or `pi --help` would answer go to the on-disk tree and the
shipped extension instead.

## 1. Environment variables

One command:

```sh
env | grep -iE '^(KIRO|TERM_PROGRAM|__CFBundleIdentifier|AWS_SDK_UA_APP_ID)'
```

| Variable                                | Meaning                                               |
| --------------------------------------- | ----------------------------------------------------- |
| `KIRO_SESSION_ID`                       | This session's id, `sess_<uuid>`. Key to its records. |
| `TERM_PROGRAM=kiro`                     | "Am I running inside Kiro" test for scripts.          |
| `__CFBundleIdentifier=dev.kiro.desktop` | macOS host-app witness.                               |
| `AWS_SDK_UA_APP_ID=kiro-ide`            | Second host witness; survives into AWS SDK calls.     |
| `GIT_ASKPASS`, `VSCODE_GIT_ASKPASS_*`   | Point into `Kiro.app`; the VS Code lineage witness.   |

`KIRO_SESSION_ID` plus the working directory is the whole of self-location: the
session id names the record directory, and the working directory determines
which workspace bucket holds it.

Two verified absences, both of which change the method:

- **There is no `KIRO_PID`.** Process self-identification comes from the
  process table, not the environment.
- **There is no model or effort variable.** Unlike `CLAUDE_EFFORT` or
  `PI_REASONING_LEVEL`, Kiro exposes nothing about the model in the
  environment, and the configured value may be `auto` (server-selected) and so
  not knowable in advance at all. The authoritative witnesses are
  `session.json` (`modelId`, `contextSnapshotModelDisplay`) for what was
  configured, and the transcript's per-turn `reasoningModelId` for what
  actually ran.

One caution on reading the environment at all: a developer's shell may export
variables belonging to _other_ agent harnesses, and those survive into Kiro's
shell tool. The presence of a foreign harness variable is not evidence that
harness is driving the session — corroborate with `TERM_PROGRAM` or the bundle
identifier before attributing anything.

## 2. The `~/.kiro/` tree

This is the agent-state tree, and it is where most questions are answered.

```text
~/.kiro/
  sessions/            transcripts and per-session state, see below
  session-index/       append-only existence log per workspace bucket
  spec-sessions/       <workspace-hash>.json: spec name -> session id
  settings/            permissions.yaml (user-level policy)
  workspace-roots/     <workspace-hash>/permissions.yaml (workspace policy)
  agents/              *.json custom agent definitions
  powers/              installed.json + registries/
  skills/              user skills, one directory per skill with SKILL.md
  extensions/          installed IDE extensions
  logs/                <YYYYMMDDTHHMMSSmmm>/{kiro.log,mcp.log,powers.log}
  crew/                kirocrew subsystem, present by default
  argv.json            launch arguments
```

The Electron user-data directory is separate, and holds the IDE half rather
than the agent half: on macOS `~/Library/Application Support/Kiro/` with
`logs/`, `machineid`, `Crashpad/`, `User/workspaceStorage/<hash>/`, and a
`<version>-main.sock` IPC socket.

`crew/` belongs to the kirocrew subsystem and is created by default whether or
not it is used. It holds a service tree (gateway, databases, its own sessions
and skills) and **a token signing key**. Note its existence and move on; see
[Credentials](#credentials).

### Sessions

```text
~/.kiro/sessions/<workspace-hash>/<session-id>/
  messages.jsonl      the transcript, appended live
  session.json        session metadata
  snapshots/          pre-edit file backups, see below
  sub-executions/     one JSONL per subagent or workflow step
  publish.cursor      "<byteOffset>:<lineCount>" into messages.jsonl
~/.kiro/sessions/<workspace-hash>/.index/index.json
~/.kiro/sessions/_global/
```

The `<workspace-hash>` is a 16-hex bucket derived from the workspace root, with
`_global` holding sessions that belong to no workspace. **Do not hand-derive
the hash.** Unlike Claude Code's path-slug, it is opaque: find your bucket by
matching `session.json`'s `workspacePaths` instead, or by locating
`KIRO_SESSION_ID` directly:

```sh
find ~/.kiro/sessions -maxdepth 2 -name "${KIRO_SESSION_ID}"
```

That one command is the whole of self-location, and it sidesteps the derivation
fragility that `claude.md` has to warn about at length.

#### Transcript record shape

Records are a uniform envelope, and this is the single most important
structural difference from the other harnesses:

```json
{
  "id": "<record-id>",
  "payload": { "type": "assistant", "…": "…" },
  "timestamp": "…"
}
```

**The role and type live inside `.payload`, not at the top level.** Claude Code
puts `.type` on the record and pi puts `.type` on a tree node; Kiro wraps
everything. Every `jq` filter ported from those references must unwrap
`.payload` first, or it silently matches nothing.

`payload.type` values observed:

| `payload.type`                          | Contents                                         |
| --------------------------------------- | ------------------------------------------------ |
| `session_start`                         | Session opening marker                           |
| `user`                                  | A human turn; `images`/`documents` when attached |
| `assistant`                             | A model turn                                     |
| `tool_call`                             | One tool invocation                              |
| `tool_result`                           | Its result                                       |
| `turn_start`, `turn_end`                | Turn boundaries; `turn_end` carries `stopReason` |
| `usage_summary`                         | Per-turn accounting, see below                   |
| `session_metadata`                      | Key/value state, e.g. context usage              |
| `session_event`                         | Lifecycle events, e.g. `category: session_pause` |
| `pending_interaction`                   | A question put to the user, with `options`       |
| `interaction_resolved`                  | Its `outcome` and `selectedOption`               |
| `agent_note`                            | A note the agent recorded                        |
| `sub_agent_start`, `sub_agent_complete` | Delegation boundaries                            |

Fields that repay attention:

- `executionId` ties records to one execution, and is present on nearly all of
  them. It is the join key for reconstructing a single run.
- `toolName`, `args`, `toolCallId`, `success` on tool records.
- `kind` and `actionType` give a normalised tool taxonomy independent of tool
  names: `read/read_files`, `edit/create`, `edit/write`, `edit/replace`,
  `edit/append`, `execute/run_command`, and `other/*` for the rest. This is
  more useful than the raw `toolName` histogram, because it survives tool
  renames.
- `reasoningModelId` and `reasoningSignature` record the model that actually
  served each turn. **This is the only reliable model witness**, given the
  environment carries none and the configured value may be `auto`.
- `usage_summary` carries `promptTurnSummaries[]` with `{unit, unitPlural,
usage, usedTools}`, plus `requestIds`, `elapsedTime` and `status`.
- `session_metadata` with `key: "contextUsage"` carries
  `value.usagePercentage`. An agent can therefore read its own context
  pressure from its own transcript.

Profiling one-liners, each run for real:

```sh
SELF="$(find ~/.kiro/sessions -maxdepth 2 -name "${KIRO_SESSION_ID}")"

# what kinds of record does this session hold
jq -r '.payload.type' "${SELF}/messages.jsonl" | sort | uniq -c | sort -rn

# what did it actually do, by tool
jq -r 'select(.payload.type=="tool_call") | .payload.toolName' \
  "${SELF}/messages.jsonl" | sort | uniq -c | sort -rn

# the same, by normalised action
jq -r 'select(.payload.type=="tool_call")
       | (.payload.kind // "-") + "/" + (.payload.actionType // "-")' \
  "${SELF}/messages.jsonl" | sort | uniq -c | sort -rn

# which models actually served turns
jq -r 'select(.payload.reasoningModelId) | .payload.reasoningModelId' \
  "${SELF}/messages.jsonl" | sort | uniq -c

# current context pressure
jq -r 'select(.payload.key=="contextUsage") | .payload.value.usagePercentage' \
  "${SELF}/messages.jsonl" | tail -1
```

#### `session.json`

The richest single metadata witness in the harness, and the cheapest way to
identify a session:

```json
{
  "schemaVersion": "…",
  "dataModelVersion": 1,
  "id": "<session-id>",
  "title": "<auto-generated title>",
  "agentMode": "vibe",
  "workspacePaths": ["<workspace>"],
  "rootPaths": ["<workspace>"],
  "createdAt": "…",
  "lastModifiedAt": "…",
  "modelId": "auto",
  "contextSnapshotModelDisplay": {
    "modelId": "auto",
    "display": "<display name>"
  },
  "status": "in_progress",
  "specWorkflow": "quick",
  "specPlanEnabled": false,
  "workflowsEnabled": true,
  "semanticReviewEnabled": true,
  "disableAutoCompaction": false,
  "steeringSupervisorEnabled": null,
  "memoryConfig": { "mode": "read_write", "reflection": true },
  "_meta": { "kiro": { "policyPreset": ["…"], "shellType": "zsh" } }
}
```

`title` is harness-generated and is the one-line answer to "what is this
session about", the equivalent of Claude Code's `aiTitle`. `agentMode`
distinguishes a `vibe` session from a `spec` one. `_meta.kiro.policyPreset`
names the permission preset in force, and `shellType` the shell the agent's
commands run under. `steeringSupervisorEnabled` gates an undocumented check
that has a fast model vet shell commands and file writes against steering.

#### The session roster, and why it needs a second witness

Two surfaces answer "what sessions exist", and neither answers "what is
running".

`~/.kiro/sessions/<workspace-hash>/.index/index.json` is a roster **cache**:

```json
{
  "schemaVersion": "…",
  "entries": [
    {
      "id": "…",
      "title": "…",
      "agentMode": "…",
      "status": "…",
      "createdAt": "…",
      "lastModifiedAt": "…",
      "workspacePaths": ["…"],
      "rootPaths": ["…"],
      "_meta": {}
    }
  ],
  "dirMtimeMs": 0,
  "dirNamesHash": "…",
  "walkedAtMs": 0
}
```

The `walkedAtMs`, `dirMtimeMs` and `dirNamesHash` fields exist precisely
because it is a cache of a directory walk, so it can lag the tree. Corroborate
against the directories themselves before believing an entry.

`~/.kiro/session-index/<workspace-hash>.jsonl` (plus `_global.jsonl`) is an
append-only operation log, one line per change:

```json
{ "op": "add", "sessionPath": "<workspace-hash>/<session-id>", "at": 0 }
```

It records **existence over time, not liveness**. Kiro writes no per-PID
registry of running sessions — verified by walking the tree and finding none —
so unlike Claude Code's `~/.claude/sessions/<pid>.json`, the question "what is
running right now" has only one answer:

```sh
ps -eo pid,etime,command | grep '[K]iro'
```

That shows the Electron process tree (main, renderers, utility and extension
hosts) rather than one line per agent session, so it establishes that Kiro is
running, not which sessions are live. State that limit rather than implying
per-session liveness.

#### Snapshots are file backups

`snapshots/<short-hash>/` holds a `.hash` file containing a SHA-256, alongside
a **mirror of the workspace-relative paths the session modified**. This is
Kiro's equivalent of Claude Code's `file-history/`: it allows reconstructing
what a file looked like before an edit without relying on git, which matters
for untracked or ignored files.

Two consequences. It is a second witness for "what did this session change",
independent of the transcript. And it is a privacy surface: a snapshot
contains file _contents_, so it deserves the same restraint as any other
workspace read.

#### Sub-executions

`sub-executions/<execution-uuid>.jsonl` holds one transcript per subagent or
workflow step, in **the same `{id, payload, timestamp}` envelope** as the
parent. The parent transcript brackets each with `sub_agent_start` and
`sub_agent_complete` records.

So delegated work is fully readable after the fact, and the parent's
`executionId` values link the two. This is the surface for "what did the agent
I dispatched actually do".

### Workspace-level configuration

Alongside the user tree, each project carries its own:

```text
<workspace>/.kiro/
  specs/<name>/{requirements.md,design.md,tasks.md,.config.kiro}
  settings/mcp.json
  steering/     created on demand
  hooks/        created on demand
  workflows/    created on demand
  agents/       created on demand
```

The `specs/<name>/` triple is the spec workflow on disk, in its running order:
`requirements.md`, then `design.md`, then `tasks.md`. Reading them is how you
establish what phase a feature is actually in, rather than asking.

The on-demand directories are **absent until first used**, so their absence is
a finding about this project, not about the harness. Do not conclude a feature
is unavailable from a missing directory. `steering/` is created by the IDE's
"Generate Steering Docs" and "+" commands and by the first-open Cursor-rules
import, as well as by the agent writing a file there.

## 3. The `kiro` CLI

```sh
kiro --version   # version, commit hash, architecture
kiro --help
```

Set expectations correctly: this is a VS Code-style **window launcher**, not an
agent-state tool. It offers `--diff`, `--merge`, `--goto`, `--add`, `--remove`,
`--new-window`, `--reuse-window`, `--wait`, `--locale`, `--user-data-dir`,
`--profile`, and `--agents` (which opens a window, rather than printing a
roster). There are no session, transcript, or configuration subcommands.

`--user-data-dir` is worth noting for a different reason: it is the lever that
relocates the Electron tree, so a tree that looks missing may simply have been
moved.

For questions the CLI cannot answer, the shipped agent extension is the
authority on what the agent layer knows:

```sh
ls /Applications/Kiro.app/Contents/Resources/app/extensions/kiro.kiro-agent/
```

Grepping that bundle is the way to settle a provenance question — whether a
name belongs to Kiro or to something installed. Inferring provenance from a
directory's name alone produces wrong answers; this reference's own first draft
got one wrong that way, and the bundle corrected it in one command.

## 4. The prompt itself

Free, already loaded, and incomplete in the usual ways. It carries the tool
roster, the skill list with one-line descriptions, the agent roster for
delegation, and any steering content in force.

Two gaps specific to Kiro:

- **Skill bodies load only on activation.** The roster shows name and
  description; the instructions arrive when the skill is activated. Read a
  `SKILL.md` directly to inspect a skill without triggering it.
- **Steering may be in context without a workspace directory to explain it.**
  Steering shown in the prompt does not imply `<workspace>/.kiro/steering/`
  exists. There are two channels. User files arrive as
  `## Included Rules (<name>)` messages added to the conversation. The
  `<steering-files>` block in the system prompt is compiled into the extension
  and carries the mode prompt, the "Workflow Orchestration" instructions, the
  workflow-step contract, and any cloud-configuration steering. No file on disk
  backs that block. Treat the prompt as evidence of _what is loaded_ and the
  disk as evidence of _where it came from_, and do not assume the two agree.

## Permission policy

Kiro mediates tool access through policy files, and this surface has more
practical consequence for introspection than in any other harness, because it
can stop you reading your own work.

```text
~/.kiro/settings/permissions.yaml                      user-level
~/.kiro/workspace-roots/<workspace-hash>/permissions.yaml   workspace-level
```

```yaml
rules:
  - capability: fs_read # also: fs_write, shell, web_fetch, web_search, mcp, skill
    effect: allow # or deny
    match:
      - <glob>
```

Four behaviours, all verified in a live session, and each one counter-intuitive
enough to be worth knowing before you design around it:

1. **Deny beats allow.** An explicit workspace-level `allow` for a path did
   **not** restore read access to a path denied by policy, including after a
   full session reload. Adding an allow rule is not a way out of a deny.
2. **Ignore files feed the deny list.** Patterns from the user's gitignore
   appeared as `fs_read` deny rules, attributed to that file by path in the
   refusal message. Ignored directories are therefore frequently unreadable,
   which catches scratch and log directories in particular. The refusal names
   its source, so read the refusal rather than guessing.
3. **Paths are canonicalised before matching.** A symlink pointing at a denied
   directory is denied too, and the refusal still names the resolved target.
   Aliasing does not evade policy.
4. **The agent cannot edit its own policy.** A built-in `kiro-scope` rule
   denies `fs_write` to `~/.kiro/settings/`, `~/.kiro/workspace-roots/`, and
   several sibling directories. Policy changes belong to the user, which is
   the correct boundary — surface the exact edit for them to make instead of
   attempting it.

The combination of 1 and 2 produces the trap worth internalising: **write
access does not imply read access.** A session can create a file and then be
unable to read it back. Before choosing a location for findings, notes, or a
log, confirm the destination is readable as well as writable — a `deny` on an
ignored directory will let every write succeed and every read fail.

## Credentials

The `crew/` subtree contains a token signing key and related material, and it
is present by default. Introspection stops at noting existence. Nothing about
understanding the harness requires reading it.

The Electron tree additionally holds `Cookies`, `machineid` and
`TransportSecurity`. Same rule: their existence is the finding.

## Overrides

Some locations are user-configurable or conventionally relocated, so treat the
layout above as the default rather than a guarantee:

- `--user-data-dir` relocates the Electron tree.
- `~/.kiro/skills/` is frequently a **symlink** into a dotfiles repository, a
  common pattern for keeping skills version-controlled. Resolve it before
  reporting where a skill lives.
- Permission policy is layered user-then-workspace, so a capability available
  in one project may be denied in another. A roster or capability reading from
  one session does not describe another.

## Known limits

- No access to another session's in-memory context or current turn. Its
  `messages.jsonl` is readable and lags by seconds, which is a different thing
  and worth stating precisely.
- No per-session liveness surface. `ps` shows the Electron process tree, not
  one entry per agent session, and the session index records existence rather
  than liveness.
- No `KIRO_PID`.
- No model or effort environment variable; the configured model may be `auto`,
  so only the transcript's `reasoningModelId` reports what actually ran.
- The `kiro` CLI answers nothing about agent state.
- `.index/index.json` is a cache and can lag the session directories.
- Policy can make a written path unreadable, and an allow rule will not undo a
  deny.

## Steering resolution

Read from the `kiroAgent` 1.1.237 bundle and checked against kiro.dev where
the docs cover it; not observed in a run. The full write-up, with creation
prompts, front-matter schema and limits, is `references/kiro-steering.md` in
the `kiro-docs-nav` skill.

- **Locations:** each workspace root's `.kiro/steering/**/*.md` (recursive),
  `~/.kiro/steering/**/*.md`, a cloud-configuration `steering/` scanned before
  the home one, the root `AGENTS.md` (always included), nested `AGENTS.md`
  files (trusted workspaces only, `fileMatch` on their own directory),
  steering pushed by an ACP client, and three built-in `manual` documents.
- **No override.** Every scope loads; the only dedupe is by file URI.
  "Workspace beats global" is a sentence in the rendered block, left to the
  model. Name collisions only matter in the `disclose_context` catalog, where
  later wins in the order cloud, global, then each workspace, skills before
  steering.
- **Untrusted workspaces** load global-scope documents only.
- **Per turn, not per session.** Documents are added once and not re-sent, so
  an edit to an attached file does not reach that conversation.
- **The transcript does not record injected steering.** `messages.jsonl` will
  not tell you which steering a session saw.

## Not yet verified

Named so the next agent digs rather than assuming absence. Each is a gap in
this document, not a statement about the harness:

- **Compaction.** `session.json` carries `disableAutoCompaction`, so the
  feature exists, but no compaction record type appeared in the transcripts
  sampled. Whether compaction writes a record, rewrites the file, or leaves no
  trace is unresolved.
- **Memory.** `session.json` carries `memoryConfig` with a mode and a
  reflection flag, but the storage location backing it was not established.
- **`spec-sessions/<workspace-hash>.json`** maps a spec name to an identifier;
  the full lifecycle it drives was not traced.
- **`powers/`** was empty in the session observed, so the installed-power
  layout is undocumented here.
- **Hooks**: the on-disk shape under `<workspace>/.kiro/hooks/` was not
  observed, since the directory did not exist. The bundle (one witness) shows
  legacy `<name>.kiro.hook` files migrating to `<name>.json` holding
  `{"version": "v1", "hooks": [...]}`, each hook with `name`, `trigger`, an
  optional regex `matcher`, an `action` of `{type: "command"}` or
  `{type: "agent", prompt}`, and `enabled`. The kiro.dev hooks page corroborates
  the `.json` file location only.
- **Steering in custom agents and Powers.** Steering resolution itself is now
  established from the bundle; see
  [Steering resolution](#steering-resolution). Whether IDE custom agents skip default
  steering (the docs say they do unless it is listed in `resources`) and how
  Powers load their steering files were not traced.
- **`publish.cursor`** reads as `<byteOffset>:<lineCount>`; what consumes it
  is unconfirmed.
- Everything here is stamped to Kiro 1.2.4 / `kiroAgent` 1.1.237. An update
  can invalidate it.

## Quick reference

```sh
# who am I
echo "${KIRO_SESSION_ID}"; echo "${TERM_PROGRAM}"

# my own session directory, without deriving any hash
SELF="$(find ~/.kiro/sessions -maxdepth 2 -name "${KIRO_SESSION_ID}")"

# what is this session about
jq -r '.title, .agentMode, .status' "${SELF}/session.json"

# what did it do
jq -r 'select(.payload.type=="tool_call") | .payload.toolName' \
  "${SELF}/messages.jsonl" | sort | uniq -c | sort -rn

# which model actually served the turns
jq -r 'select(.payload.reasoningModelId) | .payload.reasoningModelId' \
  "${SELF}/messages.jsonl" | sort | uniq -c

# what did I delegate, and what did it do
ls "${SELF}/sub-executions/" 2>/dev/null

# which files did I change (independent of the transcript)
find "${SELF}/snapshots" -mindepth 2 -not -name .hash

# what sessions exist for this workspace
jq -r '.entries[] | [.id, .status, .title] | @tsv' \
  "$(dirname "${SELF}")/.index/index.json"

# is Kiro running, and as what
ps -eo pid,etime,command | grep '[K]iro' | head

# what policy applies to me
cat ~/.kiro/settings/permissions.yaml
```
