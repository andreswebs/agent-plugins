# SciELO OAI-PMH for harvesting

Base `https://oai.scielo.org/request`; keyless, OAI-PMH 2.0, no limit
published and no rate-limit headers returned. One request at a time,
`--max-time 60`. The scielo.br CDN dropped connections for about ten minutes
during the probe and then recovered, so on a timeout or a `000` status
wait a minute before treating the host as down. The documented bulk file
`articles.json.zip` at `static.scielo.org` is now a 964-byte HTML page, so
this provider is the bulk route for a SciELO collection.

## Sets and formats

| Item              | Value                                                                                                   |
| ----------------- | ------------------------------------------------------------------------------------------------------- |
| Metadata prefixes | `oai_dc` (default here), `oai_openaire`, `oai_dc_agris`                                                 |
| Collection sets   | `com_Brasil`, `com_PEPSIC`, `com_REVENF`, `com_Saúde Pública`, `com_Social Sciences`                    |
| Journal sets      | one per ISSN, for example `0102-311X`                                                                   |
| `ListSets`        | 415 entries, paged 100 at a time with its own resumption token                                          |
| Granularity       | `YYYY-MM-DDThh:mm:ssZ`; a bare `YYYY-MM-DD` `from` was accepted                                         |
| `deletedRecord`   | `persistent`                                                                                            |

Set names with spaces or accents reach the server only through
`--data-urlencode`. The Brazilian collection is `com_Brasil`; `com_Saúde
Pública` and `com_Social Sciences` are thematic collections that re-publish
articles from the national ones, so a record can appear in more than one
set.

## Paging

```bash
curl --silent --get --max-time 60 --output page1.xml "https://oai.scielo.org/request" \
    --data-urlencode "verb=ListRecords" --data-urlencode "metadataPrefix=oai_dc" \
    --data-urlencode "set=com_Brasil" --data-urlencode "from=2026-10-01"
```

- Pages hold 100 records. The token looks like
  `oai_dc/2026-10-01T00:00:00.000Z//com_Brasil/100` and carries
  `completeListSize` and `cursor` attributes; `completeListSize` drifts
  between pages, so the manifest records every page's value. No token
  lifetime is stated; a `badResumptionToken` restarts from `from`.
- Datestamps are re-index times, not publication dates: a window selects
  what SciELO touched in it. About 55,000 `com_Brasil` records had changed
  since 2026-10-01 at probe time, 550 pages, so a collection harvest is
  long; a journal set is the usual unit.
- `until` is a standard OAI-PMH argument but the guide did not exercise it
  on this server; the local cut on the datestamp applies regardless.
- Errors are XML with HTTP 200: `idDoesNotExist`, `noRecordsMatch`,
  `badResumptionToken`. `earliestDatestamp` in `Identify` equals the
  response time, a provider quirk, not a signal.

## Identifiers and fields

| Item                 | Value                                                                                              |
| -------------------- | -------------------------------------------------------------------------------------------------- |
| Identifier scheme    | `oai:scielo:<PID>`, for example `oai:scielo:S0102-311X2020000500502`                               |
| PID                  | the identifier's last segment, for example `S0102-311X2020000500502`                               |
| `oai_dc` identifiers | the PID, the 23-character opaque article id, the DOI, legacy HTML URLs (one may be malformed as `https://http://...`) |
| DOI                  | prefix `10.1590`; suffix either the PID or a journal-specific code                                 |

When only PIDs, DOIs and processing dates are needed, ArticleMeta lists
identifiers 1,000 per page by processing date:
`https://articlemeta.scielo.org/api/v1/article/identifiers/?collection=scl&from=YYYY-MM-DD&limit=1000&offset=0`,
with `issn=` to restrict to one journal and `until=` to close the window;
`meta.total` is the count.

## Terms

License CC BY for journals indexed since 2015; earlier journals may keep
another Creative Commons license, so read the record's `dc:rights`. No
terms for automated access beyond the open-access statement were found;
the guide leaves confirming sustained harvesting with SciELO as an open
question.

## Verified

Live on 2026-10-16: `Identify`, `ListMetadataFormats`, `ListSets`,
`ListRecords` with `set=com_Brasil&from=2026-10-01` and its first token.
`oaipmh` source last pushed 2026-04-06. The `until` argument
and token expiry were not observed.
