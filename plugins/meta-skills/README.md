# meta-skills

Skills for working on skills and on repeatable work: author and audit agent
skills, field-test a skill on a real task, record a task while it is done so it
can become a skill, and hand a task over as a runbook the user reviews and runs.

## Skills

| Skill | What it does | Claude Code |
| --- | --- | --- |
| `skill-builder` | Reference for authoring, editing and auditing agent skills against the Agent Skills spec, with a validator script | `/meta-skills:skill-builder` |
| `skill-recorder` | Field-tests a skill on a real task and records what happened while it ran | `/meta-skills:skill-recorder` |
| `task-recorder` | Records a task while it is done (phases, forks, pitfalls, user interventions, commands worth scripting) as a seed for a future skill | `/meta-skills:task-recorder` |
| `task-script` | Hands a task over as one idempotent Bash runbook, dry run by default, for the user to review and run | `/meta-skills:task-script` |

Every skill also loads on its own when a request matches its description.

## Artifacts

The skills write their records under `AGENT_ARTIFACTS_DIR`, one subdirectory
per skill. When the variable is unset they default to
`.local/data/agentartifacts` under the current working directory. Set it to
keep records in one place across projects:

```sh
export AGENT_ARTIFACTS_DIR="${HOME}/agentartifacts"
```

## Requirements

- `skill-builder`: `uv`, to run `scripts/skill_ref.py` with its inline
  dependencies.
- `task-script`: Bash, plus `shellcheck` and `shfmt` to review the runbook it
  produces.
- `task-recorder`: `jq`, to read the harness session transcripts it mines.
- `skill-recorder`: no tools beyond the agent's own.

## Compatibility

| Client | Reads |
| --- | --- |
| Claude Code | `.claude-plugin/plugin.json` and `skills/` |
| Agent Plugins 1.0.0 clients | `plugin.json` and `skills/` |

The plugin ships only skills, so it conforms fully to the Agent Plugins
specification.

## Install

In Claude Code:

```sh
claude plugin marketplace add andreswebs/agent-plugins
claude plugin install meta-skills@andreswebs
```

For other clients and for project-wide setup, see the
[marketplace README](https://github.com/andreswebs/agent-plugins#install).

## Authors

**Andre Silva** - [@andreswebs](https://github.com/andreswebs)

## License

This project is licensed under the [MIT License](LICENSE).
