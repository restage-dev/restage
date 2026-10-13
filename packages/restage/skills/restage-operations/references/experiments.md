# Design and run experiments

Use an experiment to compare surface changes against a defined outcome. Resolve
the [target](targets-and-tools.md), choose the design, then create and review the
draft. Experiment authoring and result reads are available through CLI, TUI and
MCP without an experimental opt-in.

## Protect running experiments

Before changing serving or measurement, inspect the affected target's experiments
and obtain the operation's authoritative impact review when available. Uploading
an immutable candidate revision does not activate it or replace an experiment's
pinned revision; preparation can stop at that upload.

For publication, rollback, kill, freeze and routing changes, review the returned
experiment names, metric names, affected versions and consequences. Warnings can
describe lost metric sources, changed populations or lost scheduled output.

- If newly disclosed impact is outside the user's authorization, stop before
  applying. Explain the concrete effect and present the prepared change for a
  decision. Existing authorization that explicitly covers those effects remains
  valid; do not request it again for the same reviewed operation.
- Only supply a review digest or warning acknowledgement after that impact is
  authorized. Copying a token from an error is not approval. General `--yes`,
  `confirmLive` or TUI confirmation does not acknowledge experiment warnings.
- Treat refusals as blockers. For stale state, obtain a fresh review and compare
  its impact with the authorized change. Do not pause or conclude an experiment,
  change targets, or switch tools merely to get an operation accepted.

The tools enforce exact review evidence, not independent proof that a human
approved it. An acknowledged warning can permit a change that disrupts an
experiment; it does not certify that the experiment remains valid.

Impact reviews cover specific delivery and measurement changes. They are not a
universal guard for credential revocation, SDK configuration or app releases.
For example, revoking a key used by installed apps or disabling analytics or
measurement can interrupt delivery or assignment without this warning workflow.
Inspect those dependencies and stop when likely experiment impact is outside
the user's authorization. A missing review mechanism is not evidence of no impact.

See [Delivery](delivery.md) and [Routing](routing.md) for the exact review and
acknowledgement inputs. Rollback compatibility preview is a separate check.

## Choose what to test

Start with a hypothesis and a decision: what change could improve which outcome,
for which audience, and what would justify serving it more widely?

The usual workflow compares published versions of one surface. It works for
onboarding, messages, surveys, paywalls and other surfaces. Restage supports
2–16 named variants, a reference variant and even or unequal allocation weights.
Choose exact published versions so the comparison has stable inputs.

Use the ordinary generated `*Surface(...)` mount and hosted configuration.
Placements are implicit. Keep analytics and measurement enabled so the SDK can
obtain assignment credentials. The SDK resolves assignments; the app does not
need its own random variant picker. An unassigned fallback is not an experiment
exposure. A user can still belong to the assigned analysis population even when
the assigned version does not render.

Discover the target's surfaces, versions, metrics and audiences. Audience
selection binds an exact revision. Check installed-build and attribute readiness
before activation. Installation is the default randomization unit; preserve the
resolved setting and distinguish it from a signed-in user account.

## Select metrics and analysis

| Choice | Purpose |
| --- | --- |
| Primary metric | The outcome the experiment should improve |
| Safety metrics | Outcomes whose deterioration would block a rollout |
| Diagnostic metrics | Additional observations that help explain the result |
| Measure only | Report observations without calling a winner |
| Fixed-horizon rate comparison | Compare multiple variants using the planned enrollment and follow-up |

Use metric identities and analysis choices returned by discovery. The rate
comparison requires a supported binary outcome; some metrics support only
measurement. Match each variant's metric bindings and preserve the service's
denominators. A surface's presentation count and an experiment's assigned-unit
population answer different questions.

For a fixed-horizon comparison, review these inputs before activation:

- Reference variant, allocation weights and expected baseline rate.
- Minimum detectable effect and the improvement that would be practically useful.
- Resolved significance level and target power.
- Enrollment cap and maximum enrollment duration.
- Follow-up duration and grace period for late outcomes.
- Each safety metric's adverse direction, harm margin and planning assumptions.

Use validation's feasibility result and planned per-variant enrollment. Resolve
infeasible or indeterminate planning before launch. Treat server defaults as
explicit resolved choices. Monitoring an active run does not create an interim
winner; the retained design governs when inference is available.

## Example: shorten onboarding

1. Define the hypothesis: fewer steps improve completion. Choose an available
   safety outcome whose deterioration would outweigh that improvement.
2. Build and upload the alternative flow revision with `restage surface push`.
   Keep the current version serving. Exercise both generated mounts and
   delivered rendering with the installed app contract.
3. Discover the completion metric, supported analysis and eligible audience for
   the exact target. Choose the current version as reference and set allocation.
4. Select the primary rate, available safety metrics and useful diagnostic
   metrics. Set the baseline, useful effect and time/enrollment limits.
5. Validate feasibility, compatibility and readiness. Review the exact draft,
   then activate it within the user's authorization.
6. Monitor collection, exclusions and delivery while enrollment and follow-up
   run. Read the final primary and safety outcomes before choosing a rollout.
7. Use the returned delivery options to prepare the subsequent serving change.
   Selecting a winner and publishing a delivery rule are separate operations.

## Create and save a draft

Prepare each alternative locally and upload its compiled revision. Replace
`SURFACE_SLUG` with the authored surface's slug:

```sh
dart run build_runner build
restage surface push SURFACE_SLUG
```

Preserve the uploaded revision. Discovery includes admitted revisions whether
active or inactive. `surface publish` changes default serving, so experiment
candidate preparation ends at upload.

```sh
restage experiment discover --json
restage experiment create --json
restage experiment resolve-draft --draft-id DRAFT_ID --json > draft.json
```

