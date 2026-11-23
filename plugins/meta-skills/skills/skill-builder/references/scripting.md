# Scripting

Reference for a skill's `scripts/` directory. Loaded from [SKILL.md](../SKILL.md).

A script exists to pin behaviour that must be **deterministic**: the same result every run, out of the model's hands. It earns that only if it runs the same way on every machine, so write every script **self-contained**: one file that declares its own dependencies and runs with a single command, with no separate install step and no ambient virtualenv, `node_modules`, or lockfile to set up first.

Self-contained buys three things:

- **Portability.** Clone the skill, run the script, it works.
- **Legibility.** The dependencies sit at the top of the file the agent is already reading.
- **No setup drift.** Nothing to forget, nothing to keep in sync with a separate manifest.

Invoke a script from `SKILL.md` with the one command that runs it, e.g. `uv run scripts/foo.py`. Give that command a **completion criterion** the agent can check: a meaningful exit code and, where the agent parses the output, a stable and documented format.

## Python: `uv` with inline metadata

Declare dependencies in a [PEP 723](https://packaging.python.org/en/latest/specifications/inline-script-metadata/) inline-metadata block at the top of the file. `uv run` reads it, builds an ephemeral environment, and runs the script:

```python
# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx", "rich"]
# ///
import httpx
```

Run it:

```sh
uv run scripts/fetch.py
```

No `pip install`, no `requirements.txt`, no virtualenv to activate.

## Shell

A POSIX shell script is self-contained when it leans only on tools the environment already guarantees. State the requirement and fail loud when a tool is missing, so a missing dependency is an immediate error rather than silent wrong behaviour:

```sh
#!/usr/bin/env bash
set -euo pipefail
command -v jq >/dev/null || { echo "needs jq" >&2; exit 1; }
```

Reach for shell only when the whole job is a short pipe of standard tools. The moment you need a real dependency, move to Python or Deno.

## JavaScript and TypeScript: Deno

Deno runs a single `.ts` or `.js` file directly and resolves dependencies inline via `npm:` or URL specifiers, so there is no `node_modules` to install:

```ts
import { z } from "npm:zod@3";
```

Run it:

```sh
deno run --allow-read scripts/foo.ts
```

Prefer Deno over plain Node here: Node needs a `package.json` plus `npm install`, which breaks self-containment.

## Conventions

- **One documented command.** State it in `SKILL.md` so the agent copies it verbatim.
- **Meaningful exit codes.** `0` for success, non-zero for failure, so the agent can branch on the result.
- **Self-describing.** A `--help` flag or a header comment states what the script does, its arguments, and its output.
- **Stable output.** Fixed ordering, no timestamps or random ids in anything the agent parses.
