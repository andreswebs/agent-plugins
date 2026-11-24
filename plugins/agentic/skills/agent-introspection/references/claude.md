# Claude Code self-introspection

What an agent running inside Claude Code can learn about its own harness, by
looking rather than by recalling. Every claim below was verified empirically in
a live session; the method used is given alongside each finding so it can be
re-run rather than trusted.

Read this before spending tokens rediscovering the same surfaces.

## Why bother

The system prompt describes the harness in prose, and prose is lossy. It names
the tools but not their storage; it names skills but not where they resolve
from; it says nothing about what other sessions are doing. Most of that is
sitting on disk in a documented-enough shape, readable with the same Bash and
Read tools used for any other file.

The single most useful habit: **an agent can read its own transcript while the
session is still running.** Everything else follows from that.

## The four introspection surfaces

| Surface               | What it answers                                | Cost           |
| --------------------- | ---------------------------------------------- | -------------- |
| Environment variables | Who am I, which session, which effort level    | Free           |
| `~/.claude/` on disk  | History, memory, config, other sessions        | Cheap          |
| The `claude` CLI      | What the binary can do, health, MCP, plugins   | Cheap          |
| The prompt itself     | Tool list, skill list, agent types, MCP roster | Already loaded |

Work down that list. The first two answer most questions.

### 1. Environment variables

The fastest orientation available. One command:

```sh
env | grep -E '^CLAUDE|^ANTHROPIC'
```

Observed keys, and what each is good for:

| Variable                    | Meaning                                                      |
| --------------------------- | ------------------------------------------------------------ |
| `CLAUDE_CODE_SESSION_ID`    | This session's UUID. The key to the transcript path.         |
| `CLAUDE_PID`                | This process's PID. The key to the live-session registry.    |
| `CLAUDECODE=1`              | Reliable "am I running inside Claude Code" test for scripts. |
| `CLAUDE_CODE_ENTRYPOINT`    | `claude-vscode`, `cli`, and so on. Which host is driving.    |
| `CLAUDE_EFFORT`             | Current reasoning effort tier.                               |
| `CLAUDE_AGENT_SDK_VERSION`  | SDK version, distinct from the CLI version.                  |
| `CLAUDE_CODE_EXECPATH`      | The actual binary in use.                                    |
| `CLAUDE_CODE_CHILD_SESSION` | Set when the session was spawned by another.                 |

`CLAUDECODE=1` is the right guard for a script that must behave differently
under an agent. Do not sniff for a TTY.

Caution on versions: `claude --version` reports whatever binary is first on
`PATH`, which is frequently a user wrapper script and can lag the binary the
session is actually running. `CLAUDE_CODE_EXECPATH` and the `version` field
inside transcript records are authoritative; trust those instead.

### 2. The `~/.claude/` tree

```text
~/.claude/
  CLAUDE.md                  user-level global instructions
  settings.json              user settings (permissions, effortLevel, env)
  .credentials.json          auth material, mode 0600, do not read
  history.jsonl              every prompt typed, across all projects
  projects/<slug>/           per-project state, see below
  sessions/<pid>.json        live-session registry, see below
  session-env/<uuid>/        per-session environment scratch
  file-history/<uuid>/       pre-edit file backups, keyed by session
  shell-snapshots/           captured shell init, sourced by every Bash call
  plans/                     saved plan-mode documents
  plugins/                   marketplaces and installed plugins
  skills/                    user skills, often a symlink into dotfiles
  mcp-needs-auth-cache.json  which MCP servers are unauthenticated
  policy-limits.json         active policy limits
```

#### Project state and the slug

The per-project directory name is the absolute working directory with every
`/` replaced by `-`:

```sh
PROJECT_DIR="${PWD}"
SLUG="$(echo "${PROJECT_DIR}" | sed 's|/|-|g')"
ls "${HOME}/.claude/projects/${SLUG}/"
```

Consequences worth knowing, because each one silently splits state in two:

