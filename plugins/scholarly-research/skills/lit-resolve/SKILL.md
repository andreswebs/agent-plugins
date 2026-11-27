---
name: lit-resolve
description: "Resolve a DOI, a title, a citation string, an OpenAlex id, a URL or a formal identifier (LexML URN, ISBN, report number) to one clean bibliographic record with its open-access verdict, across Crossref, OpenAlex, Unpaywall and SciELO, or from the document itself when it has no DOI. Use when a research step needs a reference's canonical DOI and metadata, a title or citation matched to a DOI, the open-access status and PDF of a known DOI, or a record for a report, guidance document, law, dataset or web page that has no DOI."
metadata:
  argument-hint: "a DOI, title, citation string, OpenAlex id, URL or formal identifier, or a file with one per line"
---

# lit-resolve

```bash
AGENT_ARTIFACTS_DIR="${AGENT_ARTIFACTS_DIR:-${PWD}/.local/data/agentartifacts}"
mkdir -p "${AGENT_ARTIFACTS_DIR}/lit-resolve" && echo "${AGENT_ARTIFACTS_DIR}/lit-resolve"
date -u +%Y%m%dT%H%M%SZ
```

Run this once when the run opens, and use the two printed values, the
directory and the run's `<UTC>` stamp, for every path below.

One input in, one **record** out: the shape in
[references/record.md](references/record.md), filled from Crossref (the
authority on whether a DOI exists and what its publisher deposited),
OpenAlex (identifiers, language, citations, abstract, open-access
verdict), Unpaywall (the open-access verdict in its classic shape) and
SciELO (the PID and full-text URLs of a `10.1590` DOI), with Europe PMC
asked only where OpenAlex has no abstract. Every query is
logged as [references/search-log.md](references/search-log.md) describes.

## Environment

| Variable                 | Used for                                            | When unset                                                                             |
| ------------------------ | --------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `RESEARCH_CONTACT_EMAIL` | Crossref `mailto` (polite pool); Unpaywall `email`  | Crossref runs in the public pool; the Unpaywall step is skipped and the record says so |
| `OPENALEX_API_KEY`       | OpenAlex bearer key                                 | Keyless: singleton lookups are free, searches share a small daily budget               |
| `RESEARCH_SEARCH_LOG`    | JSONL file every search appends to                  | `${AGENT_ARTIFACTS_DIR}/lit-resolve/<slug>.<UTC>.search.jsonl`, and the reply names it |
| `RESEARCH_NO_AUTOMATION_HOSTS` | Space-separated hosts the caller forbids any automated request to | Nothing is skipped                                                          |

Set once per run; values never go into a file. No `User-Agent` header is
sent:

```bash
MAILTO="${RESEARCH_CONTACT_EMAIL:-}"
```

Every call: one request at a time, `curl --silent --max-time 30`, exponential
backoff of 1, 2, 4, 8 s on 429 and 5xx, no retry on other 4xx.

## Steps

1. **Classify the input.** A DOI matches `10.` followed by 4 to 9 digits, a
   slash and a suffix; strip a `https://doi.org/` prefix and lower-case it.
   A SciELO PID is `S` plus a hyphenated ISSN plus 13 digits (year, issue
   code, sequence), 23 characters in all. An OpenAlex id is `W`
   plus digits, bare or under `openalex.org/`. A LexML URN starts
   `urn:lex:`; an ISBN is 10 or 13 digits after removing hyphens, given
   bare or as `isbn:`; a report number is given as `report:` and the
   issuer's own number; a bill number is given as `bill:` and the number
   as the legislature prints it. Any other `http` or `https` URL is a URL. Anything
   else is a title or citation string. Done when each input line has a
   class and a normalised value.
2. **Crossref**, per [references/crossref.md](references/crossref.md). A
   DOI goes to `/works/{doi}`; a 404 goes to `/works/{doi}/agency` to
   learn which agency holds it. A string goes to `query.bibliographic`
   with `rows=3`: accept the first hit when its `score` is at least 1.25
   times the second and its title is the same work on inspection. When
   the top two are the same work in two languages (SciELO deposits the
   Portuguese and English records under separate DOIs), accept the hit
   whose title is in the input's language regardless of the ratio. When
   the top two are the same work as a preprint and its published
   version, accept the published version regardless of the ratio and
   keep the preprint's DOI in `ids.preprint_doi`. They are the same work
   when one of the two has type `posted-content` and either Crossref's
   `relation` links them (`is-preprint-of` on one, `has-preprint` on the
   other) or their titles match after the normalisation in
   [references/record.md](references/record.md) and the first author's
   family name is the same. When the top two are a `journal-article`
   and a `book-chapter` with the same normalised title and the same
   first author's family name, the chapter is the article reprinted in a
   book: accept the journal article regardless of the ratio and keep the
   chapter's DOI in `notes`. Else
   mark the input `unmatched` and keep the three candidates in `notes`.
   Inputs classed as an OpenAlex id, a URL or a formal identifier skip to
   step 5. Done when every DOI or string input has a DOI, an agency other
   than Crossref, or `unmatched` with candidates.