Replace placeholders with returned identities. Edit only `response.choices` in
the accepted draft result, using discovered options and the public authoring
schema. Save the entire envelope:

```sh
restage experiment save --replacement draft.json --json > saved-draft.json
```

Keep the target, draft id, revision and compare-and-set token intact. Use the
newly returned revision and token for subsequent operations. Resolve again after
a stale-edit refusal. A bare choices object is not a replacement envelope.

## Validate, review and activate

```sh
restage experiment validate --draft-id DRAFT_ID \
  --draft-revision-id REVISION_ID --expected-cas CAS_TOKEN --json
restage experiment review --draft-id DRAFT_ID \
  --draft-revision-id REVISION_ID --expected-cas CAS_TOKEN --json
restage experiment activate --draft-id DRAFT_ID \
  --draft-revision-id REVISION_ID --expected-cas CAS_TOKEN \
  --review-id REVIEW_ID --review-digest REVIEW_DIGEST
```

Read `response.planningPreview` and the returned validation issues. Inspect
audience conflicts and impact. Activation uses
the review for the exact current draft; any edit requires a fresh review. Preserve
an explicit `--idempotency-key` and unchanged payload when retrying a write after
a lost response. Live changes retain their normal confirmation controls.

## Read results and choose the next action

```sh
restage experiment list --json
restage experiment results --experiment EXPERIMENT_ID --json
restage analytics health --json
restage delivery map --json
```

Results default to the accepted run. `--from` and `--until` narrow descriptive
traffic breakdowns; they do not recompute the retained statistical result for a
new period. Keep the experiment epoch, metric binding and assigned population
attached to the inference you interpret.

Use the service's result status, effect estimates, intervals and approved
comparisons. Fixed-horizon rate inference compares every variant pair with
family adjustment. Beating the reference alone does not establish a winner:
the winning variant must exceed the practical margin against every other
variant, with all required safety comparisons acceptable. Safety can be
acceptable, harmful or unresolved. Measure-only runs do not call winners.

Inference counts assigned randomized units, including assignments before
rendering, with one binary outcome per unit. Missing or unresolved outcomes are
not failures. Evaluated results require enrollment, follow-up and late-arrival
grace to finish with complete counts. Use the returned confidence level and
decisions; do not invent p-values or assume a confidence level.

Platform, country and build breakdowns describe traffic. They do not establish
segment-specific treatment effects. Respect each result family's availability;
descriptive traffic may be available while inference is withheld or pending.
See [Analytics](analytics.md) for disclosure and denominator rules.

### Inspect the numerical result

The ordinary results command returns a page envelope. Handle a refusal first,
then select the `experiment-results-page` projection and read its `document`.
When the inference family is available, `inference.value.documentBytes` is
unpadded base64url containing canonical JSON. Decode it with `dart:convert` and
the public `restage_measurement_schema` helper:

<!-- skill-check: declarations -->
```dart
final inference = decodeCanonicalObject(
  base64Url.decode(base64Url.normalize(encodedDocumentBytes)),
);
```

Check `kind` and `outcome.state` before reading figures. An evaluated
`nArmRateExperimentInference` has `outcome.primaryPairs`,
`outcome.guardrailFamilies` and top-level `allowedCopy`. Preserve exact rational
and dyadic values. This generic decoder does not validate the inference schema.
Use the approved comparisons when a brief summary does not explain which
variants differ.

For the public typed numerical view, first call `experiment read --experiment-id
EXPERIMENT_ID --json`. Its accepted `response.summary` supplies
`activationOrdinal` and, when available, `inferenceReference.resultDigest`.
Call MCP `restage_experiment_apply` with operation `readExperimentResults` and
payload fields `experimentId`, `activationOrdinal` and `resultDigest` at the
same exact target. This read takes no idempotency key. Its accepted response is
`ExperimentResultsViewV1`, with decimal and exact figures. Public
`ExperimentApi.execute` supports the same operation.

The typed view reports effect as variant rate minus reference rate. Full
inference pair differences are oriented toward the configured benefit. Preserve
the metric direction when interpreting either representation. Resolve the
reference again if the service refuses a stale result digest.

Read lifecycle state with `restage experiment read --experiment-id EXPERIMENT_ID --json`.
Use `response.summary.lifecycleOrdinal` as `--expected-lifecycle-ordinal` for
pause, resume or conclude. A concluded experiment cannot resume. The public review
workflow covers drafts and initial activation; it does not provide configuration
edits to an already active comparison.

A winning variant is not promoted automatically. Inspect
`restage experiment delivery-options --experiment-id EXPERIMENT_ID --json`.
Preserve the measured audience revision when preparing the next
[delivery plan](routing.md). Confirm
the serving change independently of the experiment's statistical result.

## Advanced authoring and other tools

The dashboard's normal authoring form compares versions of one surface. Public
authoring contracts also support placement-root experiments with whole-surface
destinations, and surface-root candidates with point-subtree treatment origins.
Use discovered candidates and typed contracts for those cases. Preserve the
root, family, installed capabilities and review requirements. Ordinary authoring
uses mutually exclusive experiment layers.

TUI commands use the same CLI syntax through `/`, including the `restage` prefix.
Commands inherit the selected target. Use an external terminal when an operation
needs interactive confirmation.

MCP uses `restage_experiment_apply` with the exact target, operation and semantic
payload. `replaceDraft` accepts the whole accepted result with edited
`response.choices`. Writes require `idempotencyKey`; reads refuse it. Consult the
registered schema for each payload and use `confirmLive` for authorized live
changes. Result reads use `restage_read_experiments` and
`restage_read_experiment`.
