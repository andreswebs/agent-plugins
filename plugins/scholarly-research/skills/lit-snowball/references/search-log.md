# The search log

Every search a research skill runs appends one JSON line to the file named
by `RESEARCH_SEARCH_LOG`, or, when it is unset, to the skill's own file
under the artifacts root. A search is any call whose results depend on a
query, a filter or a date window; a lookup by identifier is not a search
and is recorded in the resolved record's `sources` instead.

```json
{"ts": "2026-10-19T04:07:35Z", "operator": "agent", "skill": "lit-snowball", "database": "crossref", "interface": "api", "query": "Fatores de Risco e Riscos Psicossociais no Trabalho", "filters": {"rows": 3}, "url": "https://api.crossref.org/works?query.bibliographic=...&rows=3", "hits": 10343237, "kept": 1, "kept_ids": ["10.1590/0102.3772e36nspe19"], "export": null, "notes": "score 69.6 against 53.7"}
```

| Field       | Value                                                                                                   |
| ----------- | ------------------------------------------------------------------------------------------------------- |
| `ts`        | UTC, `YYYY-MM-DDTHH:MM:SSZ`, when the request was sent                                                  |
| `operator`  | `agent` or `human`                                                                                      |
| `skill`     | the skill that ran the search, or `manual`                                                              |
| `database`  | `crossref`, `openalex`, `unpaywall`, `europe-pmc`, `core`, `arxiv`, `bdtd`, `cinii`, `scielo`, `scielo-preprints`, `opencitations`, `semantic-scholar`, `zotero`, `querido-diario`, `ibge`, `web` (a general web search the agent ran) |
| `interface` | `api`, `oai-pmh`, `web`, `export`                                                                       |
| `query`     | the search string as sent, or the filter expression when there is no free text                          |
| `filters`   | an object of every narrowing parameter (dates, language, type, set, rows); `{}` when none               |
| `url`       | the full request URL with `email`, `mailto`, `api_key` and `appid` values removed                       |
| `hits`      | the service's total count for the query; `null` when the service gives none                             |
| `kept`      | how many results this run kept                                                                          |
| `kept_ids`  | the identifiers kept (DOIs, OpenAlex ids, PIDs, URLs); `[]` when none                                         |
| `export`    | path of any export file written for this search, relative to the working directory; `null` otherwise       |
| `notes`     | free text: the score gap, a cap hit, a throttle, why a result was dropped                               |

A web search, run with whatever web search capability the environment
offers, is logged like any other: `database: "web"`, `interface: "web"`,
`query` exactly as sent (with any `site:` restriction), `url` the search
URL when the tool exposes one and `null` otherwise, `hits` the number of
results the tool returned, and the kept URLs in `kept_ids`.

A search that returned nothing is logged like any other, with `hits: 0`.
Any human-readable log the caller keeps is written from this record by
the caller, not by the skill.
