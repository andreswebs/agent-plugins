# OpenAlex for snowballing

Base `https://api.openalex.org`. Usage is metered in credits against a
daily budget: a singleton lookup by id is free, a filtered list page costs
1 credit (0.0001 USD), a text search 10. Keyless, one network address
shares 1,000 credits a day, reset at midnight UTC; a free key gives
10,000. `mailto=` is accepted and raises no limit. Send the key as
`Authorization: Bearer ${OPENALEX_API_KEY}` when set. Read
`X-RateLimit-Remaining` from every response and stop paid calls when it
is below the next call's cost; errors cost nothing. Keyless rate: 10
requests per second. Keep every URL under 4,094 bytes.

## Resolve a seed (free)

```bash
seed="doi:10.1590/0102.3772e36nspe19" # or W3108335682
openalex_auth=()
if [ -n "${OPENALEX_API_KEY:-}" ]; then openalex_auth=(--header "Authorization: Bearer ${OPENALEX_API_KEY}"); fi
curl --silent --max-time 30 --output seed.json --write-out '%{http_code}\n' \
    "${openalex_auth[@]}" \
    "https://api.openalex.org/works/${seed}"
jq '{id: (.id | sub("https://openalex.org/"; "")), doi, title, publication_year,
    language, cited_by_count, referenced_works_count,
    referenced_works: [.referenced_works[] | sub("https://openalex.org/"; "")]}' seed.json
```

- 404 with an HTML body: the work is not in OpenAlex (one of two SciELO
  DOIs tried in the lab was absent). A 301 points at a merged survivor;
  follow with `--location`.
- `doi` comes back in the `https://doi.org/` form; strip it. `language`
  is detected from title and abstract (`pt` for SciELO).
- `referenced_works` holds matched references only, so the count can be
  below the printed bibliography.
- A book record can carry a reference list of its own: on 2026-11-25 a
  book on an open-access books platform had `referenced_works_count`
  48 and was walked backward (46 records returned), while Crossref,
  OpenCitations and Semantic Scholar gave 0 references for its DOI.
- A book's own record can carry `referenced_works_count` 0 while a
  record with the same title typed `book-review` carries the book's
  reference list and part of its citations. On 2026-11-24 a 2009
  monograph's record had 2,512 citations and no references, and a
  same-titled `book-review` record had 902 citations and 144
  references. The version search finds such a record. It is a related
  record, never walked in the book's place: report its id and reference
  count, and the book stays not walkable backward (SKILL.md, steps 3
  and 8).
- A review of a book can also be typed `article`. On 2026-11-24 a title
  search for a book seed returned two records of a review of it, both
  typed `article`, with 1 and 2 citations and 0 references. Read the
  titles of same-titled hits: one that carries a review label ("Book
  review", "Resenha", "Review of") or is the book's full citation
  (author, title, publisher, year) is a review whatever its type, and is
  handled as a `book-review` record is.
- Two more shapes, met on 2026-11-24. A review typed `article` can carry
  the book's bare title with the reviewer as first author (`W3037262639`,
  34 citations, beside ten `book-review` records of the same 2019 book):
  it has no review label, and only its first author tells it from the
  book, so step 1 lists it as a probable review. And when a book has no record of its own, the most cited
  same-titled record can be a review that absorbed the book's citations:
  a 1981 law review's review of a 1980 monograph, typed `article`,
  showed 9,131 citations.

## Versions of a seed (10 credits)

```bash
title="Conducting Qualitative Interviews with AI"
openalex_auth=()
if [ -n "${OPENALEX_API_KEY:-}" ]; then openalex_auth=(--header "Authorization: Bearer ${OPENALEX_API_KEY}"); fi
curl --silent --max-time 30 --get --output versions.json --dump-header versions.headers \
    "${openalex_auth[@]}" \
    "https://api.openalex.org/works" \
    --data-urlencode "filter=title.search:\"${title}\"" --data-urlencode "per_page=25" \
    --data-urlencode "select=id,doi,title,type,publication_year,cited_by_count,authorships"
jq -c '.results[] | [(.id | sub("https://openalex.org/"; "")), .doi, .type,
    .cited_by_count, .authorships[0].author.display_name, .title]' versions.json
```

- `title.search` is a text search: 10 credits a call against 1 for a
  filter page (observed 2026-11-13 from `X-RateLimit-Remaining`). It is a
  list query, so it gets a search-log line.
- Matching is stemmed (`meta.x_query.oql` reads `stemmed "…" in the
  title`), so a longer title holding the phrase also matches; the
  title-and-first-author rule in the steps decides what is a version.
