# /// script
# requires-python = ">=3.11"
# dependencies = ["strictyaml>=1.7.3"]
# ///
"""Validate and inspect Agent Skills.

A self-contained port of the `skills-ref` reference library. Checks a skill
against the Agent Skills spec and reads its frontmatter, with no install step:
run it directly with `uv run`.

Commands:
    validate SKILL_DIR          check a skill conforms to the spec, and the
                                shape of evals/evals.json when present
    read-properties SKILL_DIR   print parsed SKILL.md frontmatter as JSON
    to-prompt SKILL_DIR...      emit the <available_skills> XML block

Usage:
    uv run scripts/skill_ref.py validate path/to/skill

Exit codes:
    0   success (valid skill / output produced)
    1   validation failure or parse error
    2   usage error (handled by argparse)
"""

from __future__ import annotations

import argparse
import html
import json
import sys
import unicodedata
from pathlib import Path
from typing import Any, cast

import strictyaml  # pyright: ignore[reportMissingTypeStubs]

MAX_SKILL_NAME_LENGTH = 64
MAX_DESCRIPTION_LENGTH = 1024
MAX_COMPATIBILITY_LENGTH = 500
EVALS_FILE = Path("evals") / "evals.json"

# Frontmatter fields permitted by the Agent Skills spec.
ALLOWED_FIELDS = {
    "name",
    "description",
    "license",
    "allowed-tools",
    "metadata",
    "compatibility",
}


class SkillError(Exception):
    """Base exception for skill parsing and validation failures."""


class ParseError(SkillError):
    """Raised when SKILL.md cannot be located or its frontmatter parsed."""


class ValidationError(SkillError):
    """Raised when required properties are missing or malformed."""


def find_skill_md(skill_dir: Path) -> Path | None:
    """Return the SKILL.md path in a skill directory, or None if absent."""
    for name in ("SKILL.md", "skill.md"):
        path = skill_dir / name
        if path.exists():
            return path
    return None


def _load_yaml(text: str) -> object:
    """Parse a YAML document into plain Python objects.

    strictyaml ships no type stubs, so its `load(...).data` is untyped; this
    helper is the single boundary where that Unknown is pinned to `object`.
    """
    return strictyaml.load(text).data  # pyright: ignore[reportUnknownMemberType, reportUnknownVariableType]


def parse_frontmatter(content: str) -> dict[str, Any]:
    """Parse the YAML frontmatter of a SKILL.md file into a mapping.

    Raises:
        ParseError: if the frontmatter is missing, unclosed, or not a mapping.
    """
    if not content.startswith("---"):
        raise ParseError("SKILL.md must start with YAML frontmatter (---)")

    parts = content.split("---", 2)
    if len(parts) < 3:
        raise ParseError("SKILL.md frontmatter not properly closed with ---")

    try:
        data = _load_yaml(parts[1])
    except strictyaml.YAMLError as exc:
        raise ParseError(f"Invalid YAML in frontmatter: {exc}") from exc

    if not isinstance(data, dict):
        raise ParseError("SKILL.md frontmatter must be a YAML mapping")

    metadata = cast("dict[str, Any]", data)
    extra = metadata.get("metadata")
    if isinstance(extra, dict):
        pairs = cast("dict[object, object]", extra)
        metadata["metadata"] = {str(k): str(v) for k, v in pairs.items()}
    return metadata


def _validate_name(name_value: object, skill_dir: Path) -> list[str]:
    """Validate the `name` field and its match with the directory name."""
    if not isinstance(name_value, str) or not name_value.strip():
        return ["Field 'name' must be a non-empty string"]

    errors: list[str] = []
    name = unicodedata.normalize("NFKC", name_value.strip())

    if len(name) > MAX_SKILL_NAME_LENGTH:
        errors.append(
            f"Skill name '{name}' exceeds {MAX_SKILL_NAME_LENGTH} character "
            f"limit ({len(name)} chars)"
        )
    if name != name.lower():
        errors.append(f"Skill name '{name}' must be lowercase")
    if name.startswith("-") or name.endswith("-"):
        errors.append("Skill name cannot start or end with a hyphen")
    if "--" in name:
        errors.append("Skill name cannot contain consecutive hyphens")
    if not all(c.isalnum() or c == "-" for c in name):
        errors.append(
            f"Skill name '{name}' contains invalid characters. "
            "Only letters, digits, and hyphens are allowed."
        )

    dir_name = unicodedata.normalize("NFKC", skill_dir.name)
    if dir_name != name:
        errors.append(
            f"Directory name '{skill_dir.name}' must match skill name '{name}'"
        )
    return errors


