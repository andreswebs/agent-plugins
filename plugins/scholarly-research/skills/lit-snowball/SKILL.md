---
name: lit-snowball
description: "Snowball citations forward and backward from seed DOIs or OpenAlex ids, across OpenAlex, OpenCitations and Semantic Scholar, with citation counts cross-checked against Crossref. Use when a research step needs the works that cite a known set of papers, the works those papers cite, a citation graph of edges to a chosen depth, or an independent check of a work's citation count."
metadata:
  argument-hint: "one or more DOIs or OpenAlex W ids (or a file with one per line); direction forward, backward or both; depth (default 1)"
---

# lit-snowball

```bash
AGENT_ARTIFACTS_DIR="${AGENT_ARTIFACTS_DIR:-${PWD}/.local/data/agentartifacts}"
mkdir -p "${AGENT_ARTIFACTS_DIR}/lit-snowball" && echo "${AGENT_ARTIFACTS_DIR}/lit-snowball"
date -u +%Y%m%dT%H%M%SZ
```

Run this once when the run opens, and use the two printed values, the
directory and the run's `<UTC>` stamp, for every path below.

Seeds in, a citation **graph** out: a file of **edges** (one citation
link each, with the database that reported it), a file of **candidates**
(every work the walk reached that was not a seed), and a **counts table**
putting each seed's OpenAlex, OpenCitations, Semantic Scholar and Crossref
citation counts side by side; the shapes are in
[references/outputs.md](references/outputs.md). OpenAlex walks the graph
(ids, DOIs, language, both directions in one record); OpenCitations is
the second opinion on counts and the source of record for each citation's
date and self-citation flags; Semantic Scholar adds citation contexts and
intents. Counts differ between databases by design: report every one,
never merge or average them. Citation counts come only from these four
services; SciELO's CitedBy answered wrong or failed on every probe. Every
list query is logged as [references/search-log.md](references/search-log.md)
describes; lookups by identifier are not searches.

## Environment

| Variable                 | Used for                                   | When unset                                                                 |
| ------------------------ | ------------------------------------------ | -------------------------------------------------------------------------- |
| `RESEARCH_CONTACT_EMAIL` | Crossref `mailto` (polite pool)            | Crossref runs in the public pool                                           |
| `OPENALEX_API_KEY`       | OpenAlex bearer key                        | Keyless: singletons free, 1,000 list credits a day shared by the network address, paging stops at 10,000 results |
| `S2_API_KEY`             | Semantic Scholar `x-api-key` header        | Keyless pool: one request every 3 s, 429s expected and retried             |
| `RESEARCH_SEARCH_LOG`    | JSONL file every list query appends to     | `${AGENT_ARTIFACTS_DIR}/lit-snowball/<slug>.<UTC>.search.jsonl`, and the reply names it |

Set once per run; values never go into a file; keys are never requested.
No `User-Agent` header is sent:

```bash
MAILTO="${RESEARCH_CONTACT_EMAIL:-}"
```

Every call: one request at a time, `curl --silent --max-time 30` (longer for OpenCitations list calls, per its page), exponential
backoff of 1, 2, 4, 8 s on 429 and 5xx, no retry on other 4xx. Pace per
service: OpenAlex at most 10 per second keyless; OpenCitations at least
350 ms between calls (180 per minute); Semantic Scholar 3 s between calls
keyless, 1 s with a key.

## Steps

1. **Normalise the seeds.** A DOI matches `10.` followed by 4 to 9 digits,
   a slash and a suffix; strip a `https://doi.org/` prefix and lower-case
   it. An OpenAlex id is `W` plus digits, with any `https://openalex.org/`
   prefix stripped. Resolve each seed with the free OpenAlex singleton in
   [references/openalex.md](references/openalex.md) to its `W` id, DOI,
   `cited_by_count`, `referenced_works` and `referenced_works_count`. A
   404 means OpenAlex lacks the seed: keep its DOI for the other services
   and note the absence. A seed with no DOI and no citation graph (absent
   from OpenAlex, or present with `cited_by_count` 0 and no citations in
   Crossref, OpenCitations or Semantic Scholar), as a report or guidance
   document often is, cannot be snowballed: the edges file and the log
   say so for that seed, no fallback is run, and the reply tells the
   caller it needs a keyword search instead, for example a phrase search
   on its title. A seed whose DOI resolves to a `W` id carrying
   another DOI is a version OpenAlex already merged: note it, seed the
   `W` id once, and keep both DOIs, the caller's and the one OpenAlex
   kept, for steps 4 to 6. The merge is OpenAlex's own view; the other
   services index a work under the DOI they were given. On 2026-11-13 an
   arXiv DOI that OpenAlex had merged into a repository DOI was known to
   Semantic Scholar only under the arXiv DOI (292 citations; the
   repository DOI answered 404), and to OpenCitations under both, with 6
   and 1 citations.
   Then look for other versions of each caller-given seed with the title
   search in [references/openalex.md](references/openalex.md): the same
   work can sit in OpenAlex as a preprint, a working paper, a report and
   a journal article, each with its own citing works. A hit is a version
   when its title matches the seed's after lower-casing and dropping
   punctuation and it shares the seed's first author; a hit typed
   `dataset`, `study-registration`, `peer-review`, `paratext`,
   `erratum` or `book-review` is a related record, noted, not seeded. So
   is a hit typed `article` that is a review of a book by its title: the
   title carries a review label ("Book review", "Resenha", "Review of")
   or is the book's full citation (author, title, publisher, year). It
   is handled as a `book-review` record is, and the notes say it was
   recognised by title. When the seed is a book, a hit whose title
   equals the seed's and whose first author differs from the book's is a
   **probable review**: it is not a version, it is not seeded, and it is
   listed under the counts table with its counts. Every version with
   `cited_by_count` above 0 joins the batch as a seed, noted as a version
   of the caller's seed; the later steps walk each one and step 7's
   deduplication merges what they share. Done when every seed has a `W`
   id, an absence note or a no-citation-graph note, every caller-given
   seed has its versions seeded or a no-versions note, and `<slug>` names
   the batch.
