---
name: lit-fulltext
description: "Fetch the full text (PDF, JATS XML or HTML) of a known work, given as a DOI, a resolved record or a document URL, from scholarly indexes and repositories, trying Unpaywall, OpenAlex, SciELO, Europe PMC and CORE in that order for a DOI and an escalating fetch for a URL, and write a manifest line saying what the copy is: its source, version and license. Use when a research step needs a known reference's full text on disk, needs to know which source holds a copy, which version it is and under which license, or needs a report, guidance document or law that has no DOI read from its issuer's site."
metadata:
  argument-hint: "a DOI, a document URL, a resolved record line or file, or a file with one per line; optionally a form (pdf, xml, html) and a target path"
---

# lit-fulltext

```bash
AGENT_ARTIFACTS_DIR="${AGENT_ARTIFACTS_DIR:-${PWD}/.local/data/agentartifacts}"
mkdir -p "${AGENT_ARTIFACTS_DIR}/lit-fulltext" && echo "${AGENT_ARTIFACTS_DIR}/lit-fulltext"
date -u +%Y%m%dT%H%M%SZ
```

Run this once when the run opens, and use the two printed values, the
directory and the run's `<UTC>` stamp, for every path below.

One input in, one **copy** out: a file saved as
`${AGENT_ARTIFACTS_DIR}/lit-fulltext/<doi-slug>.<UTC>.<ext>` (or at the
path the user names) plus one **provenance** line, in the shape of
[references/manifest.md](references/manifest.md), appended to
`${AGENT_ARTIFACTS_DIR}/lit-fulltext/<slug>.<UTC>.manifest.jsonl`, `<slug>`
naming the batch. Sources are asked in a fixed order and the first live
copy wins. The skill fetches a copy and reports what it is; it does not
decide whether a copy may be kept. No copy is refused or removed for
lacking a license: the manifest's `source`, `license`, `version` and
`reuse` describe the copy, and whoever uses the text later reads them.
Every call here is a lookup by identifier, so a run writes a
[search-log](references/search-log.md) line only when a search was run.

## Environment

| Variable                 | Used for                                   | When unset                                                                 |
| ------------------------ | ------------------------------------------ | -------------------------------------------------------------------------- |
| `RESEARCH_CONTACT_EMAIL` | Unpaywall `email`, its only credential     | Unpaywall is skipped and the manifest says so; the order starts at OpenAlex |
| `OPENALEX_API_KEY`       | OpenAlex bearer key; its cached PDF        | Singleton lookups are free; the cached copy at content.openalex.org is not tried |
| `CORE_API_KEY`           | CORE bearer key; `fullText` and download   | CORE gives metadata and repository links only; its own PDF is not tried    |
| `RESEARCH_SEARCH_LOG`    | JSONL file every search appends to         | `${AGENT_ARTIFACTS_DIR}/lit-fulltext/<slug>.<UTC>.search.jsonl`            |
| `RESEARCH_NO_AUTOMATION_HOSTS` | Space-separated hosts whose terms of service forbid automated access by any means, a browser driven by an agent included | Nothing is skipped |

No `User-Agent` header is sent. Every call: one request at a time, `curl --silent --max-time 60`, exponential
backoff of 1, 2, 4, 8 s on 429 and 5xx, no retry on other 4xx; 250 ms
between Unpaywall calls, one per second at Europe PMC, 3 s between any two
arXiv requests.

## Hosts that forbid automated access

Before any HEAD or GET, on every route below (a DOI candidate from any
source, and each of the three URL routes), compare the candidate's host
with the entries in `RESEARCH_NO_AUTOMATION_HOSTS`. A host matches an
entry when it equals it or is a subdomain of it. A matching candidate is
not requested: it goes under `tried` with `note: "no-automation host"`
and the next candidate is tried. When no other candidate remains, the
input ends with `none: full text on a host whose terms forbid automated
access`; the work is read from its abstract, or a person fetches it.

```bash
read -r -A no_auto_hosts <<< "${RESEARCH_NO_AUTOMATION_HOSTS:-}" 2>/dev/null \
    || read -r -a no_auto_hosts <<< "${RESEARCH_NO_AUTOMATION_HOSTS:-}"
candidate_host="${url#*://}"
candidate_host="${candidate_host%%/*}"
candidate_host="${candidate_host%%:*}"
blocked=no
for entry in "${no_auto_hosts[@]}"; do
    if [[ "${candidate_host}" == "${entry}" || "${candidate_host}" == *".${entry}" ]]; then
        blocked=yes
    fi
done
```

The `read` line covers both shells: zsh fills an array with `-A`, bash
with `-a`.

## Fetching a candidate

