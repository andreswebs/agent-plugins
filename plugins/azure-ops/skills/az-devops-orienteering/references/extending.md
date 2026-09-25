# Extending

How to add a module, a capture or a report table.

## Module contract

A module is a file in `scripts/lib/` exposing:

| Name | Purpose |
| --- | --- |
| `SCOPE` | `"org"` (runs once, raw under `raw/_org/`) or `"project"` (runs per project) |
| `TITLE` | Report heading |
| `collect(ctx)` | Captures through `ctx.store`; no analysis |
| `analyse(ctx)` | Reads captures back with `ctx.store.load(name)`; returns a JSON-serialisable dict |
| `render(metrics)` | Returns the report's markdown from that dict alone |

Register it in `MODULES` in `scripts/az-devops-discovery.py`, in run order.
Keeping `analyse` and `render` apart is what makes `--render-only` and the
golden test work: a report can be rebuilt from `raw/` with no network.

`ctx` carries `store`, `hosts` (every service host for the organisation),
`project`, `projects`, `since_iso`, `since_sk` (Analytics date key), `today`,
`auth` and `args`.

## Captures

Use the `Store` method that matches the API's paging, or results truncate
silently:

| Method | Paging | APIs |
| --- | --- | --- |
| `get` | none | most |
| `get_paged` | `x-ms-continuationtoken` response header | builds, release deployments, approvals, graph |
| `get_skip` | `$top`/`$skip` | pull requests, pushes |
| `get_body_token` | `continuationToken` in the body | user entitlements |
| `odata` | `@odata.nextLink` | Analytics |
| `post` | none; read-only POST | WIQL |
| `text` | none; plain-text body | task logs |

Rules that each cost a run to learn:

- Aggregate on the server (Analytics `$apply`) before fetching items.
- Leave `?` and `&` unencoded in Analytics URLs; the service rejects an encoded
  `?` as a dangerous path.
- Filter snapshot dates with chained `DateSK eq … or …`; `DateSK in (…)` is
  rejected.
- Analytics `UserName` fields hold display names, not addresses.
- Select captures with `name.endswith(".meta.json")` exclusion, never a glob.
- Capture environment-variable-bearing data (agent capabilities) raw, and
  derive only keys that name software and versions.
- Anything a report quotes from user-written text goes through `redact`.

## Testing

`scripts/tests/test_reports.py` rebuilds reports from a sweep's `raw/` and
compares each report's JSON with an `expected.json` of known values:

```sh
AZDO_FIXTURE="${SWEEP_DIR}" uv run scripts/tests/test_reports.py
```

`expected.json` maps `"<scope>/<module>"` to a dict of metric names and values;
only the keys listed are checked. Fixtures hold client data, so they stay with
the engagement, never in the skill.
