# pi self-introspection

What an agent running inside pi (`@earendil-works/pi-coding-agent`) can learn
about its own harness, by looking rather than by recalling. Companion to
[claude.md](claude.md) for the other harness; the method is shared, the
surfaces differ where pi differs.

Verified against pi 0.85.1 in a live session. Every claim below has two
witnesses: the shipped docs at
`/home/pi/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/docs/`
(read them with the same `read` tool as any file), and the live machine.
Harness facts drift between versions — re-derive rather than trust.

## The four introspection surfaces

| Surface                | What it answers                             | Cost           |
| ---------------------- | ------------------------------------------- | -------------- |
| Environment variables  | Which session, which model, which effort    | Free           |
| `~/.pi/agent/` on disk | Sessions, settings, skills, extensions      | Cheap          |
| The `pi` CLI           | What this build can do                      | Cheap          |
| The prompt itself      | Tool list, skill list, loaded context files | Already loaded |

Work down that list. The first two answer most questions.

## 1. Environment variables

One command:

```sh
env | grep -E '^(AI_AGENT|PI_)'
```

Observed keys, and what each is good for:

| Variable               | Meaning                                                      |
| ---------------------- | ------------------------------------------------------------ |
| `AI_AGENT=pi`          | Generic cross-harness marker: "an agent launched me".        |
| `PI_CODING_AGENT=true` | Pi-specific marker. **Not set** when pi is embedded via SDK. |
| `PI_SESSION_ID`        | This session's UUID.                                         |
| `PI_SESSION_FILE`      | Absolute path to this session's JSONL transcript.            |
| `PI_PROVIDER`          | Currently selected provider (e.g. `zai`).                    |
| `PI_MODEL`             | Currently selected model ID.                                 |
| `PI_REASONING_LEVEL`   | Effective level: `off`…`max`.                                |

The big convenience vs Claude Code: **`PI_SESSION_FILE` hands you the
transcript path directly** — no slug derivation, no registry lookup. It is
unset for ephemeral sessions (`--no-session`).

Gotchas worth knowing before trusting a reading:

- Values are **resolved per command**. Switching models or thinking level
  changes what the _next_ shell command sees, without restarting pi. A
  mid-session `/model` switch is therefore visible in `env` and in the
  transcript's `model_change` entry, two independent witnesses.
- They are injected **only into the LLM-callable `bash`/`powershell` tools**.
  User-typed `!` and `!!` commands do not receive them.
- `PI_PROVIDER`/`PI_MODEL` name the selected pi model, not any upstream model
  a router may pick internally.

Process-configuration variables (read by pi itself, set by the user, not by
the session): `PI_CODING_AGENT_DIR` (default `~/.pi/agent`),
`PI_CODING_AGENT_SESSION_DIR`, `PI_PACKAGE_DIR`, `PI_OFFLINE`,
`PI_SKIP_VERSION_CHECK`, `PI_TELEMETRY`. If `~/.pi/agent` does not exist,
check `PI_CODING_AGENT_DIR` before concluding anything was deleted.

Absence, verified: **there is no `PI_PID` equivalent.** Find your process via
the table, not the environment.

## 2. The `~/.pi/agent/` tree

```text
~/.pi/agent/
  settings.json      global settings (all projects)
  auth.json          credentials, mode 0600 — note existence, never read
  models-store.json  custom model catalogs per provider, 0600
  skills/            user skills, one dir per skill with SKILL.md
  extensions/        user extensions (*.ts), auto-discovered at startup
  npm/               user-scoped installed pi packages
  sessions/          transcripts, one munged-cwd dir per project
```

Project-level counterparts (only loaded **after the project is trusted**):
`.pi/settings.json`, `.pi/skills/`, `.pi/npm/`, and `.agents/skills/` in cwd
and ancestor directories up to the git root. Trust decisions are saved in
`~/.pi/agent/trust.json` by `/trust`; non-interactive modes fall back to the
`defaultProjectTrust` setting.

Unlike Claude Code, storage is **configurable**, not positional: precedence
`--session-dir` > `PI_CODING_AGENT_SESSION_DIR` > `sessionDir` setting >
default. Check all four before declaring a session "missing".

### Transcripts

```text
~/.pi/agent/sessions/--<munged-cwd>/<start-timestamp>_<session-uuid>.jsonl
```

The munged cwd is the working directory with every `/` replaced by `-`
(`/workspace` → `--workspace--`). Same fragilities as Claude Code's slug: keys
on launch directory not git root, case-sensitive, worktrees split state. The
filename embeds both the start timestamp and the session UUID, and `--session`
/ `--resume` / `--fork` accept a **partial UUID**.