A candidate is a URL a source announced together with the form it claims
(pdf, xml, html), the license and the version. The preferred form is the
one the user named, else PDF, then XML, then HTML. For each candidate:

1. HEAD first: `curl --silent --max-time 60 --head --location --output /dev/null --write-out '%{http_code} %{content_type} %{url_effective}\n' "${url}"`.
   Publishers redirect, sometimes across schemes; keep the URL as given
   and let curl follow.
2. Fetch with `--location --output` to the stem path only when the content type matches
   the claimed form: `application/pdf` to `.pdf`, `application/xml` or
   `text/xml` to `.xml`, `text/html` to `.html` only for a candidate
   announced as HTML. Then check the bytes: a PDF opens with `%PDF`, a
   JATS file contains `<article`. A candidate announced as a PDF whose
   HEAD answers any content type ending in `/octet-stream`, read without
   its parameters and in any case (`application/octet-stream`,
   `binary/octet-stream` and the like), as
   some repositories label every download, is fetched too and kept only
   if its bytes open with `%PDF`; a file that fails is discarded and the
   candidate ends.
3. Check that a saved PDF is **complete**. When the response announced a
   `Content-Length` and no `Content-Encoding`, the saved size equals it;
   otherwise the file's last 1024 bytes hold the end-of-file marker
   `%%EOF`. A file that fails was cut short: discard it and fetch the
   candidate once more with `--max-time 180`. A second failure ends the
   candidate with the note `incomplete`.

   ```bash
   announced="$(sed --quiet 's/^[Cc]ontent-[Ll]ength: *//p' headers.txt | tail --lines=1 | tr -d '\r')"
   saved="$(wc --bytes <"${file}")"
   if [ -n "${announced}" ] && ! grep --quiet --ignore-case '^content-encoding:' headers.txt; then
       [ "${saved}" -eq "${announced}" ] || echo "incomplete: ${saved} of ${announced} bytes" >&2
   else
       tail --bytes=1024 "${file}" | grep --quiet --text '%%EOF' || echo "incomplete: no end-of-file marker" >&2
   fi
   ```

   `headers.txt` is what `--dump-header headers.txt` wrote on the GET;
   with redirects it holds several header blocks and the last
   `Content-Length` is the file's.
4. A 401, 403, a challenge page, a landing page where a PDF was promised,
   or a body that fails the byte check ends that candidate: record its
   status and note under `tried` and move to the next. The copy kept is
   the one the source served to a plain client.
5. When the final host is `arxiv.org` or `export.arxiv.org`, the file is
   read for research and linked by its abstract page, never copied into
   a published output; the manifest carries `reuse: "link-only"` and any
   output drawing on it carries "Thank you to arXiv for use of its open
   access interoperability."

## A source that times out in a batch

When a source's lookup times out on two consecutive inputs of a batch,
the remaining inputs of that batch skip the source, and it is not asked
again in that batch. Each skipped input carries a `tried` entry for the
source with `status: null` and the note `skipped, source timed out on
two consecutive inputs`. An input that skipped a source and ended with
no copy was not fully searched, and its `none` reason says which source
was skipped. The reply names the source and how many inputs skipped it,
so the caller can run them again later.

## Classifying a PDF copy

A PDF that passes the byte check may still hold no readable text. After
saving any PDF, on every route, classify the copy and record what kind
it is, with the script path taken from this skill's directory:

```bash
uv run scripts/classify_pdf.py "${file}"
```

It prints one JSON object whose four fields go into the manifest line as
they are: `pdf_type` (`text`, `scanned`, `image`, `mixed`), `confidence`,
`pages_needing_ocr` and `encoding_broken`. Exit 0 means classified. On
any other outcome (exit 2, or the command cannot run at all) the four
fields are `"unknown"` and the fetch still succeeds. A copy typed
`scanned` or `image`, or with `encoding_broken: true`, is not readable
as fetched: the reply says so, and whoever reads it states in the note
on the source how it was read and which pages.

## Checking the copy is the work

A source can serve another work at the address it announced. After the
byte check, and for a PDF after the classification, read the copy's
first page and compare the title printed there with every title the
record carries (the input record's, else the one the answering source
gave; original and translated). Differences of case, punctuation or
language of the same title are a **match**. For an XML or HTML copy the
title element is compared the same way.