def _validate_description(description_value: object) -> list[str]:
    """Validate the `description` field."""
    if not isinstance(description_value, str) or not description_value.strip():
        return ["Field 'description' must be a non-empty string"]
    if len(description_value) > MAX_DESCRIPTION_LENGTH:
        return [
            (
                f"Description exceeds {MAX_DESCRIPTION_LENGTH} character limit "
                f"({len(description_value)} chars)"
            )
        ]
    return []


def _validate_compatibility(compatibility_value: object) -> list[str]:
    """Validate the optional `compatibility` field."""
    if not isinstance(compatibility_value, str):
        return ["Field 'compatibility' must be a string"]
    if len(compatibility_value) > MAX_COMPATIBILITY_LENGTH:
        return [
            (
                f"Compatibility exceeds {MAX_COMPATIBILITY_LENGTH} character limit "
                f"({len(compatibility_value)} chars)"
            )
        ]
    return []


def validate_metadata(metadata: dict[str, Any], skill_dir: Path) -> list[str]:
    """Validate parsed frontmatter, returning a list of problems (empty if valid)."""
    errors: list[str] = []

    extra_fields = set(metadata.keys()) - ALLOWED_FIELDS
    if extra_fields:
        errors.append(
            f"Unexpected fields in frontmatter: {', '.join(sorted(extra_fields))}. "
            f"Only {sorted(ALLOWED_FIELDS)} are allowed."
        )

    if "name" not in metadata:
        errors.append("Missing required field in frontmatter: name")
    else:
        errors.extend(_validate_name(metadata["name"], skill_dir))

    if "description" not in metadata:
        errors.append("Missing required field in frontmatter: description")
    else:
        errors.extend(_validate_description(metadata["description"]))

    if "compatibility" in metadata:
        errors.extend(_validate_compatibility(metadata["compatibility"]))

    return errors


def _validate_eval_case(case: dict[str, Any], label: str, skill_dir: Path) -> list[str]:
    """Validate one entry of `evals`; extra fields beyond the spec's are allowed."""
    errors: list[str] = []
    for field in ("prompt", "expected_output"):
        value = case.get(field)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{label}: '{field}' must be a non-empty string")
    files = case.get("files", [])
    if not isinstance(files, list) or not all(
        isinstance(f, str) for f in cast("list[Any]", files)
    ):
        errors.append(f"{label}: 'files' must be a list of strings")
    else:
        for rel in cast("list[str]", files):
            if not (skill_dir / rel).exists():
                errors.append(f"{label}: file not found: {rel}")
    assertions = case.get("assertions", [])
    if not isinstance(assertions, list) or not all(
        isinstance(a, str) and a.strip() for a in cast("list[Any]", assertions)
    ):
        errors.append(f"{label}: 'assertions' must be a list of non-empty strings")
    return errors


def validate_evals(skill_dir: Path, skill_name: object) -> list[str]:
    """Validate `evals/evals.json` against the evaluating-skills guide, when present."""
    path = skill_dir / EVALS_FILE
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return [f"{EVALS_FILE}: cannot parse: {exc}"]
    if not isinstance(data, dict):
        return [f"{EVALS_FILE}: top level must be an object"]
    doc = cast("dict[str, Any]", data)

    errors: list[str] = []
    declared = doc.get("skill_name")
    if not isinstance(declared, str) or not declared.strip():
        errors.append(f"{EVALS_FILE}: 'skill_name' must be a non-empty string")
    elif isinstance(skill_name, str) and declared != skill_name:
        errors.append(
            f"{EVALS_FILE}: skill_name '{declared}' does not match skill name '{skill_name}'"
        )
    evals = doc.get("evals")
    if not isinstance(evals, list) or not evals:
        errors.append(f"{EVALS_FILE}: 'evals' must be a non-empty list")
        return errors

    seen_ids: set[str] = set()
    for index, raw in enumerate(cast("list[Any]", evals)):
        label = f"{EVALS_FILE} evals[{index}]"
        if not isinstance(raw, dict):
            errors.append(f"{label}: must be an object")
            continue
        case = cast("dict[str, Any]", raw)
        case_id = case.get("id")
        if isinstance(case_id, bool) or not isinstance(case_id, (int, str)):
            errors.append(f"{label}: 'id' must be an integer or a string")
        elif str(case_id) in seen_ids:
            errors.append(f"{label}: duplicate id {case_id!r}")
        else:
            seen_ids.add(str(case_id))
        errors.extend(_validate_eval_case(case, label, skill_dir))
    return errors


