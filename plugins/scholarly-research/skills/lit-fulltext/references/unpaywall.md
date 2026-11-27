# Unpaywall for the first candidate

Base `https://api.unpaywall.org/v2`. The only credential is `email=`, a
real address: a missing one returns 422 "Email address required", a
placeholder returns 422 "Please use your own email address". Use one
address for the whole run (more than 20 distinct addresses from one
network address are refused). Allowance 100,000 calls a day; stay under
4 per second (250 ms between calls). No rate-limit headers are returned.
Since late 2025 Unpaywall reads the OpenAlex database, so its copy and
OpenAlex's are the same data in two shapes. It knows Crossref DOIs only:
DataCite DOIs and shortDOIs return 404.

## Lookup

```bash
http_status="$(curl --silent --max-time 60 --output up.json --write-out '%{http_code}' \
    "https://api.unpaywall.org/v2/${doi}?email=${RESEARCH_CONTACT_EMAIL}")"
echo "${http_status}"
jq '{is_oa, oa_status, updated,
    best: (.best_oa_location | {url_for_pdf, url_for_landing_page, license, version, host_type, oa_date})}' up.json
```

- 200: parse. 404 (an HTML body, not JSON): not in Unpaywall, not a
  Crossref DOI, or a shortDOI. 410: retired endpoint, body names the
  replacement. 422: fix the email or slow down; never retry unchanged.
  5xx: retry with backoff.
- `best_oa_location: null` with `is_oa: false` means no free copy known,
  not proof that none exists; Unpaywall indexes publisher sites and
  repositories, not personal pages.
- A repository link can answer with a generic content type: on
  2026-11-24 an OSF preprint's `url_for_pdf` (`https://osf.io/<id>/download`)
  answered HEAD 200 with `application/octet-stream`. Such a candidate
  is fetched and judged by its bytes (SKILL.md, "Fetching a candidate").
- Repositories use other generic labels too: on 2026-11-26 a university
  repository's PDF announced by Unpaywall answered HEAD 200 with
  `binary/octet-stream`. Any content type ending in `/octet-stream` is
  now fetched and judged by its bytes. PubMed Central's
  `/articles/<PMCID>/pdf/` links answered HEAD 200 with `text/html` (an
  interstitial page), not the PDF.
- Unpaywall returns URLs, never files. `url_for_pdf` is the PDF when one
  is known, `url_for_landing_page` otherwise; `url` is whichever exists.
  A landing page is not a candidate for a PDF fetch.

## Candidates, in order

```bash
jq --raw-output '[.oa_locations[] | select(.version == "publishedVersion" and .url_for_pdf != null)][0].url_for_pdf // empty' up.json
jq --raw-output '.best_oa_location.url_for_pdf // empty' up.json
jq --raw-output '.oa_locations[] | select(.url_for_pdf != null) | [.host_type, .version, (.license // "null"), .url_for_pdf] | @tsv' up.json
```

The ranked `best_oa_location` puts the publisher first, then the version
of record, then repository authority; the first line above prefers the
version of record when it has a PDF, the last lists every PDF with its
`host_type`, `version` and `license` for the remaining candidates.

- `license` is a lower-case CC abbreviation (`cc-by`), a publisher
  string, `implied-oa`, `other-oa`, or null. `version` follows DRIVER.
  `oa_date` is when the copy first became available at that location.
- A location's `license` can disagree with what the copy itself prints:
  on 2026-11-26 a repository location labelled `cc-by-nc-nd` served an
  accepted manuscript whose cover page said all rights reserved unless
  indicated otherwise. The label is Unpaywall's reading of the location,
  not a statement printed on the file, so the copy's own statement is
  the one the manifest records and the label goes into `notes`.
- `evidence` and `updated` inside a location are `"deprecated"` and
  scheduled for removal; the record-level `updated` is the timestamp to
  keep.
- An Elsevier `url_for_pdf` on sciencedirect answered `text/html` to a
  plain client (2026-11-10, a CC BY-NC-ND article); the candidate fails
  the content-type check and Europe PMC's JATS takes the copy.
- SciELO PDF links may come as `http://www.scielo.br/pdf/...`; keep the
  scheme and let curl follow the upgrade.
- Expect publisher redirects, cookies and 403s on the fetch; a HEAD
  request first says whether the link is live. On 2026-11-24, 12 of 18
  open-access PDF candidates from Unpaywall or OpenAlex answered 403 to
  a plain client (Hindawi downloads, ScienceDirect, Wiley `pdfdirect`,
  OUP, Taylor and Francis, the Cochrane Library); Europe PMC's JATS then
  supplied 5 of them, so a 403 here moves on to the later sources rather
  than ending the input.

## Verified

Live on 2026-10-17, API version `2.0.1`. On the lab's SciELO record the
best location was the scielo.br PDF, `cc-by`, `publishedVersion`, the
same copy OpenAlex named. The 4 per second throttle and the 20-email
rule come from the backend source and were not exercised; a Data Feed
`api_key` on lookups is documented but unverified.
