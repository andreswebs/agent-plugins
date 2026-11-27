# Zotero for filing records

Web API base `https://api.zotero.org`, version 3, pinned by the header
`Zotero-API-Version: 3` on every request. The library prefix is
`/users/<id>` or `/groups/<id>`; a group's writes are allowed by its
`libraryEditing` setting and its files count against the owner's quota.
The key travels only in the `Zotero-API-Key` header, never as `key=` in
the URL, and no URL that carried it is logged. At most 4 requests in
flight (this skill sends one); pages hold at most 100 objects (default 25) with the total in `Total-Results` and the next page in the `Link`
header's `rel="next"`; writes take at most 50 objects. Any response may
carry `Backoff: <seconds>`; 429 and 503 carry `Retry-After`.

## Key and permissions

```bash
curl --silent --show-error --max-time 30 "${zotero_headers[@]}" "https://api.zotero.org/keys/current" | jq .
```

200 returns the key's user id and library permissions; 403 means no key
or a wrong one. Without write access to the target library, stop.

## Collection by name

```bash
NAME="${ZOTERO_COLLECTION_NAME}"
curl --silent --show-error --max-time 30 "${zotero_headers[@]}" --output collections.json \
    "${ZOTERO_PREFIX}/collections?format=json&limit=100"
COLLECTION_KEY="$(jq --raw-output --arg n "${NAME}" '.[] | select(.data.name == $n) | .key' collections.json)"
```

`NAME` is the name the user gave, else `ZOTERO_COLLECTION_NAME`. Page by
`Link` when `Total-Results` exceeds 100; a name absent from the first
page may be on a later one. When no collection has the name and the user
named it in this request, create one (documented write shape, not run in
the lab); a name from `ZOTERO_COLLECTION_NAME` that matches nothing stops
the run instead:

```bash
library_version="$(curl --silent --show-error --max-time 30 --head "${zotero_headers[@]}" "${ZOTERO_PREFIX}/items?format=versions&limit=1" |
    awk 'tolower($1)=="last-modified-version:"{print $2}' | tr -d '\r')"
jq --null-input --arg name "${NAME}" '[{name: $name}]' >new-collection.json
if [ -z "${library_version}" ]; then
    echo "no Last-Modified-Version header; collection not created" >&2
else
    curl --silent --show-error --max-time 30 --request POST "${zotero_headers[@]}" --header 'Content-Type: application/json' \
        --header "If-Unmodified-Since-Version: ${library_version}" --data-binary @new-collection.json \
        "${ZOTERO_PREFIX}/collections" | jq '.successful["0"].key'
fi
```

## Deduplicate against a local index (one listing; logged)

The target collection is listed once per run and every input is matched
against that listing on disk. Items outside the collection are not read,
unless the caller asked for the whole library: then the listing path is
`${ZOTERO_PREFIX}/items/top` and everything else below is the same. The API's `q` search decides nothing: on
2026-11-25 `q=<DOI>` with `qmode=everything` answered `Total-Results: 0`
for a DOI an item of the library held, and so did fragments of that DOI,
and across 268 logged calls the query had never returned a hit, so an
empty answer from it is no evidence that the library lacks a work.

List the collection's top-level items, 100 per page, until a page comes
back short:

```bash
start=0
: >library.jsonl
while :; do
    curl --silent --show-error --max-time 60 --get "${zotero_headers[@]}" --dump-header headers.txt --output page.json \
        "${ZOTERO_PREFIX}/collections/${COLLECTION_KEY}/items/top" --data-urlencode "format=json" --data-urlencode "limit=100" --data-urlencode "start=${start}"
    count="$(jq 'length' page.json)" || { echo "listing failed at start=${start}" >&2; break; }
    jq --compact-output '.[]' page.json >>library.jsonl
    [ "${count}" -lt 100 ] && break
    start=$((start + 100))
    sleep 1
done
total="$(awk 'tolower($1) == "total-results:" {print $2}' headers.txt | tr -d '\r')"
```

