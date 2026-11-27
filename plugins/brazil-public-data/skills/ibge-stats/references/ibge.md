# IBGE: localidades, agregados v3 and SIDRA

Three keyless JSON APIs, no documented rate limit, no polite pool, no
`mailto` parameter, and no `User-Agent` header is sent. One request at a time,
one second between the parts of a split pull. Both value APIs encode the
whole query in the URL, so the URL is the citation of each value.

| API | Base | Role |
| --- | ---- | ---- |
| localidades v1 | `https://servicodados.ibge.gov.br/api/v1/localidades` | name to 7-digit code; territorial hierarchy |
| agregados v3 | `https://servicodados.ibge.gov.br/api/v3/agregados` | table catalogue, per-table metadata and periods; nested values form |
| SIDRA values | `https://apisidra.ibge.gov.br/values` | flat values form, one URL per query |

The municipality code is 7 digits with the state prefix (`3534401`
Osasco, state `35` Sao Paulo); SIDRA and agregados both use it under
level `N6`. Table numbers are shared by SIDRA, agregados v3 and
`sidra.ibge.gov.br/tabela/<n>`.

## Resolve a name to a code

```bash
curl --silent --globoff --max-time 60 "${IBGE_API}/v1/localidades/estados/35/municipios" --output municipios-35.json
jq --compact-output '.[] | select((.nome | ascii_downcase) == "osasco") | {id, nome}' municipios-35.json
curl --silent --globoff --max-time 60 "${IBGE_API}/v1/localidades/municipios/3534401" --output municipio.json
jq '{id, nome, micro: .microrregiao.id, meso: .microrregiao.mesorregiao.id,
     uf: .microrregiao.mesorregiao.UF.sigla, imediata: ."regiao-imediata".id}' municipio.json
```

- The state list for `35` held 645 municipalities and gave
  `{"id":3534401,"nome":"Osasco"}`; the municipality record gave
  microrregiao `35057`, mesorregiao `3515` (Metropolitana de Sao Paulo),
  regiao imediata `350001`, UF `35`, regiao `3`.
- `jq`'s `ascii_downcase` folds ASCII case only; fold accents on both
  sides before comparing a name that carries them.
- Other collections on the same base, from the docs page and not called:
  `/regioes`, `/estados`, `/mesorregioes`, `/microrregioes`,
  `/regioes-intermediarias`, `/regioes-imediatas`, `/municipios`,
  `/distritos`, `/subdistritos`, `/regioes-metropolitanas`,
  `/aglomeracoes-urbanas`, `/paises`, each with `/{id}`.
- Responses carry `Cache-Control: max-age=2592000`: reuse a saved list
  for a month. Unknown codes were not probed; treat any non-200 as
  "check the code".

## Find a table and read its contract

The catalogue is one 1.95 MB JSON array of 70 surveys, each with its
tables; filter it with `jq`, never read it.

```bash
curl --silent --globoff --max-time 60 "${IBGE_API}/v3/agregados" --output agregados.json
jq --raw-output '.[] | "\(.id)\t\(.nome)\t\(.agregados | length)"' agregados.json
keyword="ocupadas"
jq --raw-output --arg s "Censo Demográfico" '.[] | select(.nome == $s) | .agregados[] | "\(.id)\t\(.nome)"' agregados.json | grep -i "${keyword}"
table="10268"
curl --silent --globoff --max-time 60 "${IBGE_API}/v3/agregados/${table}/metadados" --output "meta-${table}.json"
jq '{nome, pesquisa, periodicidade, niveis: .nivelTerritorial.Administrativo,
     variaveis: [.variaveis[] | {id, nome, unidade}],
     classificacoes: [.classificacoes[] | {id, nome, total: (.categorias[] | select(.nome == "Total") | .id)}]}' "meta-${table}.json"
curl --silent --globoff --max-time 60 "${IBGE_API}/v3/agregados/${table}/periodos" | jq --compact-output '[.[].id]'
```

Metadata fields: `variaveis[].id`, `classificacoes[].id`,
`classificacoes[].categorias[].id`, `nivelTerritorial.Administrativo[]`
(`N6` means the table reaches municipalities), `periodicidade.{inicio,fim}`.

Tables verified for a municipality, with the ids a value needs:

