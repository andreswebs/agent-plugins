# Semantic Scholar for snowballing

Base `https://api.semanticscholar.org/graph/v1`. Keyless calls share one
throttled pool: 429s were observed even at one request every 3 s, with
no `Retry-After` and no rate-limit headers, so keep one request in flight,
3 s apart, and back off 1, 2, 4, 8 s on 429; every 429 in the lab cleared
within three attempts. With `S2_API_KEY`, sent as the case-sensitive
header `x-api-key`, the rate is 1 request per second on every endpoint. A
key is granted by a human-reviewed form; the skill never requests one. A
wrong key answers 403. Documentation URLs spend the same budget.

What it adds: per-citation sentence `contexts`, `intents` (such as
`methodology` or `background`) and an `isInfluential` flag, present only
where the citing paper's full text was parsed, so they are often empty
arrays. What it lacks: any language field or filter; abstracts for
Springer titles.

## Counts

```bash
doi="10.18653/v1/N18-3011"
s2_auth=()
if [ -n "${S2_API_KEY:-}" ]; then s2_auth=(--header "x-api-key: ${S2_API_KEY}"); fi
curl --silent --max-time 30 "${s2_auth[@]}" --output paper.json --write-out '%{http_code}\n' \
    "https://api.semanticscholar.org/graph/v1/paper/DOI:${doi}?fields=title,year,citationCount,referenceCount,influentialCitationCount,externalIds"
jq '{paperId, title, year, citationCount, referenceCount, influentialCitationCount, doi: .externalIds.DOI}' paper.json
```

Id prefixes accepted in the path: none (a 40-hex Semantic Scholar sha),
`DOI:`, `ARXIV:`, `PMID:`, `PMCID:`, `MAG:`, `ACL:`, `CorpusId:`, `URL:`.
DOIs go raw, slashes included. Without `fields` only `paperId` and
`title` come back. A 404 means the paper is unknown. A 429 body is
`{"message": "...", "code": "429"}`.

Seeds are looked up by identifier only. A title match
(`paper/search/match`) for a document with no DOI can land on a work
that names the document in its own title: on 2026-11-11 the titles of
two guidance documents matched a later article analysing one
(`citationCount` 304) and a commentary on the other, whose counts would
have stood in for the documents' own. A match is the document only when
its title is the document's own title, not one that quotes it.

## Forward and backward, with contexts

```bash
offset=0
s2_auth=()
if [ -n "${S2_API_KEY:-}" ]; then s2_auth=(--header "x-api-key: ${S2_API_KEY}"); fi
curl --silent --max-time 30 "${s2_auth[@]}" --output cits.json \
    "https://api.semanticscholar.org/graph/v1/paper/DOI:${doi}/citations?fields=title,year,externalIds,contexts,intents,isInfluential&offset=${offset}&limit=1000"
jq '{offset, next, n: (.data | length)}' cits.json
jq --compact-output '.data[] | {id: .citingPaper.paperId, doi: .citingPaper.externalIds.DOI,
      title: .citingPaper.title, year: .citingPaper.year, contexts, intents, isInfluential}' cits.json

curl --silent --max-time 30 "${s2_auth[@]}" --output refs.json \
    "https://api.semanticscholar.org/graph/v1/paper/DOI:${doi}/references?fields=title,year,externalIds,contexts,intents,isInfluential&offset=${offset}&limit=1000"
jq --compact-output '.data[] | {id: .citedPaper.paperId, doi: .citedPaper.externalIds.DOI,
      title: .citedPaper.title, year: .citedPaper.year, contexts, intents, isInfluential}' refs.json
```

- Citation items are `{contexts, intents, isInfluential, citingPaper}`,
  reference items the same with `citedPaper`; the references response
  also carries `citingPaperInfo` for the seed. `contextsWithIntent` pairs
  each context with its intents.
- Paging: `next` is present while more remain; set `offset` to it.
  `limit` is at most 1000 and `offset + limit` must stay below 10,000, so
  a seed with more than 10,000 citations cannot be walked completely
  here; the 400 body names the violated limit verbatim. Note the cap and
  the number retrieved. `year=2016-2020` or
  `publicationDateOrYear=2016-03-05:2020-06-06` slices a walk.
- A cited or citing paper without `externalIds.DOI` is kept in the edge
  by its `paperId` and becomes a candidate with `doi: null`.
- A references call can answer 200 with `"data": null` and a
  `disclaimer` under `citingPaperInfo.openAccessPdf` saying the
  publisher elided the paper's `references` field. Read `.data // []`,
  and record the seed as having its references withheld there, not as
  having none. Seen on 2026-11-24 for a Wiley article DOI. The paper
  lookup can still report a `referenceCount` above 0 for such a seed
  (1, 6 and 2 for two books and a 1973 article the same day, each with
  `data: null`), so the count does not show that a list can be walked:
  step 8 goes by the list, and the counts table writes such a count with
  `withheld` beside it.
- `citationCount` can sit far from the other services in either
  direction: on 2026-11-24 a 2018 second edition of a book showed 470
  here against 214 in OpenAlex and 17 in OpenCitations, and a Springer
  article 5 against 481 in OpenAlex.
- `POST /paper/batch` with `{"ids": [...]}` (up to 500 ids, `fields` in
  the query string) resolves many ids in one call when a frontier needs
  counts for every candidate at once.

## Verified

Live on 2026-10-16, keyless: 16 distinct requests in 19 attempts, 3 of
them 429. Behaviour with a key, and whether the documented shared pool of
"1000 requests per second" is still configured, were not exercised;
observed behaviour suggests a lower effective rate. The corpus changes
weekly, so counts drift between runs.