`items/top` leaves out child attachments and notes; standalone ones are
dropped when the index is built. `Total-Results` on any page is the
number of the collection's top-level items, and the listing is complete
when
`library.jsonl` has that many lines; a status other than 200 on a page
stops the run, since a partial index would pass duplicates. Listing a
whole library of 3,228 top-level items took 33 pages and about three
minutes on 2026-11-25, which is why the collection is the default scope. Log
the listing once: `database: "zotero"`, `interface: "api"`, `query`
`collections/<key>/items/top` or `items/top`, `hits` from `Total-Results`,
`kept` the number of index lines.

Build the index, one line per item:

```bash
jq --compact-output '
  def norm: ascii_downcase | gsub("[^a-z0-9 ]"; "") | gsub(" +"; " ") | ltrimstr(" ") | rtrimstr(" ");
  def bare_url: ascii_downcase | sub("#.*$"; "") | rtrimstr("/");
  def names_a_document: sub("^[a-z][a-z0-9+.-]*://"; "") | sub("[?#].*$"; "") | test("/[^/]");
  def bare_doi: ascii_downcase | sub("^https?://(dx\\.)?doi\\.org/"; "") | ltrimstr(" ") | rtrimstr(" ");
  def extra_line($label): [(.extra // "") | split("\n")[] | select(ascii_downcase | startswith($label))
      | .[($label | length):] | ltrimstr(" ") | rtrimstr(" ")] | first // null;
  select(.data.itemType != "attachment" and .data.itemType != "note") | .data as $d |
  {key, version, item_type: $d.itemType, collections: ($d.collections // []),
   doi: ((if ($d.DOI // "") != "" then $d.DOI else ($d | extra_line("doi:")) end) | if . then bare_doi else null end),
   preprint_doi: (($d | extra_line("preprint doi:")) | if . then bare_doi else null end),
   url: (if ($d.url // "") != "" and ($d.url | names_a_document) then ($d.url | bare_url) else null end),
   openalex: ($d | extra_line("openalex:")),
   lexml_urn: ($d | extra_line("lexml urn:")),
   isbn: (if ($d.ISBN // "") != "" then ($d.ISBN | gsub("-"; "")) else null end),
   number: ([$d.reportNumber, $d.publicLawNumber, $d.docketNumber, $d.number, $d.identifier] | map(select(. != null and . != "")) | first // null),
   bill_number: (if ($d.billNumber // "") != "" then $d.billNumber else null end),
   citation_key: (if ($d.citationKey // "") != "" then $d.citationKey else null end),
   title: (($d.title // $d.nameOfAct // $d.caseName // "") | norm),
   year: ((($d.date // $d.dateEnacted // $d.dateDecided // "") | [scan("[0-9]{4}")] | first) // null)}' library.jsonl >index.jsonl
```

An item type without a `DOI` field keeps its DOI on a `DOI:` line of
`extra`, which the index reads as the item's DOI. A URL is indexed only
when it names a document: with its scheme, query and fragment dropped,
it must still have a path of at least one character after the host's
slash. `https://repository.example.org`, `https://repository.example.org/`
and `https://repository.example.org/?lang=en` name a site, are left on
the item and get `url: null` in the index;
`https://repository.example.org/handle/1/2345` is indexed. On 2026-11-25
two different reports whose records carried only their repository's
front page as `ids.url` would have been matched as one work on it. The `extra` value is
read here to compare identifiers and is never copied anywhere. The
normalisation drops every character outside `a-z`, `0-9` and the space,
accented letters included, the same way on both sides, so two spellings
of one title compare equal.

Match one record; the first line of output is the verdict:

