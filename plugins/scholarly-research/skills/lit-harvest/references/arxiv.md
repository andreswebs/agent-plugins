# arXiv OAI-PMH for harvesting

Base `https://oaipmh.arxiv.org/oai`, the host rewritten in March 2025; the
old `export.arxiv.org/oai2` answers 301 to it. Keyless. arXiv's terms set
one limit for every interface: one request every three seconds, on a
single connection, counted across all your machines. Sleep 3 s between
pages, `--max-time 120`, and never run two requests in parallel. The docs say the
query API is not meant for harvesting; OAI-PMH is.

## Sets and formats

| Item              | Value                                                                                     |
| ----------------- | ----------------------------------------------------------------------------------------- |
| Metadata prefixes | `oai_dc`, `arXiv` (default here), `arXivOld`, `arXivRaw`                                  |
| Sets              | `group:archive:CATEGORY`, for example `cs:cs:HC`, `cs`, `physics:hep-th`; 183 in `ListSets` |
| Granularity       | `YYYY-MM-DD`                                                                              |
| `deletedRecord`   | `persistent`; `earliestDatestamp` 2005-09-16                                              |
| Page              | 1,300 records (4.3 MB for `set=cs`)                                                       |
| Update            | nightly; announcements Sunday to Thursday around 20:00 Eastern                            |

A category is `archive.SUBJECT` (`cs.HC`); its set is `cs:cs:HC`. Old
archives such as `hep-th` have no subject class.

## Paging

```bash
curl --silent --get --max-time 120 --output oai-1.xml "https://oaipmh.arxiv.org/oai" \
    --data-urlencode "verb=ListRecords" --data-urlencode "metadataPrefix=arXiv" \
    --data-urlencode "set=cs:cs:HC" --data-urlencode "from=2026-10-13"
```

- Datestamps are last-modification dates, so a `from` window returns new
  and updated records; `created` inside the `arXiv` format is the
  submission date and becomes the record line's `date`.
- The token encodes the whole query
  (`verb%3DListRecords%26metadataPrefix%3DarXiv%26from%3D2026-10-14%26set%3Dcs%26skip%3D1300`)
  with `expirationDate` at the next midnight UTC: a harvest interrupted
  overnight restarts from `from`.
- `until` is listed as an optional `ListRecords` argument in the docs; the
  guide did not exercise it live. The local datestamp cut applies anyway.
- A 503 (`text/html`, body "503") on the first call after a long wait is
  normal: the probe's first request took 46 s and returned 503, and the
  retry succeeded. The guide retried 5xx at 15, 30, 45 s; allow at least
  that on this host. No `Retry-After` header is sent.
- 403 means arXiv has blocked the client for crawling: stop the harvest,
  record `failed` with 403, and do not retry.
- `Identify` may be served from cache (its `responseDate` was a month
  old), so its values are not a liveness signal.

## Identifiers and fields

| Item              | Value                                                                                        |
| ----------------- | -------------------------------------------------------------------------------------------- |
| Identifier scheme | `oai:arXiv.org:<id>` without a version, for example `oai:arXiv.org:2510.13011`               |
| New ids           | `YYMM.NNNNN` since 2007-04 (four digits before 1501), optional `vN`                          |
| Old ids           | `archive/YYMMNNN`, for example `cs/9901002`                                                   |
| arXiv DOI         | `10.48550/arXiv.<id>` (DataCite); the record's `doi` element is the author-supplied journal DOI, so the record line's `doi` is the journal one when present |
| `arXiv` format    | namespace `http://arxiv.org/OAI/arXiv/`; always `id`, `created`, `updated`, `authors` (`keyname`, `forenames`), `title`, `categories`, `abstract`, `license`; when present `doi`, `journal-ref`, `comments`, `acm-class`, `msc-class`, `report-no` |

Observed on 2026-10-16: `set=cs:cs:HC&from=2026-10-13` returned 171
records in one 543 KB response with no token; `set=cs&from=2026-10-14`
returned 1,300 records and a `skip=1300` token, then 1,300 more and a
`skip=2600` token.

## Terms

Metadata is CC0 1.0: free to store and redistribute. Full text is not:
most papers carry arXiv's non-exclusive distribution license, so published
outputs link to `https://arxiv.org/abs/<id>` and never re-serve the PDF;
each record's `license` URI tells the CC BY subset apart. arXiv asks that
published work acknowledge "Thank you to arXiv for use of its open access
interoperability." Repeated violations of the three-second rule end in a
403 and further requests are treated as an attack.

## Verified

Live on 2026-10-16 (21:45 to 22:15 UTC): `Identify`, `ListMetadataFormats`,
`ListSets`, `ListRecords` on two sets and one token continuation. Docs
read from the `develop` branch of `arXiv/arxiv-docs`, last pushed the same
day. `until` and `oai_dc` on this host were not exercised.
