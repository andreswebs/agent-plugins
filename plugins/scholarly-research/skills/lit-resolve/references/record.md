# The resolved record

One JSON object per input, one per line in a `.records.jsonl` file. Every
field is present; a value the services did not give is `null`, never
omitted, so a reader can tell "not asked" from "not known" by reading
`sources` and `notes`.

```json
{
  "input": "Fatores de Risco e Riscos Psicossociais no Trabalho: Definição e Implicações",
  "input_kind": "title",
  "doi": "10.1590/0102.3772e36nspe19",
  "resolved_by": "crossref",
  "title": "Fatores de Risco e Riscos Psicossociais no Trabalho: Definição e Implicações",
  "authors": [{"family": "Silva", "given": "Ana", "orcid": "https://orcid.org/0000-0002-5188-7110"}],
  "year": 2020,
  "venue": "Psicologia: Teoria e Pesquisa",
  "issn": ["0102-3772", "1806-3446"],
  "type": "journal-article",
  "publisher": "FapUNIFESP (SciELO)",
  "language": "pt",
  "ids": {"openalex": "W3108335682", "pmid": null, "scielo_pid": "S0102-37722020000100501", "lexml_urn": null, "isbn": null, "report_number": null, "bill_number": null, "url": null, "preprint_doi": null},
  "accessed": null,
  "citation_key": null,
  "oa": {
    "is_oa": true,
    "status_openalex": "diamond",
    "status_unpaywall": "gold",
    "pdf_url": "https://www.scielo.br/j/ptp/a/.../?format=pdf&lang=pt",
    "landing_url": "https://www.scielo.br/j/ptp/a/.../?lang=pt",
    "license": "cc-by",
    "version": "publishedVersion"
  },
  "counts": {"cited_by_openalex": 12, "is_referenced_by_crossref": 9, "references_crossref": 66},
  "abstract": "…",
  "abstract_at": null,
  "sources": [
    {"service": "crossref", "url": "https://api.crossref.org/v1/works/10.1590/0102.3772e36nspe19", "ts": "2026-10-19T04:07:35Z", "status": 200},
    {"service": "openalex", "url": "https://api.openalex.org/works/doi:10.1590/0102.3772e36nspe19", "ts": "2026-10-19T04:07:36Z", "status": 200},
    {"service": "unpaywall", "url": "https://api.unpaywall.org/v2/10.1590/0102.3772e36nspe19", "ts": "2026-10-19T04:07:37Z", "status": 200},
    {"service": "scielo", "url": "https://doi.org/10.1590/0102.3772e36nspe19", "ts": "2026-10-19T04:07:38Z", "status": 301}
  ],
  "notes": []
}
```

Field rules:

- A DOI Crossref does not hold (`/agency` answers `datacite`, as for
  arXiv and Zenodo DOIs) takes `title`, `authors`, `type`, `venue` and
  `year` from DataCite's record, `GET https://api.datacite.org/dois/{doi}`
  (no key): `titles[0].title`, `creators[]` with `familyName` and
  `givenName` (an organisation has only `name`, kept as `{name}`),
  `publicationYear`, `types.resourceTypeGeneral`, `publisher`; set
  `resolved_by: datacite` and say so in `notes`. For a `JournalArticle`
  the journal is `container.title`, taken as `venue`, and
  `container.identifier` with its `identifierType` (`ISSN` or `EISSN`)
  goes to `issn`. On 2026-11-13, 10.18148/srm/2026.v20i2.8624 answered
  with `container.type: Series`, `title: Survey Research Methods`, an
  EISSN, volume, issue and pages, and `relatedItems` repeated the title
  under `relationType: IsPublishedIn`. OpenAlex still supplies
  `ids` and the open-access fields. Do not build `family` and `given` by
  splitting an OpenAlex `display_name`: on 2026-11-10 that turned
  "Carolyn Q. Zou" into family "Q.", given "Zou, Carolyn".
- A DOI that no agency knows (Crossref 404, `/agency` with no id,
  DataCite 404) stays `unmatched`, with a note saying so.
- `input_kind` is `doi`, `pid`, `openalex`, `url`, `urn`, `isbn`,
  `report` or `string`. `resolved_by` is `crossref`, `datacite`,
  `openalex`, `scielo`, `document` (described from the document itself),
  or `unmatched`; an unmatched input keeps `doi` null and lists its
  candidates in `notes` as `candidate: <doi> score <n> "<title>"`.
- `doi` is bare and lower-case, or `null` for a work without one.
  `ids.openalex` is the bare `W` id.