When the record lists people as authors, a title match is confirmed on
them: at least one of their family names is printed on the same page.
When none is, the copy is a **mismatch** as well, noted `author
mismatch: <names seen>`, since a repository can deposit under a work's
DOI a discussion of the work by another author (on 2026-11-24 a seminar
discussion paper stood under a book chapter's DOI). A record whose
author is an organisation, or that has no author, keeps the title check
alone.

A match on a title in another language than the record's means the copy
is a translated edition. It is kept, its `language` is the language of
its title page, and `notes` names the edition read as `edition:
<language>, <publisher>, <year>`, so whoever quotes it cites the edition
actually read. A repository item holding several files can serve a
translation first: on 2026-11-24 the first file of a WHO IRIS item was a
Portuguese edition published in 2011, not the 2008 English original.

- A **mismatch** ends that candidate: it goes under `tried` with the
  note `title mismatch` and the title seen, its file is not kept as the
  work's copy, and the next candidate in the order is tried.
- A copy with no readable first page (typed `scanned` or `image`, or
  `encoding_broken: true`), or an input that came with no title to
  compare, is kept as **unchecked**, and the reply says so.

The manifest's `title_check` carries the outcome for the copy kept.

## Fetching from a URL

A document with no DOI (a record whose `doi` is `null`, or a bare URL)
is fetched from its own URL, the record's `oa.pdf_url` first, then
`ids.url`; step 8 sends a DOI's landing page and the one full-text link
it announces through the same routes. Escalate through three routes and stop at the first that
yields the document; the manifest's `route` names the one that worked
and `tried` keeps every attempt:

1. **`curl`**, as in "Fetching a candidate" above, with the byte check.
   Known host quirks: a link ending `.pdf` on a Plone site (many
   government portals) serves an HTML wrapper page, and the file itself
   is at the same URL followed by `/@@display-file/file`; some hosts
   answer a plain client with HTML or 403 where a browser gets the
   document. HTML where a PDF was expected, a 403, a challenge page or a
   refused connection moves to the next route.
2. **`web-fetch`**: the agent's own web fetch capability, when the
   environment offers one, on the same URL. A binary it saves is checked
   for `%PDF` like any other copy; text it returns is saved as `.html`
   or `.md` with `form: "html"` and a note that it is the tool's
   rendering, not the served bytes.
   A fetch capability that answers through a model can cap each verbatim
   quotation at a short length (near 125 characters on 2026-11-13 and
   2026-11-24, reading compiled statutes on Planalto, the federal statute
   portal, which refused curl): a long passage is read in consecutive
   short quotations, each asked for by the opening words of the next
   part, and the note says the text was assembled that way.
3. **`browser`**: whatever browser automation capability the
   environment offers, found at run time (agent-browser is one example),
   only when the first two failed. It opens the one known document URL
   and saves what that URL serves; it never follows links, searches the
   site or crawls. When no such capability exists, the input ends with
   `none: no route` and the URL stays in the reply for a person to fetch.
   When the first two routes both failed to connect at all (curl with no
   HTTP status, the web fetch refused), the browser is not tried, since
   it reaches the host from the same network address as curl: the input
   ends with `none: host refused connections`, and the reply names the
   host so the document can be fetched in a later session.
   When the URL renders a document viewer in place of the file, take the
   **viewer** path in [references/manifest.md](references/manifest.md).

None of the three routes is used on a service the project's policy
excludes or on a host listed in `RESEARCH_NO_AUTOMATION_HOSTS`, and none sends a `User-Agent` or contact address the other
steps would not send. The license is read from the document as in
"Reading the license from the copy" below, else from its landing page,
else `null`, so `reuse` is `read-only` by default.

## Reading the license from the copy

For every copy kept, whether or not a source gave a license, read the
copy's first page and its last page for a license or rights line:
journals print the license in the first-page footer or in the closing
notes, and a repository prints its rights statement on a cover page.
Only those two pages are read; a license named elsewhere in the text can
belong to a cited work or a figure. An XML or HTML copy is read at its
front matter and its closing matter (the `permissions` element of a JATS
file). This section is where the manifest's `license` and `reuse` are
settled; a source's label is a claim about the location, and the copy's
own statement outranks it:

- The copy states a license and no source gave one: the copy's license
  is `license`.
- The copy states a license that differs from the source's label: the
  copy's license is `license`, and the label goes into `notes` as
  `license label: <source> <label>; the copy states <statement>`. The
  same license written another way (`cc-by` and "CC BY 4.0") is no
  difference, and the label stands.
- The copy states "all rights reserved", or another reservation of
  rights (download for private study only, no reuse without permission):
  `license` is `null` and `reuse` is `read-only`, and a source's label,
  when one was given, goes into `notes` in the same form.
- The copy states nothing: the source's label stands, else `null`.
- The copy's first page cannot be read (typed `scanned` or `image`, or
  `encoding_broken: true`): the source's label stands, and `notes` says
  `license not read from the copy`.

## Steps

