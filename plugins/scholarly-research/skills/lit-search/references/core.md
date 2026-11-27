# CORE for searching

Base `https://api.core.ac.uk/v3`. The search path ends with a slash
(`/search/works/`); without it the API answers `301`. Keyless access is
10 requests a minute and 100 tokens a day, a simple query costing one
token, and the `fullText` field is the string "Not available for public
API users." A key (requested by email form, never by API) raises the day
to 1,000 or 5,000 tokens and unlocks full text; send it as
`Authorization: Bearer ${CORE_API_KEY}`. Every response carries
`X-RateLimit-Limit`, `X-RateLimit-Remaining` and `X-RateLimit-Retry-After`;
stop for the minute when remaining reaches 0. Six seconds between calls
keeps under the keyless minute.

CORE aggregates repositories and OJS portals, among them hundreds of
Brazilian ones (LAReferencia, SciELO's OAI feed, BDTD, USP theses,
Fiocruz Arca, Lume UFRGS, university periodical portals), and reports a
`language.code` per work, so it reaches theses and small journals that
OpenAlex misses. About half its works have no DOI.

## Search

```bash
query='title:"participação social"'
lang="pt"
from_year="2018"
to_year="2026"
core_auth=()
if [ -n "${CORE_API_KEY:-}" ]; then core_auth=(--header "Authorization: Bearer ${CORE_API_KEY}"); fi
curl --silent --max-time 60 --get --dump-header "${RAW}/core-1.headers" --output "${RAW}/core-1.json" \
    "${core_auth[@]}" \
    "https://api.core.ac.uk/v3/search/works/" \
    --data-urlencode "q=(${query}) AND yearPublished>=${from_year} AND yearPublished<=${to_year} AND language.code:${lang}" \
    --data-urlencode "limit=100" --data-urlencode "offset=0" --data-urlencode "exclude=fullText"
grep -i '^x-ratelimit-remaining:' "${RAW}/core-1.headers"
jq '{totalHits, returned: (.results | length), searchId}' "${RAW}/core-1.json"
```

- Query language: `field:value`, quoted phrases, `AND`, `OR`,
  parentheses, `>` `>=` `<` `<=` on numbers and dates, `_exists_:field`.
  An unfielded term searches every searchable field; unquoted words match
  any or all of them. Searchable work fields include `title`, `abstract`,
  `authors`, `doi`, `yearPublished`, `publishedDate`, `documentType`,
  `publisher`, `dataProviders` (by id).
- `language.code:` is undocumented but worked for `pt` (815 hits became
  346), and for `en` on 2026-11-24 (three English strings returned
  1,073, 319 and 753 works with the clause); `ja` was not exercised. It selects the language, not the
  country: a `pt` query returned Portuguese institutions first (92 hits on
  a COPSOQ validation string, almost all from Portugal, on 2026-11-10).
  Narrow by `dataProviders` or filter after the fact when Brazilian
  material is wanted.
- `limit` up to 100 is documented only for the provider-outputs route and
  was not tested on `/search/`; the result window stops at 10,000 and
  `scroll` is gone (`scrollId: null`). Page with `offset`; split a large
  pull by year.
- `429` arrives with an empty HTML body and an `X-RateLimit-Retry-After`
  timestamp that ran ten minutes ahead of reality; sleep 10 s and retry
  once, then wait for the timestamp. `401` means the key, not the quota.

## Hits

```bash
jq --compact-output --arg q "${query}" '.results[] | {
  id: (.id | tostring), id_type: "core",
  doi: (if .doi then (.doi | ascii_downcase) else null end),
  title, year: .yearPublished, database: "core", also_in: [],
  url: (if .doi then "https://doi.org/\(.doi | ascii_downcase)"
        else ([.links[]? | select(.type == "display") | .url][0] // null) end),
  language: (.language.code // null), query: $q}' "${RAW}/core-1.json"
```

`doi` is bare; `documentType` (`thesis`, `journal article`, `research`)
tells grey literature apart. `citationCount` is a frozen Microsoft
Academic number: never a citation signal.

## Log

`database: "core"`, `hits` from `totalHits`, `url` the request URL with
any `api_key` value removed (none when the key travels in the header),
`filters` the year bounds, `language.code`, `limit` and `offset`, `notes`
carrying `searchId` and the `X-RateLimit-Remaining` value.

## Duties

Individuals may use the API under the terms; a research project at a
non-member institution is asked to contact CORE for a license. PDF
harvesting that bypasses the API, or from `fileserver-az.core.ac.uk`,
gets keys disabled; `downloadUrl` sits behind a browser challenge for
scripts anyway. This skill reads metadata only.

## Verified

Live on 2026-10-16 and 2026-10-17, keyless, from one network address,
about 20 calls; `X-RateLimit-Limit: 10` observed. `title:"participação
social" AND yearPublished>=2020` gave 815, with `language.code:pt` 346.
On 2026-11-24, with a key, seven searches six seconds apart each answered
200, and `X-RateLimit-Remaining` read 9 or 10 after every call: the header
counts the per-minute window, not the day's tokens.
