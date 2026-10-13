# Routing and experiments

Resolve the [target](targets-and-tools.md), then decide whether the requested
change belongs to a placement plan, surface routing policy or experiment.
Generated `*Surface(...)` mounts declare implicit placements. Routing does not
require changing them to `.atPlacement()`.

## Review and publish a placement plan

Read the placement directory, current plan, fit and timeline before editing.
Use the exact namespace-qualified key returned by the directory:

```sh
restage delivery placements list --json
restage delivery plan read --placement default:onboarding:welcome_flow --json
restage delivery plan fit --placement default:onboarding:welcome_flow --json
restage delivery plan history --placement default:onboarding:welcome_flow --json
restage delivery plan timeline --placement default:onboarding:welcome_flow \
  --json > timeline.json
```

The timeline contains a complete `DeliveryPolicyPlanV1` in `plan`, when a
policy exists. Each snapshot retains its routing document as base64-encoded
canonical bytes. The public schema supports these envelopes and their schedules;
it does not expose builders for new routing-rule bodies. Use the dashboard for
new rules or destinations. Do not invent the embedded JSON or import an
unpublished schema package.

For an existing plan, this public-only helper exports it unchanged or reschedules
one future snapshot while preserving every routing document. Add
`restage_measurement_schema` as a development dependency and save this as
`tool/prepare_delivery_plan.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2 && args.length != 4) {
    throw ArgumentError('Expected: timeline.json plan.json [index localStart]');
  }
  final timeline = DeliveryPolicyTimelineV1.fromJson(
    jsonDecode(await File(args[0]).readAsString()) as Map<String, Object?>,
  );
  final original = timeline.plan;
  if (original == null) throw StateError('There is no published plan to reuse.');
  final snapshots = [...original.snapshots];
  if (args.length == 4) {
    final index = int.parse(args[2]);
    if (index < 1 || index >= snapshots.length) {
      throw ArgumentError('Select an existing future snapshot, starting at 1.');
    }
    snapshots[index] = DeliveryPolicySnapshotInputV1(
      effectiveFromLocal: LocalCivilDateTimeV1.parse(args[3]),
      documentCanonicalBytes: snapshots[index].documentCanonicalBytes,
    );
  }
  final candidate = DeliveryPolicyPlanV1(
    scope: original.scope,
    snapshots: snapshots,
  );
  await File(args[1]).writeAsBytes(candidate.canonicalBytes);
  stdout.writeln('Expected head: ${timeline.policy.revision!.ordinal}');
}
```

```sh
dart run tool/prepare_delivery_plan.dart timeline.json plan.json
```

With two arguments this only exports the original plan. To change a schedule,
add an existing future snapshot's index and its intended local start, for example
`1 2027-01-04T09:30:00`. Keep the baseline's start null and future starts strictly
increasing. The constructor checks this ordering; the service reviews the
complete candidate. Preserve the exact target, scope and embedded bytes.

Review a changed candidate against the head printed by the helper. In this
example it is 3:

```sh
restage delivery plan review --plan plan.json --expected-head-ordinal 3 \
  --reason "Reschedule the introduction" --out plan-review.json
```

For a complete plan supplied by a supported authoring tool with a genuinely
absent head, use `--expect-no-head` instead. Inspect refusals,
fit and every measurement warning. Preserve the exact review file. With an
authorized, warning-free review, publish using a new UUIDv4 for the attempt:

```sh
restage delivery plan publish --review plan-review.json \
  --operation-id YOUR_UUID_V4
```

If warnings exist, add `--acknowledgement` with the canonical
`DeliveryMeasurementImpactAcknowledgementV1` for the reviewed warning set.
Reuse the same operation id and content only when retrying that attempt. A
changed plan, stale head or changed impact requires another review. Verify the
new policy after publishing.

`delivery plan undo` creates a review restoring a complete immutable revision;
it does not publish by itself. Supply the exact placement or scope,
`--restore-ordinal`, current `--expected-head-ordinal`, `--reason` and `--out`,
then inspect and publish the returned review.

MCP equivalents are `restage_delivery_policy_read`,
`restage_delivery_policy_fit`, `restage_delivery_policy_review`,
`restage_delivery_policy_publish` and `restage_delivery_policy_undo_review`.
They take `requestJson` containing the canonical request for that operation.
Publishing takes a `DeliveryPolicyPublishRequestV1` with the server review
reference, operation id and required acknowledgement, not the candidate plan.

