# OpenAlex for searching

Base `https://api.openalex.org`. Usage is metered in credits against a
daily budget: a text search, in either the `search=` form or the
`title_and_abstract.search:` filter form, costs 10 credits per page; a
plain filtered list costs 1; a lookup by id is free; errors cost nothing.
Keyless, one network address shares 1,000 credits (0.10 USD) a day, reset
at midnight UTC, at 10 requests a second; a free key gives 10,000 credits
and 30 requests a second. `mailto=` raises no limit any more. Send the key
as `Authorization: Bearer ${OPENALEX_API_KEY}` when set. Read
`X-RateLimit-Remaining` from every response and stop paid calls when it
is below the next call's cost.

## Search

```bash
query="riscos psicossociais trabalho"
lang="pt"
from_year="2018"
to_year="2026"
openalex_auth=()
if [ -n "${OPENALEX_API_KEY:-}" ]; then openalex_auth=(--header "Authorization: Bearer ${OPENALEX_API_KEY}"); fi
curl --silent --max-time 60 --get --dump-header "${RAW}/openalex-1.headers" --output "${RAW}/openalex-1.json" \
    "${openalex_auth[@]}" \
    "https://api.openalex.org/works" \
    --data-urlencode "filter=title_and_abstract.search:${query},language:${lang},publication_year:${from_year}-${to_year}" \
    --data-urlencode "per_page=100" \
    --data-urlencode "select=id,doi,title,publication_year,language,type,open_access,cited_by_count,relevance_score"
grep -i '^x-ratelimit-remaining:' "${RAW}/openalex-1.headers"
jq '{count: .meta.count, cost: .meta.cost_usd, oql: .meta.x_query.oql, url: .meta.x_query.url}' "${RAW}/openalex-1.json"
```

- The colon in the grep matters: the response also carries
  `X-RateLimit-Remaining-USD`, which a prefix match would print too.
- `title_and_abstract.search:` matches title and abstract, stemmed; the
  broad `search=` parameter also matches full text and keywords and
  returns far more (38,058 against 853 for the query above). Use
  `search=` only when the plan asks for full-text matching.
- Filter clauses are joined by `,` (AND); `|` is OR within one attribute
  (up to 100 values). Date bounds: `publication_year:2018-2026`, or
  `from_publication_date:2018-01-01` and `to_publication_date:`. Omit the
  `language:` clause when the plan wants every language.
- Boolean operators inside the search text are uppercase `AND`, `OR`,
  `NOT`; quote phrases; a leading minus does not exclude. Wildcards need
  `search.exact=` or `fulltext.search.exact:`. Whether Portuguese terms
  are stemmed was not tested.
- Japanese terms match poorly in `title_and_abstract.search:` with
  `language:ja`: on 2026-11-26 `ブロードリスニング` returned 0 and
  `広聴AI OR "Kouchou AI"` returned 12 works unrelated to either term
  (hearing aids, audiology, AI in general), while CiNii held the relevant
  records.
- Keep the URL under 4,094 bytes (`400 Request URL too long`).
- Paging: `page=2` with `per_page=100`, each page 10 credits, up to
  10,000 results; past that cursor paging needs a key (`401` keyless).
- A `400` on an unknown filter name returns the full list of valid
  filters in `message`.
- On 429 the per-second limit and the exhausted budget look the same;
  `X-RateLimit-Remaining` tells them apart. A budget 429 ends the source
  for the day: note it and move on.

## Venues

A plan that names journals or proceedings gets a second pass restricted
to them. Find each venue's source records (a text search, 10 credits, so
it is logged):