| Topic | Table | Survey | Variables | Classification totals | Periods |
| ----- | ----- | ------ | --------- | --------------------- | ------- |
| Population | 4714 | Censo Demografico 2022 | 93 Populacao residente; 6318 Area; 614 Densidade | none | 2022 |
| Labour | 10268 | Censo Demografico 2022 | 140 pessoas de 10 anos ou mais; 696 ocupadas; 675 nivel de ocupacao | 2 Sexo `6794`; 86 Cor ou raca `95251`; 58 Grupo de idade `95253` | 2022 |
| Formal establishments and employment | 9510 | CEMPRE (municipalities of 50,000 or more) | 13, including 707 pessoal ocupado total, 708 assalariado, 10143 salario medio | 12762 CNAE 2.0 section (109 categories) | 2022 to 2024 |
| Municipal councils (culture, heritage, sport, health) | 7402, 7403, 7405 | Pesquisa de Informacoes Basicas Municipais | 603 Numero de municipios (7402); 12822 Municipios com Conselho Municipal de Saude (7403, 7405) | 12446 population size class `47692`; 1511 existence; 1510 situation `58782`; 1165 character `50636`; 1164 representation `50632`; 1276 infrastructure `57144`; 1070 training `50115`; 1277 meetings `57145` | 2021 |

The council tables are counts of municipalities: at `n1` a value is the
number of municipalities in the category, and at `n6` it is `1` when the
municipality is in the category and `-` when it is not (read on
2026-11-25: Brasil 5,526 municipalities with a health council; one
municipality `1` for an active council and `-` for an inactive one). One
URL can carry `n1/all` and `n6/<code>` together; each record's `NC` and
`NN` then say which level it belongs to, and the value line keeps `NN`
as `territory_level`.

Education: the guide verified no table; find one in the Censo Demografico
survey (1,388 tables) by keyword, then confirm `N6` in its metadata.
Municipal labour figures come from the 2022 Census (one point in time)
and from CEMPRE (formal establishments only); the quarterly PNAD does
not reach municipalities.

## SIDRA values

```bash
IBGE_MUN="3534401"
curl --silent --globoff --max-time 60 --output pop.json --write-out '%{http_code}\n' "${SIDRA_API}/t/4714/n6/${IBGE_MUN}/v/93/p/all"
jq --raw-output '.[1:][] | "\(.D1N) | \(.D3N) | \(.D2N) = \(.V) \(.MN)"' pop.json
curl --silent --globoff --max-time 60 --output work.json "${SIDRA_API}/t/10268/n6/${IBGE_MUN}/v/all/p/all/c2/6794/c86/95251/c58/95253"
jq --raw-output '.[1:][] | "\(.D2N) | \(.D3N) | \(.V) \(.MN)"' work.json
curl --silent --globoff --max-time 60 --output cempre.json "${SIDRA_API}/t/9510/n6/${IBGE_MUN}/v/allxp/p/last/c12762/all"
jq --raw-output '.[1:][] | select(.D4N == "Total") | "\(.D2N) | \(.D3N) | \(.V) \(.MN)"' cempre.json
```

Parameters, from the help page:

| Parameter | Values | Default | Notes |
| --------- | ------ | ------- | ----- |
| `t` | table number | required | one per query |
| `p` | `all`; `first N`; `last N`; codes `2008,2010-2014`; monthly `201101-201112` | `last` | annual codes `AAAA`, others `AAAASS` |
| `v` | `all`; `allxp` (all except auto-generated percentages); codes `93,1000093` | `allxp` | codes above 1,000,000 are percentage variables |
| `n<level>` | `all`; codes `3534401,3550308`; `in n3 35` (every municipality of a state) | none | `n1` Brasil, `n2` Grande Regiao, `n3` UF, `n6` Municipio; repeatable; `/u/y` includes extinct units |
| `c<id>` | `all`; `allxt` (all except total); codes `2692,2702`; a space joins a sum `2694 2695` | the Total category | up to 6 classifications per table |
| `h` | `y`, `n` | `y` | header record first |
| `f` | `a` codes and names, `c`, `n`, `u` | `a` | |
| `d` | `s` standard decimals, `m` max, `0` to `9` | `s` | |
| `?formato=` | `json`, `xml` | `json` | query string wins over `Accept` |

