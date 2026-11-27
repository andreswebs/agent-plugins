# The records file and the manifest

Both files are JSONL under `${AGENT_ARTIFACTS_DIR}/lit-harvest/`, sharing
the stem `<slug>.<UTC>`: `<slug>.<UTC>.records.jsonl` and
`<slug>.<UTC>.manifest.jsonl`. Lines are only ever appended; a resumed
harvest appends to the files of the run it continues.

## A record line

One object per OAI record, every field present, `null` where the metadata
gave nothing.

```json
{"provider": "scielo", "identifier": "oai:scielo:S0102-311X2020000500502", "datestamp": "2026-10-03T14:21:07Z", "status": null, "sets": ["com_Brasil", "0102-311X"], "title": "Participação social e saúde no Brasil", "doi": "10.1590/0102-311x00083520", "date": "2020-05-29", "metadata_prefix": "oai_dc", "page": 3, "ts": "2026-10-19T04:12:51Z", "metadata": "<oai_dc:dc xmlns:oai_dc=\"http://www.openarchives.org/OAI/2.0/oai_dc/\" ...>...</oai_dc:dc>"}
```

| Field             | Value                                                                                                   |
| ----------------- | ------------------------------------------------------------------------------------------------------- |
| `provider`        | `scielo`, `scielo-preprints` or `arxiv`                                                                 |
| `identifier`      | the OAI header identifier, in the provider's scheme (see its page)                                      |
| `datestamp`       | the header datestamp as sent: a modification or re-index time on all three providers                    |
| `status`          | the header `status` attribute, `deleted` for a tombstone (then `metadata` is `null`), else `null`       |
| `sets`            | every `setSpec` in the header                                                                           |
| `title`           | the first `title` element in the metadata, whitespace collapsed                                         |
| `doi`             | the first `10.`-prefixed DOI found in an `identifier` or `doi` element, lower-cased, bare               |
| `date`            | the metadata's own date: `dc:date` (SciELO, SciELO Preprints posting date) or `created` (arXiv format) |
| `metadata_prefix` | the format harvested                                                                                    |
| `page`            | the page number within the harvest                                                                      |
| `ts`              | UTC time the page was parsed                                                                            |
| `metadata`        | the child element of `<metadata>` re-serialised with its content intact (namespace prefixes may be rewritten), so nothing the provider sent is lost |

## A manifest line

The first line is `start`, then one `page` line per response, then `end`.

```json
{"event": "start", "ts": "2026-10-19T04:12:40Z", "provider": "scielo", "base": "https://oai.scielo.org/request", "set": "0102-311X", "from": "2026-10-01", "until": null, "metadata_prefix": "oai_dc", "resumed_from_page": null}
{"event": "page", "n": 1, "ts": "2026-10-19T04:12:42Z", "request": "verb=ListRecords&metadataPrefix=oai_dc&set=0102-311X&from=2026-10-01", "status": 200, "bytes": 412337, "records": 100, "written": 100, "completeListSize": 312, "cursor": 0, "token": "oai_dc/2026-10-01T00:00:00.000Z//0102-311X/100"}
{"event": "end", "ts": "2026-10-19T04:12:51Z", "status": "complete", "pages": 4, "records": 312, "error": null}
```

- `request` is the query string as sent, decoded; a resumed page's is
  `verb=ListRecords&resumptionToken=<token>`.
- `records` counts records in the response, `written` those appended after
  the `until` cut and the resume de-duplication.
- `token` is the resumption token of the next page, `null` on the last.
- `end.status` is `complete`, `stopped` (interrupted on purpose, resume
  later from the last `page` line's token) or `failed` (`error` holds the
  OAI error code or the HTTP status).

Resume reads the token with:

```bash
manifests=("${AGENT_ARTIFACTS_DIR}/lit-harvest/${SLUG}".*.manifest.jsonl)
manifest="${manifests[-1]}"
tail -n 1 "${manifest}" | jq --raw-output 'select(.event == "page") | .token // empty'
```

## Fetching and parsing one page

```bash
oai_set=()
if [ -n "${SET:-}" ]; then oai_set=(--data-urlencode "set=${SET}"); fi
http_status="$(curl --silent --get --max-time "${TIMEOUT}" --output page.xml --write-out '%{http_code}' "${BASE}" \
    --data-urlencode "verb=ListRecords" --data-urlencode "metadataPrefix=${PREFIX}" \
    "${oai_set[@]}" --data-urlencode "from=${FROM}")"
token_element="$(grep -o '<resumptionToken[^>]*>[^<]*' page.xml)"
token="${token_element##*>}"
list_size_attribute="$(grep -o 'completeListSize="[0-9]*"' page.xml | head -n 1)"
list_size="${list_size_attribute//[!0-9]/}"
grep -o '<error code="[^"]*"' page.xml
```

A later page sends `--data-urlencode "verb=ListRecords"` and
`--data-urlencode "resumptionToken=${token}"` only. Records of a page
become lines with:

```bash
python3 -I - page.xml "${PROVIDER}" "${PREFIX}" "${UNTIL:-}" "${page}" >>"${RECORDS}" <<'EOF'
import datetime, json, re, sys
import xml.etree.ElementTree as ET

page, provider, prefix, until, n = sys.argv[1:6]
OAI = "{http://www.openarchives.org/OAI/2.0/}"
root = ET.parse(page).getroot()
err = root.find(OAI + "error")
if err is not None:
    sys.exit("oai error %s: %s" % (err.get("code"), (err.text or "").strip()))
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
doi_re = re.compile(r"10\.\d{4,9}/\S+")

def local(el):
    return el.tag.rsplit("}", 1)[-1]

def first(inner, *names):
    if inner is None:
        return None
    for el in inner.iter():
        if local(el) in names and el.text and el.text.strip():
            return " ".join(el.text.split())
    return None

def doi_of(inner):
    if inner is None:
        return None
    for el in inner.iter():
        if local(el) in ("identifier", "doi") and el.text:
            m = doi_re.search(el.text)
            if m:
                return m.group(0).lower()
    return None

for rec in root.iter(OAI + "record"):
    h = rec.find(OAI + "header")
    datestamp = h.findtext(OAI + "datestamp") or ""
    if until and datestamp[:10] > until[:10]:
        continue
    md = rec.find(OAI + "metadata")
    inner = list(md)[0] if md is not None and len(md) else None
    print(json.dumps({
        "provider": provider,
        "identifier": h.findtext(OAI + "identifier"),
        "datestamp": datestamp or None,
        "status": h.get("status"),
        "sets": [s.text for s in h.findall(OAI + "setSpec")],
        "title": first(inner, "title"),
        "doi": doi_of(inner),
        "date": first(inner, "date", "created"),
        "metadata_prefix": prefix,
        "page": int(n),
        "ts": ts,
        "metadata": ET.tostring(inner, encoding="unicode") if inner is not None else None,
    }, ensure_ascii=False))
EOF
```

On a restart from `from` after an expired token, build the set of
identifiers already written (`jq --raw-output .identifier "${RECORDS}" | sort -u`)
and skip those lines before appending. The page's `written` count in the
manifest is the number of lines actually appended.