- `citation_key` is the key the caller already uses for the work (the
  name of its note or file, for example) when the caller gave one with
  the input; it is passed through unchanged, never generated here, and
  `null` when none was given. It is not an identifier: deduplication
  does not match on it.
- `ids.preprint_doi` is the bare, lower-case DOI of the work's preprint
  when a title match returned the preprint and the published version
  together and the published version was accepted; `null` otherwise. It
  is a related identifier, never the identity key, and deduplication
  matches on it: a later input giving the preprint's DOI is the same
  work.
- `type` is Crossref's `type` for a Crossref DOI. A DOI that Crossref
  types `dataset`, or that only OpenAlex holds with `type: dataset`,
  yields `type: dataset`; both services use that string (read on
  2026-11-24). Its `publisher` is the issuing body and its `venue` the
  hosting repository or data collection when the service names one
  (Crossref's `container-title`).
- A record that OpenAlex alone resolved (no Crossref or DataCite record
  behind it) takes its `type` from OpenAlex's word through this table,
  so every record speaks one vocabulary whichever service answered:

  | OpenAlex `type` | Record `type` |
  | --- | --- |
  | `article`, `review`, `letter`, `editorial`, `erratum`, `retraction`, `data-paper`, `software-paper`, `book-review` | `journal-article` |
  | `book-chapter` | `book-chapter` |
  | `book` | `book` |
  | `conference-paper`, `conference-abstract` | `proceedings-article` |
  | `preprint` | `posted-content` |
  | `dissertation` | `dissertation` |
  | `report` | `report` |
  | `standard` | `standard` |
  | `dataset` | `dataset` |
  | `software` | `software` |

  A word with no counterpart (`other`, `paratext`, `reference-entry`,
  `peer-review`, `supplementary-materials`,
  `study-registration`, or one the service adds later) leaves `type`
  `null`. Whenever the word and the record's type differ, `notes` keeps
  the original as `openalex type: <word>`, so a book review filed as a
  journal article can still be told apart. The 25 words were read from
  `GET /works?group_by=type` on 2026-11-25; the work object returned no
  `type_crossref` field on that date.
- `oa.status_openalex` takes OpenAlex's values (`diamond`, `gold`,
  `green`, `hybrid`, `bronze`, `closed`); `oa.status_unpaywall` takes
  Unpaywall's five (`gold`, `hybrid`, `bronze`, `green`, `closed`).
  OpenAlex labels no-fee gold as `diamond`, which Unpaywall never emits,
  so those two differing on a SciELO article is expected. `pdf_url`,
  `license` and `version` come from Unpaywall's `best_oa_location` when
  present, else from OpenAlex's.
- `abstract` is rebuilt from OpenAlex's inverted index; Crossref's
  `abstract` (a JATS fragment under publisher copyright) is not copied.
- `abstract_at` says where to read an abstract when `abstract` is
  `null` and the work has a DOI: `crossref` when the Crossref response
  already held carries `abstract`, else `europe-pmc` when one lookup by
  DOI returns `abstractText`, else `none`. It stays `null` when OpenAlex
  supplied the abstract or the work has no DOI. Nothing is copied from
  either service; the field only points the reader there. On 2026-11-13
  three DOIs without an OpenAlex abstract gave `crossref` (an SSRN
  deposit), `europe-pmc` and `none`.
- `sources` lists every HTTP call made for this record, with the URL
  stripped of any `email`, `mailto` or `api_key` value.
- `notes` holds free text: absences (`openalex: 404`), skipped steps
  (`unpaywall: skipped, RESEARCH_CONTACT_EMAIL unset`), disagreements, a
  redirect of an unexpected shape, and the DOI of a book chapter that
  reprints the article (`reprinted as chapter: <doi>`), which is a
  separate publication and not an identifier of this record.

## Identity and works without a DOI

A record's identity key is the first identifier it holds in this order:
`doi`, `ids.openalex`, a formal identifier (`ids.lexml_urn` for a
Brazilian norm, `ids.isbn`, `ids.report_number` as the issuer prints
it, `ids.bill_number` as the legislature prints it), then `ids.url`. The record stores every identifier it has, not only
the key, and deduplication matches on any of them, then on normalised
title (lower-case, diacritics and punctuation removed, whitespace
collapsed) plus `year`. Punctuation here is every Unicode punctuation
and dash character, not only the ASCII ones:
deposits of one work differ in typographic hyphens and quotes. On
2026-11-24 a journal article's title carried "Citizen‐State" with
U+2010 and its preprint's "Citizen-State" with the ASCII hyphen, and
the two compared unequal under an ASCII-only rule.

