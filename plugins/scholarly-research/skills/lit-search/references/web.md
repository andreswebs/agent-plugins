# Grey literature on the web

Reports, guidance, laws, survey manuals and other documents that no
scholarly index holds are found on the web. This page covers finding
them; resolving one into a bibliographic record and fetching its text
are outside this skill.

## Order

1. **Seeds first.** The plan's named institutions and documents are
   looked up on the issuing body's own site: its publications page, its
   search, or a web search restricted to its domain
   (`site:who.int "mental health" guidance`). A seed found is a hit; a
   seed not found is logged with `hits: 0` and named in the reply.
2. **Then open discovery**, with whatever web search capability the
   environment offers, restricted to institutional domains where the
   tool supports it (`site:gov.br`, `site:oecd.org`, a regulator's
   domain). A query without a domain restriction is allowed when the
   issuing bodies are not known in advance, and the log line's `notes`
   says so.

Every query, seed lookups included, appends one search-log line with
`database: "web"` and `interface: "web"`, as
[search-log.md](search-log.md) describes. Google Scholar is never
scripted; a person may search it and log the search with
`operator: "human"`. A service the project's policy excludes is neither
searched nor fetched, through any route.

## Hit lines

A web result kept becomes one hit line in the shape of
[hit.md](hit.md):

- `id` is the canonical URL of the document itself (the PDF or the
  official page), not of the search result page; `id_type` is `url`;
  `database` is `web`.
- `doi` is set only when the document itself prints one.
- `title` and `year` are read from the document's page or front matter,
  never from the search snippet alone and never from memory.
- `url` repeats `id`; `language` is the document's language when the
  page states it, else `null`.

A result is kept when it is issued by a body with standing for the claim
(a regulator, a ministry, a standards body, an international
organisation, a professional association, a university) and is the
document itself or its official landing page. Copies hosted by third
parties, news items and summaries are not kept; the original they point
to is looked up instead.
