# sdd

Skills for spec-driven development: take a feature from requirements to
a technical design, check the plan against the code, and file it as tickets
an agent can work through.

## Skills

| Skill              | What it does                                                                                                                                        | Claude Code             |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| `ears-prd`         | Writes a `requirements.md` whose acceptance criteria are EARS sentences, each numbered so a design and its tests can trace back to it               | `/sdd:ears-prd`         |
| `technical-design` | Writes or re-syncs a `technical-design.md` from an EARS `requirements.md`, in the shape of a Kiro spec design document, with every criterion traced | `/sdd:technical-design` |
| `verify-plan`      | Fact-checks a plan, spec or assessment against the code it describes before anyone acts on it                                                       | `/sdd:verify-plan`      |
| `plan-to-tickets`  | Decomposes a finalized plan, spec or phase document into self-contained, dependency-mapped tickets that an independent agent can implement cold     | `/sdd:plan-to-tickets`  |
| `ticket`           | Tracks work with the `tk` ticket CLI, which keeps markdown tickets in `.tickets/` with dependencies and a ready queue                               | `/sdd:ticket`           |

Every skill also loads on its own when a request matches its description.

The skills work in sequence but do not depend on each other: `ears-prd`
produces the requirements, `technical-design` turns them into a design,
`verify-plan` checks any plan against the source, `plan-to-tickets` splits it
into work, and `ticket` runs the queue. `plan-to-tickets` works with any
tracker; `ticket` covers `tk` specifically.

## Requirements

- `ears-prd`, `verify-plan`, `plan-to-tickets`: no tools beyond the agent's
  own.
- `technical-design`: `uv`, to run `scripts/check_design.py`, which checks
  that the design traces every acceptance criterion. The script needs
  Python 3.12 or later, which `uv` provides.
- `ticket`: the `tk` CLI (Homebrew package `ticket`), verified against
  version 0.3.2, and `uv`, to run `scripts/tk_export.py`, which exports and
  audits the ticket store. The script needs Python 3.11 or later.

## Compatibility

| Client                      | Reads                                      |
| --------------------------- | ------------------------------------------ |
| Claude Code                 | `.claude-plugin/plugin.json` and `skills/` |
| Agent Plugins 1.0.0 clients | `plugin.json` and `skills/`                |

## Install

In Claude Code:

```sh
claude plugin marketplace add andreswebs/agent-plugins
claude plugin install sdd@andreswebs
```

For other clients and for project-wide setup, see the
[marketplace README](https://github.com/andreswebs/agent-plugins#install).

## Authors

**Andre Silva** - [@andreswebs](https://github.com/andreswebs)

## License

This project is licensed under the [MIT License](LICENSE).
