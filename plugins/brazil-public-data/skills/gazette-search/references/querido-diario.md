# Querido Diário for gazette search

Querido Diário (Open Knowledge Brasil) scrapes the official gazettes of
Brazilian municipalities, extracts their text and serves it through a
public REST API. A record is one gazette edition of one city on one day,
identified by the 7-digit IBGE territory id, the date and a file hash;
each carries a PDF and a plain-text extraction. It holds no articles,
DOIs or citations.

Base `https://api.queridodiario.org.br` (FastAPI; `/docs` Swagger UI,
`/openapi.json` the spec, `/health` status and version). Files live on
`https://data.queridodiario.ok.org.br`. The docs and the API README still
cite `api.queridodiario.ok.org.br`, which does not answer. Every public
endpoint is keyless: the only credential, `X-API-Key`, belongs to the
internal `/scraper/*` routes. No `User-Agent` header is sent. No rate-limit headers exist; the docs ask for 60
requests per minute, so pace at one per second. Cold queries take 20 to
40 s: use `--max-time 90`.

```bash
QD_API="https://api.queridodiario.org.br"
QD_DATA="https://data.queridodiario.ok.org.br"
```

## Resolve the municipality

```bash
curl --silent --max-time 90 "${QD_API}/cities?city_name=Osasco" | jq '.cities'
curl --silent --max-time 90 "${QD_API}/cities/3534401" | jq '.city'
```

`City`: `territory_id`, `territory_name`, `state_code`, `publication_urls`,
`level` (`""`, `"0"`, `"1"`, `"2"`, `"3"`), `availability_date`. Only
level `"3"` cities are searchable and only they carry an
`availability_date`, which is when the platform started serving the city
(Osasco 2023-08-03), not its earliest gazette: read that with
`size=1&sort_by=ascending_date` (Osasco: 2002-08-05). `city_name` is a
similar-name search and can return several cities; pick by `state_code`.
One `GET /cities` call lists all 5,570 cities for local filtering.

## Search

```bash
IBGE_CODE="3534401"
query='"saúde mental"'
since_date="2024-01-01"
until_date="2024-12-31"
curl --silent --max-time 90 --get --output hits.json --write-out '%{http_code}\n' "${QD_API}/gazettes" \
    --data-urlencode "territory_ids=${IBGE_CODE}" --data-urlencode "querystring=${query}" \
    --data-urlencode "published_since=${since_date}" --data-urlencode "published_until=${until_date}" \
    --data-urlencode "size=100" --data-urlencode "offset=0" \
    --data-urlencode "sort_by=ascending_date" \
    --data-urlencode "excerpt_size=500" --data-urlencode "number_of_excerpts=3" \
    --data-urlencode "pre_tags=<<" --data-urlencode "post_tags=>>"
jq '{total_gazettes, hits: [.gazettes[] | {territory_id, date, edition, is_extra_edition, url, txt_url, scraped_at, excerpts}]}' hits.json
```

| Parameter | Default | Meaning |
| --------- | ------- | ------- |
| `territory_ids` | all cities | 7-digit IBGE id; repeat the parameter for several cities. Omitting it searches every covered city (22 s for a phrase) |
| `published_since`, `published_until` | none | `YYYY-MM-DD`, inclusive |
| `scraped_since`, `scraped_until` | none | `YYYY-MM-DDTHH:MM:SS` |
| `querystring` | `""` | OpenSearch simple query string syntax |
| `excerpt_size` | 500 | characters per excerpt |
| `number_of_excerpts` | 1 | excerpts per gazette |
| `pre_tags`, `post_tags` | `""` | wrapped around each match inside excerpts |
| `size` | 10 | page size; `size=0` returns the count alone; 1001 was accepted |
| `offset` | 0 | `offset=9999` worked, `offset=10000` answered 500 |
| `sort_by` | `relevance` | `relevance`, `descending_date`, `ascending_date` |

