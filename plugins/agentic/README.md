# agentic

Skills for working with agent harnesses.

## Skills

| Skill                 | What it does                                                                                                                                                                                | Claude Code                    |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| `agent-introspection` | Establishes what tools, storage, sessions, history and configuration the current harness has, and checks claims about the harness before they are acted on. Covers Claude Code, Kiro, Pi and Hermes | `/agentic:agent-introspection` |
| `make-agents-md`      | Restructures a long or contradictory `AGENTS.md` or `CLAUDE.md` into a minimal root file plus grouped, linked docs                                                                          | `/agentic:make-agents-md`      |

Every skill also loads on its own when a request matches its description.

## Requirements

- `agent-introspection`: `jq` and `ps`. Its `scripts/sample-agent-log.bash`,
  which samples records from a Claude Code session transcript, needs Bash.
  Its `scripts/snapshot-env.bash`, which prints a live Hermes environment in
  one pass, needs Bash as well.
- `make-agents-md`: no tools beyond the agent's own.

## Compatibility

| Client                      | Reads                                      |
| --------------------------- | ------------------------------------------ |
| Claude Code                 | `.claude-plugin/plugin.json` and `skills/` |
| Agent Plugins 1.0.0 clients | `plugin.json` and `skills/`                |

## Install

In Claude Code:

```sh
claude plugin marketplace add andreswebs/agent-plugins
claude plugin install agentic@andreswebs
```

For other clients and for project-wide setup, see the
[marketplace README](https://github.com/andreswebs/agent-plugins#install).

## Authors

**Andre Silva** - [@andreswebs](https://github.com/andreswebs)

## License

This project is licensed under the [MIT License](LICENSE).
