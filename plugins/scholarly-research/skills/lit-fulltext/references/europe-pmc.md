# Europe PMC for JATS full text

Base `https://www.ebi.ac.uk/europepmc/webservices/rest`; free, no key, no
quota documented, no rate-limit header. Stay at about one request per
second. Always pass `format=json` on the search module (the default is
XML) and `--data-urlencode` for the query. Application errors arrive as
HTTP 200 with `{"errCode": 404, "errMsg": "..."}`, so test the body.
Full text in the open-access subset is JATS XML addressed by PMCID; the
same index also lists free copies found elsewhere.

## Lookup by DOI

```bash
curl --silent --max-time 60 --get --output epmc.json "https://www.ebi.ac.uk/europepmc/webservices/rest/search" \
    --data-urlencode "query=DOI:\"${doi}\"" --data-urlencode "resultType=core" --data-urlencode "format=json"
jq '.hitCount, (.resultList.result[0] | {id, source, pmid, pmcid, doi, language, isOpenAccess, inEPMC, hasPDF, license,
    urls: [.fullTextUrlList.fullTextUrl[]? | {site, documentStyle, availabilityCode, url}]})' epmc.json
```

- Latency varies: on 2026-11-24 lookups by DOI took 13 to 40 seconds
  each for about an hour and one exceeded the 60 second limit, while
  searches earlier the same evening answered at once. A timeout is a
  failed lookup, noted under `tried`, not an absent record; two in a
  row end the source for the rest of a batch (SKILL.md, "A source that
  times out in a batch").
- `hitCount: 0` means the DOI is not in Europe PMC; two of three SciELO
  DOIs tried in the lab were absent. The lookup is by identifier and is
  not a search for the log.
- `isOpenAccess`, `inEPMC`, `hasPDF` are `Y` or `N` strings; `license` is
  a string such as `cc by`; `language` is ISO 639-2 (`por`) and `null` on
  preprints (`source: PPR`).
- `fullTextUrlList.fullTextUrl[]` carries `site` (`Unpaywall`, `DOI`,
  `Europe_PMC`), `documentStyle` (`pdf`, `html`, `doi`) and
  `availabilityCode` (`OA`, `F`, `S`); the `OA` entries with
  `documentStyle: pdf` or `html` are candidates after the JATS.

## JATS XML by PMCID

Only with `inEPMC: "Y"`, `isOpenAccess: "Y"` and a `pmcid`:

```bash
pmcid="$(jq --raw-output '.resultList.result[0].pmcid // empty' epmc.json)"
curl --silent --max-time 60 --output "${stem}.xml" --write-out '%{http_code} %{content_type} %{size_download}\n' \
    "https://www.ebi.ac.uk/europepmc/webservices/rest/${pmcid}/fullTextXML"
grep -o '<article [^>]*>' "${stem}.xml" | head -n 1
grep -o '<article-id pub-id-type="[a-z]*">[^<]*' "${stem}.xml"
```

- Observed: `200 application/xml 94330` for PMC7617041 (a Ciência & Saúde
  Coletiva article), which came back as `xml:lang="en"` with an `emsid`
  article-id: an English author manuscript, not the published Portuguese
  article on scielo.br. Read `xml:lang` and the `article-id` list and set
  `text_kind` to `author-manuscript` when an `emsid` is present or the
  language differs from the record's; say so in `notes`.
- A non-OA record answers a JSON 404 on `fullTextXML`; a preprint id
  (`PPR...`) answers a JSON 500 even with `hasPDF: "Y"`, and the preprint
  PDF route under `europepmc.org/api/fulltextRepo` sits behind a
  challenge page, so a preprint has no shell-readable copy here.
- For a known pair, `article/{source}/{id}?resultType=core&format=json`
  returns the record without a query.

## Verified

Live on 2026-10-17, production API version 6.9, no key: the DOI lookup,
`fullTextXML` on two PMCIDs, the 404 and 500 cases. The `fulltextRepo`
PDF route is reported blocked, not exercised; no rate limit was observed
over twelve rapid calls, and the real threshold is unknown.
