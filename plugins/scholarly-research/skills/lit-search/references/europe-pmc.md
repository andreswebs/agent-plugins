# Europe PMC for searching

Base `https://www.ebi.ac.uk/europepmc/webservices/rest`; keyless, no
quota documented, no rate-limit header. The `email` parameter is a
mailing-list sign-up, not a polite pool; leave it out. Always pass
`format=json` (the default is XML). One request a second; a `503` on a
page happened once in the lab and the retry succeeded. Application errors
arrive as HTTP 200 with `{"errCode":404,"errMsg":"..."}` (bad `pageSize`,
empty query, query over 1,500 characters), so test every body with
`jq --exit-status '.errCode // empty'`. An unknown field name gives `hitCount: 0`
without an error. `{"errCode":503,"errMsg":"Search service is temporarily
unavailable. Please retry later."}` also arrives as HTTP 200: it is a
transient server error, treated like a 5xx (backoff and retry), and each
failed call is still a search for the log, with `hits: null` and the
error in `notes`. On 2026-11-26 two calls in a row answered it and the
third, after a 4 s wait, answered with hits.

One index covers MEDLINE abstracts (`SRC:MED`), PubMed Central full text
(`PMC`) and preprints harvested from Crossref (`PPR`), among them SciELO
Preprints. It is the only source in this skill that indexes SciELO
Preprints as first-class records. The Portuguese MEDLINE slice is small
(91,993 records; 6,075 since 2020) because most SciELO journals are not
in MEDLINE, and two of three SciELO DOIs tried were absent.

## Search

```bash
query='saúde mental'
from_year="2020"
to_year="2026"
curl --silent --max-time 60 --get --output "${RAW}/epmc-1.json" \
    "https://www.ebi.ac.uk/europepmc/webservices/rest/search" \
    --data-urlencode "query=TITLE_ABS:(${query}) AND PUB_YEAR:[${from_year} TO ${to_year}] AND LANG:por" \
    --data-urlencode "resultType=lite" --data-urlencode "format=json" \
    --data-urlencode "pageSize=100" --data-urlencode "sort=CITED desc"
jq --exit-status '.errCode // empty' "${RAW}/epmc-1.json" && echo "application error" >&2
jq '{version, hitCount, n: (.resultList.result | length), request}' "${RAW}/epmc-1.json"
```

- Syntax: bare terms are ANDed; `OR` and `NOT` uppercase; parentheses;
  double quotes for phrases; trailing `*` wildcard; `FIELD:value`;
  ranges `[A TO B]`. Free-text terms fold diacritics (`participação` and
  `participacao` give the same count); quoted field values do not fold a
  journal name's `&`.
- `LANG:por` selects MEDLINE-language Portuguese; `LANG:` takes ISO 639-2
  codes and only `por` was exercised. For an English query send no `LANG`
  clause. `TITLE:"..."` restricts to the title; `FIRST_PDATE:[2024-01-01
  TO 2024-12-31]` bounds by date instead of year.
- The query goes inside `TITLE_ABS:(...)` by default, restricting the
  match to title and abstract like the other services. The reason: a bare
  query also matches the full-text body of PMC articles, so top hits
  sorted by citations can be papers that only mention the terms; a
  three-clause string gave 1,045 hits bare and 1 inside `TITLE_ABS:(...)`
  (2026-11-11). Send the bare form only when the plan explicitly asks for
  mentions in full text, and say so in the log line's `notes`.
- `pageSize` 1 to 1,000; `page=` is ignored on `search`. More than one
  page: send `cursorMark=*`, then each response's `nextCursorMark`, with
  a fixed `sort`, until a page is short or the cursor repeats.
- `synonym=true` expands with MeSH synonyms; `resultType=core` adds
  `abstractText`, `language` and `fullTextUrlList` at a heavier payload.

## SciELO Preprints

Preprints carry `language: null`, so `LANG:por` zeroes them; select the
server by publisher instead. Run this as a second query for every
Portuguese string.

```bash
curl --silent --max-time 60 --get --output "${RAW}/epmc-ppr-1.json" \
    "https://www.ebi.ac.uk/europepmc/webservices/rest/search" \
    --data-urlencode "query=SRC:PPR AND PUBLISHER:\"SciELO Preprints\" AND TITLE_ABS:(${query}) AND PUB_YEAR:[${from_year} TO ${to_year}]" \
    --data-urlencode "resultType=lite" --data-urlencode "format=json" \
    --data-urlencode "pageSize=100" --data-urlencode "sort=P_PDATE_D desc"
```

Their DOIs sit under `10.1590/scielopreprints.`; ids are `PPR` plus
digits.

## Hits

```bash
jq --compact-output --arg q "${query}" --arg lang "pt" '.resultList.result[] | {
  id: "\(.source)/\(.id)", id_type: "europe-pmc",
  doi: (if .doi then (.doi | ascii_downcase) else null end),
  title, year: (.pubYear | tonumber? // null), database: "europe-pmc", also_in: [],
  url: (if .doi then "https://doi.org/\(.doi | ascii_downcase)" else null end),
  language: (if $lang == "" then null else $lang end), query: $q}' "${RAW}/epmc-1.json"
```

Pass `--arg lang ""` for the preprint query and for English queries sent
without a `LANG` clause: the lite record carries no language field.

## Log

`database: "europe-pmc"`, `hits` from `hitCount`, `url` the request URL,
`filters` the year range, the `LANG` or `PUBLISHER` clause, `resultType`,
`sort` and `pageSize`, `notes` carrying the response `version` and, for
the second Portuguese query, `SciELO Preprints slice`.

## Verified

Live on 2026-10-17, API version 6.9, from one network address, no rate
limit met over twelve back-to-back calls. `TITLE:"saúde mental"` gave 541;
with `PUB_YEAR:[2020 TO 2026]` 207; with `LANG:por` 86. `SRC:PPR AND
PUBLISHER:"SciELO Preprints"` gave 4,941, all 2020 to 2026.
