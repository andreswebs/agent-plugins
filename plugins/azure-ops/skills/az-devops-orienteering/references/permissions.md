# Permissions

What each module reads, what it needs, and how a refusal looks. Read it when
settling the summary's "Could not read" table, and before asking for access.

## Reading a refusal

| Result | Meaning | Report it as |
| --- | --- | --- |
| 200 with items | readable | the data |
| 200, empty list | nothing visible to this identity | "none visible", never "none" |
| 403 | refused; the message names the missing permission | "could not read: needs X" |
| 404 where a sibling endpoint gives 403 | permission gap on that service | as 403 |
| 404 on its own | endpoint absent at that address or API version | an open question, not a finding |
| 401 | the token was not accepted | fix sign-in; see [identity.md](identity.md) |

## By module

| Module | Reads | Needs |
| --- | --- | --- |
| `access` | one probe per surface | any organisation member |
| `org` | graph users, groups, memberships; user entitlements; extensions; feeds; processes | Project Collection Valid Users for graph and entitlements; `ReadPackages` on a feed for its contents |
| `repos` | repositories, pull requests, refs, branch statistics, pushes, policies, builds, TFVC | project Reader; the repository recycle bin needs Edit project |
| `pipelines` | Analytics pipeline runs, build and release records, approvals, agents and capabilities, environments, retention, parallel jobs | project Reader plus View analytics; agent pools need pool Reader; service connections need endpoint Reader or User |
| `boards` | classification, Analytics work items and snapshots, WIQL, work item batches and comments | project Reader plus View analytics |
| `wiki` | wiki list and page tree | project Reader |

## Administrator-only reads

These return empty or refuse for a non-administrator. Ask an organisation
administrator to grant read, or to run the reads for you:

- **Service connections**: which subscriptions pipelines deploy to, and how
  they authenticate.
- **Service hooks**: what outside the project can trigger a pipeline or
  receive events.
- **Hidden projects**: membership in their Readers group.
- **Audit log**: the "View audit log" permission, and auditing switched on;
  available only for organisations backed by Entra ID, and kept 90 days.
- **Deleted repositories**: Edit project.

## Asking for access

One request, listing every refusal from the summary with the permission its
message names, is better than one request per surface. Read access to a
project is its Readers group; organisation-wide read of administrative
surfaces has no single role and usually means an administrator runs the reads.
