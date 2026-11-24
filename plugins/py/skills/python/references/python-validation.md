# Linting and typing standalone Python scripts

A repeatable workflow for cleaning lint and type errors in standalone Python
scripts (the kind run with `uv run script.py`, using PEP 723 inline metadata).
Written to be generic so it applies to any project with similar scripts.

## Preferred conventions

- Scripts are self-contained and run via `uv run`, declaring dependencies with
  PEP 723 inline metadata at the top:

  ```python
  # /// script
  # requires-python = ">=3.11"
  # dependencies = ["pyyaml"]
  # ///
  ```

- Three checkers must all pass clean, in this order of authority:
  1. `ruff` for style and lint.
  2. `pyright` in **strict** mode for typing (this is what an editor with
     Pylance/Pyright surfaces as red squiggles; it is usually the source of
     "a bunch of lint errors").
  3. `ty` as a secondary type check.
- Every function has annotated parameters and a return type.
- Dynamic data (YAML, JSON) is typed at the boundary as `dict[str, Any]` and
  narrowed with `isinstance` before use. Never leave inferred `Unknown` types
  flowing downstream.

## Why the editor shows errors the CLI does not

Two traps account for almost all of the noise:

1. **Empty or wrong virtualenv.** A standalone script's dependencies live in
   the ephemeral `uv run` environment, not in the project `.venv`. The editor's
   language server points at `.venv`, so imports like `import yaml` resolve at
   runtime but show as unresolved in the editor.
2. **Strict mode is not reproduced on the CLI by default.** Plain `pyright`
   runs in basic mode and skips dot-directories (for example `.scripts/`).
   The editor checks open files in strict mode, so the CLI reports zero while
   the editor reports many.

## Workflow

### 1. Reproduce what the editor sees

Install the scripts' declared dependencies into the project `.venv` so the
language server can resolve imports:

```sh
uv pip install --python .venv/bin/python ${DEPS}   # e.g. pyyaml, requests
```

Run each checker. Start with the cheap ones:

```sh
uvx ruff check ${SCRIPT_DIR}/
VIRTUAL_ENV=.venv uvx ty check ${SCRIPT_DIR}/
```

Reproduce strict Pyright. Because Pyright ignores dot-directories and needs a
config for strict mode, use a throwaway config outside the repo and pass the
files explicitly (explicit file args override Pyright's default excludes):

```sh
CFG=$(mktemp -d)/pyrightconfig.json
cat > "${CFG}" <<EOF
{
  "typeCheckingMode": "strict",
  "venvPath": "${PWD}",
  "venv": ".venv",
  "exclude": []
}
EOF

VIRTUAL_ENV=.venv uvx pyright -p "${CFG}" ${SCRIPT_DIR}/*.py
```

The final line of output gives the error count. Read the per-line errors to see
the categories.

### 2. Fix, most impactful first

The errors cascade from a few roots. Fixing the roots clears most of the leaves.

- **Unresolved imports** (`reportMissingImports`): fixed by step 1's
  `uv pip install` into `.venv`. No code change.
- **Missing parameter and return types** (`reportMissingParameterType`,
  `reportUnknownParameterType`): annotate every function signature. This is the
  biggest source of cascading `Unknown` errors, because one untyped parameter
  makes every variable derived from it unknown.
- **Untyped dynamic data** (`reportUnknownVariableType`,
  `reportUnknownMemberType`): type the parse boundary and narrow.

### 3. Patterns for common cases

Type a YAML or JSON parse function at its boundary and `cast` the narrowed
result so callers get a concrete type:

```python
from typing import Any, cast

def parse_frontmatter(text: str) -> dict[str, Any] | None:
    ...
    meta = yaml.safe_load(text[4:end])
    return cast("dict[str, Any]", meta) if isinstance(meta, dict) else None
```

`cast` is needed because narrowing a value of type `Any` with
`isinstance(x, dict)` yields `dict[Unknown, Unknown]` under strict, which
re-triggers the unknown-type errors. The cast pins it to a concrete type.

Bind a `.get()` result to a local before narrowing, so the checker can track
the type. Do not call `.get()` twice on the same key inside a ternary:

```python
# bad: checker cannot narrow across two separate .get() calls
t = m.get("title") if isinstance(m.get("title"), str) else default

# good: bind once, then narrow
title = m.get("title")
t = title if isinstance(title, str) else default
```

Annotate empty containers that are populated later, since the checker cannot
infer their element type from an empty literal:

```python
scores: dict[str, float] = {}
results: list[str] = []
seen: set[Path] = set()
```

Use a `TypedDict` when dict values have different types and you do arithmetic or
sorting on them (a plain `dict[str, object]` breaks `key=lambda c: -c["score"]`
because `object` does not support unary minus):

```python
from typing import TypedDict

class Candidate(TypedDict):
    path: str
    score: float

cands: list[Candidate] = []
cands.sort(key=lambda c: -c["score"])   # score is float, so this type-checks
```

For a value read from `Any`-typed dynamic data that you know is a list, cast at
assignment so both branches agree:

```python
raw = meta.get("tags")
tags: list[Any] = cast("list[Any]", raw) if isinstance(raw, list) else []
```

Annotate generator functions with `Iterator[...]`:

```python
from collections.abc import Iterator

def iter_files(paths: list[Path]) -> Iterator[Path]:
    ...
    yield f
```

### 4. Incidental ruff fixes worth taking

- `subprocess.run(...)` without `check=`: add `check=False` (or `True`) to
  silence `PLW1510` and make intent explicit.
- `read_text()` / `open()` without encoding: add `encoding="utf-8"` to match
  common project convention and silence encoding warnings.

Do not chase the full `--select ALL` ruff set. Rules like `T201` (print found)
and `D103` (missing docstring) are noise for CLI scripts and are not part of
this standard.

### 5. Verify

Re-run all three checkers and confirm the scripts still execute:

```sh
uvx ruff check ${SCRIPT_DIR}/
VIRTUAL_ENV=.venv uvx ty check ${SCRIPT_DIR}/
VIRTUAL_ENV=.venv uvx pyright -p "${CFG}" ${SCRIPT_DIR}/*.py
uv run ${SCRIPT_DIR}/${SOME_SCRIPT}.py ${ARGS}   # smoke test
```

All three should report zero. The annotation changes are pure typing and must
not change runtime behavior, so a quick smoke test of the most-refactored
functions is enough.

## Notes

- If `.venv` is git-ignored and there is no `pyproject.toml`, installing deps
  into `.venv` is a local editor convenience and does not affect the tracked
  repo or how the scripts run under `uv`.
- The scripts remain runnable with `uv run` throughout; the inline PEP 723
  metadata is the source of truth for dependencies, and `.venv` only mirrors it
  for the editor.
