# Reading the findings

Three rules steer the whole read. Breadth before depth: open every report's
headline table before chasing any one row. Norms before anomalies: learn what
this estate's normal looks like from the inventory and cost shape, then the
outlier is the row that does not fit. Footholds first: a finding that grants an
attacker initial access outranks one that only deepens access they do not have.

## Order

Work the reports in this sequence. The first six are the priority reports; the
rest supply depth once the map is drawn.

### 1. `summary.md`

- Modules completed. Anything short of N of N is a blind spot to state up front.
- Resource types with no dedicated module: unexplored territory. Each row is a
  follow-up, and a count out of proportion to the rest of the estate is worth a
  sentence even before it is understood.

### 2. `reports/inventory.md`

This is the map. Read it for shape, not for findings.

- Management group chain: is the subscription under a landing-zone hierarchy or
  orphaned at the root? Orphaned means no inherited policy, no inherited RBAC.
- Resources by type, by RG, by location: the architecture in silhouette. Note
  the dominant patterns; they define what "normal" means for later reports.
- Registered providers versus observed types: a provider registered with no
  resources of its kind is a trace of something removed or moved.
- Locks: absent locks on stateful resources is a hygiene note, not a foothold.

### 3. `reports/exposure.md`

The outside-in view. Everything here is a candidate foothold.

- Public IPs attached to a VM NIC with an NSG rule open to any source on 22,
  3389, 5985, 1433, 5432, 6379, 27017, 9200: rank highest. Web ports open are
  expected for a web tier; check they front a WAF or gateway, not a bare VM.
- Public IPs attached to nothing: cheap to release, and each one is a dangling
  DNS risk if a name still points at it.
- PaaS with public network access enabled plus local auth enabled: two signals
  on the same row is a stronger finding than either alone. Storage with
  `allowBlobPublicAccess=true` is the highest-value instance.
- Minimum TLS below 1.2: compliance finding, rarely a foothold.
- Public DNS zones: the record names are the externally discoverable surface;
  cross-check them against the public IP list for orphans.

### 4. `reports/identity.md`

The identity perimeter, which in Azure is the primary one.

- Privileged assignments: every Owner, Contributor, User Access Administrator.
  Users holding Owner directly on the subscription (rather than via a group)
  and service principals with Contributor at management-group scope are the
  rows to name. Guests (`#EXT#` in the principal name) with any privileged role
  rank at the top.
- Unresolvable principals: dead assignments. Zero risk until the object id is
  reused; clean-up finding.
- Assignments at resource-group or resource scope: a long list here means
  access grew by hand. Note the pattern rather than each row.
- Custom roles with wildcard actions are privilege hidden behind a friendly name.
- Resources with a managed identity: cross-reference against the privileged
  list. A system-assigned identity holding Contributor on the subscription is
  a lateral-movement path from that resource.

### 5. `reports/network.md`

The inside-out view of the same perimeter.

- Subnets without an NSG that carry VMs or delegated services.
- Peerings to VNets in other subscriptions: the trust boundary extends there;
  note the remote subscription id for the multi-subscription follow-up.
- Default route to a firewall or NVA means egress is controlled; no route table
  means every subnet egresses directly.
- Private endpoints present with the matching PaaS still showing public access
  enabled in `exposure.md`: the private path exists but the public one was
  never closed.

### 6. The floor: `governance.md`, `defender.md`, `observability.md`

Universal controls whose value is proportional to coverage. Gaps here are not
footholds but they decide whether a foothold would be noticed.

- Policy: assignments in `DoNotEnforce`, expired or open-ended exemptions, and
  the non-compliance-by-policy table, which is a free ranked list of what the
  organisation already said it wanted and does not have.
- Defender: plans on Free, no security contact, provider never registered.
- Observability: activity-log export absent means the control-plane audit trail
  expires after 90 days. Diagnostic coverage per type: Key Vault, storage, NSG
  and databases without settings are the ones that matter for forensics. No
  action groups or no alert rules means nobody is paged for anything.

### 7. Norms: `activity.md`, `cost.md`, `advisor.md`

- Activity: the callers table tells you who actually operates this
  subscription; a human account doing most writes is a process finding, a
  service principal doing them is the deployment pipeline. Failed and
  Forbidden operations show someone or something trying. RBAC changes in the
  window are always worth listing.
- Cost: services by cost is the architecture weighted by importance. A service
  with material spend and no matching module report is unexplored territory
  with a price tag.
- Advisor: read the High-impact rows; they are already ranked and free.

### 8. Depth: service reports

Open each present service report and check the columns that carry security
meaning: public access, local auth, firewall rules (a `0.0.0.0` to `0.0.0.0`
SQL rule is "allow all Azure tenants"), HA and backup where the data matters,
soft delete and purge protection on vaults, admin user on registries, RBAC vs
access policies on vaults. A dash in an object-count column means the caller
could not read, not empty.

## Ranking

| Rank | Meaning                                                                   |
| ---- | ------------------------------------------------------------------------- |
| 1    | Foothold: reachable from the internet and weakly authenticated, or a      |
|      | privileged identity an attacker could plausibly obtain                    |
| 2    | Amplifier: turns a foothold into control (over-broad RBAC, MI privilege,  |
|      | peering into other subscriptions, unrestricted egress)                    |
| 3    | Floor gap: would let a foothold go unnoticed (no log export, no Defender, |
|      | no alerts, no diagnostics on stateful services)                           |
| 4    | Hygiene: compliance, cost, tags, dead assignments, unattached IPs         |

Two rank-1 signals on the same resource stay one finding, ranked 1, with both
signals named.

## `findings.md` structure

```markdown
# Findings: <subscription name> (<id>)

- Swept: <timestamp from summary.md>; modules completed N of N
- Blind spots: <failed modules, data-plane reads denied, truncated queries>

## Shape of the estate

Three to six sentences: hierarchy position, dominant services, regions,
who operates it (from activity), what it costs (from cost).

## Ranked findings

| #   | Rank | Finding | Evidence                                                    | Resource(s)  |
| --- | ---- | ------- | ----------------------------------------------------------- | ------------ |
| 1   | 1    | ...     | reports/exposure.md, "NSG inbound rules open to any source" | nsg-x / vm-y |

## Unexplored territory

Resource types with no module, services with spend but no report, and
anything the sweep cannot see: data-plane contents, external scan results,
Entra ID objects.

## Follow-ups

Concrete next reads or runs, including other subscriptions named by peerings
or management-group siblings.
```

Every finding row cites the report and table it came from. A reader must be
able to open the report and see the row.
