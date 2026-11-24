# inter

Skills for working through ideas interactively with the user or other agents.

## Skills

| Skill         | What it does                                                                                                          | Claude Code          |
| ------------- | --------------------------------------------------------------------------------------------------------------------- | -------------------- |
| `brainstorm`  | Acts as a brainstorming partner and stays divergent until asked to converge                                           | `/inter:brainstorm`  |
| `question-me` | Questions the user about a plan, design or vague idea until each branch of the decision tree is resolved              | `/inter:question-me` |
| `handoff`     | Writes a handoff document summarising the conversation, with suggested skills, so a fresh agent can continue the work | `/inter:handoff`     |

Every skill also loads on its own when a request matches its description.

## Artifacts

`handoff` saves its document under `AGENT_ARTIFACTS_DIR`, in a `handoff`
subdirectory. When the variable is unset it defaults to
`.local/data/agentartifacts` under the current working directory. Set it to
keep handoffs in one place across projects:

```sh
export AGENT_ARTIFACTS_DIR="${HOME}/agentartifacts"
```

## Requirements

No tools beyond the agent's own.

## Compatibility

| Client                      | Reads                                      |
| --------------------------- | ------------------------------------------ |
| Claude Code                 | `.claude-plugin/plugin.json` and `skills/` |
| Agent Plugins 1.0.0 clients | `plugin.json` and `skills/`                |

## Install

In Claude Code:

```sh
claude plugin marketplace add andreswebs/agent-plugins
claude plugin install inter@andreswebs
```

For other clients and for project-wide setup, see the
[marketplace README](https://github.com/andreswebs/agent-plugins#install).

## Authors

**Andre Silva** - [@andreswebs](https://github.com/andreswebs)

## License

This project is licensed under the [MIT License](LICENSE).