```bash
jq --null-input --raw-output --slurpfile r record.json --slurpfile index index.jsonl '
  def norm: ascii_downcase | gsub("[^a-z0-9 ]"; "") | gsub(" +"; " ") | ltrimstr(" ") | rtrimstr(" ");
  def bare_url: ascii_downcase | sub("#.*$"; "") | rtrimstr("/");
  def names_a_document: sub("^[a-z][a-z0-9+.-]*://"; "") | sub("[?#].*$"; "") | test("/[^/]");
  ($r[0]) as $rec | ($rec.ids // {}) as $ids |
  (($rec.doi // "") | ascii_downcase) as $doi | (($ids.preprint_doi // "") | ascii_downcase) as $pre |
  [ $index[] | . as $i |
    if $doi != "" and ($i.doi == $doi or $i.preprint_doi == $doi) then {status: "matched", key: $i.key, on: "doi", rank: 1}
    elif $pre != "" and $i.doi == $pre then {status: "preprint_held", key: $i.key, on: "preprint doi", rank: 2}
    elif $pre != "" and $i.preprint_doi == $pre then {status: "matched", key: $i.key, on: "preprint doi", rank: 2}
    elif ($ids.url // "") != "" and ($ids.url | names_a_document) and $i.url == ($ids.url | bare_url) then {status: "matched", key: $i.key, on: "url", rank: 3}
    elif ($ids.openalex // "") != "" and $i.openalex == $ids.openalex then {status: "matched", key: $i.key, on: "openalex", rank: 3}
    elif ($ids.lexml_urn // "") != "" and $i.lexml_urn == $ids.lexml_urn then {status: "matched", key: $i.key, on: "lexml urn", rank: 3}
    elif ($ids.isbn // "") != "" and $i.isbn == ($ids.isbn | gsub("-"; "")) then {status: "matched", key: $i.key, on: "isbn", rank: 3}
    elif ($ids.report_number // "") != "" and $i.number == $ids.report_number then {status: "matched", key: $i.key, on: "number", rank: 3}
    elif ($ids.bill_number // "") != "" and $i.bill_number == $ids.bill_number then {status: "matched", key: $i.key, on: "bill number", rank: 3}
    elif ($doi == "" or $i.doi == null) and $rec.year != null and ($rec.title // "") != ""
         and $i.title == ($rec.title | norm) and $i.year == ($rec.year | tostring)
      then {status: "matched", key: $i.key, on: "title and year", rank: 4}
    elif ($rec.citation_key // "") != "" and $i.citation_key == $rec.citation_key
      then {status: "key_held", key: $i.key, on: "citation key", rank: 5}
    else empty end ]
  | sort_by(.rank) | (first // {status: "create"}) | [.status, (.key // ""), (.on // "")] | @tsv'
```

A record whose `ids.url` names a site and not a document is never
matched on it; its other identifiers, then title and year, decide.
`matched` on the item's `preprint_doi` is the published version already
filed, for an input that is its preprint: the same work. Title and year
decide only when the record or the item has no DOI, since two works with
different DOIs can share a title (a preprint and its article, an article
and its reprint). `preprint_held` means the index holds the preprint
as an item of its own: create nothing, send no `PATCH` to that item, and
report its key; replacing it, keeping
both or leaving it is the caller's choice, since changing an item's
metadata can change its citation key.

With the whole-library scope, a matched item whose `collections` lacks
the collection key is updated with `PATCH <prefix>/items/<key>`, body
`{"collections": [<every existing key>, "<COLLECTION_KEY>"]}` and header
`If-Unmodified-Since-Version: <item version>`; `collections` is the
complete list, so omitting a key removes that membership. A
`preprint_held` item is never patched, in either scope.

When the record carries `citation_key` and the matched item's
`citation_key` in the index differs from it (or is `null`), the item is
left as it is and the manifest line gets the note
`citation key differs: item has <key or none>, record gives <key>; not changed`,
repeated in the reply: changing the key of an existing item can break
whatever already cites the old one.

`key_held` is checked last, before an input is marked for creation:
when no identifier and no title and year matched, but the record's
`citation_key` equals, character for character, the `citation_key` of
an item in the index, that item holds the key the new item would take.
On 2026-11-26 a software record
for a project's code repository carried the key of an existing web page
item for the same project, with another URL and another title; neither
identifiers nor title and year matched, and a second item with the same
key was created and deleted by hand.

