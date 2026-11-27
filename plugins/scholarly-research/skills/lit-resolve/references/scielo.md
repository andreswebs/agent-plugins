# SciELO for resolving a 10.1590 DOI

SciELO is where a Brazilian article is resolved and fetched, not searched:
its search portal sits behind a JavaScript challenge, and discovery goes
through Crossref (`prefix:10.1590`) or OpenAlex (`language:pt`). No
SciELO route takes a key; none publishes a limit or returns rate-limit
headers. One request at a time, `--max-time 60`; the scielo.br CDN dropped
connections for about ten minutes during the lab and then recovered, so
on a timeout wait a minute before treating the host as down.

Identifiers: a PID looks like `S0102-311X2020000500502`; the current
sites also use a 23-character opaque id in `/j/<acron>/a/<id>/`; DOIs
sit under `10.1590`.

## DOI to PID

ArticleMeta has no DOI parameter. Resolve the DOI and read the PID from
the legacy URL SciELO registered with Crossref:

```bash
redirect_url="$(curl --silent --max-time 30 --output /dev/null --write-out '%{redirect_url}' "https://doi.org/${doi}")"
pid_parameter="$(printf '%s' "${redirect_url}" | grep -o 'pid=S[0-9X-]*')" || echo "no pid in ${redirect_url}" >&2
pid="${pid_parameter#pid=}"
printf '%s\n' "${redirect_url}" "${pid}"
```

The lab's DOI redirected to
`http://www.scielo.br/scielo.php?script=sci_arttext&pid=S0102-311X2020000500502&tlng=pt`.
When the redirect is already the `/j/<acron>/a/<id>/` form, fetch it with
`&format=xml` and read the PID and `citation_doi` from the JATS; OpenAlex's
`best_oa_location.pdf_url` also carries the 23-character id.

## Full-text URLs from the PID

```bash
article_url="$(curl --silent --max-time 30 --output /dev/null --write-out '%{redirect_url}' \
    "https://www.scielo.br/scielo.php?script=sci_arttext&pid=${pid}&tlng=pt")"
echo "${article_url}"            # https://www.scielo.br/j/<acron>/a/<id>/?lang=pt
echo "${article_url}&format=pdf" # application/pdf
echo "${article_url}&format=xml" # JATS 1.1 full text
```

RIS and BibTeX: `https://www.scielo.br/citation/export/<id>/?format=ris`
(or `bib`), with `<id>` the 23-character id from `${article_url}`.

## The authoritative record

```bash
curl --silent --max-time 30 \
    "https://articlemeta.scielo.org/api/v1/article/?collection=scl&code=${pid}" --output am.json
jq --exit-status 'type == "object"' am.json >/dev/null || echo "unknown PID" >&2
jq '{doi, pid: .code, collection, publication_year, document_type, fulltexts}' am.json
```

Always pass `collection` (`scl` for Brazil); without it the API may return
the thematic collection's copy. An unknown PID answers HTTP 200 with the
body `null`, so test the body, not the status. `format=xmlrsps` returns
the JATS record, `format=xmlcrossref` the Crossref deposit.

License: CC BY for journals indexed since 2015; read the article's own
license line for older ones.

## Verified

Live on 2026-10-16. ArticleMeta version 1.32.25; 36 collections listed.