- It keys on the **launch directory**, not the git root. Starting from a
  subdirectory produces a different slug and therefore different memory and a
  different transcript set.
- It is **case-sensitive**. A path typed with a different capitalisation is a
  different project as far as the harness is concerned.
- **Git worktrees** get their own slug.
- Moving or renaming a repository orphans everything under the old slug. The
  files remain, unreferenced.
- There is **no inheritance** between a parent directory and a nested
  repository. Each has its own memory and sees nothing of the other's.

#### Transcripts

Every session is a JSONL file at
`~/.claude/projects/${SLUG}/${CLAUDE_CODE_SESSION_ID}.jsonl`, appended to in
real time. An agent can read its own:

```sh
SLUG="$(echo "${PWD}" | sed 's|/|-|g')"
SELF="${HOME}/.claude/projects/${SLUG}/${CLAUDE_CODE_SESSION_ID}.jsonl"
jq -r '.type' "${SELF}" | sort | uniq -c | sort -rn
```

They get large. Observed in one project: a four-day session of 68,019 records
and 143 MB. Never `cat` one. Sample it, or filter with `jq` in a single pass.

Record types observed, with what each is for:

| `type`                  | Contents                                                       |
| ----------------------- | -------------------------------------------------------------- |
| `user`                  | Human prompts and tool results, distinguished by `origin.kind` |
| `assistant`             | Model turns: `text`, `thinking`, `tool_use` blocks             |
| `attachment`            | Injected context (deferred tool deltas, reminders, file reads) |
| `system`                | Harness notices                                                |
| `ai-title`              | The rolling auto-generated session title                       |
| `last-prompt`           | Snapshot of the most recent prompt                             |
| `file-history-snapshot` | Full file state before an edit                                 |
| `file-history-delta`    | Backup pointer for one tracked file                            |
| `queue-operation`       | Prompt enqueue and dequeue                                     |
| `mode`, `atis-latch`    | Harness-internal state                                         |

Fields that repay attention on `user` and `assistant` records:

- `timestamp`, `sessionId`, `uuid`, `parentUuid`: the message tree.
- `cwd`, `gitBranch`, `version`, `entrypoint`: environment at that moment.
- `isSidechain`: true for subagent turns, so a boolean separates a subagent's
  work from the main thread.
- `effort` and `message.model`: the tier and model actually used for that turn.
- `attributionSkill`: **which skill an action is attributed to.** This is the
  hook that makes skill usage auditable after the fact.
- `origin.kind`: `human` distinguishes a real user prompt from a tool result,
  both of which carry `type: "user"`.
- `toolUseResult`: structured result payload for a tool call.

A useful profiling one-liner, which tells you what a session actually did:

```sh
jq -r 'select(.type=="assistant") | .message.content[]?
       | select(.type=="tool_use") | .name' "${SELF}" \
  | sort | uniq -c | sort -rn
```

The ratio is diagnostic. A session with Bash far above Read verified through
the shell rather than by reading; a high `AskUserQuestion` count against a low
`Agent` count was interactive and did not delegate.

Extracting the opening prompt identifies a session in one line:

```sh
jq -r 'select(.type=="user" and .origin.kind=="human")
       | .message.content[0].text // empty' "${SELF}" | head -1
```

Or just read the `aiTitle`, which the harness maintains for free.

#### The live-session registry

`~/.claude/sessions/<pid>.json`, one file per running session. This is the
surface most easily overlooked, and it is the one that answers "what else is
running right now".

```json
{
  "pid": 58045,
  "sessionId": "…",
  "cwd": "/path/to/project",
  "startedAt": 1788132948919,
  "version": "2.1.247",
  "kind": "interactive",
  "entrypoint": "claude-vscode",
  "name": "liane-toolkit-ae",
  "nameSource": "derived",
  "peerProtocol": 1,
  "peerFeatures": ["notify_idle", "artifact_yield"]
}
```

Entries can be stale, so cross-check against the process table before
believing one:

