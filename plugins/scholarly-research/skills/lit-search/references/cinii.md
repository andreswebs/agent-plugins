# CiNii Research for searching

Japan's national discovery service (NII): OpenSearch at
`https://cir.nii.ac.jp/opensearch/{type}`, record JSON-LD at
`https://cir.nii.ac.jp/crid/{CRID}.json`. The docs call the free
application ID `appid` required on every call, in the query string only,
never in a link shown to a human. On 2026-10-17 the API answered without
it, a wrong value gave the HTML 404 page, and an empty one was ignored;
the Web API regulations nonetheless make the `appid` a condition of use
(see "Robots and terms"), so this skill makes no call without it.
Registration commits the holder to NII's usage regulations and
commercial use needs prior email. Pace one request a second
(see "Robots and terms"); the registration page threatens
blocking without notice for heavy use; no rate-limit headers or numeric
quota exist. Every error is the same HTML 404 page, so test the content
type before parsing; a `202` with an empty body on an API URL means the
WAF has begun challenging that path (only HTML pages were challenged on
the verified date, and the website can never be a fallback).

CiNii carries Japanese journals, bulletins, dissertations and KAKEN
projects that exist nowhere else, with bilingual metadata where the
source has it. It has no citation data and no abstract search beyond the
free-word `q`; snowballing goes through a hit's DOI in OpenAlex.

## Search

```bash
query="デジタル民主主義"
from_year="2020"
to_year="2026"
if [ -z "${CINII_APPID:-}" ]; then
  echo "CiNii skipped: CINII_APPID unset; for a human to run: ${query}" >&2
else
  http_status="$(curl --silent --max-time 60 --get --output "${RAW}/cinii-1.json" --write-out '%{http_code} %{content_type}' \
      "https://cir.nii.ac.jp/opensearch/articles" \
      --data-urlencode "q=${query}" --data-urlencode "format=json" \
      --data-urlencode "from=${from_year}" --data-urlencode "until=${to_year}" \
      --data-urlencode "languageType=ja" \
      --data-urlencode "count=100" --data-urlencode "start=1" \
      --data-urlencode "appid=${CINII_APPID}")"
  case "${http_status}" in
  "200 application/json"*)
    jq '{url: ."@id", total: ."opensearch:totalResults", n: (.items | length)}' "${RAW}/cinii-1.json" ;;
  *) echo "CiNii error: ${http_status}" >&2 ;;
  esac
fi
```

- `q` is the free-word field, with the syntax under "Query syntax"
  below. Japanese terms match Japanese metadata;
  English terms match the English forms many sources carry (`digital
  democracy` gave 409). `lang=en` switches output language, it does not
  filter: the same records come back, each with its English `title` and
  `description` (abstract) where CiNii holds them and its Japanese ones
  otherwise. The default output gives only one `description` per item,
  the Japanese one, so whether a record has an English abstract is read
  from a second call with `lang=en`, testing whether the `description`
  is in Latin script.
- `from` and `until` take `YYYY` or `YYYYMM`. `languageType` is ISO
  639-1, comma-separated for OR; `ja` kept all 24 hits of the query above
  and `en` kept 0.
- Search types: `articles` for journal literature; `all` adds books,
  data, dissertations, projects and other works (`dc:type` tells them
  apart); `dissertations` on its own. `hasLinkToFullText=true` keeps
  records with a full-text link (5 of 24 above).
- `count` 1 to 200 (larger clamps to 200); `start` 1-based, at most
  10,000, beyond which `items` is empty: slice a bigger set by year.
  `sortorder` `0` newest, `1` oldest, `4` relevance (default), `10` most
  cited first for articles (count not exposed).
- `title`, `creator`, `dataSourceType` and `resourceType` parameters are
  documented but were not exercised.

## Query syntax

Documented, read 2026-11-26. The OpenSearch specification
(`https://support.nii.ac.jp/ja/cir/r_opensearch`, English at
`https://support.nii.ac.jp/en/cir/r_opensearch`) marks `q`, `title`,
`creator` and `description` as accepting a Boolean expression, with
space-separated entries ANDed; code and id parameters (`doi`, `issn`,
`languageType`) take comma-separated values, ORed, and no expression.
The operators are documented in section A-4, "Complex Search Methods",
of the keyword search manual (`https://support.nii.ac.jp/ja/cir/manual_keyword`,
English at `https://support.nii.ac.jp/en/cir/manual_keyword`):

| Element  | Written as                                                         |
| -------- | ------------------------------------------------------------------ |
| AND      | a half- or full-width space, ` AND `, or ` & `                     |
| OR       | ` OR ` (uppercase) or ` \| `                                       |
| NOT      | ` NOT ` (uppercase), or `-` directly before the excluded term     |
| Grouping | parentheses set the precedence: `安達 NOT (武田 AND 相澤)`           |
| Phrase   | double quotes around a string with spaces, single-byte text only   |
| Prefix   | trailing `*`, single-byte text only                                |

Operators may also be written in full-width characters. A space between
two words is AND, so unquoted `Talk to the City` asks for records holding
all four words. The search FAQ (`https://support.nii.ac.jp/ja/cir/faq/searches`)
adds that exact-match search does not exist. Not settled by these pages:
the manual describes the web search box and the OpenSearch page does not
restate the operators for `q`, and no page says how double quotes around
double-byte text are read. No query was sent to settle either point.

## Robots and terms

