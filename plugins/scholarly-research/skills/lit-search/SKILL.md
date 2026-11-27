---
name: lit-search
description: "Keyword-search scholarly literature across OpenAlex, Europe PMC, CORE, arXiv, BDTD and CiNii, choosing sources by query language, and find grey literature on the web, into one deduplicated JSONL of candidate hits with every query logged. Use when a research plan's search block needs running, when a topic needs candidate references gathered from several databases, when a Portuguese, English or Japanese search string must be run reproducibly, or when reports, guidance or laws named by a plan must be located."
metadata:
  argument-hint: "one or more search strings, or a plan's search block (strings with optional date range, language, sources, cap)"
---

# lit-search

```bash
AGENT_ARTIFACTS_DIR="${AGENT_ARTIFACTS_DIR:-${PWD}/.local/data/agentartifacts}"
mkdir -p "${AGENT_ARTIFACTS_DIR}/lit-search" && echo "${AGENT_ARTIFACTS_DIR}/lit-search"
date -u +%Y%m%dT%H%M%SZ
```

Run this once when the run opens, and use the two printed values, the
directory and the run's `<UTC>` stamp, for every path below.

Search strings in, one **hits** file out: the shape in
[references/hit.md](references/hit.md), one line per candidate work,
deduplicated by DOI across sources. Each source is a reference page;
every query sent to every source appends one line to the search log as
[references/search-log.md](references/search-log.md) describes. Response
bodies are kept under `${AGENT_ARTIFACTS_DIR}/lit-search/<slug>.<UTC>.raw/`.

## Environment

| Variable                 | Used for                                    | When unset                                                    |
| ------------------------ | ------------------------------------------- | ------------------------------------------------------------- |
| `OPENALEX_API_KEY`       | OpenAlex bearer key                         | keyless: searches cost 10 of a 1,000-credit daily budget shared by the network address |
| `CORE_API_KEY`           | CORE bearer key                             | keyless: 10 requests a minute, 100 a day, metadata only       |
| `CINII_APPID`            | CiNii `appid`, a condition of use           | no CiNii call is made; the reply reports CiNii as skipped for want of a key and names the run's Japanese strings for a human to run |
| `RESEARCH_SEARCH_LOG`    | JSONL file every search appends to          | `${AGENT_ARTIFACTS_DIR}/lit-search/<slug>.<UTC>.search.jsonl`, and the reply names it |

Set once per run; values never go into a file. No `User-Agent` header is
sent to any host:

```bash
RAW="${AGENT_ARTIFACTS_DIR}/lit-search/<slug>.<UTC>.raw"
mkdir -p "${RAW}"
```

Every call: one request at a time, `curl --silent --max-time 60 --get` with
`--data-urlencode` for every parameter, exponential backoff of 1, 2, 4, 8 s
on 429 and 5xx, no retry on other 4xx, and the source's own pace where its
page names one (arXiv 3 s, BDTD 4 to 5 s, CORE 6 s, Europe PMC and CiNii 1 s).

## Sources by language

| Query language | Sources, in order                      |
| -------------- | -------------------------------------- |
| `pt`           | openalex, europe-pmc, bdtd, core       |
| `en`           | openalex, europe-pmc, arxiv, core      |
| `ja`           | cinii, openalex                        |

A source list in the input replaces the row. These six are the scholarly
sources this skill runs; a request for another is answered with this
table. Grey literature (reports, guidance, laws) is found on the web in
step 9, whatever the language.

## Steps

1. **Parse the search block.** For each string record its language
   (`pt`, `en` or `ja`; infer from the script and words when unstated),
   its date window (`from` and `to` years; open when unstated), its
   sources (the table row unless listed) and its cap per source (100 when
   unstated), then write each source's form of the string by the rules in
   [references/query-translation.md](references/query-translation.md).
   Note the plan's named **venues** (journals and proceedings) for step 8
   and its grey-literature seeds (named institutions and documents) for
   step 9. Choose `<slug>` from the plan or topic. Done when every string
   has those four values and one translated form per source, the venues
   and the seeds are listed, and the slug is fixed.
2. **OpenAlex**, per [references/openalex.md](references/openalex.md):
   one `title_and_abstract.search` filter call per string with
   `language:` and the date bounds, `per_page` at the cap. Read
   `X-RateLimit-Remaining` first and stop paid calls when it is below 10.
   Done when every string has a saved response or a budget note, and a
   log line carrying `meta.count` and `meta.x_query.oql`.
