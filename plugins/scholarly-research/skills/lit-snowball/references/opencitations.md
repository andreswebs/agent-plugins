# OpenCitations for snowballing

Base `https://api.opencitations.net`; no key, no budget. The single
OpenCitations Index (the former COCI, DOCI, POCI, JOCI and OROCI merged;
`index/v2` is current, `index/v1` legacy) holds citation links harvested
from Crossref, DataCite, NIH-OCC, OpenAIRE, JaLC, OUTCITE and Matilda;
OpenCitations Meta holds minimal metadata for the works those links
connect. Every work carries an OMID (`omid:br/<digits>`), every citation
an OCI (`<citing-digits>-<cited-digits>`). There is no language field, no
abstract, no open-access link. Limit: 180 requests per minute per network
address; no rate-limit headers; sleep at least 350 ms between calls.
Check the HTTP status before parsing: a 400 body is plain text, a miss is
200 with `[{"count": "0"}]` or `[]`.

Counts here differ from OpenAlex in both directions by design (different
sources, matched differently): the lab's SciELO article had 16 citations
and 36 references here against 35 and 49 in OpenAlex; a QSS article had
136 and 13 against 152 and 12. Expect lower figures for recent and for
non-English work. Report both with the date; never merge.

## Counts

```bash
doi="10.1590/0102.3772e36nspe19"
curl --silent --max-time 30 "https://api.opencitations.net/index/v2/citation-count/doi:${doi}" | jq --raw-output '.[0].count'
curl --silent --max-time 30 "https://api.opencitations.net/index/v2/reference-count/doi:${doi}" | jq --raw-output '.[0].count'
```

A one-element array with the count as a string; `"0"` for an unknown id.
An id without its `doi:` prefix answers 400.

## Forward and backward rows

```bash
curl --silent --max-time 30 --output cits.json --write-out '%{http_code}\n' "https://api.opencitations.net/index/v2/citations/doi:${doi}"
curl --silent --max-time 30 --output refs.json --write-out '%{http_code}\n' "https://api.opencitations.net/index/v2/references/doi:${doi}"
jq 'length' cits.json refs.json
jq --compact-output '.[] | {oci, citing, cited, creation, timespan, journal_sc, author_sc}' cits.json
jq --raw-output '.[].citing' cits.json | tr ' ' '\n' | grep '^doi:' | sed 's/^doi://'
jq --raw-output '.[].cited' refs.json | tr ' ' '\n' | grep '^doi:' | sed 's/^doi://'
```

- The whole array comes back in one call; there is no paging. A
  server-side cap of 200,000 rows applies to `citations` and `references`
  (50,000 to `citation/{oci}`); a seed with more citations than that needs
  the SPARQL endpoint with `LIMIT` and `OFFSET`, out of this skill's
  scope, so note the cap.
- A large array takes longer than a short timeout to arrive: on
  2026-11-13 a `citations` call for a seed with 6,335 citations, sent
  with `--max-time 60`, stopped at 377,824 bytes and the body did not
  parse, so no row was collected. Give list calls a longer `--max-time`
  than the 30 s used for counts, check that the body parses as JSON
  before counting rows, and note a truncated body as a failed call, not
  as zero citations.
- `citing` and `cited` are space-separated `prefix:value` lists, OMID
  first. A citing or cited work with no DOI appears as `omid:` only;
  resolve it through Meta below.
- `creation` is the citing work's publication date (`YYYY`, `YYYY-MM` or
  `YYYY-MM-DD`); `timespan` an XSD duration; `journal_sc` and `author_sc`
  are `yes` or `no` self-citation flags.
- RAMOSE parameters narrow or order the array: `filter=creation:>2025`,
  `sort=desc(creation)`, `format=csv` (an `Accept: text/csv` header alone
  was ignored). The 136-row response in the lab took about 1 s.

## Resolve an OMID or DOI through Meta

```bash
omid="omid:br/062501777134"
curl --silent --max-time 30 "https://api.opencitations.net/meta/v1/metadata/${omid}" |
    jq '.[0] | {id, title, pub_date, venue, type}'
```

- `id` lists every identifier known for the work, space-separated
  (`omid:`, `doi:`, `openalex:`, `pmid:`, ...). Several ids go in one
  call joined by `__`: `metadata/doi:${doi}__doi:${doi2}`.
- An unknown id answers 200 with `[]`. `pub_date` gives the year; there
  is no language.

## Verified

Live on 2026-10-16, unauthenticated, under 40 requests. `index/v2`
version 2.2.0 (2025-04-15), `meta/v1` 1.1.1; latest Index dump July 2026.
No 429 was provoked, so its shape is unverified; the 200,000-row cap was
read from the service configuration, not hit.
