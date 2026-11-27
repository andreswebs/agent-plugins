---
name: ibge-stats
description: "Pull official municipal statistics for a Brazilian municipality from IBGE's keyless APIs: resolve a municipality name to its 7-digit IBGE code, then read values from SIDRA tables and the agregados v3 API as JSONL with the exact request URL per value. Use when a research step needs a municipality's IBGE code, its population, labour or education figures, or any named SIDRA table read for one or more municipalities."
metadata:
  argument-hint: "a municipality name with its state, and the topics or SIDRA table numbers wanted"
---

# ibge-stats

```bash
AGENT_ARTIFACTS_DIR="${AGENT_ARTIFACTS_DIR:-${PWD}/.local/data/agentartifacts}"
mkdir -p "${AGENT_ARTIFACTS_DIR}/ibge-stats" && echo "${AGENT_ARTIFACTS_DIR}/ibge-stats"
date -u +%Y%m%dT%H%M%SZ
```

Run this once when the run opens, and use the two printed values, the
directory and the run's `<UTC>` stamp, for every path below.

A municipality and a list of topics or table numbers in, one **value**
line out per figure: the shape in [references/value.md](references/value.md),
read from IBGE's three keyless APIs described in
[references/ibge.md](references/ibge.md): localidades (name to code),
agregados v3 (table catalogue, metadata, and a nested values form) and
SIDRA (the flat values form, the default). IBGE is the only source this
skill calls; [references/other-portals.md](references/other-portals.md)
says why dados.gov.br and INEP are out of reach. Every query is logged as
[references/search-log.md](references/search-log.md) describes.

## Environment

| Variable                 | Used for                           | When unset                                                                              |
| ------------------------ | ---------------------------------- | --------------------------------------------------------------------------------------- |
| `RESEARCH_SEARCH_LOG`    | JSONL file every search appends to | `${AGENT_ARTIFACTS_DIR}/ibge-stats/<slug>.<UTC>.search.jsonl`, and the reply names it   |

Set once per run; values never go into a file:

```bash
IBGE_API="https://servicodados.ibge.gov.br/api"
SIDRA_API="https://apisidra.ibge.gov.br/values"
```

Every call: one request at a time, `curl --silent --globoff --max-time 60` (`--globoff`
keeps the `[]` and `|` of agregados URLs literal), exponential backoff of
1, 2, 4, 8 s on 429 and 5xx, no retry on 400. An agregados 500 with the
body `Internal server error` means an unknown table id: check the id
before retrying. Nothing is written over; every file is a new stamped one.

## Steps

1. **Resolve the municipality.** Take the state's two-digit code from
   `/v1/localidades/estados` (SP is `35`), list
   `/v1/localidades/estados/<uf>/municipios` and select the entry whose
   `nome` equals the input, case and accents folded; then read
   `/v1/localidades/municipios/<code>` for the hierarchy. A 7-digit input
   is already a code and goes straight to the hierarchy call. Done when
   every municipality has a 7-digit code and a hierarchy record, or is
   marked `ambiguous` with the candidate codes and states.
2. **Choose the tables.** Population, labour and formal employment use
   the tables and ids pinned in `references/ibge.md`; a table the user
   names is used as given; education and any other topic are found by
   filtering the agregados catalogue by survey and keyword. For every
   table read `/v3/agregados/<table>/metadados` and `/periodos`: keep the
   variable ids and units, each classification's `Total` category id, and
   the period list; `N6` must appear under `nivelTerritorial.Administrativo`.
   Done when every topic has a table number, variable ids, total ids and
   periods, or a note that no municipal table was found for it.
3. **Size each query.** Multiply the counts of territories, variables,
   periods and categories selected; a query above 100,000 values is
   refused, so split by period, variable or territory until each URL is
   under the cap, and sleep one second between the parts. Done when every
   planned URL has a computed count below 100,000.
4. **Pull the values.** SIDRA by default, per `references/ibge.md`:
   `/t/<table>/n6/<code>/v/<vars>/p/<periods>/c<class>/<cats>`, with
   `n1/all` or `n3/<uf code>` before `n6` when a national or state figure
   is wanted beside the municipal one, saved to
   `${AGENT_ARTIFACTS_DIR}/ibge-stats/<slug>.<UTC>.<table>.sidra.json`.
   Use the agregados form `/v3/agregados/<table>/periodos/<p>/variaveis/<v>`
   when the user asks for it or to cross-check a SIDRA figure; the two
   forms return the same value. Done when every planned URL has a saved
   response with status 200, or a note carrying the status and body.
5. **Emit the values.** Strip SIDRA's header record (element 0), then
   write one line per value in the shape of `references/value.md` to the
   path the user named or to
   `${AGENT_ARTIFACTS_DIR}/ibge-stats/<slug>.<UTC>.values.jsonl`, `<slug>`
   naming the municipality. Every line carries the territory's level
   and name from the response; a row for a territory other than a
   municipality (a URL that adds `n1` or `n3` for comparison) is written
   to the same file. `V` is a string: a number becomes
   `value_number`; `-`, `0`, `X`, `..`, `...` or a letter becomes `flag`
   with `value_number` null. Done when every record of every saved
   response has a value line carrying its exact request URL.
6. **Log and report.** Append one search-log line (`database` `ibge`,
   `interface` `api`) for the name resolution, for each catalogue keyword
   filter, and for each values URL, with `hits` the record count and
   `kept_ids` the table ids; print both paths and, per municipality, its
   code and the headline figures. Done when every query has a log line
   and the reply names the values file and the log file.

Attribution carried by the values: IBGE data is public, keyless and free
of charge; the guide this skill distils recorded no license text, so a
published figure names IBGE, the survey and table (as
`sidra.ibge.gov.br/tabela/<table>`), the variable, period and territory,
and the request URL with the date retrieved, which is what each value
line holds.