3. **Europe PMC**, per [references/europe-pmc.md](references/europe-pmc.md):
   one `search` call per string, inside `TITLE_ABS:(...)`, with `PUB_YEAR`
   bounds; `LANG:por` for
   Portuguese, and for Portuguese a second call on the SciELO Preprints
   slice (`SRC:PPR AND PUBLISHER:"SciELO Preprints"`, no `LANG` clause).
   Test every body for `errCode`. Done when every string has its
   response, its preprint response when Portuguese, and a log line each
   carrying `hitCount`.
4. **CORE**, per [references/core.md](references/core.md): one
   `search/works/` call per string with `yearPublished` bounds and
   `language.code:`, `exclude=fullText`, six seconds apart. Done when
   every string has a response or a quota note, and a log line carrying
   `totalHits` and `searchId`.
5. **arXiv**, per [references/arxiv.md](references/arxiv.md), English
   strings only: one query API call sorted by relevance, with a
   `submittedDate` clause when a window is set, three seconds apart, the Atom converted to JSON. Done
   when every string has a converted response and a log line carrying
   `totalResults` and the feed title.
6. **BDTD**, per [references/bdtd.md](references/bdtd.md), Portuguese
   strings only: one `search` call per string with a `publishDate` filter,
   sorted by relevance, five seconds apart, at most two `filter[]`
   values. On a 429 stop the source for the run. Done when every string
   has a response or a stop note, and a log line carrying `resultCount`,
   the sort sent and, when `resultCount` exceeds the cap, a cap note
   with both numbers.
7. **CiNii**, per [references/cinii.md](references/cinii.md), Japanese
   strings only, and only with `CINII_APPID` set. Without it no CiNii
   call is made: the reply reports CiNii as skipped for want of a key and
   names the run's Japanese strings for a human to run, and the step is
   done. With it: one `articles` call per string, translated into CiNii's
   documented syntax, with `from`, `until` and `languageType=ja`, `count`
   at the cap. A string carrying an operator CiNii does not support is
   instead run as one call per distinct term, every call logged and the
   hits merged, per "CiNii: translation and the single-term fallback" in
   [references/query-translation.md](references/query-translation.md). Done when every
   string has its response or its per-term responses, and a log line per
   call carrying `opensearch:totalResults` and the echoed `@id`.
8. **Venue pass**, when the plan names journals or proceedings, after
   the open searches of steps 2 to 7: for each venue, look up its source
   records in OpenAlex and choose the ones that are the venue, per
   "Venues" in [references/openalex.md](references/openalex.md); a
   renamed or merged venue can sit under one record or several, and
   proceedings under several. Then rerun every plan string in OpenAlex
   with the chosen ids as one more filter clause, the other clauses
   unchanged. A venue with no record is a coverage gap, named in the
   reply. Done when every venue has a lookup log line whose `kept_ids`
   are the chosen source ids and whose `notes` say why each was chosen
   or left out, or a gap note, and every string has a saved response and
   a log line carrying the source filter for the venues that have ids.
9. **Grey literature**, per [references/web.md](references/web.md),
   when the plan names seeds or asks for grey literature: the seeds on
   their issuing bodies' sites first, then web searches restricted to
   institutional domains, with whatever web search capability the
   environment offers. Done when every seed is a hit or a logged miss,
   every web query has a log line, and every kept document has a hit
   line with `id_type: "url"`.
10. **Merge, emit and reply.** Map every saved response to hit lines
    with its page's `jq`, deduplicate as `references/hit.md` says, and
    write `${AGENT_ARTIFACTS_DIR}/lit-search/<slug>.<UTC>.hits.jsonl` (or
    the path the user named; never over an existing file). Reply with the
    hits path, the log path, per string per source the service total
    and the number kept, any source skipped and why, and for the venue
    pass the ids used and any venue without a record. Done when every string has one log line per
    source it ran against, every kept hit has one line, the DOI column
    holds no duplicates, and the reply names both files.

Duties carried by the hits file: OpenAlex and arXiv metadata are CC0;
arXiv full text is never re-served and a published output acknowledges
arXiv with "Thank you to arXiv for use of its open access
interoperability"; Europe PMC data is free; CORE asks research projects to
contact it for a license and forbids PDF harvesting outside its API; BDTD
and CiNii records are metadata only, and a hit never copies an author's
Lattes profile URL; a CiNii abstract is reused only when its
`abstractLicenseFlag` is `allow`, and an `appid` never appears in any
file or link.
