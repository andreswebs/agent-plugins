# OpenAlex for the second candidate

Base `https://api.openalex.org`. Usage is metered in credits against a
daily budget: a singleton lookup by id is free. Keyless, one network
address shares 1,000 credits (0.10 USD) a day, reset at midnight UTC; a
free key gives 10,000. Send the key as
`Authorization: Bearer ${OPENALEX_API_KEY}` when set. Keyless rate: 10
requests per second. Errors cost nothing. Read `X-RateLimit-Remaining`
from every response.

## Lookup by DOI (free)

```bash
openalex_auth=()
if [ -n "${OPENALEX_API_KEY:-}" ]; then openalex_auth=(--header "Authorization: Bearer ${OPENALEX_API_KEY}"); fi
curl --silent --max-time 60 --output oa.json --write-out '%{http_code}\n' \
    "${openalex_auth[@]}" \
    "https://api.openalex.org/works/doi:${doi}"
jq '{id: (.id | sub("https://openalex.org/"; "")), updated_date, language,
    is_oa: .open_access.is_oa, oa_status: .open_access.oa_status, oa_url: .open_access.oa_url,
    best: (.best_oa_location | {pdf_url, landing_page_url, license, version}),
    others: [.locations[] | select(.pdf_url != null) | {pdf_url, license, version}],
    has_content, content_urls}' oa.json
```

- 404 with an HTML body: the work is not in OpenAlex (it misses some
  SciELO DOIs; one of two tried in the lab). A 301 points at a merged
  survivor; follow with `--location`.
- `best_oa_location.pdf_url` and `open_access.oa_url` point at the
  publisher or repository copy and need no key; `oa_url` may be a
  landing page rather than a PDF, so the HEAD check decides its form.
- `best_oa_location.version` is `publishedVersion`, `acceptedVersion` or
  `submittedVersion`; `license` is the license of that copy. `oa_status`
  includes `diamond` for no-fee gold.
- `locations[]` holds every copy OpenAlex knows, each with its own
  `pdf_url`, `license` and `version`; `locations[].doi` can differ from
  the work's (preprint and article merged into one work).

## The cached copy (key only, 100 credits)

Asked last among the sources, after every free one has failed, and
before the landing page. On 2026-11-25, with the cached copy still
inside the OpenAlex lookup and a publisher platform slow that evening,
18 articles the platform serves free were taken from the cached route at
100 credits each.

`content_urls.pdf` names OpenAlex's own cached PDF; `has_content.pdf`
says whether one exists. The content API refuses keyless calls (401
observed) and charges 0.01 USD per PDF; pass `--compressed` for the TEI.

```bash
work_id="$(jq --raw-output --exit-status '.id | sub("https://openalex.org/"; "")' oa.json)" || echo "no OpenAlex id in oa.json" >&2
curl --silent --max-time 60 --output "${stem}.pdf" --write-out '%{http_code} %{content_type}\n' \
    "https://content.openalex.org/works/${work_id}.pdf?api_key=${OPENALEX_API_KEY}"
curl --silent --max-time 60 --compressed --output "${stem}.tei.xml" \
    "https://content.openalex.org/works/${work_id}.grobid-xml?api_key=${OPENALEX_API_KEY}"
```

The cached file is whatever copy OpenAlex harvested, which can differ
from the location its record calls best, so the manifest describes the
file itself: its version is read from the file's own first page and its
license from its first and last pages, as for every copy; when neither
states one, `license` is `null` and `reuse` `read-only`; a download stamp seen on the page goes into `notes`. The
copy is kept in every case. On 2026-11-24, of 23 cached copies kept, 17
carried a license on the file and 6 none, and one of the 6, for a work
marked `bronze`, carried "All rights reserved" and a library's download
stamp. A journal can print its license on the last page only: on
2026-11-25, of 18 cached copies with no license on the first page, two
were found by their readers to state CC BY at the end of the text. Check `has_content.pdf` on the work record before calling, and
leave about ten seconds between downloads.

Stop paid calls when `X-RateLimit-Remaining` is below 100. The TEI is a
Grobid parse, not the publisher's JATS; record it as `form: xml` with a
note saying `grobid-tei`.

## Verified

Live on 2026-10-16, keyless: singleton lookups cost 0 credits, a 404
reported `X-RateLimit-Credits-Used: 0`, and `content.openalex.org`
answered 401 without a key. On 2026-11-24, with a key, 23 cached PDFs
were fetched: each answered 200 with `X-RateLimit-Credits-Used: 100`; a
work whose `has_content.pdf` is false answered 404 with a JSON body and
no charge; sent back to back, the route answered 429 with
`application/json` after about ten downloads, and ten seconds between
calls cleared it. The TEI route was not exercised.
