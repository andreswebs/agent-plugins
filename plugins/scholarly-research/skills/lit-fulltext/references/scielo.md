# SciELO for a 10.1590 DOI

The Brazilian collection site `www.scielo.br` serves open HTML, PDF and
JATS XML for every article by URL, with no login, cookie or referer. No
SciELO route takes a key; none publishes a limit or returns rate-limit
headers. One request at a time, `--max-time 60`; the scielo.br CDN dropped
connections for about ten minutes during the lab and then recovered, so
on a timeout or a `000` status wait a minute before treating the host as
down.

Identifiers: a PID looks like `S0102-311X2020000500502`; the current
sites also use a 23-character opaque id in `/j/<acron>/a/<id>/`; DOIs
sit under `10.1590`.

## DOI to PID to article URL

```bash
redirect_url="$(curl --silent --max-time 60 --output /dev/null --write-out '%{redirect_url}' "https://doi.org/${doi}")"
pid_parameter="$(printf '%s' "${redirect_url}" | grep -o 'pid=S[0-9X-]*')" || echo "no pid in ${redirect_url}" >&2
pid="${pid_parameter#pid=}"
article_url="$(curl --silent --max-time 60 --output /dev/null --write-out '%{redirect_url}' \
    "https://www.scielo.br/scielo.php?script=sci_arttext&pid=${pid}&tlng=pt")"
printf '%s\n' "${redirect_url}" "${pid}" "${article_url}"
```

The lab's DOI redirected to
`http://www.scielo.br/scielo.php?script=sci_arttext&pid=S0102-311X2020000500502&tlng=pt`,
and the legacy URL answered 301 to `https://www.scielo.br/j/csp/a/<id>/?lang=pt`.
When the DOI redirect is already in the `/j/<acron>/a/<id>/` form, use it
as `article_url` directly; the PID and `citation_doi` are in its JATS. A redirect
of any other shape is a note in the manifest, and the step ends.

## The three forms

```bash
curl --silent --max-time 60 --location --output "${stem}.pdf" --write-out '%{http_code} %{content_type} %{size_download}\n' "${article_url}&format=pdf"
curl --silent --max-time 60 --location --output "${stem}.xml" --write-out '%{http_code} %{content_type} %{size_download}\n' "${article_url}&format=xml"
curl --silent --max-time 60 --location --output "${stem}.html" --write-out '%{http_code} %{content_type} %{size_download}\n' "${article_url}"
```

| Form                            | Result                                                             |
| ------------------------------- | ------------------------------------------------------------------ |
| `/j/<acron>/a/<id>/?format=pdf&lang=pt` | `application/pdf`; the PDF HEAD answered that content type directly |
| `/j/<acron>/a/<id>/?format=xml` | JATS 1.1 full text                                                 |
| `/j/<acron>/a/<id>/?lang=pt`    | article HTML with `citation_pdf_url`, `citation_doi` and the CC license link |
| `/scielo.php?script=sci_pdf&pid=<PID>&tlng=<lang>` | 301 to the `format=pdf` form                              |

On the probe article the three weighed 522,677, 55,282 and 116,591 bytes.
`format=json` answered 502.
`tlng` and `lang` carry the language code; the lab used `pt` only.

A second JATS source: ArticleMeta
`https://articlemeta.scielo.org/api/v1/article/?collection=scl&code=${pid}&format=xmlrsps`
returns JATS 1.0 (SPS 1.4); always pass `collection`, and an unknown PID
answers HTTP 200 with the body `null`.

## License

CC BY for journals indexed since 2015 (the probe article was CC BY 4.0);
read the article page's own license link for older ones and record it as
read from the page. The text served is the published version
(`publishedVersion`).

## Verified

Live on 2026-10-16 against scielo.br and ArticleMeta (version 1.32.25)
with unauthenticated GET requests, one article, language `pt`. The
`sci_pdf` legacy route is listed in the guide's URL table and was not
fetched here. Terms for automated access beyond the CC BY statement were
not found.