2. **Forward in OpenAlex** (direction forward or both), per
   [references/openalex.md](references/openalex.md): `filter=cites:W…`,
   `per_page=100`, `page` up to 100; past 10,000 results cursor paging
   needs the key, otherwise note the cap. Each result is an edge `from`
   the citing work `to` the seed, source `openalex`, and a candidate.
   One search-log line per seed with `hits` from `meta.count`. Done when
   every seed's edges number `meta.count` or carry a cap note.
3. **Backward in OpenAlex** (direction backward or both): fetch the seed's
   `referenced_works` in chunks of 100 ids with `filter=openalex_id:`
   joined by `|`. Each record is an edge `from` the seed `to` the cited
   work and a candidate; fewer records than ids is a merged or deleted
   work, noted. One search-log line per chunk. A related record of
   another work type that shares the seed's title (a review, an erratum),
   or a review or probable review recognised in step 1,
   is never walked in the seed's place, whatever reference list it
   carries: the counts table reports it, with its id and reference
   count, and the caller decides. Done when every seed's referenced ids
   are fetched or noted.
4. **OpenCitations**, per [references/opencitations.md](references/opencitations.md),
   for every seed DOI (both DOIs of a merged seed, step 1): `citation-count` and `reference-count`, then
   `citations/doi:` and `references/doi:` for the walked directions. Each
   row is an edge with source `opencitations`, carrying `oci`, `creation`,
   `journal_sc` and `author_sc`; a row whose other end is `omid:` only is
   resolved through Meta before it becomes a candidate. `[]` or `"0"`
   means the DOI is unknown there, noted. One search-log line per list
   call. Done when every seed has both counts and its rows, or an absence
   note.
5. **Semantic Scholar**, per [references/semantic-scholar.md](references/semantic-scholar.md),
   for every seed DOI (both DOIs of a merged seed, step 1): `citationCount` and `referenceCount` from
   the paper lookup, then `citations` and `references` for the walked
   directions with `contexts`, `intents` and `isInfluential`, `limit=1000`,
   paging by `offset` while `next` is present and `offset + limit` stays
   under 10,000 (note the cap beyond). Each item is an edge with source
   `semantic-scholar` and a candidate when it carries a DOI; language is
   `null` from this service. One search-log line per page. Done when every
   seed has both counts and its items, a 404 note, or a cap note.
6. **Crossref count**, with the lookup in
   [references/outputs.md](references/outputs.md): `is-referenced-by-count`
   and `references-count` from `/works/{doi}` for every seed DOI (both
   DOIs of a merged seed); a 404 is noted, and is what a DataCite DOI,
   such as an arXiv or repository DOI, answers. Done when every seed DOI
   has both numbers or a note.
7. **Deepen** when depth is above 1: deduplicate candidates by `W` id,
   else DOI, drop seeds and works already walked, and run steps 1 to 6
   again with the remaining candidates as seeds at depth plus one, keeping
   the same direction; the version search in step 1 runs for the
   caller's seeds only, since it costs 10 credits a seed. Done when the frontier at the requested depth has
   been walked and every candidate carries the depth it was first reached
   at.
8. **Not walkable backward.** When backward was asked and a seed has
   citations but no service returned a reference list for it (steps 3 to
   5 collected no backward edge), as a book or a report often has, the
   counts table and the reply record it as **not walkable backward**,
   with the four reference counts, and the reply says its reference list
   must be read from the document itself. What decides is the list, not
   the count: a service that reports a reference count above 0 and
   returns no list has it **withheld**, and its cell in the counts table
   shows the count with `withheld` beside it. Done when every such seed
   carries that note and no edge stands in for its references.
9. **Emit.** Write `<slug>.<UTC>.edges.jsonl`, `<slug>.<UTC>.candidates.jsonl`
   and `<slug>.<UTC>.counts.md` under `${AGENT_ARTIFACTS_DIR}/lit-snowball/`
   or to paths the user named, in the shapes of
   [references/outputs.md](references/outputs.md); print the counts table
   in the reply with one line per seed naming where the databases disagree.
   Done when every edge and candidate has a line, every list call a
   search-log line, and the reply names all three files and the log.

Attribution carried by the outputs: OpenAlex data is CC0; OpenCitations
data is CC0; Crossref metadata is CC0; Semantic Scholar data is under
ODC-BY or CC BY-NC per dataset, and any published output that used its
API must credit "Semantic Scholar" and cite Kinney et al. 2023, "The
Semantic Scholar Open Data Platform" (arXiv 2301.10140). Citation
contexts are sentence fragments from the citing papers and stay under
their copyright; the outputs carry links, never PDFs.
