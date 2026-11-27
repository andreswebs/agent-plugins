---
name: lit-harvest
description: "Harvest every record a provider holds for a collection, journal, set or category within a date window over OAI-PMH, from SciELO, SciELO Preprints or arXiv, into one JSONL file plus a manifest a stopped harvest resumes from. Use when a research step needs all records of a set changed since a date, an incremental sync since the last harvest, or a stopped harvest continued from its last resumption token."
metadata:
  argument-hint: "provider (scielo, scielo-preprints, arxiv), a set, journal ISSN or category, a from date, optional until date and metadata format"
---

# lit-harvest

```bash
AGENT_ARTIFACTS_DIR="${AGENT_ARTIFACTS_DIR:-${PWD}/.local/data/agentartifacts}"
mkdir -p "${AGENT_ARTIFACTS_DIR}/lit-harvest" && echo "${AGENT_ARTIFACTS_DIR}/lit-harvest"
date -u +%Y%m%dT%H%M%SZ
```

Run this once when the run opens, and use the two printed values, the
directory and the run's `<UTC>` stamp, for every path below.

One harvest request in (provider, set, from, until, metadata format), two
files out: the **records** file, one JSON line per OAI record, and the
**manifest**, one JSON line per page fetched whose last line carries the
resumption token a stopped harvest resumes from; both shapes are in
[references/record.md](references/record.md). Each provider's endpoint,
sets, page size, token lifetime and quirks are on its own page:
[references/scielo.md](references/scielo.md),
[references/scielo-preprints.md](references/scielo-preprints.md),
[references/arxiv.md](references/arxiv.md). Every harvest is logged as
[references/search-log.md](references/search-log.md) describes.

## Environment

| Variable                 | Used for                           | When unset                                                                                |
| ------------------------ | ---------------------------------- | ----------------------------------------------------------------------------------------- |
| `RESEARCH_SEARCH_LOG`    | JSONL file every harvest appends to | `${AGENT_ARTIFACTS_DIR}/lit-harvest/<slug>.<UTC>.search.jsonl`, and the reply names it    |

No provider takes a key, and no `User-Agent` header is sent. arXiv blocks
clients that look like crawlers, so keep to its pace and say so in the
reply if it refuses.

Every call: one request at a time, `curl --silent --get` with every
parameter passed through `--data-urlencode` (set names carry spaces and
accents), the timeout and the gap between requests the provider page
names, exponential backoff of 1, 2, 4, 8 s on 429 and 5xx, no retry on
other 4xx. An OAI-PMH error arrives as HTTP 200 with an
`<error code="...">` element, so read the body, never the status alone.

## Steps

1. **Fix the request.** Provider, set (`all` when none), `from`, optional
   `until` (`YYYY-MM-DD`), metadata prefix (the provider page's default
   when none). The slug is `<provider>.<set>.<from>` lower-cased with
   every character outside `a-z`, `0-9`, `.` and `-` replaced by `-`.
   List `${AGENT_ARTIFACTS_DIR}/lit-harvest/<slug>.*.manifest.jsonl`: when
   the newest one's last line is not an `end` with status `complete`, that
   harvest is unfinished and this run resumes it, appending to its records
   file and manifest; otherwise this run opens `<slug>.<UTC>.records.jsonl`
   and `<slug>.<UTC>.manifest.jsonl`. The stem belongs to the harvest,
   not the run, and nothing is ever rewritten. Done when the five
   parameters, the slug, fresh or resumed, and both file paths are fixed.
2. **Open the list.** Append the manifest `start` line. Fresh:
   `verb=ListRecords` with `metadataPrefix`, `set` (omitted for `all`),
   `from`, and `until` only where the provider page says the server takes
   it. Resumed: `verb=ListRecords` and `resumptionToken` from the last
   `page` line, nothing else; a `badResumptionToken` (tokens expire, each
   page says when) restarts from `from`, and records whose identifier is
   already in the records file are skipped as they arrive. A
   `noRecordsMatch` error is a complete harvest of zero records. Done when
   the first response is on disk and parsed, or its error code is in the
   manifest.
3. **Page.** For each response: drop records whose header datestamp is
   later than `until` (every provider; datestamps are modification or
   re-index times, never publication dates, and SciELO Preprints rejects
   `until` outright), append the remaining records in the shape of
   `references/record.md`, append a manifest `page` line (page number,
   request, status, bytes, records, `completeListSize`, `cursor`, next
   token), wait the provider's gap, then send the token. Log every page's
   `completeListSize`, since SciELO's drifts between pages. Done when a
   response carries no token or an empty token element (`end` with
   `complete`), or the run stops with the last token in the manifest
   (`end` with `stopped`), or an error ends it (`end` with `failed` and
   the code).
4. **Close and log.** Append one search-log line: `database` the provider,
   `interface` `oai-pmh`, `query` the filter expression as sent
   (`set=... from=... until=...`), `filters` with set, from, until and
   metadataPrefix, `url` the first request's URL, `hits` the last
   `completeListSize` or `null`, `kept` the records written by this run,
   `kept_ids` `[]`, `export` the records file, `notes` pages, status,
   resumed-from and the last token. Print the records path, the manifest
   path, pages fetched, records written, and the end status. Done when
   the manifest ends on an `end` line, the log line exists, and the reply
   names both files and says whether the harvest is complete.

Attribution carried by the records: SciELO content is CC BY unless the
article says otherwise, and no terms for automated access beyond that were
found, so published outputs cite SciELO and the collection; SciELO
Preprints records are CC BY 4.0; arXiv metadata is CC0, arXiv full text may
be read but never re-served (link to the abstract page), and arXiv asks
published work to carry "Thank you to arXiv for use of its open access
interoperability." Author names in the records are personal data: keep
them in the records file, not in a derived public list without need.