```sh
for f in "${HOME}"/.claude/sessions/*.json; do
    jq -r '[.pid, .name, .cwd, .sessionId] | @tsv' "${f}"
done | while IFS=$'\t' read -r pid name cwd sid; do
    ps -p "${pid}" >/dev/null 2>&1 && echo "ALIVE ${pid} ${name} ${cwd} ${sid}"
done
```

The `peerFeatures` array implies sessions can signal one another, but no
agent-facing tool for that was found. Treat cross-session messaging as
unavailable unless a tool for it appears in the prompt.

The process table is itself informative. Session arguments are visible in
full, including `--resume=<uuid>`, `--permission-mode`, `--setting-sources`,
and `--max-thinking-tokens`:

```sh
ps -eo pid,etime,command | grep '[c]laude'
```

#### What this means for "can I see other agents"

The honest answer has three parts, and the middle one is easy to get wrong:

1. **No live channel.** Another session's in-memory context, its current turn,
   its unsaved reasoning: not reachable. The only agents whose output arrives
   directly are subagents spawned in this session.
2. **But transcripts are readable, and they are near-live.** Another session's
   JSONL is appended as it works. Reading it gives its prompts, tool calls,
   results and reasoning, seconds behind. This is a real capability, and
   claiming otherwise is wrong.
3. **And the registry exposes existence.** Names, working directories,
   versions, uptime, resumed session IDs, all without reading a transcript.

So: no shared mind, but close to a shared filing cabinet.

#### Memory

`~/.claude/projects/${SLUG}/memory/`, holding `MEMORY.md` as an index plus one
file per fact. `MEMORY.md` is loaded into context automatically at session
start; the individual files are pulled in on relevance.

The location is **positional, not configurable**. No settings key points at it.
It inherits every slug fragility listed above.

To stabilise it, symlink the directory. Pointing several slugs at one target
(repository root, parent workspace, worktrees) collapses the fragmentation:

```sh
REPO="${HOME}/path/to/repo"
SLUG="$(echo "${REPO}" | sed 's|/|-|g')"
MEM="${HOME}/.claude/projects/${SLUG}/memory"
mv "${MEM}" "${REPO}/.claude-memory"
ln -s "${REPO}/.claude-memory" "${MEM}"
```

This is the same pattern the harness itself tolerates for `~/.claude/skills`,
which is commonly a symlink into a dotfiles repository.

#### File history

`~/.claude/file-history/<session-uuid>/` holds pre-edit backups, named by a
content hash plus a version suffix (`36f352cd79749bcb@v1`). The transcript's
`file-history-delta` records map a `trackingPath` to its backup. Together these
allow reconstructing what a file looked like before any given edit, without
git. Useful when an edit was made to an untracked or gitignored file.

#### Prompt history

`~/.claude/history.jsonl` records every prompt typed, across all projects, with
`display`, `project`, `sessionId`, `timestamp` and `pastedContents`. It is the
fastest way to answer "when did I last ask about X" without scanning
transcripts, since it is small and covers everything.

### 3. The `claude` CLI

`claude --help` is the authoritative capability list for the installed build,
and it changes between versions. Read it rather than recalling it.

Subcommands observed:

| Command               | Use                                                         |
| --------------------- | ----------------------------------------------------------- |
| `doctor`              | Installation health. Reads settings without a trust prompt. |
| `mcp`                 | Configure and inspect MCP servers.                          |
| `plugin`              | Manage plugins and marketplaces.                            |
| `agents`              | Manage background agents.                                   |
| `project`             | Manage project state.                                       |
| `auth`, `setup-token` | Authentication.                                             |
| `auto-mode`           | Inspect or reset the auto-mode classifier.                  |
| `ultrareview`         | Cloud-hosted multi-agent review of a branch or PR.          |
| `install`, `update`   | Build management.                                           |
| `gateway`             | Enterprise auth and telemetry gateway.                      |

Flags worth knowing for introspection specifically:

