# dados.gov.br and INEP

Neither is called by this skill. What the guide found on 2026-10-17:

## dados.gov.br

The national open data catalogue, rebuilt in 2023 as a single-page
application with its own REST API under `https://dados.gov.br/dados/api/`.
Every API call needs an API key sent as the header
`chave-api-dados-abertos`, issued to a gov.br account (a consumer key from
"Minha Conta", an organisation key from the organisation dashboard);
without one every call, including the old CKAN `/api/3/action/*`, answers
`401` with an empty body. The only readable file without a key is the
OpenAPI document at `https://dados.gov.br/v3/api-docs`. Registering is a
human decision, so this skill makes no call there; a user who holds a key
runs the search themselves (`GET /dados/api/publico/conjuntos-dados?nomeConjuntoDados=&pagina=1`,
the success path unverified by the guide).

## INEP

INEP publishes no API. The Censo Escolar microdata is one zip per year at
`https://download.inep.gov.br/dados_abertos/microdados_censo_escolar_<YEAR>.zip`
(1995 to 2024; the 2025 file is `microdados_censo_escolar_2025_.zip` with
a trailing underscore), linked from
`https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/microdados/censo-escolar`.
There is no server-side filter: download a year by hand or with a plain
`curl --location --retry 3` into its own empty directory, then filter locally by
`CO_MUNICIPIO` (the 7-digit IBGE code) and `TP_DEPENDENCIA` (3 is
municipal). The file layout (a `;`-separated Latin-1 CSV under `dados/`
plus a dictionary) and those column names are unverified: the download
host did not answer from the guide's network, and the sizes (2024:
30,469,230 bytes; 2023: 32,094,587 bytes) came from Wayback Machine
headers. The Catalogo de Escolas is an Oracle BI dashboard with no stable
query URL; the microdata is the only reproducible route.

## Verified

2026-10-17: dados.gov.br contract read and `401` observed; INEP links
read from the gov.br page; INEP downloads and dados.gov.br data calls
not run.