- The JSON is an array whose element 0 is the header record; strip it
  (`.[1:]`) or request `/h/n`. Each record: `V` value, `MC`/`MN` unit,
  `NC`/`NN` territorial level, `D1C`/`D1N` to `D9C`/`D9N` dimension code
  and name in the order the parameters appeared in the URL, not a fixed
  schema. Every field is a string.
- Special values in `V`: `-` absolute zero, `0` rounded zero, `X`
  suppressed for confidentiality, `..` not applicable, `...` not
  available, a letter for a precision band.
- Limit: 100,000 values per query (the product of the element counts of
  every selected dimension), at most 9 dimensions; the refusal comes from
  the help page and was not exercised. No pagination: split by period
  (`/p/2022`, `/p/2023`), by variable, or by territory (`/n6/in n3 35`
  is 645 municipalities for Sao Paulo), and list several municipalities
  with commas.
- Errors: `400` with a plain-text body for a bad table
  (`Tabela 999999: Tabela invalida`). The HTML pages on the same host
  (help, `sidra.ibge.gov.br/tabela/<n>`) sit behind a Cloudflare
  challenge; the `/values/` API answers curl.

## Agregados v3 values

```bash
curl --silent --globoff --max-time 60 "${IBGE_API}/v3/agregados/4714/periodos/2022/variaveis/93?localidades=N6[${IBGE_MUN}]" |
    jq --compact-output '.[] | {id, variavel, unidade, serie: .resultados[0].series[0].serie}'
curl --silent --globoff --max-time 60 "${IBGE_API}/v3/agregados/10268/periodos/2022/variaveis/696|675?localidades=N6[${IBGE_MUN}]&classificacao=2[6794]|86[95251]|58[95253]" |
    jq --compact-output '.[] | {id, variavel, unidade, serie: .resultados[0].series[0].serie}'
```

- Form: `/{table}/periodos/{p}/variaveis/{v}?localidades=N6[code]&classificacao={c}[{cat}]`;
  `|` joins variables, classifications and periods; `[]` and `|` need
  curl's `--globoff` and a quoted URL.
- Result: `[{id, variavel, unidade, resultados[{classificacoes, series[{localidade{id}, serie{period: value}}]}]}]`,
  one element per variable, the value a string per period.
- From the docs page, not called: `/{table}/localidades/{nivel}`,
  `/{table}/variaveis?localidades=&view=OLAP`, and period forms `-6`
  (last six), `201701-201706`, `201701|201710`.
- Errors: an unknown table answers
  `500 {"statusCode":500,"message":"Internal server error"}`; check the
  id before retrying.

## Worked example: Osasco, 2022

| Table and variable | SIDRA URL path | Value |
| ------------------ | -------------- | ----- |
| 4714 v93 Populacao residente | `/t/4714/n6/3534401/v/93/p/all` | 728,615 pessoas (2022) |
| 10268 v140 pessoas de 10 anos ou mais | `/t/10268/n6/3534401/v/all/p/all/c2/6794/c86/95251/c58/95253` | 639,174 (2022) |
| 10268 v696 ocupadas na semana de referencia | same | 349,813 (2022) |
| 10268 v675 nivel de ocupacao | same | 54.73% (2022) |
| 9510 unidades locais, total of CNAE | `/t/9510/n6/3534401/v/allxp/p/last/c12762/all` | 43,522 (2024); 1,417 values, 307 KB |

The agregados form `/4714/periodos/2022/variaveis/93?localidades=N6[3534401]`
returned `"2022": "728615"`, and
`/10268/periodos/2022/variaveis/696|675?localidades=N6[3534401]&classificacao=2[6794]|86[95251]|58[95253]`
returned `"2022": "349813"` and `"2022": "54.73"`: the same figures as
SIDRA.

## Verified

Live on 2026-10-17, keyless, from one non-Brazilian network: localidades
(state list and municipality record), the agregados catalogue, metadata
for tables 4714, 10268 and 9510, SIDRA values for the same three tables,
and the agregados values form for 4714 and 10268. The 100,000-value cap,
the localidades collections other than the two called, and the agregados
`localidades`, `OLAP` and period-range forms come from documentation and
were not exercised. The guide recorded no license text for IBGE data.
