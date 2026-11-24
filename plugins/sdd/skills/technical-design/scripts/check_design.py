#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# ///
"""Check a technical design against its EARS requirements document.

Usage:
    uv run scripts/check_design.py REQUIREMENTS_MD DESIGN_MD

Reports, in this order:
  - mandated design sections that are missing
  - acceptance criteria (N.M) never referenced anywhere in the design
  - clause references in the design that do not exist in the requirements
  - correctness properties lacking a Validates line or a "for all"
  - a note when the Correctness Properties section is absent
  - a warning listing clauses "tested but not designed": referenced only
    under Testing Strategy (non-failing)

Exit code 0 when nothing is wrong, 1 otherwise. Output ordering is stable.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

MANDATED_SECTIONS = (
    "Overview",
    "Architecture",
    "Components and Interfaces",
    "Data Models",
    "Error Handling",
    "Testing Strategy",
)

REQUIREMENT_HEADING = re.compile(r"^###\s+Requirement\s+(\d+)\b", re.M)
CRITERION_LINE = re.compile(r"^\s*(\d+)\.\s+\S")
H2 = re.compile(r"^##\s+(.+?)\s*$", re.M)
PROPERTY_HEADING = re.compile(r"^###\s+Property\s+(\d+)\b", re.M)
VALIDATES = re.compile(r"Validates:\s*Requirements?\s+([^*\n]+)", re.I)
# "Requirements 1.1, 1.2", "Req 1.5", "Requirement 3.2", "criteria 2.1-2.3",
# "Requirements 3.1 to 3.5"
SEP = r"(?:\s*[-–—]\s*|\s+to\s+)"
REF_LEAD_IN = re.compile(
    r"\b(?:Requirements?|Reqs?|Req\.|criteria|criterion|clauses?|AC)\s+"
    r"((?:\d+\.\d+(?:" + SEP + r"\d+\.\d+)?)(?:\s*,\s*(?:and\s+)?"
    r"\d+\.\d+(?:" + SEP + r"\d+\.\d+)?)*)",
    re.I,
)
# "(3.5)" or "(3.5, 4.4)" as a bare parenthesised reference
PAREN_REF = re.compile(r"\((\d+\.\d+(?:\s*,\s*\d+\.\d+)*)\)")
CLAUSE = re.compile(r"(\d+)\.(\d+)")
RANGE = re.compile(r"(\d+)\.(\d+)" + SEP + r"(\d+)\.(\d+)")
FOR_ALL = re.compile(r"\bfor\s+(?:all|any|every)\b", re.I)


def parse_requirements(text: str) -> set[tuple[int, int]]:
    clauses: set[tuple[int, int]] = set()
    current: int | None = None
    in_criteria = False
    for line in text.splitlines():
        m = REQUIREMENT_HEADING.match(line)
        if m:
            current = int(m.group(1))
            in_criteria = False
            continue
        if line.startswith("## "):
            current = None
            in_criteria = False
            continue
        if line.startswith("#### "):
            in_criteria = "acceptance criteria" in line.lower()
            continue
        if current is not None and in_criteria:
            c = CRITERION_LINE.match(line)
            if c and not line.startswith("   "):
                clauses.add((current, int(c.group(1))))
    return clauses


def expand(ref_text: str) -> set[tuple[int, int]]:
    found: set[tuple[int, int]] = set()
    rest = ref_text
    for r in RANGE.finditer(ref_text):
        a_req, a_cl, b_req, b_cl = (int(x) for x in r.groups())
        if a_req == b_req and a_cl <= b_cl:
            found.update((a_req, n) for n in range(a_cl, b_cl + 1))
        else:
            found.update({(a_req, a_cl), (b_req, b_cl)})
    rest = RANGE.sub(" ", rest)
    found.update((int(a), int(b)) for a, b in CLAUSE.findall(rest))
    return found


def design_references(text: str) -> set[tuple[int, int]]:
    refs: set[tuple[int, int]] = set()
    for m in REF_LEAD_IN.finditer(text):
        refs |= expand(m.group(1))
    for m in PAREN_REF.finditer(text):
        refs |= expand(m.group(1))
    for m in VALIDATES.finditer(text):
        refs |= expand(m.group(1))
    return refs


def sections(text: str) -> list[str]:
    return [h.strip() for h in H2.findall(text)]


def section_bodies(text: str) -> dict[str, str]:
    heads = list(H2.finditer(text))
    out: dict[str, str] = {}
    for i, h in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        out[h.group(1).strip()] = text[h.end() : end]
    return out


def tested_only(text: str, clauses: set[tuple[int, int]]) -> list[tuple[int, int]]:
    bodies = section_bodies(text)
    tested = design_references(bodies.get("Testing Strategy", ""))
    designed: set[tuple[int, int]] = set()
    for name, body in bodies.items():
        if name != "Testing Strategy":
            designed |= design_references(body)
    return sorted((tested - designed) & clauses)


def split_properties(text: str) -> list[tuple[int, str]]:
    heads = list(PROPERTY_HEADING.finditer(text))
    out = []
    for i, h in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        body = text[h.end() : end]
        stop = re.search(r"^##\s", body, re.M)
        if stop:
            body = body[: stop.start()]
        out.append((int(h.group(1)), body))
    return out


def fmt(c: tuple[int, int]) -> str:
    return f"{c[0]}.{c[1]}"


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if len(argv) == 2 else 2
    req_path, design_path = Path(argv[1]), Path(argv[2])
    req_text = req_path.read_text(encoding="utf-8")
    design_text = design_path.read_text(encoding="utf-8")

    problems = 0
    clauses = parse_requirements(req_text)
    if not clauses:
        print(f"error: no acceptance criteria found in {req_path}")
        return 1

    present = sections(design_text)
    missing = [s for s in MANDATED_SECTIONS if s not in present]
    if missing:
        problems += len(missing)
        print("Missing mandated sections:")
        for s in missing:
            print(f"  - {s}")

    refs = design_references(design_text)
    unaddressed = sorted(clauses - refs)
    if unaddressed:
        problems += len(unaddressed)
        print(f"Acceptance criteria never referenced in the design ({len(unaddressed)}):")
        for c in unaddressed:
            print(f"  - {fmt(c)}")

    dangling = sorted(refs - clauses)
    if dangling:
        problems += len(dangling)
        print(f"References to clauses that do not exist ({len(dangling)}):")
        for c in dangling:
            print(f"  - {fmt(c)}")

    props = split_properties(design_text)
    if "Correctness Properties" in present:
        bad = []
        for num, body in props:
            v = VALIDATES.search(body)
            reasons = []
            if not v:
                reasons.append("no Validates line")
            elif not expand(v.group(1)):
                reasons.append("Validates line names no clause")
            if not FOR_ALL.search(body.replace("_", " ").replace("*", " ")):
                reasons.append('no explicit "for all"')
            if reasons:
                bad.append((num, reasons))
        if not props:
            problems += 1
            print("Correctness Properties section present but holds no '### Property N' entries")
        if bad:
            problems += len(bad)
            print("Properties with defects:")
            for num, reasons in bad:
                print(f"  - Property {num}: {'; '.join(reasons)}")
    else:
        print(
            "Note: no Correctness Properties section; Testing Strategy must state "
            "why property-based testing does not apply."
        )

    only_tested = tested_only(design_text, clauses)
    if only_tested:
        print(f"Warning, tested but not designed ({len(only_tested)}): "
              "referenced only under Testing Strategy")
        for c in only_tested:
            print(f"  - {fmt(c)}")

    total = len(clauses)
    covered = total - len(unaddressed)
    print(f"Coverage: {covered}/{total} acceptance criteria referenced; "
          f"{len(props)} properties.")
    if problems:
        print(f"FAIL: {problems} problem(s)")
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