An agent can read its own transcript while the session runs — it is appended
in real time, so `$PI_SESSION_FILE` lags the current turn by seconds at most.
This remains the single most useful habit.

Record shape differs structurally from Claude Code. First line is a header;
everything after is a **tree** of entries linked by 8-char hex `id`/`parentId`
(null on the first), so branching happens in place rather than in new files:

```json
{"type":"session","version":3,"id":"<uuid>","timestamp":"…","cwd":"/workspace"}
{"type":"model_change","id":"62f610b7","parentId":null,…,"provider":"zai","modelId":"glm-5.3"}
{"type":"message","id":"a1b2c3d4","parentId":"62f610b7",…,"message":{"role":"user","content":"…"}}
```

Entry types (`type` field):

| `type`                  | Contents                                             |
| ----------------------- | ---------------------------------------------------- |
| `session`               | Header: version, id, cwd, optional `parentSession`   |
| `message`               | One conversation turn; role lives in `.message.role` |
| `model_change`          | Provider + modelId switch mid-session                |
| `thinking_level_change` | Reasoning level switch                               |
| `compaction`            | Summary checkpoint (see below)                       |
| `branch_summary`        | LLM summary of an abandoned branch                   |
| `custom`                | Extension state; **not** in LLM context              |
| `custom_message`        | Extension-injected context; **is** in LLM context    |
| `label`                 | User bookmark on an entry                            |
| `session_info`          | Display name (from `/name`)                          |

Message roles (`.message.role`): `user`, `assistant`, `toolResult`,
`bashExecution` (user `!`/`!!` commands; `excludeFromContext: true` marks the
`!!` form), `custom`, `branchSummary`, `compactionSummary`.

Assistant messages carry the audit trail Claude Code puts on the record
itself: `.message.provider`, `.model`, `.api` (wire API, e.g.
`openai-completions`), `.usage` with token counts **and cost**, `.stopReason`
(`error` turns carry `errorMessage`). Content blocks are `text`, `thinking`,
`toolCall`. `toolResult` messages carry `toolCallId`, `toolName`, `isError`.

Compaction entries hold `summary`, `tokensBefore`, and either `retainedTail`
(a self-contained message checkpoint — context rebuilds from it without older
entries) or legacy `firstKeptEntryId`. When profiling a long session, expect
pre-compaction entries to remain in the file even though they left the
context.

Profiling one-liners that have been run for real:

```sh
# what roles does this session contain
jq -r 'select(.type=="message") | .message.role' "$PI_SESSION_FILE" | sort | uniq -c

# what did the session actually do
jq -r 'select(.type=="message" and .message.role=="assistant")
       | .message.content[]? | select(.type=="toolCall") | .name' \
  "$PI_SESSION_FILE" | sort | uniq -c | sort -rn

# what did it cost
jq -s '[.[] | select(.type=="message" and .message.role=="assistant")
       | .message.usage.cost.total // 0] | add' "$PI_SESSION_FILE"

# identify a session in one line: first human prompt
jq -r 'select(.type=="message" and .message.role=="user")
       | .message.content | if type=="string" then . else empty end' \
  "$PI_SESSION_FILE" | head -1
```

There is no auto-generated title field; the harness equivalent is the
`session_info` name, present only if the user set one. Fallback: the filename
timestamp plus the first user prompt.

### No live-session registry

Verified absence (full `find` of `~/.pi`, plus a CLI help listing no such
subcommand): pi writes **no per-PID registry** of running sessions, unlike
Claude Code's `~/.claude/sessions/<pid>.json`. Consequences:

- "What else is running" is answered by the process table only:

  ```sh
  ps -eo pid,etime,command | grep -E '[p]i( |$)|pi-coding'
  ```

  Session arguments are visible in full, including `--session <uuid>`,
  `--fork`, `--mode rpc`.

- The tree also holds no prompt-history file. "When did I last ask about X"
  means grepping session JSONLs (`grep -l` over
  `~/.pi/agent/sessions/*/*.jsonl`), there is no `history.jsonl` equivalent.

### What this means for "can I see other agents"

Same three-part answer as Claude Code, with a weaker third part:

1. **No live channel.** Another session's in-memory context and current turn
   are unreachable.
2. **Transcripts are readable and near-live.** Any session's JSONL is
   appended as it works; reading it gives prompts, tool calls, results and
   reasoning, seconds behind. Other projects' sessions sit in sibling
   munged-cwd directories.
