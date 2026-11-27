# CORE for the last candidate

Base `https://api.core.ac.uk/v3`. Access is tiered by tokens: keyless,
100 tokens a day and 10 per minute, and the `fullText` field is the
literal string "Not available for public API users."; a registered key
(requested by email through the form on the API service page, none is
issued by an API call) raises the tier and unlocks full text. Send the
key as `Authorization: Bearer ${CORE_API_KEY}`; an invalid key answers
401 "The API key you provided is not valid." Every response carries
`X-RateLimit-Limit`, `X-RateLimit-Remaining` and
`X-RateLimit-Retry-After`; a 429 comes with an empty HTML body and an
advisory timestamp, so sleep 10 s and retry once, then wait for the
timestamp. End the search path with a slash, or the API answers 301.

A work's copy is reached through the API only: the terms forbid
harvesting from `fileserver-az.core.ac.uk` directly and disable keys that
bypass the API, and the terms ask research projects to contact CORE for
a license unless their institution is a member.

## Lookup by DOI (one token)

There is no `/works/doi:` route; search the `doi` field.

```bash
core_auth=()
if [ -n "${CORE_API_KEY:-}" ]; then core_auth=(--header "Authorization: Bearer ${CORE_API_KEY}"); fi
curl --silent --max-time 60 --get --dump-header core.headers --output core.json "https://api.core.ac.uk/v3/search/works/" \
    "${core_auth[@]}" \
    --data-urlencode "q=doi:\"${doi}\"" --data-urlencode "limit=1" --data-urlencode "exclude=fullText"
grep -i '^x-ratelimit' core.headers
jq '{totalHits, hit: (.results[0] | {id, doi, yearPublished, lang: .language.code, documentType, downloadUrl,
    sourceFulltextUrls, links, outputs, providers: [.dataProviders[].name]})}' core.json
```

- `totalHits: 0` means CORE has no work with that DOI; about half of
  CORE's works carry no DOI at all. The lookup is by identifier and is
  not a search for the log.
- `sourceFulltextUrls[]` are the repository's own links: the keyless
  candidates, fetched like any other. `downloadUrl` is CORE's cached PDF
  at `https://core.ac.uk/download/{output_id}.pdf`; `links[]` carries
  `download`, `reader`, `display` and thumbnail types.
- Outputs are `https://api.core.ac.uk/v3/outputs/{id}`; the output id is
  what the download and reader URLs use.

## CORE's own copy (key)

```bash
output_id="$(jq --raw-output --exit-status '.results[0].outputs[0] | sub(".*/"; "")' core.json)" || echo "no CORE output in core.json" >&2
curl --silent --max-time 60 --dump-header dl.headers --output "${stem}.pdf" --location --header "Authorization: Bearer ${CORE_API_KEY}" \
    "https://api.core.ac.uk/v3/outputs/${output_id}/download"
grep -iE '^(HTTP|content-type|location)' dl.headers
```

`GET /v3/outputs/{id}/download` answers 302 to `core.ac.uk/download/{id}.pdf`,
and that URL answered 403 with a Cloudflare JavaScript challenge to a
keyless client with and without a browser user agent. A key does not
clear it: on 2026-11-26 the keyed `GET /v3/outputs/{id}/download`
answered 302 to that file, which answered 403 `text/html` (a challenge
page of about 5 KB). A challenge page ends the candidate. The docs
call this route more expensive than a normal query. With a key the
`fullText` field (plain text extracted with PDFBox) is the cheaper way
to the text; record it as a note, not as a copy.

`POST /v3/discover` with `{"doi": "..."}` (keyless, GET answers 405)
returns `{"fullTextLink", "source"}`; in the lab the link was a
`core.ac.uk/labs/oadiscovery/redirect` to the reader page, which is
HTML, not a copy.

## Verified

Live on 2026-10-16 and 2026-10-17, keyless, about 20 calls: the DOI
lookup (the lab's SciELO DOI resolved to work 107958421 from the UnB
periodical portal), the discover route, the 302 then 403 on download,
the rate-limit headers and one 429. Keyed behaviour (`fullText` on
results, the download challenge) and the `limit` maximum are unverified.
On 2026-11-24, with a key, DOI lookups answered 200 and found works; the
`sourceFulltextUrls` tried answered 403 to curl, and the download route
was not tried. On 2026-11-26, with a key, a hit's `sourceFulltextUrls`
held only CORE's own `core.ac.uk/download/{id}.pdf` (not a repository
link), its `fullText` was empty, and the keyed download route ended in
the challenge above.
