# SciELO Preprints OAI-PMH for harvesting

Base `https://preprints.scielo.org/index.php/scielo/oai`; Open Preprint
Systems 3.4.8.0, open, complete, Dublin Core only. No rate limit is
documented or observed and no headers announce one: one request at a
time with a short pause between pages, `--max-time 60`. The REST API under
`/api/v1/` answers 403 to every route without a per-account token and is
never used here; OAI-PMH is the whole machine interface.

## Sets and formats

| Item                    | Value                                                            |
| ----------------------- | ---------------------------------------------------------------- |
| Metadata prefix         | `oai_dc` only; any other answers `cannotDisseminateFormat`       |
| Granularity             | `YYYY-MM-DDThh:mm:ssZ`; `from` takes a date or a datetime         |
| `deletedRecord`         | `persistent`; none seen in 200 sampled records                   |
| `ListRecords` page      | 100 records (`ListIdentifiers` 500)                              |
| Whole repository        | 5,948 records, 60 pages, earliest datestamp 2020-04-06           |

Sets (`setSpec`, name): `scielo` (everything); thematic `scielo:CA`
Ciências Agrárias, `scielo:CB` Ciências Biológicas, `scielo:CS` Ciências
da Saúde, `scielo:CET` Ciências Exatas e da Terra, `scielo:CH` Ciências
Humanas, `scielo:CSA` Ciências Sociais Aplicadas, `scielo:E` Engenharias,
`scielo:LLA` Linguística, letras e artes; event and journal sets
`scielo:CICA`, `scielo:MIOC`, `scielo:EDUR`, `scielo:47-ANPOCS` to
`scielo:50-ANPOCS`. Sixteen in all; `set` combines with `from`.

## Paging

```bash
curl --silent --get --max-time 60 --output page1.xml "https://preprints.scielo.org/index.php/scielo/oai" \
    --data-urlencode "verb=ListRecords" --data-urlencode "metadataPrefix=oai_dc" \
    --data-urlencode "set=scielo:CSA" --data-urlencode "from=2026-10-01"
```

- **Never send `until`**: it answers HTTP 500 with an empty body in every
  combination tried (four variants on 2026-10-16). The upper bound is cut
  locally on the header datestamp.
- The token is a 32-character hex string with `expirationDate` about 24
  hours after issue, `completeListSize` and `cursor`. Send it back with
  the verb only. An empty token element, or none, ends the list;
  `badResumptionToken` means expired or altered: restart from `from`.
- Datestamps are modification times. `from=2020-04-01` returns the whole
  repository because old records were touched later; the posting date is
  `dc:date` inside the record, which the record line carries as `date`.
- Other errors: a 22-byte HTML 404 for an unknown page inside the OPS
  application; JSON 403 bodies belong to the REST API, never to OAI.

## Identifiers and fields

| Item              | Value                                                                        |
| ----------------- | ---------------------------------------------------------------------------- |
| Identifier scheme | `oai:ops.preprints.scielo.org:preprint/<id>`, `<id>` the integer server id   |
| DOI               | `10.1590/SciELOPreprints.<id>` for author-submitted preprints (lower-cased by Crossref and OpenAlex); a journal-submitted preprint reuses the article's DOI, unverified by example |
| `dc:identifier`   | the landing URL, then the bare DOI                                           |
| `dc:date`         | posting date, `YYYY-MM-DD`                                                   |
| `dc:language`     | ISO 639-2: `por`, `eng`, `spa`                                               |
| `dc:type`         | `info:eu-repo/semantics/preprint` and `info:eu-repo/semantics/draft`         |
| `dc:relation`     | the galley page `preprint/view/<id>/<galleyId>`; swap `view` for `download` for the PDF |
| `dc:rights`       | a copyright line and `https://creativecommons.org/licenses/by/4.0`           |

The record gives no link to a published version; that relation lives in
Crossref as `relation.is-preprint-of` on the preprint's DOI.

## Terms

Every preprint is posted under CC BY 4.0. The PDF comes from the server
itself (`citation_pdf_url` on the landing page, `application/pdf`,
no login).

## Verified

Live on 2026-10-16 against the server: `Identify`, `ListRecords` with
`from` and with `set`, a second page by token, `GetRecord`; `until`
observed failing in four variants. An OPS upgrade may fix `until`; retest
before relying on it.
