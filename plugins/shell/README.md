# shell

Skills for the command line: write and review defensive Bash scripts and BATS
tests, query and reshape JSON with jq, test CLI programs with shelltestrunner,
and do engineering arithmetic and estimation with bc.

## Skills

| Skill       | What it does                                                                                                                                   | Claude Code        |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------ |
| `bash`      | Conventions and defensive patterns for Bash scripts, shell libraries and BATS tests, with a triage gate for which features a script has earned | `/shell:bash`      |
| `jq`        | The jq CLI and language for querying, filtering, transforming and building JSON and JSON Lines                                                 | `/shell:jq`        |
| `shelltest` | Writes shelltestrunner `.test` files for command-line programs                                                                                 | `/shell:shelltest` |
| `math`      | Calculations with bc, Fermi estimation, capacity planning and SRE math such as percentiles, Little's Law and error budgets                     | `/shell:math`      |

Every skill also loads on its own when a request matches its description.

## Requirements

- `bash`: `shellcheck` and `shfmt`, plus `bats-core` for tests. Its patterns
  assume GNU coreutils, with documented probes for BSD and macOS.
- `jq`: `jq`.
- `shelltest`: `shelltestrunner`.
- `math`: `bc`.

## Compatibility

| Client                      | Reads                                      |
| --------------------------- | ------------------------------------------ |
| Claude Code                 | `.claude-plugin/plugin.json` and `skills/` |
| Agent Plugins 1.0.0 clients | `plugin.json` and `skills/`                |

## Install

In Claude Code:

```sh
claude plugin marketplace add andreswebs/agent-plugins
claude plugin install shell@andreswebs
```

For other clients and for project-wide setup, see the
[marketplace README](https://github.com/andreswebs/agent-plugins#install).

## Authors

**Andre Silva** - [@andreswebs](https://github.com/andreswebs)

## License

This project is licensed under the [MIT License](LICENSE).