3. **Existence is visible only via `ps`.** No registry exposes names or
   uptimes; the process table plus file mtimes are the whole surface.

## Skills, extensions, packages

Skills resolve, in order, from: `~/.pi/agent/skills/` and `~/.agents/skills/`
(global); `.pi/skills/` and trusted project `.agents/skills/` (project);
package `skills/` dirs; the settings `skills` array; `--skill` paths.
Name collisions warn and keep the first found. Each skill is a directory with
a `SKILL.md` whose frontmatter `name` and `description` are loaded at startup;
the body loads only on invocation — read the file directly to inspect a skill
without triggering it. Skills also register as `/skill:name` commands.

The skill directory is otherwise freeform; `references/` and `scripts/`
subdirectories (as in this skill) are convention, not harness-enforced.

Extensions are TypeScript files auto-discovered from
`~/.pi/agent/extensions/` (disable with `--no-extensions`; explicit `-e`
paths survive that flag). Extension state persists across restarts as `custom`
entries keyed by `customType`. Packages (settings `packages` array) install
user-scoped under `~/.pi/agent/npm/`, project-scoped under `.pi/npm/`.

## Settings

Two files, project overriding global, nested objects merged:
`~/.pi/agent/settings.json` and `.pi/settings.json`. Useful keys for
introspection: `defaultProvider`/`defaultModel`/`defaultThinkingLevel`,
`packages`, `extensions`, `skills`, `prompts`, `themes`, `sessionDir`,
`defaultTools`, `compaction.*`, `enableSkillCommands`.

Context files: pi discovers `AGENTS.md` and `CLAUDE.md` (cwd and ancestors;
`--no-context-files` disables). Their presence in your system prompt is the
loaded-context witness; the files on disk are the storage witness.

## 3. The `pi` CLI

`pi --help` is the authoritative capability list for the installed build.
Subcommands: `install`, `remove`/`uninstall`, `update`, `list`, `config`,
`auth`. Introspection-adjacent flags: `--list-models [search]`,
`--export <file>` (HTML transcript export), `--session <path|partial-uuid>`,
`--fork`, `--session-id`, `--no-session`, `--verbose`.

Version needs two witnesses as always: `pi --version` reports whatever is
first on `PATH`; corroborate with `readlink -f "$(which pi)"` and the
`version` field in the package's `package.json`. All three agreed on 0.85.1
here; treat disagreement as a wrapper lagging the real binary.

Credentials: `pi auth print-api-key` and `pi auth print-bearer-token` exist to
feed external clients. **Never invoke them where the output would land in a
transcript** — which, from inside a session, is everywhere. `auth.json` is
0600 for the owning user; note its existence and move on.

## 4. The prompt itself

Already paid for, but incomplete in the usual way: it lists tools and skills
by name and one-line description. In pi there are no deferred tool schemas
visible from inside, but the roster still understates capability when
extensions register tools — cross-check `pi list` (installed extensions from
settings) and `ls ~/.pi/agent/extensions/`. The docs directory named above is
the authority for what each surface means.

## Known limits

- No cross-session messaging of any kind; no registry even implying a
  transport.
- No `PI_PID`; process discovery is `ps` only.
- No prompt-history file; grep the session JSONLs instead.
- `$PI_SESSION_FILE` unset for ephemeral sessions — absence of the variable
  is a finding about the session, not an error.
- Extension tools and project-trust gating mean a roster read in one session
  does not describe another (non-interactive modes may have skipped
  project-local resources pending `defaultProjectTrust`).
- Everything here is version-stamped 0.85.1; `pi update` can invalidate it.

## Quick reference

```sh
# who am I
echo "${PI_SESSION_ID} ${PI_PROVIDER}/${PI_MODEL} ${PI_REASONING_LEVEL}"

# my own transcript (this session, live)
wc -l "$PI_SESSION_FILE"
jq -r 'select(.type=="message") | .message.role' "$PI_SESSION_FILE" | sort | uniq -c

# what did this session do
jq -r 'select(.type=="message" and .message.role=="assistant")
       | .message.content[]? | select(.type=="toolCall") | .name' \
  "$PI_SESSION_FILE" | sort | uniq -c | sort -rn

# what else is running
ps -eo pid,etime,command | grep -E '[p]i( |$)|pi-coding'

# sessions for this project (any time, any session)
ls ~/.pi/agent/sessions/--*--*/ 2>/dev/null
ls "$(echo "$PWD" | sed 's|/|-|g')" ~/.pi/agent/sessions/ 2>/dev/null

# what this build can do
pi --help
```
