# Unpaywall for the open-access verdict

Base `https://api.unpaywall.org/v2`. The only credential is `email=`, a
real address: a missing one returns 422 "Email address required", a
placeholder returns 422 "Please use your own email address", and the
backend blocks placeholder patterns. Use one address for the whole run
(more than 20 distinct addresses from one network address are refused).
Allowance 100,000 calls a day; stay under 4 per second (250 ms between
calls). No rate-limit headers are returned.

Since late 2025 Unpaywall reads the OpenAlex database, so its verdict and
OpenAlex's come from the same data in two shapes; title search, batch
routes and the snapshot were retired (410) and point at OpenAlex. It knows
Crossref DOIs only: DataCite DOIs and shortDOIs return 404.

## Lookup

```bash
http_status="$(curl --silent --max-time 30 --output up.json --write-out '%{http_code}' \
    "https://api.unpaywall.org/v2/${doi}?email=${RESEARCH_CONTACT_EMAIL}")"
echo "${http_status}"
jq '{is_oa, oa_status, journal_is_in_doaj, updated,
    best: (.best_oa_location | {url_for_pdf, url_for_landing_page, license, version, host_type, oa_date})}' up.json
```

- 200: parse. 404 (an HTML body, not JSON): not in Unpaywall, not a
  Crossref DOI, or a shortDOI; Crossref's `/agency` route tells which.
  410: retired endpoint, body names the replacement. 422: fix the email
  or slow down; never retry unchanged. 5xx: retry once after 2 s.
- `best_oa_location: null` with `is_oa: false` means no free copy known,
  not proof that none exists.
- `oa_status` is one of `gold`, `hybrid`, `bronze`, `green`, `closed`.
  OpenAlex's `diamond` shows here as `gold`.
- `license` is a lower-case CC abbreviation (`cc-by`), a publisher
  string, `implied-oa`, `other-oa`, or null. `version` follows DRIVER:
  `publishedVersion`, `acceptedVersion`, `submittedVersion`.
- To prefer the version of record over the ranked best:
  `jq --raw-output '[.oa_locations[] | select(.version == "publishedVersion" and .url_for_pdf != null)][0].url_for_pdf'`.
- SciELO PDF links may come as `http://www.scielo.br/pdf/…`; keep the
  scheme and let curl follow the upgrade.

## Verified

Live on 2026-10-17, API version `2.0.1`. Agreement with OpenAlex on the
lab's records: same copy, same license and version; label `gold` against
`diamond` on a SciELO article.
