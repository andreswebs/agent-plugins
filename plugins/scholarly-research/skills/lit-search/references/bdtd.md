# BDTD for searching

The Biblioteca Digital Brasileira de Teses e Dissertações, IBICT's
aggregator of Brazilian university theses, served by a VuFind 7.1.1
portal: API base `https://bdtd.ibict.br/vufind/api/v1`, no key, JSON out.
It holds metadata only (`masterThesis` and `doctoralThesis`, almost all
`por`); the PDF lives in the institution's repository behind
`urls[0].url`. No OAI-PMH (the server answers "OAI Server Not
Configured."), no DOIs worth relying on, no citation data, and no result
beyond position 1,000.

The host blocks after bursts. Observed: a front proxy answered `429` with
no `Retry-After` to a request carrying three `filter[]` and four
`field[]` values while simpler requests succeeded, and after about 150
requests in 20 minutes every `*.ibict.br` host stopped completing TCP
connections for at least 40 minutes. Pace one request every 4 to 5 s, no
more than a few dozen per session, at most two `filter[]` plus a handful
of `field[]` per call; on a 429 stop the source for the run rather than
retry; on connection timeouts stop for the day and record it. Errors
also come as HTTP 200 with `{"status":"ERROR","statusMessage":"..."}`.
A front-end `503` with an HTML body ("No server is available to handle
this request") is a transient 5xx: the general backoff applies, and the
first retry after 2 s returned the JSON answer (observed 2026-11-12).
Check the body is JSON before mapping hits.
The web search page is disallowed by `robots.txt`; the API is the only
route.

## Search

```bash
query="participação social"
from_year="2020"
to_year="2026"
curl --silent --max-time 60 --get --output "${RAW}/bdtd-1.json" --write-out '%{http_code}\n' \
    "https://bdtd.ibict.br/vufind/api/v1/search" \
    --data-urlencode "lookfor=${query}" --data-urlencode "type=AllFields" \
    --data-urlencode "filter[]=publishDate:[${from_year} TO ${to_year}]" \
    --data-urlencode "sort=relevance" --data-urlencode "limit=100" --data-urlencode "page=1" \
    --data-urlencode "field[]=id" --data-urlencode "field[]=title" \
    --data-urlencode "field[]=publicationDates" --data-urlencode "field[]=urls" \
    --data-urlencode "field[]=languages"
jq '{status, resultCount, n: (.records | length)}' "${RAW}/bdtd-1.json"
```

- `lookfor` takes Lucene syntax (`AND`, `OR`, `NOT`, quotes,
  `field:value`); `type` picks the handler: `AllFields`, `Title`,
  `Author`, `Subject`, `Abstract`, `year`.
- Filters are `filter[]=field:value`, ANDed; `~field` for OR, `-field`
  for NOT. Verified fields: `publishDate` (year or `[2020 TO 2024]`),
  `institution` (acronym such as `USP`), `format`, `language` (`por`,
  `eng`, `spa`, `fra`). A Portuguese string needs no language filter; the
  index is Portuguese.
- `limit` at most 100; `page` from 1. Pages past position 1,000 silently
  repeat page 10 with `status: OK`, so a query whose `resultCount`
  exceeds 1,000 is partitioned (institution plus year) before paging,
  or capped at what the plan asked for.
- `sort` takes `relevance` or `year` (newest first). A search whose
  `resultCount` exceeds the cap sends `sort=relevance`, so the records
  kept are the best matches, and its log line carries the sort sent and
  the total. An unknown `sort` value is not refused: it answers in
  relevance order with `status: OK` (observed 2026-11-24), so the log
  records the value sent, not one inferred from the answer.
- Unknown `field[]` names are dropped silently: check the keys came back.
- `limit=0` with `facet[]=institution` or `publishDate` gives counts
  without records, 30 values per facet.

## Hits

```bash
jq --compact-output --arg q "${query}" '.records[]? | {
  id, id_type: "bdtd", doi: null, title,
  year: (.publicationDates[0] | tonumber? // null), database: "bdtd", also_in: [],
  url: (.urls[0].url // null),
  language: ({por: "pt", eng: "en", spa: "es", fra: "fr"}[.languages[0] // ""] // .languages[0] // null),
  query: $q}' "${RAW}/bdtd-1.json"
```

A zero-result answer is `{"resultCount":0,"status":"OK"}` with no
`records` key (observed 2026-11-10), hence the `?` above.

A record can carry `languages: []` (observed 2026-11-10); the `// ""`
keeps the language lookup from indexing the map with null, which stops jq
with "Cannot index object with null" and drops the rest of the page.

Record ids are `<network acronym>_<32 hex>`; the record page is
`https://bdtd.ibict.br/vufind/Record/<id>`. The default `authors` field
carries Lattes profile URLs per name; this skill does not request it and
a hit never copies one. `rawData` (advisor, program, CNPq area, rights,
defense date) is for a later record step, not for searching.

## Log

`database: "bdtd"`, `hits` from `resultCount`, `url` the request URL
after encoding (`--write-out '%{url_effective}'`), `filters` the `filter[]`
values, `type`, `sort`, `limit` and `page`, `notes` carrying the HTTP
status and any 429 or timeout that stopped the source. When
`resultCount` exceeds the cap, `notes` also says so with both numbers
and the sort (`cap hit: kept 100 of 274, sort relevance`).

## Verified

Live on 2026-10-17 from one address, unauthenticated, VuFind 7.1.1.
`participação social` matched 28,665 records (28,464 `por`); `limit=500`
answered "Invalid limit"; pages 11 and 12 at `limit=100` equalled page
10. The 429 trigger was not isolated because the host then blocked the
address. On 2026-11-24 one query of 134 results answered in a different
order under `sort=relevance` and `sort=year`, the latter newest first.
