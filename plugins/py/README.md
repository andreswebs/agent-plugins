# py

Skills for Python tooling: manage projects, scripts and tools with uv, lint
and format with ruff, type-check with ty, and get standalone scripts passing
ruff, strict pyright and ty clean.

## Skills

| Skill    | What it does                                                                                                                           | Claude Code  |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| `uv`     | Guide to uv for Python projects, scripts with inline metadata, packages, tools and Python versions                                     | `/py:uv`     |
| `ruff`   | Guide to ruff for linting, formatting and fixing Python code                                                                           | `/py:ruff`   |
| `ty`     | Guide to ty for type checking Python code and setting it up in projects                                                                | `/py:ty`     |
| `python` | Workflow for clearing ruff, strict pyright and ty errors in standalone `uv run` scripts, and for editor errors the CLI does not report | `/py:python` |

Every skill also loads on its own when a request matches its description.

## Requirements

- `uv`. The other tools can run through it (`uvx ruff`, `uvx ty`,
  `uvx pyright`) when they are not installed.
- `ruff`, `ty` and `pyright` for the skills that use them.

## Compatibility

| Client                      | Reads                                      |
| --------------------------- | ------------------------------------------ |
| Claude Code                 | `.claude-plugin/plugin.json` and `skills/` |
| Agent Plugins 1.0.0 clients | `plugin.json` and `skills/`                |

## Install

In Claude Code:

```sh
claude plugin marketplace add andreswebs/agent-plugins
claude plugin install py@andreswebs
```

For other clients and for project-wide setup, see the
[marketplace README](https://github.com/andreswebs/agent-plugins#install).

## Authors

**Andre Silva** - [@andreswebs](https://github.com/andreswebs)

## License

This project is licensed under the [MIT License](LICENSE).