1. **Classify the input and set the stem.** A DOI matches `10.` followed
   by 4 to 9 digits, a slash and a suffix; strip a `https://doi.org/`
   prefix and lower-case it. A record line gives `doi` and an `oa` block;
   when `oa.pdf_url` is set it is the first candidate (source `record`),
   with its license and version, and Unpaywall and OpenAlex are asked
   only after it fails. The
   `<doi-slug>` is the DOI with every character outside `A-Za-z0-9.-`
   replaced by `_`. A URL or a record without a DOI takes the path in
   "Fetching from a URL" and skips steps 2 to 8; its slug is the record's
   identity key (or the URL's host and last path segment) with the same
   replacement. Done when every input has a bare DOI or a URL, a slug and
   an ordered (possibly empty) candidate list.
2. **Unpaywall**, per [references/unpaywall.md](references/unpaywall.md),
   when `RESEARCH_CONTACT_EMAIL` is set: `/v2/{doi}?email=`; take
   `best_oa_location.url_for_pdf`, preferring a `publishedVersion`
   location among `oa_locations` when one has a PDF; keep `license`,
   `version` and the record's `updated`. Fetch per the rule above. Done
   when a copy is saved, or Unpaywall is marked skipped, 404, or tried
   with each candidate's status.
3. **OpenAlex**, per [references/openalex.md](references/openalex.md):
   the free `/works/doi:{doi}`; candidates are `best_oa_location.pdf_url`,
   then `open_access.oa_url`, then the other `locations[].pdf_url`. Keep
   the work record for step 7. Done when a copy is saved or OpenAlex is
   marked 404 or tried.
4. **SciELO**, per [references/scielo.md](references/scielo.md), for a
   `10.1590` DOI: follow the DOI redirect to the PID, derive the article
   URL, then `&format=pdf`, `&format=xml` (JATS 1.1) or the HTML page in
   the preferred order. Done when a copy is saved or the redirect had
   another shape and the note says which.
5. **Europe PMC**, per [references/europe-pmc.md](references/europe-pmc.md):
   `search?query=DOI:"{doi}"&resultType=core&format=json`; with
   `isOpenAccess: "Y"` and a `pmcid`, `/{PMCID}/fullTextXML`; read
   `xml:lang` and the `article-id` list, since a SciELO article here may
   be the English author manuscript rather than the published Portuguese
   text, and set `text_kind` accordingly; `fullTextUrlList` entries with
   `availabilityCode: "OA"` are further candidates. Done when a copy is
   saved or the record is absent, closed, or tried.
6. **CORE**, per [references/core.md](references/core.md):
   `search/works/?q=doi:"{doi}"&limit=1` (one token); candidates are
   `sourceFulltextUrls[]`, then, with `CORE_API_KEY` set, the output
   download route, which sits behind a challenge page. Done when a copy
   is saved or CORE is marked absent, keyless, or tried.
7. **Cached copy**, only when steps 2 to 6 saved no copy,
   `OPENALEX_API_KEY` is set and the work record of step 3 has
   `has_content.pdf` true: the paid copy at `content.openalex.org` (100
   credits), per references/openalex.md. It comes after every free
   source, so a copy a slower free source would serve is never bought.
   The manifest's `source` is `openalex-content`. Done when a copy is
   saved, or the step is marked keyless, no cached copy, or tried.
8. **Landing page**, only when steps 2 to 7 saved no copy, whatever
   open-access status the work's records give it: the DOI's landing page
   goes through "Fetching from a URL" above, with its host check, routes
   and byte check. Read where `https://doi.org/{doi}` redirects with
   `curl --head` without `--location` (`%{redirect_url}`) and apply the
   host check to that target before requesting it. On the landing page,
   take the one full-text link the page announces, the
   `<meta name="citation_pdf_url">` tag first, and fetch only that link
   through the same routes; a page with no such link ends the input. It
   never crawls or follows other links. The manifest's `source` is
   `landing-page`. Done when a copy is saved, or the step is marked no
   link or tried.
9. **Emit.** Append the manifest line (every call under `tried`; the
   winner's url, final url, status, content type, bytes, the license
   settled in "Reading the license from the copy", version,
   `text_kind`, `reuse`, `title_check`, and for a PDF the four
   classification fields)
   and print the file path, or `none` with the last
   reason, and the manifest path; for a batch, name any source skipped
   after timeouts and the number of inputs that skipped it. Done when
   every input has a manifest line and the reply names both paths.

Attribution carried by the manifest: Unpaywall data is free with the
email it was requested under; OpenAlex is CC0; SciELO content is CC BY
unless the article's own license line says otherwise; Europe PMC JATS
carries the record's `license` unless the file's `permissions` state
another; a CORE copy is reached through its API
only, never from its file servers; arXiv full text is linked, not
re-served. The `license` field is what any later reuse rests on, and
`null` means none was stated.
