# The provenance manifest

One JSON object per input, one per line in a `.manifest.jsonl` file beside
the copies it describes. Every field is present; a value no source gave is
`null`, never omitted, so a reader can tell "not asked" from "not known"
by reading `tried` and `notes`.

```json
{
  "ts": "2026-10-19T04:15:21Z",
  "input": "10.1590/0102.3772e36nspe19",
  "route": "curl",
  "doi": "10.1590/0102.3772e36nspe19",
  "file": "10.1590_0102.3772e36nspe19.20261019T041500Z.pdf",
  "form": "pdf",
  "source": "unpaywall",
  "url": "http://www.scielo.br/pdf/ptp/v36nspe/1806-3446-ptp-36-nspe-e36nspe19.pdf",
  "final_url": "https://www.scielo.br/j/ptp/a/.../?format=pdf&lang=pt",
  "status": 200,
  "content_type": "application/pdf",
  "bytes": 522677,
  "license": "cc-by",
  "version": "publishedVersion",
  "text_kind": "published",
  "language": "pt",
  "reuse": "license",
  "pdf_type": "text",
  "confidence": 1.0,
  "pages_needing_ocr": [],
  "encoding_broken": false,
  "title_check": "match",
  "via": null,
  "source_updated": "2026-10-11T02:14:09.000000",
  "tried": [
    {"source": "unpaywall", "url": "https://api.unpaywall.org/v2/10.1590/0102.3772e36nspe19", "ts": "2026-10-19T04:15:19Z", "status": 200, "note": "best_oa_location.url_for_pdf"}
  ],
  "notes": []
}
```

Field rules:

- `file` is the saved path: the bare name when the copy sits beside the
  manifest, the full path the user named otherwise. `form` is `pdf`,
  `xml` or `html`. When no copy was saved, `file`, `form`, `source`,
  `url`, `final_url`, `content_type`, `bytes` are `null` and `notes`
  opens with `none: <last reason>`; when every live candidate sat on a
  host listed in `RESEARCH_NO_AUTOMATION_HOSTS`, the reason reads `full
  text on a host whose terms forbid automated access`.
