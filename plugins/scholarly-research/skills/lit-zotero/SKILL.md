---
name: lit-zotero
description: "File resolved bibliographic records or bare DOIs into a Zotero library collection as metadata-only items, deduplicated on every identifier a record carries, and read back each item's Zotero key and Better BibTeX citation key. Use when a research step needs references stored in Zotero, including reports, laws and web pages without a DOI, a record-to-citation-key manifest, or a Better BibLaTeX export of a collection."
metadata:
  argument-hint: "a records.jsonl file or DOIs, optional collection name (default $ZOTERO_COLLECTION_NAME), optional tags, optionally 'whole library' for the duplicate check's scope (default the collection), optionally 'export'"
---

# lit-zotero

```bash
AGENT_ARTIFACTS_DIR="${AGENT_ARTIFACTS_DIR:-${PWD}/.local/data/agentartifacts}"
mkdir -p "${AGENT_ARTIFACTS_DIR}/lit-zotero" && echo "${AGENT_ARTIFACTS_DIR}/lit-zotero"
date -u +%Y%m%dT%H%M%SZ
```

Run this once when the run opens, and use the two printed values, the
directory and the run's `<UTC>` stamp, for every path below.

Records in, library items out: each input (a resolved
bibliographic record, one JSON object whose consumed fields are listed in
[references/zotero.md](references/zotero.md), or a bare DOI) becomes one
item in the named collection of a Zotero library, matched when the work
is already there and created otherwise, and one line of the **manifest**
in [references/manifest.md](references/manifest.md) mapping the record's
identity key to its Zotero item key and citation key, which is the
record's own when it supplies one. A record without a
DOI (a report, a law, a dataset, a web page, carried with `doi: null`) is filed
like any other; its identity key is the first of `doi`, `ids.openalex`,
a formal identifier and `ids.url`. Every call is in references/zotero.md.
The Web API is the surface written to; the local port of a running
desktop Zotero is read only, for Better BibTeX keys and exports. The
library listing is logged as [references/search-log.md](references/search-log.md)
describes.

## Environment

| Variable                 | Used for                                   | When unset                                                         |
| ------------------------ | ------------------------------------------ | ------------------------------------------------------------------ |
| `ZOTERO_API_KEY`         | `Zotero-API-Key` header on every Web API call | stop and ask the user to set it in the shell; the run does nothing |
| `ZOTERO_LIBRARY_ID`      | numeric user or group id in the path prefix | stop and ask the user to set it; the run does nothing              |
| `ZOTERO_LIBRARY_TYPE`    | `users` or `groups` in the path prefix     | `users`                                                            |
| `ZOTERO_COLLECTION_NAME` | collection to file into when the user names none | the user must name one; with neither, stop and ask |
| `RESEARCH_SEARCH_LOG`    | JSONL file the library listing appends to  | `${AGENT_ARTIFACTS_DIR}/lit-zotero/<slug>.<UTC>.search.jsonl`, and the reply names it |

Set once per run; values never go into a file, a URL or a log line:

```bash
ZOTERO_PREFIX="https://api.zotero.org/${ZOTERO_LIBRARY_TYPE:-users}/${ZOTERO_LIBRARY_ID}"
zotero_headers=(--header 'Zotero-API-Version: 3' --header "Zotero-API-Key: ${ZOTERO_API_KEY}")
```

Every call: one request at a time, `curl --silent --show-error --max-time 30 "${zotero_headers[@]}"`;
on 429 and 5xx wait `Retry-After` when sent, else 1, 2, 4, 8 s; a
`Backoff` header pauses the run for that many seconds; no retry on other
4xx. Per call keep method, path, status, `Last-Modified-Version` and
`Total-Results` for the manifest's `sources`.

## Steps

1. **Classify the input and check the key.** Each line is a record (JSON
   with an `ids` block, its `doi` possibly `null`) or a bare DOI;
   normalise a DOI bare and lower-case, and take each record's identity
   key.
   `GET /keys/current` must answer 200 and show write access to the
   library, else stop and say which permission is missing. Done when
   every input has an identity key and a kind, and the key's permissions
   are known.
2. **Find the collection**, per [references/zotero.md](references/zotero.md):
   the name the user gave, else `ZOTERO_COLLECTION_NAME`. List
   `<prefix>/collections` and match `data.name` exactly. When absent,
   create it only if the user named it in this request, and say so in the
   reply; a name taken from `ZOTERO_COLLECTION_NAME` that matches nothing
   stops the run with the name and the library prefix, since the variable
   names a collection that should already exist. Done when a collection
   key is held.