- On 2026-11-13 the title above returned three works by the same two
  authors: a 2023 SSRN preprint (`preprint`, 34 citing), a 2026 CESifo
  paper (`report`, 38 citing) and a trial registration
  (`study-registration`, 1 citing). The first two are versions with
  separate citation sets; the third is a related record. A replication
  package for another seed came back typed `dataset`.
- A version OpenAlex merged answers on its own DOI with the survivor's
  record: `works/doi:10.2139/ssrn.4974382` returned `W7213491390`, whose
  `doi` is the journal article's. The caller's DOI is still the one the other
  services may know the work by (SKILL.md, step 1).

## Forward: works that cite the seed (1 credit per page)

```bash
work_id="W3108335682"
openalex_auth=()
if [ -n "${OPENALEX_API_KEY:-}" ]; then openalex_auth=(--header "Authorization: Bearer ${OPENALEX_API_KEY}"); fi
curl --silent --max-time 30 --get --output citing.json --dump-header citing.headers \
    "${openalex_auth[@]}" \
    "https://api.openalex.org/works" \
    --data-urlencode "filter=cites:${work_id}" --data-urlencode "per_page=100" \
    --data-urlencode "page=1" \
    --data-urlencode "select=id,doi,title,publication_year,language,type,cited_by_count"
jq '{count: .meta.count, page: .meta.page, n: (.results | length),
     oql: .meta.x_query.oql}' citing.json
grep -i '^x-ratelimit-remaining:' citing.headers
```

- The colon in the grep matters: `X-RateLimit-Remaining-USD` is also
  sent and a prefix match prints both.
- The record's `cited_by_count` can exceed the `cites:` list's
  `meta.count` (715 against 671, 309 against 290 and 341 against 335 on
  2026-11-12), and paging can collect fewer than `meta.count`; a gap is
  a finding, noted beside the OpenAlex cell of the counts table.
- `cites:` is an alias the server rewrites to `referenced_works:` in
  `meta.x_query.url`; log `meta.x_query.oql`, the canonical restatement.
- Basic paging: `page` times `per_page` must not exceed 10,000;
  `page=2` works keyless. Beyond 10,000 results use `cursor=*` and follow
  `meta.next_cursor`; the first cursor page works keyless, following
  `next_cursor` answers `401 "API key required for cursor paging"`
  without `OPENALEX_API_KEY`. Stop on an empty page or a null cursor.
- A 401 on `cursor=` means "key required", not "key invalid". A per-second
  429 and a budget 429 look the same; `X-RateLimit-Remaining` tells them
  apart.

## Backward: the seed's references, 100 ids per call (1 credit)

```bash
ids="$(jq --raw-output '[.referenced_works[] | sub("https://openalex.org/"; "")] | .[0:100] | join("|")' seed.json)"
openalex_auth=()
if [ -n "${OPENALEX_API_KEY:-}" ]; then openalex_auth=(--header "Authorization: Bearer ${OPENALEX_API_KEY}"); fi
curl --silent --max-time 30 --get --output refs.json \
    "${openalex_auth[@]}" \
    "https://api.openalex.org/works" \
    --data-urlencode "filter=openalex_id:${ids}" --data-urlencode "per_page=100" \
    --data-urlencode "select=id,doi,title,publication_year,language,type,cited_by_count"
jq '{count: .meta.count, returned: (.results | length)}' refs.json
```

- `openalex_id:`, `openalex:` and `ids.openalex:` are aliases; the
  server echoes `ids.openalex:`. `|` ORs up to 100 values within one
  attribute; chunk longer lists and union locally.
- Fewer records than ids sent is normal: 49 ids returned 48 in the lab,
  the gap being merged or deleted works. Note the missing ids.
- Several DOIs resolve the same way with `filter=doi:a|b|c`; fewer results
  than DOIs means two DOIs map to one work or some are absent.

## Fields used

`id` (`https://openalex.org/W…`, strip the prefix for filters), `ids`
(`openalex`, `doi`, `mag`, `pmid`, `pmcid`), `doi`, `title`,
`publication_year`, `language` (ISO 639-1 or null), `type`,
`cited_by_count`, `referenced_works`, `referenced_works_count`,
`meta.count`, `meta.next_cursor`, `meta.cost_usd`, `meta.x_query.oql`.
Headers: `X-RateLimit-Remaining`, `X-RateLimit-Reset` (seconds to
midnight UTC), `X-RateLimit-Credits-Used`.

## Verified

Live on 2026-10-16, keyless, from one network address. Observed costs:
singleton 0, list page 1 credit. `cites:W3108335682` and the 49-id
`openalex_id:` batch were run; `cited_by_api_url` on the record and
`pmid:` lookups were read in the docs only.
