# The value line

One JSON object per figure, one per line in a `.values.jsonl` file. Every
field is present; what the API did not give is `null`, never omitted.

```json
{
  "municipality": "Osasco",
  "code": "3534401",
  "uf": "SP",
  "territory_level": "Município",
  "territory_name": "Osasco (SP)",
  "topic": "labour",
  "api": "sidra",
  "table": 10268,
  "survey": "Censo Demográfico",
  "variable": {"id": 696, "name": "Pessoas de 10 anos ou mais de idade, ocupadas na semana de referência", "unit": "Pessoas"},
  "classifications": {"2": {"id": 6794, "name": "Total"}, "86": {"id": 95251, "name": "Total"}, "58": {"id": 95253, "name": "Total"}},
  "period": "2022",
  "value": "349813",
  "value_number": 349813,
  "flag": null,
  "url": "https://apisidra.ibge.gov.br/values/t/10268/n6/3534401/v/all/p/all/c2/6794/c86/95251/c58/95253",
  "ts": "2026-10-17T14:02:11Z",
  "status": 200,
  "notes": []
}
```

Field rules:

- `territory_level` and `territory_name` say what the figure is about, in
  the service's own words: the level is SIDRA's `NN` (`Brasil`, `Grande
  Região`, `Unidade da Federação`, `Município`, the names of the URL's
  `n1`, `n2`, `n3` and `n6`), the name the territory's own (`D1N` when
  the territory is the first dimension, as in `Osasco (SP)` or
  `Brasil`). Both are set on every line.
- For a municipality, `municipality` is its name, `code` the 7-digit
  string and `uf` the two-letter state from the hierarchy record. For
  any other territory `municipality` is `null`, `code` is that
  territory's code as the service gives it (`1` for Brasil, two digits
  for a state) and `uf` is the state's letters for a state and `null`
  otherwise. A pull that reads a municipal answer against a national or
  state figure writes both rows to the one file:

  ```json
  {"municipality": null, "code": "1", "uf": null, "territory_level": "Brasil", "territory_name": "Brasil", "table": 7402, "value": "5570"}
  ```

  (the other fields as above).
- `topic` is the user's word for what was asked (`population`, `labour`,
  `education`, or the table number when the user named one).
- `api` is `sidra` or `agregados`; `url` is the exact request URL as
  sent, which is the value's citation.
- `variable` and `classifications` carry ids and names from the response
  (`D<n>C`/`D<n>N` in SIDRA; `id`, `variavel`, `classificacoes` in
  agregados), keyed by classification id; `unit` is SIDRA's `MN` or
  agregados' `unidade`.
- `value` is the string the API returned. `value_number` is its numeric
  form, or `null` when `flag` is set. `flag` is one of `-` (absolute
  zero), `0` (rounded zero), `X` (suppressed for confidentiality), `..`
  (not applicable), `...` (not available), or a letter (precision band);
  `null` for a plain number.
- `notes` holds free text: a cross-check against the other API, a split
  made to stay under the 100,000-value cap, a period absent from the
  table.