- `--bare` documents, by listing what it disables, exactly which implicit
  machinery a normal session runs: hooks, LSP, plugin sync, attribution,
  auto-memory, background prefetches, keychain reads, and `CLAUDE.md`
  auto-discovery. Reading that one flag's help text is the cheapest available
  summary of the harness's ambient behaviour.
- `--setting-sources` names the settings precedence chain in use, typically
  `user,project,local`.
- `--debug [filter]` takes category filters such as `api,hooks` or negations
  such as `!1p,!file`.

Run these read-only. `doctor`, `mcp list` and `plugin list` are safe;
`install`, `update` and `auth` are not, and belong to the user.

### 4. The prompt itself

Already in context, so free, but incomplete in a specific way: **deferred
tools appear by name only.** Their schemas are absent until fetched, and a
deferred tool cannot be called before then:

```text
ToolSearch(query: "select:WebFetch,WebSearch")
```

Consequences: the visible tool list understates real capability, and an
inventory of "what can I do" must include the deferred names. The prompt also
carries the skills list with one-line descriptions, the agent-type roster with
each type's tool access, and the MCP server roster including which servers
need authentication (mirrored on disk in `mcp-needs-auth-cache.json`).

Skills resolve from `~/.claude/skills/<name>/SKILL.md`, with YAML frontmatter
carrying `name`, `description` and sometimes `compatibility`. The description
is what the harness matches against, so reading it explains why a skill did or
did not trigger. The body is only loaded on invocation, so a skill's real
content is invisible until called: read the file directly to inspect one
without invoking it.

## Method notes

Four practices that made the difference here.

**Verify, do not recall.** Harness details drift between versions. Every
statement above cost one command. The version discrepancy in this very
session, a `PATH` wrapper reporting 2.1.220 while the running binary was
2.1.247, is exactly the class of error that recall produces and a command
catches.

**Sample large artefacts, never read them whole.** For a 143 MB transcript,
draw random record indices and pull them in a single pass. Uniform sampling
needs rejection sampling, since a bare modulo of a random word biases the low
residues. A companion implementation lives in this directory's `scripts/`.
Twelve random records out of 68,019 were sufficient to identify a session's
subject, and the harness-generated `aiTitle` then confirmed it independently.

**Cross-check two surfaces before believing either.** The session registry
against the process table; `claude --version` against `CLAUDE_CODE_EXECPATH`;
a sampled transcript against its own `aiTitle`. Each pairing here caught
something the single surface would have got wrong.

**State absences explicitly.** "No cross-session messaging tool was found" is a
finding. "I cannot see other sessions" was, in this session, a wrong finding
stated too absolutely, and the registry disproved it within minutes.

## Known limits

- No access to another session's in-memory context or current turn.
- No agent-facing cross-session messaging, despite `peerFeatures` implying the
  transport exists.
- No settings key relocates the memory directory; symlinking is the only lever.
- Deferred tool schemas are not enumerable in bulk, only fetched by query.
- Interactively-authenticated MCP servers may be absent in headless runs, so an
  MCP roster read in one session does not describe another.
- `.credentials.json` is readable by the owning user. Do not read it. Nothing
  legitimate requires it.

## Quick reference

```sh
# who am I
echo "${CLAUDE_CODE_SESSION_ID}" "${CLAUDE_PID}" "${CLAUDE_EFFORT}"

# my own transcript
SLUG="$(echo "${PWD}" | sed 's|/|-|g')"
SELF="${HOME}/.claude/projects/${SLUG}/${CLAUDE_CODE_SESSION_ID}.jsonl"

# what have I done this session
jq -r 'select(.type=="assistant") | .message.content[]?
       | select(.type=="tool_use") | .name' "${SELF}" | sort | uniq -c | sort -rn

# which skills have been attributed
jq -r 'select(.attributionSkill) | .attributionSkill' "${SELF}" | sort | uniq -c

# what else is running
ps -eo pid,etime,command | grep '[c]laude'

# what this build can do
claude --help
```