## Audience routing

```sh
restage surface routing list-audiences --json
restage surface routing audience-usage --audience-revision-id AUDIENCE_REVISION_ID --json
restage surface routing read welcome_flow --type onboarding --json
```

Audiences are referenced by sealed revision. Inspect usage before replacing a
reference and follow returned pagination cursors. These operations list
audiences and their usage; they do not create or edit audiences.

The surface-routing interface uses the same complete plans inside distinct
typed requests. Reuse a supplied or timeline-derived plan; a policy read's
opaque bytes are not themselves a plan or review request:

| Operation | CLI file | Public contract | MCP input |
| --- | --- | --- | --- |
| Preview | `--document simulation.json` | `DeliveryPolicySimulationRequestV1` | `restage_preview_routing.documentBase64` |
| Review | `--request review-request.json` | `DeliveryPolicyReviewRequestV1` | `restage_review_routing.requestBase64` |
| Publish | `--review routing-review.json` | Original `DeliveryPolicyReviewV1` | `restage_publish_routing.reviewBase64` |

MCP's base64 values encode the canonical bytes with standard padding. Output
from `routing read --out` is a policy document, not a simulation or review
request. Use the typed constructors and canonical serializers; do not invent
JSON envelopes or rewrite a returned review.

After preparing simulation and review requests for the same target:

```sh
restage surface routing preview welcome_flow --type onboarding \
  --document simulation.json --json
restage surface routing review welcome_flow --type onboarding \
  --request review-request.json --out routing-review.json
restage surface routing publish welcome_flow --type onboarding \
  --review routing-review.json
```

`preview` simulates the current retained policy for the requested scope and
inputs. It does not simulate pending edits in the separate review request;
`DeliveryPolicySimulationRequestV1` has no candidate-plan field. The review
evaluates the complete proposed plan before it can be published.

Inspect and acknowledge every returned warning before publication. The routing
publish interface accepts `--reviewed-digest` when acknowledgement is needed.
For a single-route restoration, `review-rollback` takes `--route-id`,
`--prior-revision-ordinal`, `--expected-revision-ordinal` and `--out`. Publish
that review separately. Structured schedules require a whole-policy review.

## Experiment reads and experimental authoring

Use `experiment list` and `experiment results` for ordinary supported reads;
see [Analytics](analytics.md) for windows and interpretation.

Draft and lifecycle authoring is experimental and is not served by production
yet. Use it only with a backend that supports those operations. Setting
`RESTAGE_EXPERIMENTAL=1` exposes commands or MCP tools; it does not provide the
backend implementation. Set it in the CLI/TUI process or MCP server process.

On a supporting target:

```sh
restage experiment discover --json
restage experiment create --json
restage experiment resolve-draft --draft-id DRAFT_ID --json > draft.json
```

Use discovery to select available surfaces, metrics and audiences. Keep the
returned draft id, revision and compare-and-set token. Edit only
`response.choices` in the accepted draft result envelope, then save the entire
file:

```sh
restage experiment save --replacement draft.json --json > saved-draft.json
```

Use the newly returned revision and token for subsequent operations. A bare
choices object is invalid; another target's envelope is invalid. Resolve again
after a stale-edit refusal rather than overwriting a newer draft.

```sh
restage experiment validate --draft-id DRAFT_ID \
  --draft-revision-id REVISION_ID --expected-cas CAS_TOKEN
restage experiment review --draft-id DRAFT_ID \
  --draft-revision-id REVISION_ID --expected-cas CAS_TOKEN --json
restage experiment activate --draft-id DRAFT_ID \
  --draft-revision-id REVISION_ID --expected-cas CAS_TOKEN \
  --review-id REVIEW_ID --review-digest REVIEW_DIGEST
```

Fix validation issues and inspect audience conflicts and impact before
activation. The review must name the exact current draft. Read the active
experiment with `experiment read --experiment-id EXPERIMENT_ID`; use its
current `--expected-lifecycle-ordinal` for pause, resume or conclude. Preserve an
explicit `--idempotency-key` and unchanged payload when retrying a write after
a lost response.

MCP uses `restage_experiment_apply` with an exact target, operation and semantic
payload. `replaceDraft` accepts the whole accepted draft result with edited
`response.choices`. State-changing operations require `idempotencyKey`; reads
refuse it. Consult the registered schema for the operation's required payload.
Use the same authorization, review and live-confirmation rules as the CLI.
