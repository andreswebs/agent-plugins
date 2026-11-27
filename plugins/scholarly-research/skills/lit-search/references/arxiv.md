# arXiv for searching

Query API `https://export.arxiv.org/api/query`; no key, no registration.
The terms set one rate limit for every arXiv host: one request every
three seconds, one connection, counted across all your machines; a `403`
means arXiv has blocked the client for crawling, so stop and do not
retry. Answers are Atom 1.0 XML, never JSON. Expect 10 to 15 seconds of
latency and an occasional `503` HTML page after a long wait (the lab's
first call took 46 s and returned 503; the retry succeeded): retry 5xx
with a growing wait. A `200` can still be an error: an `<entry>` whose
`<id>` is `https://arxiv.org/api/errors`. Always send `search_query` or
`id_list`; the bare endpoint answered 503.

arXiv is an English-language preprint corpus for physics, mathematics,
computer science, statistics and economics, with no language filter and
almost no Portuguese material, so it runs for English strings only.

## Search

```bash
query='abs:"participatory budgeting" AND submittedDate:[202401010000 TO 202612312359]'
curl --silent --max-time 120 --get --output "${RAW}/arxiv-1.xml" --write-out '%{http_code}\n' \
    "https://export.arxiv.org/api/query" \
    --data-urlencode "search_query=${query}" \
    --data-urlencode "sortBy=relevance" --data-urlencode "sortOrder=descending" \
    --data-urlencode "max_results=100" --data-urlencode "start=0"
```

- Clauses are `prefix:term` joined by `AND`, `OR`, `ANDNOT`, with
  parentheses and double-quoted phrases. Prefixes: `ti` title, `abs`
  abstract, `au` author, `cat` category, `jr` journal reference, `all`
  every field. A plain search string becomes `all:` terms; the plan's
  phrases become `ti:"..." OR abs:"..."`.
- Results are always sorted by relevance: with a `max_results` cap,
  sorting by `submittedDate` keeps only the newest matches and silently
  drops older, often foundational, ones (observed 2026-11-11 with a cap
  of 100).
- The date window is a clause, `submittedDate:[YYYYMMDDhhmm TO
  YYYYMMDDhhmm]` in GMT. Whether it filters on the first version's
  date or the returned version's was not established.
- The engine stems loosely (`ti:deliberation` matched "Deliberate") and
  gives no diagnostics: a complex query that returns 0 where hits were
  expected is simplified one clause at a time. Hit counts are
  approximate.
- `start` is 0-based, `max_results` at most 2,000 per call and 30,000 per
  result set; the manual asks that any query over 1,000 hits be refined.
  A page beyond the cap answered HTTP 500.

## Atom to JSON

Standard library only; `-I` keeps a planted module out of the import path.

```bash
python3 -I - "${RAW}/arxiv-1.xml" >"${RAW}/arxiv-1.json" <<'EOF'
import json, re, sys
import xml.etree.ElementTree as ET
NS = {"a": "http://www.w3.org/2005/Atom", "os": "http://a9.com/-/spec/opensearch/1.1/",
      "arxiv": "http://arxiv.org/schemas/atom"}
def text(el, path):
    found = el.find(path, NS)
    return " ".join(found.text.split()) if found is not None and found.text else None
root = ET.parse(sys.argv[1]).getroot()
entries = []
for e in root.findall("a:entry", NS):
    abs_url = text(e, "a:id")
    if abs_url == "https://arxiv.org/api/errors":
        sys.exit("arXiv error entry: " + (text(e, "a:summary") or ""))
    vid = abs_url.rsplit("/abs/", 1)[-1]
    entries.append({"id": re.sub(r"v\d+$", "", vid), "versioned_id": vid, "abs_url": abs_url,
        "title": text(e, "a:title"), "published": text(e, "a:published"),
        "authors": [text(a, "a:name") for a in e.findall("a:author", NS)],
        "doi": text(e, "arxiv:doi"), "journal_ref": text(e, "arxiv:journal_ref"),
        "categories": [c.get("term") for c in e.findall("a:category", NS)]})
json.dump({"feed_title": text(root, "a:title"), "total_results": int(text(root, "os:totalResults") or 0),
           "start_index": int(text(root, "os:startIndex") or 0), "entries": entries}, sys.stdout, ensure_ascii=False)
EOF
jq '{feed_title, total_results, n: (.entries | length)}' "${RAW}/arxiv-1.json"
```

## Hits

```bash
jq --compact-output --arg q "${query}" '.entries[] | {
  id, id_type: "arxiv", doi: (if .doi then (.doi | ascii_downcase) else null end),
  title, year: (.published[:4] | tonumber), database: "arxiv", also_in: [],
  url: (if .doi then "https://doi.org/\(.doi | ascii_downcase)" else .abs_url end),
  language: null, query: $q}' "${RAW}/arxiv-1.json"
```

`doi` is present only when an author supplied a journal DOI; arXiv's own
DOIs (`10.48550/arXiv.<id>`) are not in the feed, so most arXiv hits
dedupe on `arxiv:<id>`. `published` is the first version's submission
time. No references or cited-by data exist here.

## Log

`database: "arxiv"`, `hits` from `opensearch:totalResults`, `url` the
request URL, `filters` the `submittedDate` window, `sortBy`, `sortOrder`,
`start` and `max_results`, `notes` carrying the feed `title`, which
echoes the canonicalised query. Keep the raw XML: it is the evidence.

## Duties

Metadata is CC0. Full text is under arXiv's non-exclusive license: link
to the abstract page, never re-serve a PDF. A published output carries
the acknowledgement "Thank you to arXiv for use of its open access
interoperability." The robots page asks clients to identify
themselves; keep to the three-second pace and report a refusal rather
than retrying.

## Verified

Live on 2026-10-16, 25 requests from one client. The date-window query
above (to 2025) returned 33 results, all inside the window; a three-clause
title, abstract and category query returned 10 in 10 to 14 seconds; a
malformed id answered 200 with zero entries rather than an error entry.