- `source` is `record` (the input's own `oa.pdf_url`), `unpaywall`,
  `openalex`, `openalex-content`, `scielo`, `europe-pmc`, `core`,
  `landing-page` (the full-text link a DOI's landing page announced), or
  `url` (a document fetched from its own URL,
  without a DOI). On 2026-11-13 an OJS article marked gold, with no
  candidate from any source, redirected from doi.org to its article
  page, whose `citation_pdf_url` served `application/pdf` with `%PDF` to
  curl. On 2026-11-24 the article pages of a large commercial publisher,
  for works marked open, gave curl no `citation_pdf_url` tag at all, so
  the step ended with no link.
- `route` is how the winning copy was fetched: `curl`, `web-fetch` (the
  agent's own web fetch capability) or `browser` (a browser automation
  capability); `null` when no copy was saved. A DOI input is `curl`
  except through the landing-page step, which uses the URL routes. Each `tried` entry carries its own `route` when it is not
  `curl`.
- `doi` is `null` for a document fetched from its URL, and `input` is
  that URL or the record's identity key.
- `url` is the candidate as announced, `final_url` what curl reports as
  `url_effective` after redirects; both stripped of any `email`,
  `mailto` or `api_key` value.
- `license` is settled by "Reading the license from the copy" in the
  skill: the license the copy's first or last page states, which
  outranks a source's label when the two differ; else the source's own
  string (`cc-by`, `cc by`, a publisher string, `implied-oa`,
  `other-oa`); else `null`. On 2026-11-26 a repository
  location labelled `cc-by-nc-nd` served an accepted manuscript whose
  cover page said all rights reserved unless indicated otherwise:
  `license: null`, `reuse: read-only`, the label in `notes`. `version`
  follows DRIVER
  (`publishedVersion`, `acceptedVersion`, `submittedVersion`) or `null`.
- `text_kind` is `published`, `author-manuscript` or `preprint`; it is
  read from the file (JATS `article-id` types, `xml:lang`) when the
  source's `version` does not settle it. `language` is the file's
  language when it can be read (`xml:lang`), else the record's.
  For a PDF, the language of its title page counts as read, so a
  translated edition carries its own language, not the record's.
- `reuse` is `license` when a license was stated, `read-only` when none
  was or the copy reserves its rights (`license: null`), and `link-only` for an arXiv copy. It describes
  the copy kept; a copy is kept whatever its value.
- `pdf_type`, `confidence`, `pages_needing_ocr` and `encoding_broken`
  are the classifier's output for a saved PDF: `pdf_type` is `text`,
  `scanned` (page images, no text layer), `image` (mostly images) or
  `mixed`; `confidence` runs from 0.0 to 1.0; `pages_needing_ocr` lists
  1-indexed pages with no usable text; `encoding_broken` is `true` when
  the text layer decodes to wrong characters. All four are the string
  `"unknown"` when the classifier did not run or failed, and `null` for
  a copy that is not a PDF or when no copy was saved. On 2026-11-24 a
  164-page guideline printed to PDF from page images passed the `%PDF`
  check with no text layer and classified as `image`, confidence 0.8,
  every page needing OCR. A download cut short also passes the `%PDF`
  check: on 2026-11-25 two PDFs from a slow host were cut by the time
  limit at about 52 KB, opened with `%PDF`, and the classifier exited 2
  with "document has no readable pages", so their four fields read
  `"unknown"`; fetched again, both were complete and typed `text`. The
  completeness check catches such a file before it is classified.
- `title_check` is `match` when the title on the kept copy's first page
  (or its title element, for XML and HTML) is one of the record's
  titles, `unchecked` when the first page could not be read or there was
  no title to compare, and `null` when no copy was saved. A candidate
  whose title is another work's is never the kept copy: it sits under
  `tried` with the note `title mismatch: <title seen>`, and when every
  candidate ended that way `notes` opens with `none: title mismatch`. On
  2026-11-24 the open-access location announced for a 2024 book chapter
  served a discussion paper, a different work, as a PDF that passed the
  `%PDF` check and classified as `text`.
  When the record lists people as authors, a candidate whose title
  matches but whose page names none of them is handled the same way,
  with the note `author mismatch: <names seen>`. A record whose author is
  an organisation, or that has no author, keeps the title check alone.
- `via` is `viewer` when the copy came through the viewer path below,
  else `null`.
- `source_updated` is the record timestamp the winning source carries
  (Unpaywall `updated`, OpenAlex `updated_date`), since both change daily
  and a verdict is reproducible only with its date.
- `tried` lists every HTTP call made for this input in order, API lookups
  and candidate fetches alike, each with `source`, `url`, `ts`, `status`
  and a short `note` (`skipped, RESEARCH_CONTACT_EMAIL unset`,
  `404`, `challenge page`, `text/html where pdf promised`, `keyless`,
  `title mismatch: <title seen>`, `incomplete` for a PDF cut short on
  both fetches, `no-automation host` for a candidate
  skipped without a request, whose `status` is then `null`, and
  `skipped, source timed out on two consecutive inputs` for a source a
  batch stopped asking, also with `status: null`).
- `notes` holds free text: a redirect of unexpected shape, an author
  manuscript served in place of the published text, a license read from
  the article page rather than an API, and a download stamp or a
  "licensed to" line seen on the copy's first page, written as
  `stamp: <text seen>`, a source's license label the copy contradicts,
  written as `license label: <source> <label>; the copy states
  <statement>`, and `license not read from the copy` when its first page
  could not be read. When a source was skipped after timeouts and no
  copy was saved, the `none` reason names it: `none: <last reason>;
  <source> skipped after timeouts`.

## The viewer path

Some institutional libraries answer a document's delivery URL with a
page that renders the file in an embedded viewer; a plain client gets
only an application shell. The browser route may then read the file
address the viewer was given (often a `file` parameter on the embedded
frame, holding a signed storage URL) and fetch that one file with a
plain HTTP client, under three conditions:

- It is one known document that the site serves openly to any visitor.
  The path is never used to list, search or harvest documents.
- The terms of use and robots rules of both hosts, the delivery host and
  the storage host, are read first, and the candidate is skipped when
  either forbids automated access. Both hosts also pass the
  `RESEARCH_NO_AUTOMATION_HOSTS` check.
- The manifest records `url` as the delivery URL and `final_url` as the
  storage URL with its query string removed, so no signature is kept,
  with `via: "viewer"` and `route: "browser"`.

On 2026-11-24 a library's delivery page (robots rules allowed the
delivery path and disallowed only search paths) exposed such a frame,
and a plain client fetched the signed address it carried.
