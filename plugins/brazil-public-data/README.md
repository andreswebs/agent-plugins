# brazil-public-data

Skills for Brazilian public data: official municipal statistics from IBGE,
and municipal official gazettes (diários oficiais) from Querido Diário.
Every request is appended to a JSONL search log, and every value keeps the
exact request URL it came from.

## Skills

| Skill            | What it does                                                                                                             | Claude Code                           |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------- |
| `ibge-stats`     | Resolves a municipality to its 7-digit IBGE code and reads values from SIDRA tables and the agregados v3 API, as JSONL   | `/brazil-public-data:ibge-stats`      |
| `gazette-search` | Searches municipal gazettes by municipality, term and date range, fetches gazette texts, and downloads yearly bulk files | `/brazil-public-data:gazette-search`  |

Every skill also loads on its own when a request matches its description.
The worked examples use Osasco (SP), whose literals were taken from live
responses.

## Environment

| Variable              | Purpose                                                      |
| --------------------- | ------------------------------------------------------------ |
| `RESEARCH_SEARCH_LOG` | JSONL file every query appends to; a per-run file when unset |

Both services are keyless. No credential and no `User-Agent` header are
sent.

## Data terms

Each skill states the terms of the service it calls and the attribution line
its outputs carry. Querido Diário's API is meant for automated queries at a
low request rate, with a yearly file per municipality as the bulk route; the
skill paces itself to one request per second.

## Artifacts

The skills write their records under `AGENT_ARTIFACTS_DIR`, one subdirectory
per skill. When the variable is unset they default to
`.local/data/agentartifacts` under the current working directory.

## Requirements

`curl` and `jq`.

## Compatibility

| Client                      | Reads                                      |
| --------------------------- | ------------------------------------------ |
| Claude Code                 | `.claude-plugin/plugin.json` and `skills/` |
| Agent Plugins 1.0.0 clients | `plugin.json` and `skills/`                |

## Install

In Claude Code:

```sh
claude plugin marketplace add andreswebs/agent-plugins
claude plugin install brazil-public-data@andreswebs
```

For other clients and for project-wide setup, see the
[marketplace README](https://github.com/andreswebs/agent-plugins#install).

## Authors

**Andre Silva** - [@andreswebs](https://github.com/andreswebs)

## License

This project is licensed under the [MIT License](LICENSE).