For a work with no DOI (`resolved_by: openalex` without a DOI, or
`document`):

- `ids.url` is the canonical URL of the document itself on the issuing
  body's site (the PDF or the official page), not a search result or a
  third-party copy; `accessed` is the UTC date it was read,
  `YYYY-MM-DD`, so a moved or dead link can be traced.
- `title`, `year`, `publisher` and `language` are read from the landing
  page or the PDF's front matter. `authors` are the persons the document
  names; an issuing body as author is kept as `{name}`, never split into
  `family` and `given`. OpenAlex `display_name` values are kept as
  `{name}` too.
- `type` is `report` (guidance, technical report, survey manual,
  white paper), `statute` (a law, decree, ordinance or regulation in
  force), `bill` (a legislative bill not yet law), `dataset` (microdata,
  a data file or a statistical series published as data), `standard`,
  `book`, `thesis`, `posted-content`, `magazine-article` (a piece in a
  magazine or in the professional or trade press, which has issues and
  no peer review), `newspaper-article` (a news item or opinion piece in
  a newspaper or on a news site), `court-decision` (a ruling of a court
  or tribunal), `software` (a program, library or code repository) or
  `webpage`; a repository work from OpenAlex takes its type through the
  table above. The three words `magazine-article`, `newspaper-article`
  and `court-decision` arise only here, from the document itself:
  neither Crossref's type list (read from `GET /types` on 2026-11-25)
  nor OpenAlex's has a counterpart. `software` also arises from
  OpenAlex's own `software`.
- A `magazine-article` or a `newspaper-article` carries the publication
  as `venue` and the piece's own page as `ids.url`; a `webpage` is kept
  for a page that belongs to no periodical.
- A `court-decision` carries as `title` the decision as the court styles
  it (its class and number, with the parties when the court names them),
  the court as `publisher`, the case number as `ids.report_number`, the
  year decided as `year` and the full date in `notes` as
  `decided: <YYYY-MM-DD>`; `authors` holds the reporting judge only when
  the decision names one.
- A `software` record carries the program's name as `title`, the
  persons or the organisation that publish it as `authors`, the
  organisation as `publisher`, the repository or project page as
  `ids.url`, the year of the release read as `year` and that release in
  `notes` as `version: <release>`.
- A `bill` carries `ids.bill_number` (for example `PL 1234/2025`) and
  `ids.lexml_urn` when one exists; `publisher` is the legislative body
  where it stands, and `notes` its stage on the date read (for example
  `stage: approved by the upper house, under review in the lower house`).
  A bill creates no obligation. When it becomes law, the law gets its own
  `statute` record, and each record names the other in `notes`
  (`enacted as: <statute identity key>`, `bill: <bill number>`).
- A `dataset` is read from its landing page, not from the data files:
  `title` as the page names the dataset, `publisher` the issuing body
  (also the only author, as `{name}`, unless the page names persons),
  `venue` the hosting repository when it is not the issuing body,
  `year` the reference year or edition the page gives (the year the
  data describe, not the year of release or of download),
  `ids.url` the landing page and `accessed` always set, since a dataset
  is revised in place. An identifier the issuer prints for the dataset
  goes to `ids.report_number`; a release date that differs from `year`
  goes to `notes` (`released: <date>`).
- When a dataset's landing page cannot be read (a challenge page or a
  refusal to curl and to a web fetch) and the issuer serves a metadata
  record for the same dataset, the record is described from that
  metadata: `ids.url` stays the public landing address, `resolved_by` is
  `document`, `sources` lists the metadata call, and `notes` carries
  `described from the issuer's metadata record: <its URL>`. On
  2026-11-25 a statistics office's survey page and table page answered
  a challenge page (403) to curl and to a web fetch, and its metadata
  endpoint gave the table's name, survey, variables and periods.
- A survey edition published as many tables is one record, not one per
  table: `title` is the survey and its edition (the survey's name and
  the year or wave), `year` the edition's reference year, and `notes`
  lists the tables used as `tables: <number>, <number>`. A later input
  naming another table of the same edition adds its number to that
  record's note.
- `oa.is_oa` is true when the document is freely reachable at `ids.url`;
  `oa.pdf_url` is set when that URL or a link on the page serves a PDF;
  `oa.status_openalex` and `oa.status_unpaywall` stay `null`;
  `oa.license` is the license the document states, else `null`.
- `counts` and `abstract` are `null` unless OpenAlex supplied them;
  `sources` lists the page and PDF reads with their status.