3. **Deduplicate against a local index**, per references/zotero.md.
   List the target collection once per run, or the whole library when the
   caller asks for that scope, in pages of 100, and build the
   **index**: one line per item with its DOI, URL, the identifiers of
   its fields and `extra` lines, and its normalised title and year. Log
   the listing as one search-log line. Match every input against the
   index, never against a search of the library: a hit shares an
   identifier with the record (DOI case-insensitively, URL, the
   `OpenAlex:` or `LexML URN:` line in `extra`, ISBN, report or law
   number, bill number) or, when the record or the item has no DOI, the
   same normalised title and year. A URL is an identifier only when it
   points at a document: one whose path is empty or `/` once its query
   and fragment are dropped names a site, so it is kept on the item and
   never indexed or matched on. A matched item is reused; when the
   record carries a citation key (`citation_key`) and the item's differs,
   the item is not changed and the difference is reported. By
   default the index covers the target collection only: an item held
   elsewhere in the library is not read, so a work filed there and not in
   the collection is created as a new item. With the whole-library scope
   every top-level item is read, a listing that takes minutes on a large
   library, and a matched item outside the collection is added to it. A
   record that
   carries a preprint's DOI (`ids.preprint_doi`) and matched nothing on
   its own DOI is compared on that one: an item holding the preprint's
   DOI as its own is the same work filed as a preprint, so no second
   item is created and the existing one is not changed; the input is
   `preprint_held` with that item's key, and the caller chooses what to
   do with it. Before an input is marked for creation, a record that
   carries a citation key is looked up on it in the index: when another
   item already holds that key, nothing is created and that item is not
   changed; the input is `key_held` with the holder's item key, and the
   caller decides. Each item the run creates in step 5 is added to the
   index before the next batch is matched, so two inputs for one work
   make one item and two inputs never take one key. Done when the index
   has as many lines as the listed scope has items other than
   attachments and notes, and every input is `matched`, `preprint_held`
   or `key_held` with an item key, or marked for creation.
4. **Build items** for the inputs to create: a record is mapped onto the
   `GET /items/new?itemType=` template of the item type its `type` maps
   to, per the tables in references/zotero.md, with no attachment; a bare DOI goes to the translation server when
   one answers, else it is `skipped` with the note `no metadata source`.
   Every item carries `collections: [<key>]` and the run's tags, a
   record's preprint DOI as a `Preprint DOI:` line in `extra`, and a
   record's citation key (`citation_key`), when it has one, as the
   item's `citationKey`. The item's `url` is the record's `ids.url`; a
   record with a DOI and no `ids.url` takes the DOI link
   `https://doi.org/<doi>`, so an open-access location never becomes the
   item's URL; a record without a DOI keeps its own URL. Done when
   every input to create has item JSON or a skipped note.
5. **Write**, in batches of at most 50, with `If-Unmodified-Since-Version`
   set to the library version read just before; on 412 re-read the
   version and retry once. Read `successful`, `unchanged` and `failed` by
   index; a 200 with entries in `failed` is a partial failure, carried
   per item. Done when every created item has a key or a failure code.
6. **Read citation keys back.** When `connector/ping` answers on the local
   port, ask Better BibTeX `item.citationkey` for every item key; else
   read `data.citationKey` and the `Citation Key:` line of `extra` from
   the Web API, and when both are empty record `null` with the note
   `pending: assigned when a desktop with Better BibTeX syncs the item`.
   An item created from a record that carried a citation key is read
   from the Web API and its `data.citationKey` must equal the record's;
   a difference is a note on that input. Done when every item has a
   citation key or that note.
7. **Export** only when asked: the collection as Better BibLaTeX from the
   local pull URL when the desktop answers, else `format=biblatex` from the
   Web API (Zotero's own keys, said in the reply), paged by `Link`, to
   `${AGENT_ARTIFACTS_DIR}/lit-zotero/<slug>.<UTC>.biblatex.bib`. Done when
   the file exists and the reply names which exporter made it.
8. **Emit.** Write the manifest to the path the user named or to
   `${AGENT_ARTIFACTS_DIR}/lit-zotero/<slug>.<UTC>.manifest.jsonl`, `<slug>`
   naming the batch, and print per input its status, item key and
   citation key; name every `preprint_held` input with the key of the
   item that holds its preprint, and every `key_held` input with the
   citation key and the key of the item that holds it. Done when every
   input has a manifest line and the reply names the manifest, the search
   log, and the export when made.

Attribution carried by the manifest and exports: the metadata filed came
with its records (Crossref and OpenAlex are CC0; abstracts stay with
their publishers; SciELO content is CC BY unless the article says
otherwise); library content belongs to the library's owner; the API key,
the `extra` field of private-library items and PDFs are never copied into
a file, and this skill files metadata only, no attachments.
