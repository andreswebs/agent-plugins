# Crossref for resolving

Base `https://api.crossref.org/v1`; keyless. Send the contact as
`mailto=`, which moves the call into the polite pool (header `x-api-pool:
polite-single`, 10 per second singleton, 3 per second lists); with
`MAILTO` empty the parameter is sent blank and the public pool allows 5
and 1 per second. A 429 arrives with an empty body; back off 1, 2, 4, 8 s. Crossref
asks that responses be cached; records change rarely.

## Lookup by DOI

```bash
doi="10.1590/0102.3772e36nspe19"
curl --silent --max-time 30 --output work.json --write-out '%{http_code}\n' \
    "https://api.crossref.org/v1/works/${doi}?mailto=${MAILTO}"
jq '.message | {DOI, type, title: .title[0], venue: ."container-title"[0],
    year: .issued."date-parts"[0][0], publisher, ISSN, language,
    authors: [.author[]? | {family, given, orcid: .ORCID}],
    refs: ."references-count", cited: ."is-referenced-by-count",
    landing: .resource.primary.URL,
    licenses: [.license[]? | {"content-version", URL}],
    links: [.link[]? | {URL, "intended-application"}]}' work.json
```

- Slashes raw or `%2F` both work; input case is ignored and the output
  `DOI` is lower-cased.
- 404 with `message-type: route-not-found`: not a Crossref DOI. Ask
  `GET /works/{doi}/agency` and read `message.agency.id` (`datacite`,
  `medra`, and so on). 301: the DOI was aliased; follow with `--location`.
- Several DOIs in one call: `filter=doi:a,doi:b` with `rows=100`.
- `language` is null for SciELO deposits; take language from OpenAlex.
- A dataset deposit has `type: dataset`, the depositing body in
  `publisher` and the data collection in `container-title`: on
  2026-11-24, 10.17989/encsr964fec answered with publisher "ENCODE Data
  Coordination Center" and container title "ENCODE Datasets".
- `issued` is the earliest publication date. `title` and
  `container-title` are arrays; the first element is the value. Both
  can carry HTML entities and inline tags as deposited: on 2026-11-24 a
  container title read `Policy &amp; Politics`, one article title held
  `<scp>…</scp>` and a review's title `<b>…</b>`. Decode the entities
  and drop the tags before the value goes into a record.
- Books come with `type` `monograph` or `edited-book` as well as `book`
  (10.7758/9781610448789 and 10.4159/9780674981423 on 2026-11-24).
- A chapter DOI can carry its container's title: on 2026-11-24 Crossref
  gave 10.1787/ccb0b123-en the title of the whole report, while OpenAlex
  held it as a chapter with its own title and an abstract that fit that
  title. When Crossref's `title` for a DOI is the title of the work it
  belongs to and OpenAlex gives a different title whose abstract matches
  it, the record takes OpenAlex's title, the container's title goes to
  `venue`, and `notes` keeps `crossref title: <title>`.

## Match a title or citation

```bash
title="Fatores de Risco e Riscos Psicossociais no Trabalho"
curl --silent --max-time 30 --get --output match.json "https://api.crossref.org/v1/works" \
    --data-urlencode "query.bibliographic=${title}" --data-urlencode "rows=3" \
    --data-urlencode "select=DOI,title,score,issued,container-title,author,type,relation" \
    --data-urlencode "mailto=${MAILTO}"
jq '.message | {total: ."total-results", hits: [.items[] | {DOI, score, type, title: .title[0],
    year: .issued."date-parts"[0][0], first_author: .author[0].family,
    preprint_of: [.relation."is-preprint-of"[]?.id], has_preprint: [.relation."has-preprint"[]?.id]}]}' match.json
```

- `query.bibliographic` searches title, authors, ISSN and year together
  and is what Crossref recommends for reference matching. Pass text with
  `--data-urlencode` so accents survive.
- `total-results` on a query is the size of the whole scored set (over
  ten million for a Portuguese title), never a hit count. The match
  signal is the gap between the first and second `score` (69.6 against
  53.7 on the lab's title). The gap collapses when the runner-up is the
  same article's translation under its own DOI (SciELO: 59.1 and 60.5
  against the sibling on two 2008 titles, 2026-11-10); then the title
  language decides.
- The gap also collapses when the runner-up is the same work's preprint
  or published version (SKILL.md, step 2). The preprint has `type`
  `posted-content`; a deposited link shows as `relation.is-preprint-of`
  on the preprint and `relation.has-preprint` on the article, each
  naming the other's DOI, and is often absent, which is when the title
  and first `author.family` comparison decides. On 2026-11-24 the title
  of 10.1007/s10648-023-09720-w returned the article at 68.1 and its
  preprint 10.21203/rs.3.rs-1386793/v1 at 78.2; the two titles differed
  by a few words, so only the relation, present on both records, tied
  them. Read the scores, not the order: that answer listed the
  lower-scored hit first.
- The gap collapses a third way when a journal issue was republished as
  a book and each chapter got its own DOI: the article (`type`
  `journal-article`) and the chapter (`book-chapter`) carry the same
  title and first `author.family`, and no `relation` links them (the
  chapter's only relation is `is-part-of`, to the book). SKILL.md, step
  2, accepts the article. On 2026-11-24 the chapter
  10.51952/9781447365952.ch002 (2023) scored 51.9 against 51.5 for the
  article 10.1332/030557319x15579230420126 (2020), with identical titles;
  four articles of that issue behaved alike.
- An `author` entry may carry neither `family`, `given` nor `name` (a UnB
  dissertation deposit, 2026-11-10); drop such entries from the record.
- A deposit can also list fewer authors than the article: one listed
  only the second of two authors named on the title page (2026-11-12).
  When the full text is at hand, its title page is the authority for
  the author list, and the record notes where each added name came from.
- Add `query.author=` or `query.container-title=` to narrow a citation
  with a common title. There is no language filter; `filter=prefix:10.1590`
  restricts to SciELO.

## Other forms of one record

Content negotiation at `https://doi.org/{doi}` with `--location` and an `Accept`
of `application/vnd.citationstyles.csl+json`, `application/x-bibtex`, or
`text/x-bibliography; style=associacao-brasileira-de-normas-tecnicas;
locale=pt-BR` for an ABNT citation.

## Verified

Live on 2026-10-17, keyless, API version 4.4.0. Member 530 (SciELO) held
531,146 DOIs; `prefix:10.1590` matched 509,688 works.