def validate(skill_dir: Path) -> list[str]:
    """Validate a skill directory, returning a list of problems (empty if valid)."""
    if not skill_dir.exists():
        return [f"Path does not exist: {skill_dir}"]
    if not skill_dir.is_dir():
        return [f"Not a directory: {skill_dir}"]

    skill_md = find_skill_md(skill_dir)
    if skill_md is None:
        return ["Missing required file: SKILL.md"]

    try:
        metadata = parse_frontmatter(skill_md.read_text(encoding="utf-8"))
    except ParseError as exc:
        return [str(exc)]

    errors = validate_metadata(metadata, skill_dir)
    errors.extend(validate_evals(skill_dir, metadata.get("name")))
    return errors


def read_properties(skill_dir: Path) -> dict[str, Any]:
    """Read SKILL.md frontmatter into a plain dict, without full validation.

    Raises:
        ParseError: if SKILL.md is missing or its frontmatter is invalid.
        ValidationError: if the required `name` or `description` is missing.
    """
    skill_md = find_skill_md(skill_dir)
    if skill_md is None:
        raise ParseError(f"SKILL.md not found in {skill_dir}")

    metadata = parse_frontmatter(skill_md.read_text(encoding="utf-8"))

    name = metadata.get("name")
    description = metadata.get("description")
    if not isinstance(name, str) or not name.strip():
        raise ValidationError("Field 'name' must be a non-empty string")
    if not isinstance(description, str) or not description.strip():
        raise ValidationError("Field 'description' must be a non-empty string")

    result: dict[str, Any] = {"name": name.strip(), "description": description.strip()}
    for key in ("license", "compatibility", "allowed-tools"):
        value = metadata.get(key)
        if value is not None:
            result[key] = value
    extra = metadata.get("metadata")
    if isinstance(extra, dict) and extra:
        result["metadata"] = cast("dict[str, Any]", extra)
    return result


def to_prompt(skill_dirs: list[Path]) -> str:
    """Build the <available_skills> XML block for the given skill directories."""
    if not skill_dirs:
        return "<available_skills>\n</available_skills>"

    lines = ["<available_skills>"]
    for skill_dir in skill_dirs:
        resolved = skill_dir.resolve()
        props = read_properties(resolved)
        lines.append("<skill>")
        lines.append("<name>")
        lines.append(html.escape(str(props["name"])))
        lines.append("</name>")
        lines.append("<description>")
        lines.append(html.escape(str(props["description"])))
        lines.append("</description>")
        lines.append("<location>")
        lines.append(str(find_skill_md(resolved)))
        lines.append("</location>")
        lines.append("</skill>")
    lines.append("</available_skills>")
    return "\n".join(lines)


def _resolve_skill_dir(path: Path) -> Path:
    """Accept either a skill directory or a path to its SKILL.md file.

    Resolves to an absolute path so the directory-name check works for `.`,
    trailing slashes, and other relative forms.
    """
    resolved = path.resolve()
    if resolved.is_file() and resolved.name.lower() == "skill.md":
        return resolved.parent
    return resolved


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="skill_ref", description="Validate and inspect Agent Skills."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    p_validate = subparsers.add_parser("validate", help="validate a skill directory")
    p_validate.add_argument("skill_path", type=Path, help="skill dir or SKILL.md path")

    p_read = subparsers.add_parser(
        "read-properties", help="print SKILL.md frontmatter as JSON"
    )
    p_read.add_argument("skill_path", type=Path, help="skill dir or SKILL.md path")

    p_prompt = subparsers.add_parser(
        "to-prompt", help="emit the <available_skills> XML block"
    )
    p_prompt.add_argument(
        "skill_paths", type=Path, nargs="+", help="one or more skill dirs"
    )

    args = parser.parse_args(argv)
    command = cast(str, args.command)

    if command == "validate":
        skill_dir = _resolve_skill_dir(cast(Path, args.skill_path))
        errors = validate(skill_dir)
        if errors:
            print(f"Validation failed for {skill_dir}:", file=sys.stderr)
            for error in errors:
                print(f"  - {error}", file=sys.stderr)
            return 1
        print(f"Valid skill: {skill_dir}")
        return 0

    if command == "read-properties":
        skill_dir = _resolve_skill_dir(cast(Path, args.skill_path))
        try:
            props = read_properties(skill_dir)
        except SkillError as exc:
            print(f"Error: {exc}", file=sys.stderr)
            return 1
        print(json.dumps(props, indent=2))
        return 0

    # command == "to-prompt"
    skill_dirs = [_resolve_skill_dir(p) for p in cast("list[Path]", args.skill_paths)]
    try:
        print(to_prompt(skill_dirs))
    except SkillError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
