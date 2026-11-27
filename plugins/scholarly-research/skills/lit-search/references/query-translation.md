# Translating a plan string per service

A plan writes one boolean string; each service gets it in its own form.
Apply these rules the same way every run, so two runs of one plan send
the same queries. The search log keeps the exact form sent, so a reader
can always check a translation after the fact. A rule marked
**unverified** is inferred from the service's documented syntax but was
not exercised; when a run depends on it, check the service's echo of the
query (OpenAlex `meta.x_query.oql`, the CiNii `@id`) on the first call and
note the result in the log line's `notes`.

## Rules

| Service    | Where the text goes                           | AND                    | OR                       | NOT                         | Phrase                         | Grouping                        | Wildcard                                                         |
| ---------- | --------------------------------------------- | ---------------------- | ------------------------ | --------------------------- | ------------------------------ | ------------------------------- | ---------------------------------------------------------------- |
| OpenAlex   | `title_and_abstract.search:` filter value     | `AND`                  | `OR`                     | `NOT`; a leading `-` does not exclude | double quotes          | parentheses                     | not in this filter; needs `search.exact=`, so drop it            |
| Europe PMC | `query`, wrapped in `TITLE_ABS:(...)` before the date and language clauses | `AND`, or a space | `OR`         | `NOT`                       | double quotes                  | parentheses                     | trailing `*`                                                      |
| CORE       | `q`, wrapped in parentheses before the year and language clauses | `AND`            | `OR`                     | `NOT` (**unverified**)      | double quotes                  | parentheses                     | **unverified**; drop it                                          |
| arXiv      | `search_query`, every term carrying a prefix  | `AND`                  | `OR`                     | `ANDNOT`                    | `(ti:"..." OR abs:"...")`      | parentheses                     | **unverified**; drop it                                          |
| BDTD       | `lookfor` with `type=AllFields`               | `AND`                  | `OR`                     | `NOT`                       | double quotes                  | parentheses (Lucene, **unverified** here) | Lucene `*` (**unverified** here)                       |
| CiNii      | `q`                                           | `AND`, or a space      | `OR`                     | `NOT`                       | double quotes, single-byte text only | parentheses        | trailing `*`, single-byte text only                              |

Rules common to every service:

- Operators are uppercase as written above. A plan's lowercase `and` or
  `or` is an operator, not a search word.
- A plan wildcard is kept only where the table says the service supports
  it; elsewhere the stem is sent bare and the log line's `notes` says
  the wildcard was dropped.
- OpenAlex joins filter clauses with `,`, so a comma inside the search
  text would split the filter: remove commas from the text before
  sending (inferred from the clause syntax, **unverified**).
- The date window and the language travel as each service's own filter,
  never inside the translated text, except where the service has no
  separate parameter (Europe PMC `PUB_YEAR`, CORE `yearPublished`, arXiv
  `submittedDate` are clauses joined with `AND`).
- Plan strings meant for one language run only on the sources the
  language table assigns; the translation does not change the language
  of the words.
- OpenAlex keeps nested parentheses as written: `meta.x_query.oql`
  echoed `(stemmed "mental health" AND (stemmed "conversational agent" OR
  chatbot) AND (adverse OR harm OR safety))` for the grouped string
  (verified 2026-11-11).
- Europe PMC searches title and abstract by default, the same fields as
  the other services, so hit counts compare across the log. A bare query
  also matches open-access full-text bodies (one string: 1,045 hits bare,
  1 inside `TITLE_ABS:(...)`, 15 in OpenAlex), as
  [europe-pmc.md](europe-pmc.md) says. The bare form is sent only when
  the plan explicitly asks for mentions in full text, and the log line's
  `notes` says so; the `query` field shows which form was sent.

## Worked examples

Plan string (English): `"large language model" AND (suicide OR "crisis detection") NOT survey`

| Service    | Sent                                                                                                                                  |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| OpenAlex   | `filter=title_and_abstract.search:"large language model" AND (suicide OR "crisis detection") NOT survey,publication_year:2020-2026`      |
| Europe PMC | `query=TITLE_ABS:("large language model" AND (suicide OR "crisis detection") NOT survey) AND PUB_YEAR:[2020 TO 2026]`                   |
| CORE       | `q=("large language model" AND (suicide OR "crisis detection") NOT survey) AND yearPublished>=2020 AND yearPublished<=2026`            |
| arXiv      | `search_query=(ti:"large language model" OR abs:"large language model") AND (all:suicide OR ti:"crisis detection" OR abs:"crisis detection") ANDNOT all:survey AND submittedDate:[202001010000 TO 202612312359]` |

Plan string (Portuguese): `"inteligência artificial" AND ("setor público" OR governança)`

| Service    | Sent                                                                                                   |
| ---------- | ------------------------------------------------------------------------------------------------------ |
| OpenAlex   | `filter=title_and_abstract.search:"inteligência artificial" AND ("setor público" OR governança),language:pt` |
| Europe PMC | `query=TITLE_ABS:("inteligência artificial" AND ("setor público" OR governança)) AND LANG:por`          |
| BDTD       | `lookfor="inteligência artificial" AND ("setor público" OR governança)` with `type=AllFields`          |
| CORE       | `q=("inteligência artificial" AND ("setor público" OR governança)) AND language.code:pt`               |

Plan string (Japanese): `チームみらい AND (ブロードリスニング OR 広聴 OR デジタル民主主義)`;
CiNii gets `q=チームみらい AND (ブロードリスニング OR 広聴 OR デジタル民主主義)`, as
written. `広聴AI OR "Kouchou AI"` is sent as written too: the quoted phrase
is single-byte text.

## CiNii: translation and the single-term fallback

CiNii's syntax is documented in [cinii.md](cinii.md). A plan string is
translated into it operator by operator: `AND`, `OR`, `NOT` and
parentheses as written, a phrase of single-byte text in double quotes,
a wildcard on a single-byte stem as a trailing `*`. Quotes around a
double-byte term with no space inside are dropped, since such a term is
one search word already.

CiNii does not support two plan operators: a phrase whose text has
double-byte characters and a space inside (`"デジタル 民主主義"`), and a
wildcard on a double-byte stem (`民主*`). Only a string that carries one
of them falls back: it is not sent as a Boolean string; each distinct
term of the string is sent alone, as its own call (a double-byte phrase
without its quotes, a double-byte stem without its `*`); every call gets
its own log line, whose `notes` say `single-term fallback for <operator>;
plan string: <string>`; the hits of those calls are merged and
deduplicated as for any source. The merged set is the union of the
terms, not the plan's logic, and the reply says so for that string. A
string with no unsupported operator is never split.