After each write, append the created items to the index before matching
further inputs, by passing each `successful` object of the write's
answer through the same index filter, so a second input for the same
work is `matched` to the item just made.

## Item from a record

Fetch the template for the item type, then keep only the fields the
template defines:

```bash
item_type="journalArticle"
curl --silent --show-error --max-time 30 --header 'Zotero-API-Version: 3' \
    "https://api.zotero.org/items/new?itemType=${item_type}" --output template.json
jq --null-input --slurpfile t template.json --slurpfile r record.json --arg c "${COLLECTION_KEY}" --arg tags "topic-a,topic-b" '
  ($t[0]) as $tpl | ($r[0]) as $rec | ($rec.ids // {}) as $ids |
  (if $rec.year then ($rec.year | tostring) else null end) as $date |
  (if $rec.type == "bill" then "sponsor" elif $rec.type == "software" then "programmer" else "author" end) as $ct |
  ((($rec.type // "") | ascii_downcase) == "dataset") as $ds |
  def note($label): [($rec.notes // [])[] | select(startswith($label)) | .[($label | length):] | ltrimstr(" ")] | first // null;
  {title: $rec.title, nameOfAct: $rec.title, caseName: $rec.title, date: $date, dateEnacted: $date,
   dateDecided: (note("decided:") // $date), DOI: $rec.doi, citationKey: $rec.citation_key,
   court: $rec.publisher, docketNumber: $ids.report_number, number: $ids.report_number,
   versionNumber: (if $rec.type == "software" then note("version:") else null end), company: $rec.publisher,
   repository: (if $ds then ($rec.venue // $rec.publisher) else null end),
   identifier: (if $ds and ($rec.doi == null) then $ids.report_number else null end),
   publicationTitle: $rec.venue, websiteTitle: $rec.venue, bookTitle: $rec.venue, ISSN: (($rec.issn // []) | join(", ")),
   ISBN: $ids.isbn, reportNumber: $ids.report_number, publicLawNumber: $ids.report_number,
   billNumber: $ids.bill_number,
   legislativeBody: $rec.publisher, institution: $rec.publisher, university: $rec.publisher, publisher: $rec.publisher,
   language: $rec.language, accessDate: $rec.accessed,
   url: ($ids.url // (if ($rec.doi // "") != "" then "https://doi.org/" + ($rec.doi | ascii_downcase) else $rec.oa.landing_url end)),
   abstractNote: $rec.abstract,
   extra: ([(if $ids.openalex and ($rec.doi == null) then "OpenAlex: " + $ids.openalex else empty end),
            (if $ids.lexml_urn then "LexML URN: " + $ids.lexml_urn else empty end),
            (if $ids.preprint_doi then "Preprint DOI: " + ($ids.preprint_doi | ascii_downcase) else empty end)] | join("\n")),
   creators: [($rec.authors // [])[] |
     if (.family // "") != "" then {creatorType: $ct, firstName: (.given // ""), lastName: .family}
     elif (.name // "") != "" then {creatorType: $ct, name: .name}
     else empty end]}
  | with_entries(.key as $k | select(.value != null and .value != "" and ($tpl | has($k))))
  | $tpl + . + {collections: [$c], tags: [($tags | split(",")[]) | {tag: .}]}' >item.json
```

The `url` line keeps the open-access location (`oa.landing_url`) for a
record without a DOI only: such a location names one copy a service
ranked best on the day, not the work. On 2026-11-26 a 2005
journal article's best landing page was an unrelated institutional
repository in another country, which the earlier recipe made the item's
URL.

