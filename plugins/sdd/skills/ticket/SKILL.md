---
name: ticket
description: Track work with the `tk` ticket CLI, which keeps markdown tickets in `.tickets/` with dependencies, a ready queue, and JSON output. Use when filing, updating, or closing local tickets or issues, when a plan spans sessions or has blocking order worth recording, when asked what is ready or blocked, when looking up `tk` commands, flags, or the ticket file format, or when a formatter or lint gate could reach `.tickets/`.
---

# tk (ticket)

`tk` is a ticket tracker with no database: each ticket is a markdown file with
YAML frontmatter under `.tickets/`, so `grep`, `git`, and the Read/Edit tools all
work on it directly. Read commands search the cwd and its parents for
`.tickets/`; `TICKETS_DIR` overrides that search.

The **ready queue** is the whole point of the tool. A ticket is _ready_ when every
ticket it depends on is closed, so recording dependencies once turns "what do I do
next" into `tk ready` for the rest of the session.

**`tk` fails open.** Given input it cannot parse it does the plausible thing and
reports success, so the exit status rarely carries the error: mangled text gets
stored, a dropped dependency reads as no dependency, a filter that shapes nothing
returns everything. Confirm a write by reading it back, not by seeing the command
succeed. The gotchas below are each one instance of this.

Verified against tk 0.3.2 (`brew` package `ticket`, single binary `tk`).

## Working a plan through tk

1. **Locate the ledger.** Run `tk ls` from the project root. On
   `Error: no .tickets directory found`, the project has none yet; the first
   `tk create` makes one. In an existing ledger, read one or two recent tickets
   end to end: their sections, tags, priority scale, and language are the house
   conventions to match. Done when you know the `.tickets/` path in use, the
   existing ticket IDs, and the conventions your tickets will follow, so you
   extend the ledger instead of duplicating it.
