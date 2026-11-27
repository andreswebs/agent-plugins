# The snowball outputs

Three files per run share one stem,
`${AGENT_ARTIFACTS_DIR}/lit-snowball/<slug>.<UTC>`, `<slug>` naming the
seed batch. Every field is present in every line; a value a service did
not give is `null`, never omitted. Identifiers: `W…` is the bare OpenAlex
id, DOIs are bare and lower-case, and a work OpenAlex lacks is identified
as `doi:<doi>`, else `omid:br/<digits>`, else `s2:<paperId>`.

## Edges, `.edges.jsonl`

One line per citation link per reporting database. `from` is always the
citing work and `to` the cited work, whichever direction the walk ran;
`direction` says which walk found it and `seed` which seed it hangs off.
The same link reported by two databases is two lines.

```json
{"from": "W…", "to": "W3108335682", "direction": "forward", "source": "openalex", "seed": "W3108335682", "depth": 1, "from_doi": "10.…", "to_doi": "10.1590/0102.3772e36nspe19", "oci": null, "creation": null, "journal_sc": null, "author_sc": null, "contexts": null, "intents": null, "is_influential": null, "ts": "2026-10-19T04:07:35Z"}
{"from": "omid:br/06010055452", "to": "doi:10.1162/qss_a_00023", "direction": "forward", "source": "opencitations", "seed": "doi:10.1162/qss_a_00023", "depth": 1, "from_doi": null, "to_doi": "10.1162/qss_a_00023", "oci": "06010055452-062501777134", "creation": "2020", "journal_sc": "no", "author_sc": "no", "contexts": null, "intents": null, "is_influential": null, "ts": "2026-10-19T04:07:41Z"}
```

- `source` is `openalex`, `opencitations` or `semantic-scholar`.
- `oci`, `creation`, `journal_sc`, `author_sc` come only from
  OpenCitations; `contexts`, `intents`, `is_influential` only from
  Semantic Scholar, where empty arrays are kept as given.
- `ts` is when the request that returned the row was sent.

## Candidates, `.candidates.jsonl`

One line per work reached that is not a seed, deduplicated by `W` id,
else DOI, else the service id; the first database to reach it fills the
line and later ones only add to `found_by`.

```json
{"id": "W…", "doi": "10.…", "title": "…", "year": 2023, "language": "pt", "type": "article", "cited_by_count_openalex": 3, "found_by": ["openalex", "opencitations"], "via_seed": "W3108335682", "direction": "forward", "depth": 1, "notes": []}
```

- `language` comes from OpenAlex only; OpenCitations and Semantic Scholar
  give none, so a candidate they alone reached carries `null`.
- No service in the walk filters by language, and Semantic Scholar has
  no language field or filter at all, so a language restriction is
  applied to the candidates file after the walk, never by dropping a
  service's results during it. A candidate with `language: null` and a
  DOI takes its language from the free OpenAlex lookup by DOI when
  OpenAlex holds it; one with neither stays `null` for a person to judge.
- `depth` is the depth at which the work was first reached; `via_seed`
  the seed of that first edge.
- `notes` holds free text: a merged id, an `omid:` only row resolved
  through Meta, a title taken from Semantic Scholar.

## Counts table, `.counts.md`

One row per seed, every count as the service reported it on the run's
date, plus the number of edges the run actually collected from each
service in each direction. A dash marks a service that lacked the work;
"cap" marks a walk the service truncated.

```markdown
| seed | doi | OpenAlex cited_by / refs | OpenCitations citations / refs | Semantic Scholar citations / refs | Crossref is-referenced-by / refs | collected fwd (oa / oc / s2) | collected bwd (oa / oc / s2) |
| ---- | --- | ------------------------ | ------------------------------ | --------------------------------- | -------------------------------- | ---------------------------- | ---------------------------- |
| W3108335682 | 10.1590/0102.3772e36nspe19 | 35 / 49 | 16 / 36 | n / n | n / 66 | 35 / 16 / n | 48 / 36 / n |
```

A version seeded in step 1 gets its own row, its seed cell reading
`W… (version of W…)`, so the separate citation sets stay visible.
A merged seed keeps one row: its `doi` cell lists the caller's DOI then
the one OpenAlex kept, and each OpenCitations, Semantic Scholar and
Crossref cell gives one count per DOI in that order, for example
`6 / 0 ; 1 / 0`, with a dash for a DOI the service lacks. Edges from both
DOIs are deduplicated in step 7 like any other.

A seed with citations for which no service returned a reference list
keeps its row, the four reference counts as reported, and under the
table the line `W…: not walkable backward; read the reference list from
the document`. A service that reports a count above 0 and returns no
list has its reference cell written as the count followed by
`withheld`, for example `41 / 6 withheld`. On 2026-11-24 three seeds had
0 references in three services and 1, 6 and 2 in the fourth, which
returned no list for any of them. A related record of another type that shares a seed's
title is listed under the table too, as `W… (book-review of W…): n
references, not walked`; it gets no row and no edges. A review typed
`article` and recognised by its title is listed the same way, as `W…
(review of W…, by title): n references, not walked`. A probable
review, a record with a book seed's exact title under another first
author, is listed as `W… (probable review of W…, same title, first
author <name>): cited by n, n references, not walked`. On 2026-11-24 a
2020 report had 1,746 citations in OpenAlex and 313 in Crossref and a
reference list in none of the four services.

The OpenAlex and OpenCitations figures above were observed on 2026-10-16;
`n` stands for a number the run fills in. The databases count different things (OpenAlex matched references,
OpenCitations links from its sources, Semantic Scholar its own parse,
Crossref deposited references and member-reported inbound links), so a
gap between columns is a finding to report, never an error to reconcile.

### Crossref counts

Base `https://api.crossref.org/v1`; keyless. With `MAILTO` set, the call
runs in the polite pool (10 singletons per second); without it, the
public pool allows 5.

```bash
curl --silent --max-time 30 --output cr.json --write-out '%{http_code}\n' \
    "https://api.crossref.org/v1/works/${doi}?mailto=${MAILTO}"
jq '.message | {DOI, cited: ."is-referenced-by-count", refs: ."references-count"}' cr.json
```

`is-referenced-by-count` is a count only; the public API lists no citing
works behind it. `references-count` equals the deposited reference array's
length, DOI-matched or not. A 404 with `message-type: route-not-found` is
a DOI Crossref does not hold.