Query syntax: an unquoted `saúde mental` is `saúde OR mental` (2,288 of
Osasco's 2,487 gazettes); the quoted phrase `"saúde mental"` in 2024
matched 192; `"saúde mental" +CAPS` (phrase plus a required term) matched
86. Operators seen to work: `"phrase"`, `+term`, plain terms. Pass the
query through `--data-urlencode` so quotes and accents survive.

Response: `total_gazettes` and `gazettes[]` of `territory_id`, `date`,
`scraped_at`, `url` (PDF), `txt_url` (text, nullable), `territory_name`,
`state_code`, `excerpts` (absent, not empty, when `querystring` is empty),
`edition` (nullable), `is_extra_edition` (nullable).

Paging: `offset + size` stays at or below 10,000; a window with more hits
is split by date. Pages of 100 or fewer, sorted by date so they are stable
across calls, one per second. The index grows daily (the newest Osasco
gazette was dated the day before the probe), so a count is only
reproducible with the date it was taken.

Errors: `500` and Cloudflare `520` are transient (two of about twenty
calls), retry the same URL once after a pause; `422` carries a `detail[]`
naming the bad parameter (`published_since=2024-13-01`), fix it and never
retry unchanged; `404 {"detail":"Not Found"}` is an unknown path. A `503`
with an HTML body can strike single queries while others answer in the
same minutes: on 2026-11-25, 6 of 19 queries against one city ended in
503 or no answer after the full backoff, the 13 others answered 200, and
all 6 answered 200 when sent again some minutes later, which is why a
failed query is queued and sent once more at the end of the run and the
source is stopped only when a whole batch has failed. On 2026-11-24 four
queries in a row answered 503 and nothing else was sent that session.
The 503 body is not JSON, so test the status before reading
`total_gazettes`.

## Fetch one gazette

```bash
txt_url="$(jq --raw-output --exit-status '.gazettes[0].txt_url' hits.json)" || echo "no txt_url in hits.json" >&2
pdf_url="$(jq --raw-output --exit-status '.gazettes[0].url' hits.json)" || echo "no url in hits.json" >&2
curl --silent --max-time 90 --output gazette.txt --write-out '%{http_code}\n' "${txt_url}"
curl --silent --max-time 90 --head "${pdf_url}" | grep -iE '^(HTTP|content-length|last-modified|etag)'
```

Both files are served as `binary/octet-stream` with `Accept-Ranges:
bytes`. The text keeps the original line breaks (350 KB for one Osasco
edition; its PDF 12.6 MB), so fetch the text and only HEAD the PDF unless
the PDF itself is wanted. Paths follow
`<ibge>/<YYYY-MM-DD>/<40-hex sha1>.{pdf,txt}` but the hash is not
derivable: take URLs from the response. Keep the `etag` of any text
quoted.

## Bulk: one year of one city

```bash
STATE="SP"
curl --silent --max-time 90 "${QD_API}/aggregates/${STATE}?territory_id=${IBGE_CODE}" |
    jq --raw-output '.aggregates[] | "\(.year)\t\(.file_size_mb) MB\t\(.last_updated)\t\(.hash_info)\t\(.file_path)"'
curl --silent --max-time 600 --output "sposasco_3534401_2025.zip" \
    "${QD_DATA}/aggregates/SP/sposasco_3534401_2025.zip"
```

Items carry `territory_id`, `state_code`, `file_path`, `year`,
`last_updated`, `hash_info` (MD5), `file_size_mb`. `file_path` lacks the
slash after the host; rebuild the URL as
`${QD_DATA}/aggregates/<UF>/<basename>` (basename
`<uf lowercase><city slug>_<ibge>_<year>.zip`). Aggregates lag the index
(Osasco's 2025 zip: last updated 2025-07-22, 4,955,356 bytes). The terms
of use name the yearly download per municipality on the site's `/dados`
page as the intended bulk route. Unverified: the zip's internal layout and
any data dictionary published with it were not inspected, and `/dados`
is client-rendered, so a browser is needed to read it.

## Terms of use and attribution

Terms at `https://queridodiario.org.br/privacidade`, version 2.2 of
2024-06-20 (client-rendered; read in a browser). They make the API the
intended route for automated queries, at the lowest practical rate; limit
use to consulting public data for access to information and public
oversight; allow reuse of gazette content for any lawful purpose; and
license the platform's own content CC BY 4.0. Attribution line for any
published output: `Querido Diário (Open Knowledge Brasil), CC BY 4.0,
accessed YYYY-MM-DD`. Gazettes carry personal data (names, CPF numbers,
addresses): working files may hold the raw text, output meant for
publication never reproduces it. The product site's `robots.txt` signals
`ai-train=no`; it governs the site, not the API or data host.

## Verified

Live on 2026-10-17, keyless, API version 0.19.0, from `openapi.json`,
the API source and captured responses. Osasco `3534401`: level 3, 2,487
gazettes from 2002-08-05. Coverage that day: 510 of 5,570 cities at
level 3. Unverified: the meaning of levels 0 to 2 (inferred from data),
whether 10,000 is an OpenSearch window, any cap on `size`, the aggregate
zip layout, the `/gazettes/by_theme/*` and `/company/*` routes.
