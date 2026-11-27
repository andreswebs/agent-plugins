# scholarly-research

Skills for reproducible literature work: resolve a reference to one clean
record, search scholarly databases by query language, snowball citations,
harvest whole collections over OAI-PMH, fetch a legal open-access full text with its source, version and license,
and file records into Zotero. Every query is appended to a JSONL search log,
so a search can be reported and repeated.

## Skills

| Skill          | What it does                                                                                                                                    | Claude Code                        |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| `lit-resolve`  | Resolves a DOI, title, citation, URL or formal identifier to one record with its open-access verdict                                            | `/scholarly-research:lit-resolve`  |
| `lit-search`   | Keyword search across OpenAlex, Europe PMC, CORE, arXiv, BDTD and CiNii, plus grey literature on the web, deduplicated                          | `/scholarly-research:lit-search`   |
| `lit-snowball` | Forward and backward citations from seed works across OpenAlex, OpenCitations and Semantic Scholar, checked with Crossref                       | `/scholarly-research:lit-snowball` |
| `lit-harvest`  | Harvests every record of a collection, journal, set or category in a date window over OAI-PMH from SciELO, SciELO Preprints or arXiv, resumable | `/scholarly-research:lit-harvest`  |
| `lit-fulltext` | Fetches the full text of a known work and records which source holds it, which version it is and under which license                            | `/scholarly-research:lit-fulltext` |
| `lit-zotero`   | Files records into a Zotero collection as metadata-only items, deduplicated, and reads back citation keys                                       | `/scholarly-research:lit-zotero`   |

Every skill also loads on its own when a request matches its description.
The skills share one record shape and one search-log format, and each
carries its own copy of the references it needs.

## Environment

Every variable is optional except where a skill says it stops without it.
Values are read from the shell and never written to a file or a log.

| Variable                       | Used by                             | Purpose                                                           |
| ------------------------------ | ----------------------------------- | ----------------------------------------------------------------- |
| `RESEARCH_SEARCH_LOG`          | all                                 | JSONL file every query appends to; a per-run file when unset      |
| `RESEARCH_CONTACT_EMAIL`       | resolve, snowball, fulltext         | Crossref `mailto` and Unpaywall `email` only, never a header      |
| `RESEARCH_NO_AUTOMATION_HOSTS` | resolve, fulltext                   | Space-separated hosts the caller forbids any automated request to |
| `OPENALEX_API_KEY`             | resolve, search, snowball, fulltext | OpenAlex key; keyless calls share a small daily budget            |
| `CORE_API_KEY`                 | search, fulltext                    | CORE key; keyless gives metadata only                             |
| `CINII_APPID`                  | search                              | CiNii application id; CiNii is skipped without it                 |
| `S2_API_KEY`                   | snowball                            | Semantic Scholar key; keyless runs at one request every 3 s       |
| `ZOTERO_API_KEY`               | zotero                              | Required for `lit-zotero`                                         |
| `ZOTERO_LIBRARY_ID`            | zotero                              | Required for `lit-zotero`                                         |
| `ZOTERO_LIBRARY_TYPE`          | zotero                              | `users` (default) or `groups`                                     |
| `ZOTERO_COLLECTION_NAME`       | zotero                              | Collection to file into when the request names none               |

No `User-Agent` header is sent by default.

## Data terms

Each skill states, per platform, the license and attribution duty of the
data it fetches, and carries them into its output files. A full text's
license is read from the copy itself, and a copy without an open license is
marked read-only. Platforms whose terms forbid or do not sanction scripted
access are not covered.

## Artifacts

The skills write their records under `AGENT_ARTIFACTS_DIR`, one subdirectory
per skill. When the variable is unset they default to
`.local/data/agentartifacts` under the current working directory.

## Requirements

- `curl` and `jq` for every skill.
- `uv`, for `lit-fulltext`'s `scripts/classify_pdf.py`, which declares its
  dependencies inline.

## Compatibility

| Client                      | Reads                                      |
| --------------------------- | ------------------------------------------ |
| Claude Code                 | `.claude-plugin/plugin.json` and `skills/` |
| Agent Plugins 1.0.0 clients | `plugin.json` and `skills/`                |

## Install

In Claude Code:

```sh
claude plugin marketplace add andreswebs/agent-plugins
claude plugin install scholarly-research@andreswebs
```

For other clients and for project-wide setup, see the
[marketplace README](https://github.com/andreswebs/agent-plugins#install).

## Authors

**Andre Silva** - [@andreswebs](https://github.com/andreswebs)

## License

This project is licensed under the [MIT License](LICENSE).
