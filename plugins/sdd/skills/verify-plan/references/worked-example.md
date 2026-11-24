# Worked example

From two plans for the same Meteor application, verified before implementation.
Each case maps to one pattern in the skill. The second half comes from a
dependency-cleanup plan and is the better illustration of removal claims; the
first half from a defect-fix plan.

## A search that could not see the answer

**The claim.** A dependency-removal plan listed `blaze-html-templates` for
deletion, on the evidence "no Blaze templates in the repository". Nine other
packages were listed on the same evidence and were genuinely dead.

**The code.** One file: `client/head.html`, compiled by
`blaze-html-templates` and `templating-compiler`, both present in the resolved
package versions. It carried the whole document head: title, favicon, the
viewport meta, web fonts, and a third-party reCAPTCHA `<script>` tag.

**What the error would have cost.** Removing the package strips the head.
Without that script tag the reCAPTCHA global never loads, and the widget on the
**public sign-up form** stops working. A public-facing form breaks.

**Why no gate would have caught it.** The test suite ran with the client
disabled, and the CI boot check asserted only that the process started, which it
still would. Green everywhere, form broken.

**Why the claim was believable.** The package sat in the manifest beside
genuinely dead ones; an earlier assessment had marked it "zero usage, removable
now"; and there were no template files anywhere under the application source
directory, so a search scoped to application code found nothing. The one file
lived outside every directory anyone thinks to search.

**The lesson.** "Zero import sites" measures imports. A build-time compiler
leaves no import, and neither does a peer dependency, a resolution pin, or a
stylesheet. The question was "is this used"; the measurement answered "is this
imported". Empty results are indistinguishable from wrong questions.

## A claim that history answered instantly

**The claim.** The same plan listed a `resolve` dependency as dead: zero import
sites, and a suspicious tilde pin.

**The history.** One command settled it:

```sh
git log -S'"resolve"' -- package.json
```

A single commit, titled `Workaround compile issue due to resolve pkg`, which
added the dependency **in the same change as a platform-version bump**. It is a
resolution pin placed to fix a build failure during an upgrade. A dependency
tree query confirmed it was also required transitively by two build-time
toolchains, with the top-level entry deduped against both.

**The lesson.** Current code says what the system does. The commit that added a
line says why it exists, which is precisely what "this is vestigial" claims.
When the claim is about intent rather than behavior, history is the primary
source, and reading what else changed in the same commit is where the answer
usually is.

## Dead code arriving in duplicate

**The finding.** Chasing one deprecated import turned up a private helper,
`_fetchFacebookPageData`, defined **four times** across four sibling modules.
Three had been migrated to the real API client. The fourth still used the
deprecated transport, and was the one that had quietly fallen out of use.

**The lesson.** When something is dead, check whether it is one of N copies. The
copy that died is evidence the others are drifting, and the duplication is
usually the real finding. Here it became evidence for a later phase whose whole
purpose was consolidating that duplication.

## Symptom laundered into a mechanism (step 3)

**The claim.** "`mapFeatures.create` throws on every call": the linter reported
`res` as an undefined identifier, and the method returns `res`.

**The code.** The undefined identifier was real. The crash was not:

```js
const insertId = await MapFeatures.insertAsync(insertDoc);
return insertId;

Meteor.call("log", { type: "map.features.add", data: { mapFeatureId: res } });
return res;
```

An early `return` sits above the `res` references, so they are **unreachable**.
Creation works.

**What the error cost.** The plan sorted this as a user-facing crash, which it
was not, and missed the real defect, which was silent: the audit-log call is
below the return, so `map.features.add` entries have not been written since the
async refactor. Nothing errors and nothing appears in the UI.

**The lesson.** The linter was right about the symbol and said nothing about
reachability. "Undefined identifier" plus "therefore it crashes" is two claims,
and the tool only supports the first.

## An aggregate hiding shapes (step 4)

**The claim.** "76 call sites of the same guard bug, fix them mechanically."

**The code.** Three shapes, not one:

| Shape                                                   | Count | Wrong behavior                     |
| ------------------------------------------------------- | ----- | ---------------------------------- |
| `if (!Meteor.call(...)) throw`                           | 56    | Guard never fires                  |
| `const allowed = Meteor.call(...); if (allowed) return`  | 6     | Always publishes                   |
| `if (Meteor.call(...)) { ... }`                          | 14    | Body always runs                   |

Split by context: 58 in methods, 18 in publications. The permission function
signals denial by **throwing**. In a method that is a clean 401. In a publication
it is a subscription error rather than an empty result, so the prescribed
mechanical fix would have converted a data leak into broken screens on 18 sites.

**The lesson.** A count is a hypothesis that the members are alike. Sample before
prescribing one fix for all of them.

## A severity class nobody recorded (step 4)

**The claim.** Implicit throughout: this is a read-authorization bug, so the harm
is disclosure.

**The code.** Two of the 14 positive-form sites gate deletion:

```js
if (adminCount == 1 && Meteor.call("campaigns.userCan", { ... })) {
  await CampaignsHelpers.removeCampaign({ campaignId: campaign._id });
}
```

The always-truthy Promise contributes nothing, so the condition collapses to
`adminCount == 1` and campaigns are deleted without a permission check.

**What the error cost.** The whole plan was sequenced around a gate that only
made sense for disclosure: measure who loses access before restoring the checks.
That gate does not apply here, because restoring this check only makes deletion
harder. The item could have shipped immediately and was instead queued behind a
measurement. A leak is also recoverable and a deleted record is not, so the
severity ordering was backwards.

**The lesson.** The plan classified the defect by the harm its author noticed
first. Ask what else the same broken expression does.

## The wrong counting unit (step 4)

**The claim.** A progress table reading "Fixed (all of `faqMethods.js`): 5".

**The code.** The five methods were fixed. The feature's publication was not, so
it still served the same documents the methods now refused. The data leak the
plan's own confirming test had demonstrated was still reachable.

**The lesson.** The table counted files. Whether a user is affected is decided
per feature. Both numbers were accurate; only one answered the question the table
appeared to answer.

## Work that already shipped (step 4)

**The claim.** "Batch A has no gate", in a plan splitting the work into an
ungated batch and a gated one.

**The history.** The five guard fixes were already committed. Batch A could not
be assembled without them, and they were live authorization changes, so the
ungated batch carried exactly the risk the split existed to isolate.

**The lesson.** The plan partitioned work by risk while assuming none of it had
landed. Check history, not just the working tree, before trusting a partition.

## Result

Four corrections, three of which changed sequencing rather than wording: the gate
moved from between the batches to the front, one item moved out of the gated
batch entirely, and a fifth item was added that the plan had never recorded.

None of the four was findable by re-reading the plan. Every one was visible in
the first file it named.
