# The filing manifest

One JSON object per input, one per line in a `.manifest.jsonl` file.
Every field is present; a value the run did not obtain is `null`, never
omitted, so a reader tells "not asked" from "not known" by reading
`sources` and `notes`.

```json
{
  "input": "10.1590/0102.3772e36nspe19",
  "input_kind": "record",
  "doi": "10.1590/0102.3772e36nspe19",
  "identity": "10.1590/0102.3772e36nspe19",
  "status": "created",
  "library": "users/1234567",
  "collection": {"name": "my-collection", "key": "QW3R7YUI"},
  "item_key": "ABCD2345",
  "item_version": 1532,
  "item_type": "journalArticle",
  "tags": ["topic-a", "topic-b"],
  "citation_key": null,
  "citation_key_source": null,
  "sources": [
    {"service": "zotero", "method": "GET", "path": "/users/1234567/collections/ABCD2345/items/top (listing, 6 pages)", "ts": "2026-10-19T04:07:35Z", "status": 200, "total_results": 574},
    {"service": "zotero", "method": "POST", "path": "/users/1234567/items", "ts": "2026-10-19T04:07:36Z", "status": 200, "library_version": 1532}
  ],
  "notes": ["citation key pending: assigned when a desktop with Better BibTeX syncs the item"]
}
```

Field rules:

- `input_kind` is `record` or `doi`. `doi` is bare and lower-case, or
  `null` for a record without one. `identity` is the record's identity
  key (the DOI when there is one, else the OpenAlex id, a formal
  identifier, or the URL).
- `status` is `created` (a new item), `matched` (the index held an
  item sharing an identifier, or the same title and year; `item_key` is
  its key, and with the whole-library scope `notes` says whether it was
  added to the collection), `preprint_held` (the index holds the
  record's preprint as an item of its own; nothing was created or
  changed, `item_key` is the preprint item's key, `citation_key` is
  that item's, and `notes` carries
  `preprint item <key> holds <preprint doi>; published version not filed`),
  `key_held` (no identifier and no title and year matched, but an item
  in the index already holds the record's `citation_key`; nothing was
  created or changed, `item_key` is the holder's key, `citation_key` is
  the held key with `citation_key_source` `null`, and `notes` carries
  `citation key <key> held by item <item key>; not created`),
  `skipped` (a bare DOI with no metadata
  source), or `failed` (the write's `failed`
  entry; `notes` carries its `code` and `message`).
- `library` is `<type>/<id>` as used in the path prefix. `collection.key`
  is the key filed into; `notes` says `collection created` when the run
  made it.
- `item_key` is the 8-character Zotero key; `item_version` the version
  returned by the write or the read. Both `null` on `skipped`.
- `citation_key` is the item's citation key when read; `citation_key_source`
  is `record` (the record supplied the key, it was written at creation
  and the item read back with it), `bbt-jsonrpc`, `citationKey` (the
  native field, a key the record did not supply) or `extra` (the
  `Citation Key:` line), or `null` with the pending note. A created item
  whose `citationKey` reads back different from the record's keeps the
  value read, with the note `citation key differs after write`. A
  matched item whose key differs from the record's is not changed:
  `citation_key` is the item's, and `notes` carries
  `citation key differs: item has <key or none>, record gives <key>; not changed`.
- `tags` lists the tags the run asked for, as sent.
- `sources` lists every HTTP call made for this input, the run's one
  library listing included as a single entry on each line, the path with no
  key and no query values that would identify a person, plus the headers
  the call returned (`total_results`, `library_version` from
  `Last-Modified-Version`, `retry_after` or `backoff` when present).
- `notes` holds free text: the pending key, a 412 retry, a type fallback
  to `report` or `journalArticle`, a partial batch, a skipped reason.
