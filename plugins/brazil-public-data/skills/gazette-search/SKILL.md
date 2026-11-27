---
name: gazette-search
description: "Search Brazilian municipal official gazettes (diários oficiais) on Querido Diário by municipality, term and date range, fetch gazette texts, and download a municipality's yearly bulk file. Use when a research step needs what a city published (decrees, ordinances, notices, calls), the count of gazettes mentioning a term over a period, the text of one gazette edition, or a whole year of one city's gazettes."
metadata:
  argument-hint: "a municipality (name or 7-digit IBGE id), the search terms, a date range, and optionally a result cap, 'fetch texts' or 'bulk <year>'"
---

# gazette-search

```bash
AGENT_ARTIFACTS_DIR="${AGENT_ARTIFACTS_DIR:-${PWD}/.local/data/agentartifacts}"
mkdir -p "${AGENT_ARTIFACTS_DIR}/gazette-search" && echo "${AGENT_ARTIFACTS_DIR}/gazette-search"
date -u +%Y%m%dT%H%M%SZ
```

Run this once when the run opens, and use the two printed values, the
directory and the run's `<UTC>` stamp, for every path below.

A municipality, terms and a date range in; a **hits** file out, in the
shape of [references/hits.md](references/hits.md), with the texts the
user asked for saved beside it. Everything comes from Querido Diário, per
[references/querido-diario.md](references/querido-diario.md): keyless,
one request per second, `curl --silent --max-time 90`. Every query is logged
as [references/search-log.md](references/search-log.md) describes, with
`database` `querido-diario` and `interface` `api`.

## Environment

| Variable                 | Used for                           | When unset                                                                                |
| ------------------------ | ---------------------------------- | ----------------------------------------------------------------------------------------- |
| `RESEARCH_SEARCH_LOG`    | JSONL file every search appends to | `${AGENT_ARTIFACTS_DIR}/gazette-search/<slug>.<UTC>.search.jsonl`, and the reply names it |

No credential and no `User-Agent` header are sent; curl's default
identification is all the service sees. Backoff 1, 2, 4, 8 s on 429 and 5xx, with one extra retry of the same URL
on a bare 500 or 520 (they are transient); no retry on 422 or 404.

## A query that still fails

A query that ends in 503 or no answer after the full backoff is logged
with its status and put on the **retry queue**; the run goes on with the
other queries. When they are done, the queue is sent once more, in
order, one request per second. A query that fails again is logged a
second time and reported as a gap, with its terms and window, for a
later run. The source is stopped for the session only when every query
of a batch has failed, since the service fails query by query and one
503 says little about the next query.

## Steps

1. **Resolve the municipality.** A 7-digit id goes to `/cities/{id}`; a
   name goes to `/cities?city_name=`, picked by `state_code` when several
   come back. Record `territory_id`, `territory_name`, `level` and the
   earliest gazette date (`size=1&sort_by=ascending_date`). A level other
   than `"3"` means the city is not searchable; stop and say so. Done when
   the reply can name the id, the level and the first gazette date, or
   states the city is not covered.
2. **Shape the queries.** Quote every multi-word phrase (unquoted words are
   ORed); mark a required extra term with `+`. For each query take the
   count alone with `size=0` over the full window and log it. A count over
   10,000 splits the window by year, then by month, until every piece is
   under it. Done when every (query, window) pair has a logged count below
   10,000 and the user's cap, if any, is noted.
3. **Page the hits.** `size=100`, `sort_by=ascending_date`, `offset` rising
   by 100, `excerpt_size=500`, `number_of_excerpts=3`, `pre_tags=<<`,
   `post_tags=>>`, one page per second, until `offset` reaches the count
   or the cap. Append each item to
   `${AGENT_ARTIFACTS_DIR}/gazette-search/<slug>.<UTC>.hits.jsonl`,
   `<slug>` naming municipality and topic, merging duplicates across
   queries. Done when the file holds min(count, cap) gazettes per window
   and every page call is in the log with `hits`, `kept` and `kept_ids`
   (as `<territory_id>/<date>/<sha1>` taken from `txt_url`).
4. **Fetch texts** only when asked. `GET` each `txt_url` to
   `${AGENT_ARTIFACTS_DIR}/gazette-search/<slug>.<UTC>.<territory_id>-<date>-<edition>.txt`,
   `HEAD` the PDF for size and `etag`, and set `text_file` in the hit.
   Download a PDF only when the user asks for it. Done when every requested
   hit has a `text_file` that exists or a note why not.
5. **Bulk** when the user asks for a whole year. List
   `/aggregates/{state}?territory_id=`, rebuild the URL (the returned
   `file_path` lacks a slash after the host), download to
   `${AGENT_ARTIFACTS_DIR}/gazette-search/<slug>.<UTC>.<year>.zip`, and
   check `md5` against `hash_info`. The aggregate lags the index: report
   `last_updated`. Done when the zip exists, its MD5 matches and the reply
   gives `last_updated`.
6. **Report.** Send the retry queue first, per "A query that still
   fails". Print the hits path, the log path, per query and window the
   count and kept, every query left as a gap, the texts and zips written, and the attribution line
   `Querido Diário (Open Knowledge Brasil), CC BY 4.0, accessed <date>`.
   Done when every queued query answered or is named as a gap, and the
   reply names every file written and carries the attribution line.

Duties on anything published from this run: the attribution line above;
gazette content is public and reusable for any lawful purpose, within the
platform's stated use of consulting public data for access to information
and public oversight; gazettes carry personal data (names, CPF numbers,
addresses), so a quoted passage is read from the saved text and stripped
of it before it leaves the working files; counts are dated, since the
index grows daily.
