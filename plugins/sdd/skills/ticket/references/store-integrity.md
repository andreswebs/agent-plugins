# Store integrity: failure taxonomy and repair

`SKILL.md` carries the invariants. This file is for diagnosing a store that is
already damaged, and for repairing it.

Every fault here is an instance of `tk` failing open: the file still reads
correctly to a human, and nothing in the exit status says otherwise.

## What each kind of damage does

| Damage | `ls` | `ready` / `blocked` | `query` | `show` |
| ------ | ---- | ------------------- | ------- | ------ |
| `deps:` reflowed onto several lines | listed, no blockers | moves to `ready` | key becomes literal `"deps:"`, value empty | prints |
| `---` line in the body | listed | normal | invalid JSON from that row on | prints |
| opening `---` mangled | gone | gone | gone | prints |
| `id:` missing | gone | gone | gone | prints |
| `id:` disagreeing with the filename | gone | gone | gone | prints |
| `status:` outside the three valid values | listed | in neither | present | prints |
| closing `---` mangled | listed | normal | present | prints |
| non-numeric `priority`, missing title | listed | normal | present | prints |

Two consequences worth holding on to:

- **`tk show <id>` proves nothing.** It resolves a ticket by filename and prints
  it in every row above, including the three where the ticket has vanished from
  every queue. Probing a suspect ticket by ID reports it healthy.
- **The bottom three rows are tolerated.** The fragility is concentrated in the
  opening delimiter, the `id:` field, and the two arrays.

## Why a formatter destroys the graph

`tk` parses `deps:` and `links:` only as a single-line inline flow list. Prettier
rewraps any list past the print width, and long lines are normal here: twenty
dependencies run past 200 characters. After `prettier --write`, `tk dep tree`
returns a bare node and the ticket moves from `blocked` into `ready`, so a
cutover ticket presents itself as actionable with all of its prerequisites
unfinished.

A YAML block sequence fails the same way. `markdownlint-cli2 --fix` is safe: it
fixes the `MD012` two blank lines `tk create` emits and leaves the arrays alone.

`prettier --check .tickets/<id>.md` on an ignored path prints
`All matched files use Prettier code style!` and exits 0, because zero files
matched. Nothing in that output says the path was skipped.

## Detecting damage

The two faults need two different checks; neither finds the other's.

```sh
tk query 'select(has("deps:"))'      # names tickets whose deps: has been reflowed
tk query 'select(.id)' >/dev/null    # non-zero when any ticket serializes to invalid JSON
```

Both need a filter. A bare `tk query` exits 0 either way.

The second check reports the *first* bad row only, and a filtered query stops
there, so re-run it after each repair until it comes back clean rather than
assuming one pass found everything.

For a full census, including the stray keys a body `---` injects:

```sh
tk query | python3 -c '
import sys, json
KNOWN = {"id","status","deps","links","created","type","priority",
         "assignee","tags","external-ref","parent","closed","updated"}
for i, line in enumerate(sys.stdin, 1):
    try:
        o = json.loads(line)
    except Exception:
        print(f"line {i}: invalid JSON"); continue
    stray = [k for k in o if k not in KNOWN]
    if stray:
        tid = o.get("id")
        print(f"{tid}: stray keys {stray[:2]}")
'
```

## Repairing

Copy `.tickets/` aside first. The ledger is git-excluded, so this backup is the
only way back.

**A reflowed array.** Collect the IDs and write them back on one line. Confirm
each target exists before restoring an edge to it, then check `tk dep tree <id>`
and that the ticket is in `tk blocked` again.

**A body `---`.** Replace with `***`. Two checks before doing it in bulk:

- Is it a thematic break or a setext heading underline? A `---` with non-blank
  text immediately above underlines that text into an `<h2>`, and swapping it
  changes the rendering. A true break has a blank line on both sides.
- Is it inside a fenced code block? Count ```` ``` ```` fences before the line;
  an odd number means it is inside one, where the text is content and must not
  be touched.

**A vanished ticket.** Restore the opening `---`, or make `id:` match the
filename. It returns to the queues immediately; `tk` holds no index.

After any repair, confirm the store still lists what it should:
`tk ls | wc -l` against the file count, and both detectors clean.
