# OpenAlex for resolving

Base `https://api.openalex.org`. Usage is metered in credits against a
daily budget: a singleton lookup by id is free, a filtered list costs 1
credit, a text search 10. Keyless, one network address shares 1,000
credits (0.10 USD) a day, reset at midnight UTC; a free key gives 10,000.
The old `mailto` polite pool raises no limit any more. Send the key as
`Authorization: Bearer ${OPENALEX_API_KEY}` when set. Read
`X-RateLimit-Remaining` from every response and stop paid calls when it
is below the next call's cost. Errors cost nothing.

## Lookup by DOI (free)

```bash
openalex_auth=()
if [ -n "${OPENALEX_API_KEY:-}" ]; then openalex_auth=(--header "Authorization: Bearer ${OPENALEX_API_KEY}"); fi
curl --silent --max-time 30 --output oa.json --write-out '%{http_code}\n' \
    "${openalex_auth[@]}" \
    "https://api.openalex.org/works/doi:${doi}"
jq '{id: (.id | sub("https://openalex.org/"; "")), ids, language, type,
    publication_year, cited_by_count, referenced_works_count,
    is_oa: .open_access.is_oa, oa_status: .open_access.oa_status,
    oa_url: .open_access.oa_url,
    best: (.best_oa_location | {pdf_url, landing_page_url, license, version}),
    has_abstract: (.abstract_inverted_index != null)}' oa.json
```

- 404 with an HTML body: the work is not in OpenAlex. OpenAlex misses some
  SciELO DOIs (one of two tried in the lab); note the absence and move on.
  A 301 points at a merged survivor; follow with `--location`.
- Other id forms on the same route: `https://doi.org/…`, `pmid:…`, `W…`.
- Several DOIs at once: `filter=doi:a|b|c` (up to 100, one credit).
- `language` is detected from title and abstract (`pt` for SciELO).
- `oa_status` includes `diamond` for no-fee gold, a value Unpaywall does
  not emit; `best_oa_location.version` is `publishedVersion`,
  `acceptedVersion` or `submittedVersion`.
- A dataset has `type: dataset` (W2582743722 on 2026-11-24, with no
  `primary_location.source`).
- `type` is OpenAlex's own word (`article`, `preprint`,
  `conference-paper` and 22 others), not the record format's: a record
  resolved by OpenAlex alone translates it through the table in
  [record.md](record.md).
- `referenced_works` holds matched references, so the count can be below
  the printed bibliography.

## Rebuild the abstract

```bash
python3 -I - oa.json <<'EOF'
import json, sys
work = json.load(open(sys.argv[1], encoding="utf-8"))
inv = work.get("abstract_inverted_index") or {}
positions = sorted((pos, word) for word, poss in inv.items() for pos in poss)
print(" ".join(word for _, word in positions))
EOF
```

Empty output means no abstract. A few abstracts carry trailing non-abstract
text.

## Title search (10 credits; only when Crossref found nothing)

```bash
openalex_auth=()
if [ -n "${OPENALEX_API_KEY:-}" ]; then openalex_auth=(--header "Authorization: Bearer ${OPENALEX_API_KEY}"); fi
curl --silent --max-time 30 --get --output search.json "https://api.openalex.org/works" \
    "${openalex_auth[@]}" \
    --data-urlencode "search=${title}" --data-urlencode "per_page=3" \
    --data-urlencode "select=id,doi,title,publication_year,relevance_score"
jq '{count: .meta.count, cost: .meta.cost_usd, oql: .meta.x_query.oql, hits: .results}' search.json
```

Log `meta.x_query.oql`, the server's canonical restatement of the query.
Keep the URL under 4,094 bytes.

## Verified

Live on 2026-10-16, keyless. Keyless rate: 10 requests per second.