Read 2026-11-26. `robots.txt` on `cir.nii.ac.jp` gives generic agents
`Crawl-Delay: 1`, allows only `/`, `/crid/` record pages, `/sitemaps/`
and `/resourcesync/`, disallows `/crid/*.json` and the other export
suffixes, and ends with `Disallow: /`, which covers `/opensearch/`. Use is
governed by NII's Academic Content Service Usage Regulations, the CiNii
Research Usage Detailed Regulations and the Academic Content Service
Web API Usage Detailed Regulations (`https://support.nii.ac.jp/en/cinii/terms`).
The Web API regulations limit use to one's own academic research or
non-profit information use (Article 3.1), make use conditional on an
application approved by NII, which issues the key sent as `appid`
(Articles 4.1 and 4.3), and forbid short-time large-volume access
(Article 6 (iii)); the usage regulations forbid automated large-volume
searches outside the Web API regulations (Article 6 (vi)). Only the
Japanese text of the regulations is binding.

## Hits

```bash
jq --compact-output --arg q "${query}" '.items[] | {
  id: (."@id" | sub(".*/"; "")), id_type: "crid",
  doi: ([."dc:identifier"[]? | select(."@type" == "cir:DOI") | ."@value" | ascii_downcase][0] // null),
  title, year: (."prism:publicationDate" // "" | .[:4] | tonumber? // null),
  database: "cinii", also_in: [],
  url: (([."dc:identifier"[]? | select(."@type" == "cir:DOI") | "https://doi.org/\(."@value" | ascii_downcase)"][0]) // ."@id"),
  language: "ja", query: $q}' "${RAW}/cinii-1.json"
```

`prism:publicationDate` is free-form (`YYYY`, `YYYY-MM`, `YYYY-MM-DD`)
and `null` on projects. `language` is the `languageType` sent; the hit
carries none and the record's `dc:language` is a later lookup (see
"Record lookup"). A JaLC DOI
(`10.11517/...`) usually resolves to a publisher landing page with a PDF;
the hit does not say whether the link is open access.

## Record lookup

A hit already holds the bibliographic fields, so a record is looked up
only for what the hit lacks, such as `dc:language`. The record path
answered the `202` challenge in both checks of 2026-11-26, without and
with the `appid`; a `202` ends lookups for the run.

```bash
crid="1390871867482570496"
if [ -n "${CINII_APPID:-}" ]; then
  http_status="$(curl --silent --max-time 60 --get --output "${RAW}/cinii-${crid}.json" --write-out '%{http_code} %{content_type}' \
      "https://cir.nii.ac.jp/crid/${crid}.json" --data-urlencode "appid=${CINII_APPID}")"
  case "${http_status}" in
  "200 application/json"*) ;;
  "202 "*) echo "CiNii challenged the record path: ${http_status}" >&2 ;;
  *) echo "CiNii error: ${http_status}" >&2 ;;
  esac
fi
```

## Log

`database: "cinii"`, `hits` from `opensearch:totalResults`, `url` the
response's `@id` (the request URL with `appid` already removed),
`filters` the search type, `from`, `until`, `languageType`, `count` and
`start`, `notes` carrying `opensearch:itemsPerPage`.

## Duties

A hit's `description` (abstract) is reused only when its
`abstractLicenseFlag` is `allow`. The `appid` value never appears in a
file, a log line or a link.

## Verified

Live on 2026-10-17, without an appid, 30 requests from one network
address. `広聴AI` returned 1 (CRID `1390871867482570496`), `デジタル民主主義`
24, `count=250` returned 200 items, `start=10001` returned none.

Again on 2026-11-26, without an appid, 16 OpenSearch calls one second
apart, all `200 application/json`.
`チームみらい AND (ブロードリスニング OR 広聴 OR デジタル民主主義)` and
`安野貴博 AND (ブロードリスニング OR 広聴)` returned 0 while `ブロードリスニング`
alone returned 4 and `デジタル民主主義` 13; under the documented syntax both
strings also require the name, so the zeros do not show that grouping
was ignored; `広聴AI OR "Kouchou AI"` returned
1, a record matching neither term in its title; unquoted
`Talk to the City` returned 476. The `@id` echoes each query as sent, so
it confirms the sending, not the parsing. The type `all` returned the same 4 records as
`articles` for `ブロードリスニング`. Four record lookups at
`/crid/<CRID>.json` after those calls answered `202 text/html` with an
empty body, the challenge described above, on the record path; the
OpenSearch items already saved held the bibliographic fields
(`prism:publicationName`, `prism:number`, `prism:startingPage`), so a hit
can be recorded without the record lookup. Relevant hits were magazine
articles without a DOI, and one JaLC DOI that resolves to J-STAGE.

Again on 2026-11-26, with the registered `appid`, two requests one
second apart. The `articles` call for `ブロードリスニング` answered
`200 application/json;charset=UTF-8` with `opensearch:totalResults` 4
and 4 items, and its `@id` echoed the query without the `appid`. The
lookup of `/crid/1520028426731177088.json`, the first CRID returned,
answered `202 text/html; charset=UTF-8` with an empty body: the challenge
on the record path persists with the `appid`.

Again on 2026-11-27, with the `appid`, six `articles` calls one to three
seconds apart, all `200 application/json;charset=UTF-8`. A three-block
Japanese string with a nested group inside its last block (each block
an OR list, about 50 terms in all) returned 10; its blocks alone
returned 179,546, 20,373 and 1,957, and the first two ANDed 6,528, so
every count was at least the full string's, as the documented grouping
requires, though counts cannot prove the parse. In the default output
the 10 items carried 5 Japanese `description` values and 5 none; with
`lang=en` the same 10 items carried 4 English titles and 2 English
`description` values, the rest in Japanese.
