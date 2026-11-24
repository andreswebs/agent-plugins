# Hermes self-introspection

What an agent running inside Hermes can learn about its own harness, by
looking rather than by recalling. Every claim below was verified against a
live deployment; the method used to verify each finding is given alongside it,
so it can be re-run rather than trusted.

Read this before spending tokens rediscovering the same surfaces.

## The one-pass probe

[scripts/snapshot-env.bash](../scripts/snapshot-env.bash) prints, read-only
and in one pass: resolved paths, the interpreters, the distro, the Hermes
build, the tooling matrix, database sizes, the config's top-level keys (names
only, never values), the secret names in `.env`, the skill and plugin
inventories, cron jobs, and the git boundary of the home directory. Every
probe is guarded — a missing tool or path prints `-` and the run continues —
so the same script works on any install, and its absences are findings too.

```sh
bash scripts/snapshot-env.bash
```

Run it before answering anything about the deployment, and take every concrete
value from its output. This document records the _shape_ of the environment,
not its current facts.

## Surfaces

| Surface                          | What it answers                                | Cost         |
| -------------------------------- | ---------------------------------------------- | ------------ |
| `HERMES_*` environment variables | Which home, which interpreters, which build    | Free         |
| `${HERMES_HOME}` on disk         | History, memory, config, skills, plugins, cron | Cheap        |
| The `hermes` CLI                 | What this build can do                         | Cheap        |
| The loaded context               | Tool, skill, plugin rosters                    | Already paid |

## Self-location

```sh
env | grep -E '^HERMES_'
```

- **`HERMES_HOME`** — the home directory, default `~/.hermes`. Containerized
  and managed deployments relocate it, and profile installs use
  `~/.hermes/profiles/<name>/`. Never assume the default; read the variable.
- **`HERMES_PYTHON` / `HERMES_NODE`** — the interpreters the harness itself
  runs on. The `python3` first on `PATH` is frequently a _different_
  interpreter (a venv, a system Python), so a `pip show` or an `import` there
  says nothing about what the runtime can import. Check packages in
  `$HERMES_PYTHON`, not in the shell's python.
- **`HERMES_REVISION`** — the git commit of the running build.
- **`HERMES_BUNDLED_SKILLS` / `HERMES_BUNDLED_PLUGINS`** — read-only
  directories holding the shipped defaults. Local skills and plugins under
  `${HERMES_HOME}` override or add to them.

Any module's live source resolves from the runtime interpreter, which beats
remembering a store or site-packages path, because those pin hashes and
versions that rot on the next update:

```sh
"$HERMES_PYTHON" -c 'import agent.skill_utils as m; print(m.__file__)'
```

On Nix-managed installs the site-packages directory is a symlink farm — each
package symlinks into its own store path — and `grep -r` does not follow
symlinks during traversal. Grep the real path an entry points at, or the grep
returns empty and reads as "the code never mentions X".

## Storage map

What lives in `${HERMES_HOME}`:

| Path                                                   | What it is                                                         |
| ------------------------------------------------------ | ------------------------------------------------------------------ |
| `config.yaml`                                          | Live config: model, memory provider, plugins, stt/tts              |
| `.env`                                                 | Secrets. Introspection stops at the _names_                        |
| `SOUL.md`                                              | Agent identity                                                     |
| `AGENTS.md` / `CLAUDE.md`                              | Instructions for editing the home, when it is a git working tree   |
| `memories/MEMORY.md`, `memories/USER.md`               | Agent notes and user profile — injected into every session         |
| `skills/<category>/<name>/SKILL.md`                    | Skill library, with `references/`, `templates/`, `scripts/` beside |
| `state.db`                                             | Sessions and messages (SQLite + FTS5)                              |
| `plugins/`                                             | Installed plugins — real directories, or symlinks into the store   |
| `cron/jobs.json`, `cron/executions.db`, `cron/output/` | Scheduled jobs, run history, delivered output                      |
| `logs/`, `sessions/`, `cache/`                         | Runtime artifacts                                                  |

Plugin-owned databases appear as plugins are installed (a memory provider's
fact store, a kanban board's tasks, a feed reader's feeds). `ls *.db` is the
live list; treat their schemas as plugin-private and unstable unless the
plugin documents them.

## Memory architecture

| Layer        | Path                 | Scope                      | Injected       |
| ------------ | -------------------- | -------------------------- | -------------- |
| Agent notes  | `memories/MEMORY.md` | Durable facts, environment | Every session  |
| User profile | `memories/USER.md`   | Who the user is            | Every session  |
| Skills       | `skills/*/SKILL.md`  | Procedural knowledge       | On demand      |
| Session DB   | `state.db`           | Full conversation history  | On demand      |
| Cron         | `cron/jobs.json`     | Scheduled work             | Scheduler only |