The object names every field any supported item type takes, and the
template keeps only those its type defines: a `statute` takes the title
as `nameOfAct`, the year as `dateEnacted` and the norm's own number
(`ids.report_number`, for example a law's number and year) as
`publicLawNumber`, a field of the statute type read from
`GET /itemTypeFields?itemType=statute` on 2026-11-25, a `bill` the bill number
as `billNumber` and the legislative body as `legislativeBody`, with its
creators as `sponsor` (Zotero's primary creator type for a bill; confirm
with `GET /itemTypeCreatorTypes?itemType=bill`, **unverified** in the
lab), a `report` the publisher as
`institution`, a `thesis` as `university`, a `webpage` the venue as
`websiteTitle`. A `magazineArticle` and a `newspaperArticle` take the
venue as `publicationTitle` and the year as `date`. A `bookSection` has
no `publicationTitle`; it takes the venue (the book's title) as
`bookTitle`, a field its template carries (read from
`GET /items/new?itemType=bookSection` on 2026-11-26), so without it the
template filter drops the book's title. A `case` takes the
title as `caseName` (the decision as the court styles it), the court
(`publisher`) as `court`, the case number (`ids.report_number`) as
`docketNumber`, and as `dateDecided` the record's `decided: <date>` note
when it has one, else the year; its creators go in as `author`. A
`computerProgram` takes the publishing organisation as `company`, the
record's `version: <release>` note as `versionNumber`, the repository
address as `url`, and its creators as `programmer`. A `standard` takes
its number (`ids.report_number`) as `number`. These field names and
creator types were read from `GET /itemTypeFields` and
`GET /itemTypeCreatorTypes` for each type on 2026-11-25: the `case` type
has `caseName`, `court`, `dateDecided`, `docketNumber`, `reporter`,
`reporterVolume` and `firstPage` and no `title`, `date` or `publisher`;
the `computerProgram` type names its version `versionNumber` and has
`system`, `company` and `programmingLanguage`; neither article type has
a field the journal article lacks that a record fills. The record's
`citation_key`, when present, goes to `citationKey`, a field every item
type of this table had on that date; where a library's schema lacks the
field for a type, the template filter drops it, the key stays pending
and the manifest says `citation key not set: item type has no citationKey field`.
A `dataset` takes the hosting repository as
`repository` (the record's `venue`, else its `publisher`, the issuing
body, when the body hosts the data itself), the edition or reference
year as `date`, its DOI as `DOI` or, without one, the issuer's own
identifier (`ids.report_number`) as `identifier`, and always `url` with
`accessDate`, since a dataset is revised in place. The fields of the
`dataset` type were read from `GET /itemTypeFields?itemType=dataset` on
2026-11-24: `repository`, `repositoryLocation`, `identifier`, `type`,
`versionNumber`, `format`, `date`, `DOI`, `url` and `accessDate` among
them; it has no `publisher` or `institution` field, and its creator
types are `author` and `contributor`.

Record field to item type (only `journalArticle` was run in the lab; a
`dataset` item was created on 2026-11-24;
confirm any other against `GET /itemTypes` and fall back to `report`
for a document or `journalArticle` for an article, with a note):

| Record `type`         | `itemType`        |
| --------------------- | ----------------- |
| `journal-article`     | `journalArticle`  |
| `book`                | `book`            |
| `monograph`           | `book`            |
| `edited-book`         | `book`            |
| `book-chapter`        | `bookSection`     |
| `proceedings-article` | `conferencePaper` |
| `posted-content`      | `preprint`        |
| `Preprint`            | `preprint`        |
| `JournalArticle`      | `journalArticle`  |
| `dissertation`        | `thesis`          |
| `report`              | `report`          |
| `statute`             | `statute`         |
| `bill`                | `bill`            |
| `standard`            | `standard`        |
| `thesis`              | `thesis`          |
| `webpage`             | `webpage`         |
| `magazine-article`    | `magazineArticle` |
| `newspaper-article`   | `newspaperArticle` |
| `court-decision`      | `case`            |
| `software`            | `computerProgram` |
| `dataset`             | `dataset`         |
| `Dataset`             | `dataset`         |

Fields consumed from a record: `doi`, `title`, `authors[].family`,
`.given` and `.name`, `year`, `venue`, `issn`, `type`, `publisher`,
`language`, `citation_key`, `ids.url` (else, for a record with a DOI,
`https://doi.org/<doi>`; else `oa.landing_url`), `ids.isbn`,
`ids.report_number`, `ids.bill_number`, `ids.openalex`, `ids.lexml_urn`
and `ids.preprint_doi` (as `extra` lines, the OpenAlex one only when
there is no DOI, the last as `Preprint DOI: <doi>`, bare and
lower-case), `accessed`,
`abstract`, and from `notes` the `decided:` line of a court decision and
the `version:` line of software. No attachment is ever created: items are metadata only. Tags are `{"tag": "..."}` objects. A record author with
neither `family` nor `given` is dropped before building the item: Zotero
answers 400 "creator object must contain 'firstName'/'lastName' or
'name'" for it (observed 2026-11-10). An author the record lacks is read
from the document's title page, never typed from memory. `creators` take
`firstName` and `lastName`, or `name` for a single-field creator.

## Translation server (optional)

Documented, not run: a self-hosted `zotero/translation-server` on port
1969 runs the desktop's translators without a client. It turns an
identifier or URL into Zotero item JSON and converts item JSON to export
formats. It returns metadata only and applies no citation style; styling
is the CSL step in "Formatted references" below.

### Running it

The server has no authentication and fetches whatever URL it is given,
so it binds to loopback only. A `compose.yaml`:

```yaml
services:
  translation-server:
    image: zotero/translation-server:latest
    restart: unless-stopped
    ports:
      # Loopback only: the server has no auth and fetches arbitrary URLs on request.
      - "127.0.0.1:1969:1969"
```

`docker compose up -d` starts it; `latest` is a placeholder: pin a tag
or digest once one is pulled and checked.

### Endpoints

```bash
ZOTERO_TRANSLATION_SERVER="http://127.0.0.1:1969"
curl --silent --show-error --max-time 3 --output /dev/null --write-out '%{http_code}' "${ZOTERO_TRANSLATION_SERVER}/" || echo "no translation server" >&2
```

| Endpoint                  | Body                                           | Returns                                       |
| ------------------------- | ---------------------------------------------- | --------------------------------------------- |
| `POST /search`            | DOI, ISBN, PMID or arXiv id as `text/plain`    | array of items                                |
| `POST /web`               | URL as `text/plain`                            | array of items, or 300 when ambiguous         |
| `POST /import`            | an import format (BibTeX, RIS) as `text/plain` | array of items                                |
| `POST /export?format=<f>` | items array as `application/json`              | export text (`csljson`, `bibtex`, `ris`, ...) |

A 300 from `/web` carries `url`, `session` and an `items` object mapping
ids to titles; keep only the wanted entries in `items` and post the whole
object back to `/web` as `application/json`.

### Item from a bare DOI

```bash
curl --silent --show-error --max-time 60 --data "${doi}" --header 'Content-Type: text/plain' "${ZOTERO_TRANSLATION_SERVER}/search" >resolved.json
jq --arg c "${COLLECTION_KEY}" '[.[] | .collections = [$c] | .tags = [{tag: "topic-a"}]]' resolved.json >items.json
```

The Web API's own translator save (`POST <prefix>/items` with a
`{"url": ...}` body) is documented on a page marked outdated and is not
used.

### CSL-JSON from item JSON

```bash
curl --silent --show-error --max-time 60 --data @resolved.json --header 'Content-Type: application/json' \
    "${ZOTERO_TRANSLATION_SERVER}/export?format=csljson" >resolved.csl.json
```

CSL-JSON is the style-neutral input every CSL processor reads, so one
file can be formatted in any style.

## Formatted references (CSL)

Zotero formats references with Citation Style Language styles: a `.csl`
file (APA, ABNT, ...) applied by a CSL processor to CSL-JSON. Two routes.

Web API, for items already in the library (the `style` value is a style
id from the Zotero style repository or a URL to a `.csl` file; `locale`
is a CSL locale):

```bash
CSL_STYLE="associacao-brasileira-de-normas-tecnicas"
curl --silent --show-error --max-time 60 "${zotero_headers[@]}" \
    "${ZOTERO_PREFIX}/collections/${COLLECTION_KEY}/items/top?format=json&include=data,citation,bib&style=${CSL_STYLE}&locale=pt-BR&limit=100&itemType=-attachment" |
    jq '.[] | {key, citation, bib}'
```

`include=citation,bib` adds per-item HTML strings; `format=bib` returns
one HTML bibliography instead and is capped at 150 items per request.
Without `style` the default is `chicago-note-bibliography`.

Local, for items not filed, from a CSL-JSON file and a `.csl` style file
taken from the CSL styles repository
(`https://github.com/citation-style-language/styles`):

```bash
CSL_STYLE_FILE="associacao-brasileira-de-normas-tecnicas.csl"
printf -- '---\nnocite: "@*"\n---\n' |
    pandoc --citeproc --bibliography resolved.csl.json --csl "${CSL_STYLE_FILE}" --to plain
```

Swap `--to plain` for `--to html` or `--to markdown` as needed.

## Create, at most 50 per request

```bash
library_version="$(curl --silent --show-error --max-time 30 --head "${zotero_headers[@]}" "${ZOTERO_PREFIX}/items?format=versions&limit=1" |
    awk 'tolower($1)=="last-modified-version:"{print $2}' | tr -d '\r')"
if [ -z "${library_version}" ]; then
    echo "no Last-Modified-Version header; items not written" >&2
else
    curl --silent --show-error --max-time 60 --request POST "${zotero_headers[@]}" --header 'Content-Type: application/json' \
        --header "If-Unmodified-Since-Version: ${library_version}" --data-binary @items.json \
        "${ZOTERO_PREFIX}/items" --dump-header headers.txt --output result.json
    jq '{ok: (.successful | map_values(.key)), unchanged, failed}' result.json
fi
```

- `items.json` is a JSON array; the response maps array index to
  `successful` (`{key, version, ...}`), `unchanged` (a key) and `failed`
  (`{key, code, message}`). A 200 with a non-empty `failed` is partial.
- 412: the version is stale; re-read it and retry once. 428: the
  precondition header is missing. The response `Last-Modified-Version` is
  the library version after the write; keep both for `sources`.
- Item keys are 8 characters from `23456789ABCDEFGHIJKLMNPQRSTUVWXYZ`.

## Citation keys

Better BibTeX runs on the desktop and assigns keys there; an item created
through the Web API has no BBT key until a synced desktop with BBT
processes it. The formula lives in the Better BibTeX preferences of that
desktop (its default is `auth.lower + shorttitle(3,3) + year`); the skill
never prescribes a formula. It writes a key in one case only: a record
that carries `citation_key` has it written to `citationKey` in the item
JSON at creation, and the item is read back through the Web API to
confirm the field holds that value. An item that already exists never
has its key changed by this skill.

Local route, when a desktop answers (`connector/ping` returns 200 within
3 s; the lab had no desktop running, so this is documented only):

```bash
curl --silent --show-error --max-time 3 --output /dev/null --write-out '%{http_code}\n' "http://127.0.0.1:23119/connector/ping"
curl --silent --show-error --max-time 30 --request POST --header 'Content-Type: application/json' --header 'Accept: application/json' \
    --data-binary '{"jsonrpc":"2.0","id":1,"method":"item.citationkey","params":[["ABCD2345","EFGH6789"]]}' \
    "http://localhost:23119/better-bibtex/json-rpc"
```

An item created through the Web API has no key here until the desktop
has synced it: `item.citationkey` answered empty for 22 fresh items with
the desktop running (2026-11-10). Record the key as pending and read it
on a later run.

A bare key means the personal library; a group item is `<libraryID>:<key>`
with the local library id from the `user.groups` method. The reply maps
item key to citation key. `item.regenerate_key` recomputes a key from the
configured formula after metadata changed.

Web API route: read each item with `GET <prefix>/items?itemKey=a,b,c`
(up to 50) and take `data.citationKey` (native field in schema 42), else
the `Citation Key: <key>` line of `data.extra`. Both empty
means pending. On 2026-11-25, in a library on schema 42 with BBT
installed, every item carried its key in `data.citationKey` and `extra`
held no key line; a `PATCH` setting `citationKey` on an item answered
204, and the value was still there after the desktop synced, so a key
written to that field stays as written. The
`extra` value itself is never copied into the manifest.

## Export

Local pull (BBT keys), when the desktop answers; `0` is the personal
library's local id:

```bash
curl --silent --show-error --max-time 60 "http://127.0.0.1:23119/better-bibtex/collection?/0/${COLLECTION_KEY}.biblatex" >out.bib
```

Web API (`format=biblatex`, keys from Zotero's exporter, not BBT), paged
by `Link` at 100 per page and concatenated:

```bash
curl --silent --show-error --max-time 60 "${zotero_headers[@]}" --dump-header headers.txt \
    "${ZOTERO_PREFIX}/collections/${COLLECTION_KEY}/items/top?format=biblatex&limit=100&itemType=-attachment" >out.bib
```

## Local API

A running desktop also serves the same read routes keyless at
`http://localhost:23119/api/users/0/...` (403 when the preference
"Allow other applications on this computer to communicate with Zotero" is
off; writes on Zotero 10+ need a per-application authorisation dialog).
This skill reads only the Better BibTeX endpoints on that port and writes
through the Web API.

## Verified

Guide verified live on 2026-10-16, keyless, against `api.zotero.org`
(schema 42, API version 3), public group 100, the `journalArticle`
template, the schema routes, a 304 on `If-Modified-Since-Version`, and
`include=data,citation,bib&style=apa` on group 100 (returned a
`citation` span and a `csl-bib-body` `bib`). Not run: any authenticated
request or write, the `q` search, the local API, Better BibTeX JSON-RPC,
the pull export, the translation server and its compose file, the ABNT
style id, the `locale` parameter and the pandoc route; every recipe
above marked documented follows the official pages only. On
2026-11-24 three records carrying `ids.preprint_doi` were filed and the
`Preprint DOI:` line was written to `extra`; Crossref's `monograph` and
`edited-book` records were filed as `book` items. On 2026-11-25 the
listing, the index and the match block above were run read-only against
a library of 3,228 top-level items: the index found each of three DOIs
the `q` search had answered empty for, and returned `matched` on a DOI,
on a `Preprint DOI:` line and on title and year, `preprint_held` for a
record whose preprint the library held, and `create` for a DOI it did
not hold; `publicLawNumber` was set on three statute items by `PATCH`
(204) and read back. Later that day 76 items were created with
`citationKey` in the item JSON and all read back with it; the index and
match blocks were run offline on a site-root URL, the same with a query,
and a document URL, and matched only the last; the item block was run
against the live templates of `magazineArticle`, `newspaperArticle`,
`case`, `computerProgram` and `standard`; and nine items were changed to
one of the first four types by `PUT` of the new type's template with the
carried fields (204 each), their `citationKey`, tags and collections
unchanged on reading back. On 2026-11-26 the index and match blocks, as
written, were run offline on two item objects: a record whose citation
key a web page item held, with another URL and title, returned
`key_held` with that item's key; the same record with a free key
returned `create`; a record that matched an item on its URL returned
`matched` although another item held its key; and a record with no key
returned `create`.
On 2026-11-27 the item block, as written, was run offline on a template
and seven records: a record with a DOI and no `ids.url` got the DOI link
as `url` (lower-cased) whatever its `oa.landing_url`, with no `oa` block
too; a record with a DOI and an `ids.url` kept `ids.url`; a record
without a DOI kept `ids.url`, else `oa.landing_url`, else no URL. The
same day one existing item's `url` was replaced by its DOI link with
`PATCH <prefix>/items/<key>`, body `{"url": ...}` and
`If-Unmodified-Since-Version: <item version>` (204); read back, only
`url` and the server's `version` and `dateModified` had changed.