2. **File the work.** One ticket per independently closable unit, with
   `-t`/`-p`/`--tags` set at creation and `--parent` for units under an epic.
   `create` prints only the new ID, so capture it: `ID=$(tk create 'Title' -p 1)`.
   `-d` holds a flat paragraph. For anything longer, create with title and flags
   and then write the body into `.tickets/<id>.md` with a file-write tool, since
   `tk edit` blocks on `$EDITOR` and there is no other non-interactive way to set
   one. `tk` reads whatever is on disk, so hand-written `deps:` and `links:`
   count as real (`tk dep` on one answers `Dependency already exists`), subject
   to **Store integrity** below. (Cutting a plan into self-contained tickets is
   the `plan-to-tickets` skill's subject; this step is the mechanics.)
   Record each ordering constraint with `tk dep <blocked-id> <blocker-id>`. Done
   when every unit of the plan has an ID and every "X before Y" in the plan is a
   `dep` edge; check with `tk blocked` and `tk dep tree <id>`.
3. **Work the ready queue.** Take the top actionable ticket from `tk ready`,
   skipping epics (an epic has no deps of its own, so it sits in the queue the
   whole run and closes when its children are done), `tk start <id>`, and
   `tk add-note <id>` as findings, decisions, or dead ends land, since the note trail
   is what survives into the next session. Close with `tk close <id>`. Done when
   the ticket you worked no longer appears in `tk ready` and every fact a future
   session would need is in a note, not only in this conversation.
4. **Report status from the tool.** `tk ready`, `tk blocked`, `tk closed`, or
   `tk query <filter>` for anything structured. A filtered `query` stops at the
   first malformed ticket and returns only the rows sorting before it, so a short
   list is indistinguishable from a complete one until you look at the exit
   status. Done when what you tell the user matches command output you just ran,
   and that command exited 0.

## Commands

| Command                                                    | Notes                                                      |
| ---------------------------------------------------------- | ---------------------------------------------------------- |
| `tk create [title] [opts]`                                 | Prints the new ID on stdout                                |
| `tk show <id>`                                             | Frontmatter, body, blockers, children                      |
| `tk start\|close\|reopen <id>`                             | Shorthand for the three statuses                           |
| `tk status <id> <open\|in_progress\|closed>`               | Rejects any other value                                    |
| `tk add-note <id> [text]`                                  | Appends a timestamped note; reads stdin if text is omitted |
| `tk dep <id> <dep-id>`                                     | `<id>` depends on `<dep-id>`                               |
| `tk undep <id> <dep-id>`                                   | Removes one edge                                           |
| `tk dep tree [--full] <id>`                                | `--full` disables dedup of repeated subtrees               |
| `tk dep cycle`                                             | Cycles among open tickets                                  |
| `tk link <id> <id> [id...]` / `tk unlink <id> <target-id>` | Symmetric, non-blocking; links **every pair**, not a star   |
| `tk ls [--status=X] [-a X] [-T X]`                         | All tickets; `list` is an alias                            |
| `tk ready [-a X] [-T X]`                                   | Open/in_progress with all deps closed                      |
| `tk blocked [-a X] [-T X]`                                 | Open/in_progress with unresolved deps                      |
| `tk closed [--limit=N] [-a X] [-T X]`                      | Most recent by mtime, default 20                           |
| `tk query [filter]`                                        | One JSON object per line; the filter selects rows only     |
| `tk migrate-beads`                                         | Imports `.beads/issues.jsonl`                              |

Partial IDs work everywhere an ID is taken: `tk show b1kh` resolves `tkd-b1kh`.

Full create flags, frontmatter fields, output formats, and `query` recipes:
[references/reference.md](references/reference.md).

Titles live in the body, not in `query` output, so no single `tk` command yields
title plus fields. For reporting, export or migration, use the bundled
extractor, which reads the files and emits complete rows:

```sh
uv run scripts/tk_export.py --format tsv    # id, status, type, priority, title
uv run scripts/tk_export.py                 # every field, as JSON
```

## Store integrity

The on-disk format is narrower than YAML, and violating it costs dependencies or
whole tickets without a word of complaint.

- **`deps:` and `links:` parse only as a single-line inline flow list.**
  `deps: [a, b]` works; a block sequence and a wrapped multi-line flow list both
  read as _no dependencies_.
- **Keep `.tickets/` out of every formatter and lint gate** — `.prettierignore`,
  editor format-on-save, and CI. Prettier rewrapping a long `deps:` line is the
  known way this graph gets destroyed.
- **Write a thematic break as `***`.** A `---` line in a body restarts
  frontmatter parsing, which corrupts that ticket's JSON. `___` and `- - -` are
  equally safe.
- **The opening `---` and the `id:` field are a ticket's visibility.** Damage
  either, or let `id:` disagree with the filename, and the ticket leaves `ls`,
  `ready`, `blocked` and `query` while `tk show <id>` still prints it, so
  probing by ID says the ticket is fine.
- **A frontmatter value is a literal string, comments included.** Write
  `parent: lt-f3ad # Phase 5` and the value _is_ `lt-f3ad # Phase 5`, which
  matches no ticket: the child disappears from its parent's `## Children` and
  from any grouping built on `parent`. One real ledger had 13 tickets orphaned
  from an epic this way, listing 2 children instead of 15. Keep values bare, and
  put the reminder in the body where it belongs.
- **Write to one ticket serially.** `tk dep` rewrites the whole file with no
  locking, so concurrent `tk dep` calls against the same `<id>` are
  last-writer-wins: twelve parallel calls keep **one** edge, while all twelve
  print `Added dependency`. Batching independent tool calls is the default habit
  and it silently destroys the graph here. Edges on _different_ tickets run in
  parallel safely, and `add-note` survives concurrent writers.
- **Sweep the store before trusting a read, and after any edit that touched
  frontmatter.** Two checks, because the two faults look nothing alike:
  `tk query 'select(has("deps:"))'` names every ticket whose `deps:` has been
  reflowed, and `tk query 'select(.id)' >/dev/null` exits non-zero when any
  ticket serializes to invalid JSON. Neither finds the other's fault. Reporting
  on a store you have not swept is the risk this pair exists for, since a
  truncated `query` under-reports without saying so. For a single ticket,
  `tk ls | grep <id>` confirms it is still listed and shows its inline
  `<- [ids]` blockers. Neither sweep sees a reference that parses cleanly and
  points nowhere; `uv run scripts/tk_export.py --audit` catches those, printing
  one `id<TAB>fault` line each and exiting 0 when clean, 1 when it finds any.

The ledger is conventionally git-excluded, so `git status` stays clean whatever
you do to it and there is no `git checkout` to undo a bad edit: copy `.tickets/`
aside before any multi-file change. Damage is repairable in place. The failure
taxonomy, the detectors, and the repair procedure:
[references/store-integrity.md](references/store-integrity.md).

## Gotchas

- **The ID prefix comes from the cwd basename, not the project.** Running
  `tk create` from `sub/deep/` writes into the project's `.tickets/` with a
  `dee-` prefix. Create from the project root so prefixes stay uniform.
- **`start` ignores dependencies.** Starting a blocked ticket succeeds;
  `tk blocked` is advisory, so check it rather than expecting a refusal.
- **`dep cycle` exits 0 even when it finds cycles.** Read its output; the exit
  code says nothing.
- **`tk create` with no title writes `# Untitled`.** Pass a title.
- **`ls --status` needs the `=` form.** `--status open` is ignored and returns
  every ticket; an unknown value (`--status=bogus`) returns nothing. Use
  `--status=open|in_progress|closed` and treat an empty result as a possible
  typo.
- **`query`'s filter selects rows; it cannot shape them.** Every match prints
  whole, so `select(...) | .id` and `{id, status}` return the same full objects
  as no projection at all, and a bare `.id` matches every ticket because it is
  merely truthy. Project with your own jq downstream: `tk query | jq -r '.id'`.
  Output is JSONL, not an array, so `jq -s` first when you need array semantics.
  `priority` is a JSON string.
- **Single-quote every `tk` text argument, or pass it on stdin.** This is the
  shell, not `tk`: inside double quotes it expands `` `x` ``, `$(x)` and `$VAR`
  before `tk` sees the string, so backticked symbols vanish from mid-sentence
  and the mangled text is what gets stored. Ticket prose backticks every symbol,
  which makes this the common case, and nothing points at the cause unless you
  read the text back. `tk` itself preserves backticks under single quotes,
  escaped double quotes, and stdin alike. For a note, prefer a **quoted**
  heredoc: `tk add-note <id> <<'EOF'`.
- **`tk link a b c` links every pair, not a star.** To attach one ticket to
  several without cross-linking those to each other, issue one `tk link` per
  pair. The reported count is link entries written, one per side (three tickets,
  fully unlinked, report 6), so it cannot be compared against the argument count;
  a surprising number is not an error. Re-linking is idempotent.
- **Unknown and ambiguous IDs both exit 1**, as does an unknown subcommand; bare
  `tk` prints help and exits 0.
