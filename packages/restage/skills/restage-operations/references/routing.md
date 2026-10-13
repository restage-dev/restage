# Placement plans and audience routing

Resolve the [target](targets-and-tools.md), then decide whether the requested
change belongs to a placement plan, surface routing policy or
[experiment](experiments.md).
Generated `*Surface(...)` mounts declare implicit placements. Routing does not
require changing them to `.atPlacement()`.

## Choose the change

| Need | Use |
| --- | --- |
| Choose which surface appears at a placement | A placement rule targeting a live surface family |
| Choose a particular version of a surface | A surface rule targeting an exact published version |
| Gradually deliver a change | A percentage rollout with an explicit remainder or default |
| Compare outcomes under a statistical design | An [experiment](experiments.md) |
| Apply one rule during a period | A rule's start/end window |
| Replace the policy at a future time | A scheduled snapshot of the complete plan |

Placement selection happens before surface-version selection. An admitted
placement experiment takes precedence over placement rules; a surface experiment
takes precedence over that surface's rules. Required enrollment that remains
unresolved does not silently become an ordinary routing decision.

## Understand rule evaluation

Rules run in order. Disabled rules, closed windows and nonmatching audiences
are skipped. The first matching rule whose selected destination fits the app
wins. Ordinary compatibility failure continues to the next rule. Missing
required policy or audience authority refuses selection.

If no rule selects a destination, the declared default or owner's default is
checked. An incompatible default leaves no resolved path, so the placement uses
its fallback. Preserve a usable default when changing a targeted rule.

The dashboard can add, enable, reorder, remove and retarget rules. New rules
start at the lowest priority. Inspect overlap and shadowing before reordering:
a possible overlap needs inspection, while a shadowed rule may never receive
matching traffic.

Choose a saved audience revision or define conditions over available platform,
OS, app-build, country, language, device and custom attributes. The inline rule
editor combines conditions with AND; a membership condition can contain several
values. An absent observed attribute normally does not match. A missing audience
definition is an authority error. Check attribute and build readiness separately.

## Roll out a version

Surface rules support a single destination or a primary percentage with the
remainder sent to another destination or the default. Allocation is stable for
an installation within its scope. Keep the rule and allocation identities when
increasing a share: changing only the threshold preserves the existing buckets.

For an intermediate share, missing installation identity selects the remainder.
Shares of 0% and 100% are deterministic. If the selected branch is incompatible,
evaluation continues to the next rule; it does not try the other branch.
The placement editor currently creates single-surface rules and preserves
existing percentage rules.

For a gradual onboarding update:

1. Build and upload the candidate with `restage surface push`; keep the current
   default serving.
2. In the dashboard, select the audience revision and compatible candidate
   version. Start with a 10% share and the current default as the remainder.
3. Check fit, ordering and overlap, then review and publish the complete plan.
4. Inspect observed paints, delivery refusals and data coverage. Increase the
   same allocation's share when the evidence and user's authorization allow it.
5. Deliberately update the default when ready, or review restoration of the
   previous plan. A rollout's traffic split alone provides no statistical winner.

## Schedule a change

Rule windows include the start and exclude the end. Scheduled plan snapshots
replace the preceding complete policy. Times use each device's local civil
time, derived from server time and its reported offset. Do not reinterpret them
as the operator's timezone or UTC. Missing required clock evidence produces
`localClockUnavailable` fallback.

Inspect the whole timeline before editing. Keep the baseline start null and
future snapshot starts strictly increasing. The dashboard protects existing
future snapshots from ordinary edits; inspect or cancel scheduled work before
replacing it. Cancel and undo produce changes that still need publication.

## Check selection before publishing

Exercise matching and nonmatching audiences, missing attributes, each rollout
branch, an older incompatible build, and the times before/start/end of a window.
Include experiment assignment when it applies. Check offline behavior and the
generated mount's compiled fallback separately.

Fit checks use observed build requirements; missing observations leave a gap.
Simulation checks selection without enrolling users. Verify actual device
rendering through [delivery observations](delivery.md) after publication.

The dashboard authors new rule bodies. CLI and MCP inspect, simulate, review,
publish and restore complete plans using public envelopes. The TUI's `/` prompt
runs those same CLI commands, including the `restage` prefix. Use the following
recipe to preserve rule bytes while changing an existing schedule.

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

<!-- skill-check: file tool/prepare_delivery_plan.dart -->
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

If warnings exist, follow
[Protect running experiments](experiments.md#protect-running-experiments) before
applying. Once the impact is authorized, add `--acknowledgement` with the canonical
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

Inspect every returned warning and stop if its impact is outside the user's
authorization. Acknowledge authorized impact before publication. The routing
publish interface accepts `--reviewed-digest` when acknowledgement is needed.
For a single-route restoration, `review-rollback` takes `--route-id`,
`--prior-revision-ordinal`, `--expected-revision-ordinal` and `--out`. Publish
that review separately. Structured schedules require a whole-policy review.