3. **OpenAlex**, per [references/openalex.md](references/openalex.md),
   for every DOI: the free singleton `/works/doi:{doi}` for identifiers,
   language, type, counts, the open-access fields and the abstract
   rebuilt from its inverted index. A 404 means OpenAlex lacks the work;
   say so in `notes` rather than searching for it. When OpenAlex gives no
   abstract, set `abstract_at` per [references/record.md](references/record.md)
   from the Crossref response already held, else one Europe PMC lookup:
   `GET https://www.ebi.ac.uk/europepmc/webservices/rest/search` with
   `query=DOI:"{doi}"`, `resultType=core`, `format=json`, reading
   `resultList.result[0].abstractText`; a lookup by identifier, not a
   search. Done when every DOI has OpenAlex fields or an absence note,
   and every DOI without an OpenAlex abstract has `abstract_at` set.
4. **Unpaywall**, per [references/unpaywall.md](references/unpaywall.md),
   only when `RESEARCH_CONTACT_EMAIL` is set: `/v2/{doi}?email=` for the
   verdict, `best_oa_location` first. Keep Unpaywall's `oa_status` and
   OpenAlex's side by side; a disagreement is a finding, not an error,
   and the PDF URL and license are the verdict. Done when every
   Crossref DOI has an Unpaywall verdict, a 404 note, or a skipped note.
5. **No DOI**, per the identity and grey-document rules in
   [references/record.md](references/record.md), for an OpenAlex id, a
   URL, a formal identifier, or a string Crossref left `unmatched` whose
   input names a document or a dataset rather than an article. An OpenAlex id goes to
   the free `/works/{id}`; when OpenAlex gives a DOI, steps 2 to 4 run on
   that DOI. Otherwise the record is described from the document itself,
   its official landing page or the front matter of its PDF, never from
   memory, with `resolved_by: document` and the date read in `accessed`.
   Before requesting a page or a file, compare its host with the entries
   of `RESEARCH_NO_AUTOMATION_HOSTS`: a host that equals an entry or is
   a subdomain of one is not requested by any means, and the input is
   `unmatched` with the reason `host forbids automated access`, for a
   person to describe.
   A dataset is described from its landing page on the issuing body's or
   the repository's site and gets `type: dataset`; when that page cannot
   be read and the issuer serves a metadata record for the same dataset,
   it is described from the metadata, and a survey edition published as
   many tables is one record. A record OpenAlex alone resolved takes its
   `type` through the table in references/record.md, which also names
   the types a document gives itself: a magazine or newspaper article, a
   court decision, software.
   Done when every such input has a record whose identity key is set, or
   `unmatched` with the reason.
6. **SciELO**, per [references/scielo.md](references/scielo.md), for DOIs
   under `10.1590`: follow the DOI redirect to read the PID, then derive
   the current article URL and its PDF and JATS forms. Done when every
   SciELO DOI carries a PID and full-text URLs, or a note that the
   redirect had another shape.
7. **Deduplicate and emit.** Two records are the same work when they
   share any identifier (DOI, OpenAlex id, LexML URN, ISBN, report
   number, bill number, canonical URL) or, failing that, the same normalised title and
   year; keep the first and add the other input to its `notes`, and check
   the same way against any earlier records file the user names. Write
   one record per work in the shape of
   `references/record.md`, copying into `citation_key` a citation key the
   caller gave with the input and generating none, to the path the user named or to
   `${AGENT_ARTIFACTS_DIR}/lit-resolve/<slug>.<UTC>.records.jsonl`,
   `<slug>` naming the batch; append one search-log line per
   `query.bibliographic` call; print the path and, per input, its identity key or
   `unmatched`. Done when every input has a record line, every match
   query a log line, and the reply names both files.

Attribution carried by the records: Crossref metadata is CC0 and its
abstracts stay with their publishers; OpenAlex is CC0; Unpaywall data is
free with the email it was requested under; SciELO content is CC BY
unless the article says otherwise.
