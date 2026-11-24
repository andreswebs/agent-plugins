#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Export a tk ledger with titles, or audit its referential integrity.

`tk query` omits titles, so no single tk command yields title plus fields. This
reads `.tickets/*.md` directly and emits complete rows, which is what reporting,
export and migration tasks need.

    uv run tk_export.py                    # JSON array to stdout
    uv run tk_export.py --format tsv       # id, status, type, priority, title
    uv run tk_export.py --audit            # referential faults only
    uv run tk_export.py --dir path/to/.tickets

Audit reports what the two tk sweeps in SKILL.md cannot see: references that
parse cleanly but point nowhere. It exits 1 when it finds any, 0 when clean.

Rows are ordered by filename and every list is sorted, so output is stable
across runs.
"""

from __future__ import annotations

import argparse
import json
import re
import signal
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# Output is meant to be piped into head, jq or grep; die quietly when they close.
if hasattr(signal, "SIGPIPE"):
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

FRONTMATTER_KEY = re.compile(r"^([\w-]+):\s*(.*)$")
NOTE_STAMP = re.compile(r"^\*\*\d{4}-\d{2}-\d{2}T")
TICKET_REF = re.compile(r"\b[a-z0-9]{2,4}-[a-z0-9]{4}\b")
DELIMITER = "---"

# Frontmatter keys tk writes as inline flow lists; everything else is a scalar.
LIST_KEYS = ("deps", "links", "tags")


@dataclass
class Ticket:
    """One ticket file, parsed. `file_id` is the filename, always present."""

    file_id: str
    faults: list[str] = field(default_factory=list[str])
    id: str = ""
    status: str = ""
    type: str = ""
    priority: str = ""
    assignee: str = ""
    parent: str = ""
    created: str = ""
    external_ref: str = ""
    deps: list[str] = field(default_factory=list[str])
    links: list[str] = field(default_factory=list[str])
    tags: list[str] = field(default_factory=list[str])
    title: str | None = None
    note_count: int = 0
    desc_chars: int = 0
    body_refs: list[str] = field(default_factory=list[str])

    def as_dict(self) -> dict[str, Any]:
        """Flat JSON row. `external_ref` is emitted under tk's own spelling."""
        out: dict[str, Any] = {
            "file_id": self.file_id,
            "faults": self.faults,
            "id": self.id,
            "status": self.status,
            "type": self.type,
            "priority": self.priority,
            "assignee": self.assignee,
            "parent": self.parent,
            "created": self.created,
            "external-ref": self.external_ref,
            "deps": self.deps,
            "links": self.links,
            "tags": self.tags,
            "title": self.title,
            "note_count": self.note_count,
            "desc_chars": self.desc_chars,
            "body_refs": self.body_refs,
        }
        return out


def split_flow_list(value: str) -> list[str]:
    """Parse tk's `[a, b]` inline flow list. Any other form yields no entries."""
    if not (value.startswith("[") and value.endswith("]")):
        return []
    return [x.strip() for x in value[1:-1].split(",") if x.strip()]


def parse(path: Path) -> Ticket:
    """Parse one ticket file. Structural damage is recorded, never raised."""
    lines = path.read_text(encoding="utf-8").split("\n")
    row = Ticket(file_id=path.stem)

    if not lines or lines[0] != DELIMITER:
        row.faults.append("no opening delimiter: invisible to ls/ready/query")
        return row
    close = next((i for i, line in enumerate(lines[1:], 1) if line == DELIMITER), None)
    if close is None:
        row.faults.append("no closing delimiter")
        return row

    for line in lines[1:close]:
        matched = FRONTMATTER_KEY.match(line)
        if not matched:
            continue
        key, value = matched.group(1), matched.group(2).strip()
        if key in LIST_KEYS:
            setattr(row, key, split_flow_list(value))
        elif key == "external-ref":
            row.external_ref = value
        elif key in {"id", "status", "type", "priority", "assignee", "parent", "created"}:
            setattr(row, key, value)

    body = lines[close + 1 :]
    text = "\n".join(body)
    row.title = next((l[2:].strip() for l in body if l.startswith("# ")), None)
    notes_at = next((i for i, line in enumerate(body) if line.strip() == "## Notes"), len(body))
    row.note_count = sum(1 for line in body if NOTE_STAMP.match(line))
    row.desc_chars = len("\n".join(body[:notes_at]).strip())
    row.body_refs = sorted(set(TICKET_REF.findall(text)))
    return row


def audit(rows: list[Ticket]) -> list[tuple[str, str]]:
    """Referential faults, as (ticket id, message). Empty means clean."""
    by_id = {r.file_id: r for r in rows}
    faults: list[tuple[str, str]] = []
    for row in rows:
        tid = row.file_id
        faults.extend((tid, f) for f in row.faults)
        if row.id and row.id != tid:
            faults.append((tid, f"id: {row.id!r} disagrees with the filename"))
        if row.title is None:
            faults.append((tid, "no '# ' title heading in the body"))
        if row.parent and row.parent not in by_id:
            bare = row.parent.split("#")[0].strip()
            hint = f"; bare value {bare!r} exists" if bare in by_id else ""
            faults.append((tid, f"parent {row.parent!r} matches no ticket{hint}"))
        for label, refs in (("deps", row.deps), ("links", row.links)):
            faults.extend(
                (tid, f"{label} entry {ref!r} matches no ticket")
                for ref in refs
                if ref not in by_id
            )
        faults.extend(
            (tid, f"link to {ref} is one-sided")
            for ref in row.links
            if ref in by_id and tid not in by_id[ref].links
        )
    return faults


def resolve_body_refs(rows: list[Ticket]) -> None:
    """Keep only body references that name a real ticket, and never self-refs."""
    known = {r.file_id for r in rows}
    for row in rows:
        row.body_refs = [r for r in row.body_refs if r in known and r != row.file_id]


def emit_tsv(rows: list[Ticket]) -> None:
    print("id\tstatus\ttype\tpriority\ttitle")
    for row in rows:
        print("\t".join([row.file_id, row.status, row.type, row.priority, row.title or ""]))


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--dir", default=".tickets", help="ledger directory")
    parser.add_argument("--format", choices=("json", "tsv"), default="json")
    parser.add_argument("--audit", action="store_true", help="report referential faults only")
    args = parser.parse_args()

    ledger = Path(str(args.dir))
    paths = sorted(ledger.glob("*.md"))
    if not paths:
        print(f"no tickets under {ledger}", file=sys.stderr)
        return 2

    rows = [parse(p) for p in paths]
    resolve_body_refs(rows)

    if args.audit:
        faults = audit(rows)
        for tid, message in faults:
            print(f"{tid}\t{message}")
        print(f"# {len(faults)} fault(s) across {len(rows)} tickets", file=sys.stderr)
        return 1 if faults else 0

    if args.format == "tsv":
        emit_tsv(rows)
    else:
        json.dump([r.as_dict() for r in rows], sys.stdout, indent=1)
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
