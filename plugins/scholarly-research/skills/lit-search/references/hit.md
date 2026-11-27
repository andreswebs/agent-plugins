# The candidate hit

One JSON object per candidate work, one per line in a `.hits.jsonl` file.
Every field is present; a value the source did not give is `null`.

```json
{"id": "W3108335682", "id_type": "openalex", "doi": "10.1590/0102.3772e36nspe19", "title": "Fatores de Risco e Riscos Psicossociais no Trabalho: Definição e Implicações", "year": 2020, "database": "openalex", "also_in": ["core"], "url": "https://doi.org/10.1590/0102.3772e36nspe19", "language": "pt", "query": "riscos psicossociais trabalho"}
```

| Field      | Value                                                                                                    |
| ---------- | -------------------------------------------------------------------------------------------------------- |
| `id`       | the source's own identifier: a bare OpenAlex `W` id, Europe PMC `SRC/ID`, a CORE work id, an unversioned arXiv id, a BDTD record id, a CiNii CRID, a document's canonical URL for a web hit |
| `id_type`  | `openalex`, `europe-pmc`, `core`, `arxiv`, `bdtd`, `crid`, `url` (a web hit)                             |
| `doi`      | bare, lower-case, no `https://doi.org/` prefix; `null` when the source gave none                         |
| `title`    | as the source gave it, whitespace collapsed                                                              |
| `year`     | integer publication year; `null` when the source gave none                                               |
| `database` | the source whose row this is, one of the `id_type` names with `cinii` for `crid` and `web` for `url`        |
| `also_in`  | databases that returned the same DOI after the first; `[]` when none                                     |
| `url`      | `https://doi.org/<doi>` when a DOI exists, else the source's landing URL, else `null`                    |
| `language` | ISO 639-1 (`pt`, `en`, `ja`) from the record, else from the language filter the query sent, else `null` |
| `query`    | the search string that found it, as given in the input                                                   |

## Deduplication

Concatenate every source's hit lines in the order the sources ran, then
keep the first line per DOI and append each later database to its
`also_in`. A line without a DOI is kept when no earlier line shares its
`database` and `id`. Titles are not compared: two sources giving the
same title under different DOIs are two hits.

```bash
python3 -I - all.jsonl >hits.jsonl <<'EOF'
import json, sys
seen, out = {}, []
for line in open(sys.argv[1], encoding="utf-8"):
    hit = json.loads(line)
    key = hit["doi"] or f'{hit["database"]}:{hit["id"]}'
    if key in seen:
        prior = seen[key]
        if hit["database"] not in prior["also_in"] and hit["database"] != prior["database"]:
            prior["also_in"].append(hit["database"])
        continue
    hit.setdefault("also_in", [])
    seen[key] = hit
    out.append(hit)
for hit in out:
    print(json.dumps(hit, ensure_ascii=False))
EOF
```

The reply's per-source count is the number of lines that source
contributed before deduplication; the kept count in the log line is the
number of its hits written, including those merged into `also_in`.