What persists is what was written to one of these. In-context reasoning, tool
results, and working notes not explicitly saved are gone when the session
ends.

## state.db — sessions, and cost

The `sessions` table carries one row per session, with token and cost columns:
`input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`,
`reasoning_tokens`, `estimated_cost_usd`, `actual_cost_usd`, `cost_status`,
`model`.

Two schema facts that pattern-matching gets wrong:

- Timestamps live in `started_at` (REAL, Unix epoch). There is no `created_at`
  column; the name pattern-matching supplies is the one that errors. Convert
  with `datetime(started_at,'unixepoch')`.
- Read `.schema <table>` before writing a query; column sets drift per
  version.

**`estimated_cost_usd` is the harness's own estimate** — token counts times
an internal price table — and `actual_cost_usd` is empty unless billing was
reconciled, which is rare. Report cost as an estimate, never as "the spend",
and re-run the query in the turn that quotes it: a stale sum recited from an
earlier answer is how wrong figures enter memory.

```sql
SELECT source, COUNT(*), SUM(input_tokens), SUM(output_tokens),
       ROUND(SUM(estimated_cost_usd),2)
FROM sessions GROUP BY source;
```

## Skill catalog mechanics

Verified against `agent/skill_utils.py` and `agent/prompt_builder.py`,
resolved from the running interpreter:

- **Discovery** is `os.walk` over the skills directory, any depth. The
  category layer is organization, not structure.
- **Identity** is the frontmatter `name:` field; the parent directory is only
  a fallback. Loading and `skill_view` resolve by name, never by path, so
  moving a skill never breaks cross-references by name.
- **Grouping** in the roster shown each turn is **path-derived only**: the
  category is computed from the directory path. A `category:` frontmatter
  field and `tags` are inert for grouping — there is no frontmatter-only way
  to regroup a catalog.
- A `DESCRIPTION.md` in a category directory sets that category's header
  description, keyed by path — renaming a category orphans its description
  unless it moves with the directory.
- The roster is cached in `.skills_prompt_snapshot.json`, validated against
  file mtimes and sizes, so it self-invalidates after moves and edits; delete
  it to force a cold re-scan.

Flatten arithmetic worth knowing before reorganizing: at
`skills/<category>/<name>/SKILL.md` the category is `<category>`; at
`skills/<name>/SKILL.md` every skill becomes its own singleton group — noisier
than the nested layout, not cleaner. One clean category layer is the stable
shape.

## Cron

`cron/jobs.json` holds the jobs; the cron listing tool reads them. Each job
may carry a pre-run script, and two modes matter:

- **Wake gate.** The scheduler checks the last non-empty stdout line of the
  pre-run script; `{"wakeAgent": false}` makes the scheduler skip the agent
  and any delivery entirely — no tokens, no message — while the script still
  runs. Any other output wakes the agent normally. This turns any scheduled
  job into a trigger-based one.
- **`no_agent`.** The script _is_ the job; the agent never runs. A different
  thing from the wake gate.

**Silent deliveries on Telegram.** Cron output that delivers to Telegram
lands in the chat but raises no push notification. The adapter's notification
mode defaults to "important", which sets `disable_notification` on every send
unless the caller passes an explicit notify flag — and the cron scheduler
never passes one. The user sees the message only by scrolling. The fix is a
config key (`display.platforms.telegram.notifications: all`) or a targeted
source patch; there is no per-job setting. Diagnostic: the agent log shows a
`delivered to telegram:<chat_id> via live adapter` line at the delivery
timestamp — the send succeeded, silently.

## Reading the harness's own source

Bundled plugins are readable under `$HERMES_BUNDLED_PLUGINS`; installed ones
under `${HERMES_HOME}/plugins` (a symlink resolves to its real path). Core,
non-plugin source — the conversation loop, the skill loader, the prompt
builder — is under neither; resolve it from the interpreter as above.

The method that keeps this honest: find the function that performs the
operation, trace what it reads versus writes, find every consumer of the data
to be mutated, and read the `def` line before calling anything — validators
return shapes (`str | None` for valid, not a bool) that break unpacking
assumptions carried over from other codebases.

## Known limits

- Other sessions' in-memory context is unreachable; their rows in `state.db`
  lag by the session flush interval. The session search tool is the intended
  interface; raw SQL is for what it cannot express.
- `state.db` schemas drift between versions; `.schema` before querying.
- Plugin-owned databases are plugin-private surface; prefer the plugin's own
  tools over its tables.
- Gate flags differ per build and version: a subcommand that exists in one
  install may be env-gated off in another. Verify against the running build,
  never against another install's memory.
