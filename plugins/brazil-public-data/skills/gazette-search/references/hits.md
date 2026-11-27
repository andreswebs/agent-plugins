# The hits file

One JSON object per gazette kept, one per line, in a `.hits.jsonl` file.
Every field is present; a value the API did not give is `null`. A gazette
matched by several queries or windows of one run appears once, with every
matching query listed.

```json
{
  "territory_id": "3534401",
  "territory_name": "Osasco",
  "state_code": "SP",
  "date": "2024-12-20",
  "edition": "2767",
  "is_extra_edition": false,
  "scraped_at": "2024-12-21T03:12:40.512Z",
  "url": "https://data.queridodiario.ok.org.br/3534401/2024-12-20/<sha1>.pdf",
  "txt_url": "https://data.queridodiario.ok.org.br/3534401/2024-12-20/<sha1>.txt",
  "excerpts": ["... atenção em <<saúde mental>> no município ..."],
  "queries": ["\"saúde mental\""],
  "window": { "since": "2024-01-01", "until": "2024-12-31" },
  "text_file": null,
  "retrieved": "2026-10-19T04:15:00Z"
}
```

Field rules:

- `url`, `txt_url`, `date`, `edition`, `is_extra_edition`, `scraped_at`
  are copied from the API item unchanged; `excerpts` keeps the server's
  match markers (`<<` and `>>` when `pre_tags` and `post_tags` were set).
- `queries` lists every `querystring` that matched this gazette in the
  run; `window` is the date range of the page it came from.
- `text_file` is the path, relative to the working directory, of the text
  saved for this gazette when fetching was asked for; `null` otherwise.
- `retrieved` is the UTC time of the search call that returned the item.
- Excerpts are the API's working extraction and can contain personal
  data; they are for triage, and a passage quoted in a published output
  is taken from the saved text and reviewed for personal data first.