```bash
venue="Journal of Public Deliberation"
openalex_auth=()
if [ -n "${OPENALEX_API_KEY:-}" ]; then openalex_auth=(--header "Authorization: Bearer ${OPENALEX_API_KEY}"); fi
curl --silent --max-time 60 --get --output "${RAW}/openalex-source-1.json" \
    "${openalex_auth[@]}" \
    "https://api.openalex.org/sources" \
    --data-urlencode "search=${venue}" --data-urlencode "per_page=10" \
    --data-urlencode "select=id,display_name,type,issn_l,issn,works_count,host_organization_name,alternate_titles"
jq --compact-output '.results[] | [(.id | sub("https://openalex.org/"; "")), .display_name,
    .type, .issn_l, .works_count, .alternate_titles]' "${RAW}/openalex-source-1.json"
```

Then rerun the search above with the chosen ids as one more filter
clause, ids joined by `|`:

```text
filter=title_and_abstract.search:<query>,language:en,publication_year:2010-2026,primary_location.source.id:S201710173|S2170549
```

- Choose by name, `type`, `issn_l` and `host_organization_name` against
  what the plan names; `works_count` tells a live record from a stub.
  Several ids may be the one venue; an id that only shares the name is
  left out, and the lookup's log line says which and why.
- A renamed venue may keep one record: on 2026-11-24 a search for the
  former name "Journal of Public Deliberation" returned the single
  record `S4210199091`, displayed as "Journal of Deliberative
  Democracy", with the former name under `alternate_titles`. Search
  both names and merge the ids found.
- Proceedings spread over records of different types: on 2026-11-24 a
  pass over the CHI and CSCW proceedings met four records, two typed
  `conference` ("CHI Conference on Human Factors in Computing Systems",
  `S4363607743`; "ACM Conference on Computer Supported Cooperative Work
  (CSCW)", `S7407086087`) and two typed `journal` ("Proceedings of the
  ACM on Human-Computer Interaction", `S4210183893`; "Computer Supported
  Cooperative Work (CSCW)", `S177586587`, ISSN 0925-9724). Records that
  share a name are told apart by `type`, `issn_l` and host before any is
  chosen.
- A record's `display_name` can differ in case from the venue's own
  spelling: on 2026-11-24 the journal She Ji answered as "She ji"
  (`S2898472644`, ISSN-L 2405-8718), beside three records that share
  only the syllables. `issn_l` and the host organisation decide, not the
  exact name.
- No record for a venue: log the lookup with `hits: 0` and report the
  venue as a coverage gap.
- Log the lookup with `query` the venue name, `url` the `/sources`
  request, `kept_ids` the chosen source ids and `notes` the reason for
  each choice; log each restricted search like any other, its `filters`
  carrying the `primary_location.source.id:` clause and its `notes`
  opening with `venue pass`.

## Hits

```bash
jq --compact-output --arg q "${query}" '.results[] | {
  id: (.id | sub("https://openalex.org/"; "")), id_type: "openalex",
  doi: (if .doi then (.doi | sub("https://doi.org/"; "") | ascii_downcase) else null end),
  title, year: .publication_year, database: "openalex", also_in: [],
  url: (.doi // .id), language, query: $q}' "${RAW}/openalex-1.json"
```

`language` is detected from title and abstract (`pt` for SciELO
articles). OpenAlex misses some SciELO DOIs, so a Portuguese query also
runs on Europe PMC, BDTD and CORE.

## Log

`database: "openalex"`, `hits` from `meta.count`, `url` the request URL
(the key travels in a header, so nothing to strip), `filters` the
`filter` string split into its clauses plus `per_page`, and `notes`
carrying `meta.x_query.oql`, the server's canonical restatement, and the
`X-RateLimit-Remaining` value read after the call.

## Verified

Live on 2026-10-16, keyless, from one network address. The query above
with `language:pt` from 2018 returned 853 in the filter form at 0.001
USD; observed per-call costs were 0 for a singleton, 1 for a list, 10 for
a search. Keyless rate 10 requests a second. The `/sources`
search and the `primary_location.source.id:` filter were run on
2026-11-24: the search cost 10 credits, and a string restricted to
`S201710173|S2170549` returned 34 works.
