# tk reference

## create flags

```txt
-d, --description   Body text under the title
    --design        Body section "## Design"
    --acceptance    Body section "## Acceptance Criteria"
-t, --type          bug | feature | task | epic | chore   (default task)
-p, --priority      0-4, 0 = highest                      (default 2)
-a, --assignee      Assignee                              (default: git user.name)
    --external-ref  External reference, e.g. gh-123, JIRA-456
    --parent        Parent ticket ID (epic hierarchy)
    --tags          Comma-separated, e.g. --tags ui,backend
```

## Ticket file

`.tickets/<id>.md`:

```markdown
---
id: tkd-harq
status: open
deps: [tkd-ptdp]
links: []
created: 2026-08-06T03:02:45Z
type: bug
priority: 0
assignee: Andre Silva
tags: [ui, api]
external-ref: gh-12
parent: tkd-erlt
---

# Second

## Design

...

## Acceptance Criteria

...

## Notes

**2026-08-06T03:02:53Z**

did a thing
```

`id`, `status`, `deps`, `links`, `created`, `type`, `priority` are always present.
`assignee`, `tags`, `external-ref`, `parent` appear only when set. `deps` is the
blocking relation and is one-directional (`tk dep <id> <dep-id>` means `<id>`
depends on `<dep-id>`); `links` does not block. Both arrays must stay on one
line as an inline flow list, per **Store integrity** in `SKILL.md`.

`tk link` writes a link entry on both sides, but nothing enforces that on read:
a hand-edited `links:` can name a ticket that does not name it back, and `tk`
reports no error. One real ledger carried 43 such one-sided entries across 23
tickets. `uv run scripts/tk_export.py --audit` lists them.

## Output formats

`ls` and `closed` print status only, with blockers appended when present:

```txt
tkd-harq [open] - Second <- [tkd-ptdp]
```

`ready` and `blocked` include priority and sort by it:

```txt
tkd-harq [P0][in_progress] - Second
```

`show` prints the raw frontmatter and body, then appends a `## Blockers` section
(each dep with its status and title) and a `## Children` section (tickets whose
`parent` is this ID). Neither is stored in the file.

`dep tree` walks blockers (what `<id>` waits on), so a chain is visible in
full only from its final ticket; asked from the first, the tree is one node.

```txt
tkd-harq [open] Second
└── tkd-ptdp [open] Child
```

## query recipes

`tk query` emits one JSON object per ticket, one per line. The optional filter
is a **row predicate only**: a ticket whose filter result is truthy prints in
full, and one that is falsy or `empty` is dropped. The filter cannot project or
reshape, so `select(...) | .id` and `{id, status}` return the same complete
objects as no filter at all, and a bare `.id` matches every ticket because a
non-empty string is truthy. To change the shape, pipe to your own jq.

```sh
tk query 'select(.status != "closed")'
tk query 'select(.priority == "0")'
tk query 'select(.tags != null and (.tags | index("ui")))'
tk query 'select(.parent == "tkd-erlt")'
tk query 'select(.parent == "tkd-erlt")' | jq -r '.id'      # projection goes here
tk query | jq -s 'group_by(.status) | map({status: .[0].status, n: length})'
tk query | jq -s 'sort_by(.priority) | .[0]'
```

Titles live in the markdown body, not the JSON, so pull them from `ls` output or
the files themselves.

## Filters and environment

- `-a <assignee>` and `-T <tag>` on `ls`, `ready`, `blocked`, `closed` match
  exactly; quote assignees containing spaces.
- `--status=<open|in_progress|closed>` on `ls` only.
- `TICKETS_DIR` overrides the parent-directory search and is used verbatim,
  including for `create` (the ID prefix still comes from the cwd basename).
