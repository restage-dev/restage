# Publication and delivery diagnosis

Use the selected target from [Targets and tools](targets-and-tools.md). In the
examples, `welcome_flow` is an authored surface slug. Analytics commands may
instead require its discovered surface identity.

## Publish a source change

1. Build with `dart run build_runner build`. Run the app's relevant checks and
   exercise the generated mount with its compiled fallback. Runtime bundling
   is optional; publication uses the generated build manifest.
2. Inspect `restage surface status welcome_flow` and
   `restage surface history welcome_flow`. Confirm the intended target and
   surface family before changing what is served. The family is the source
   kind (screen, flow or paywall) and, for a screen, its contract version.
3. Upload with `restage surface push welcome_flow`. A source path, such as
   `lib/onboarding/welcome_flow.dart`, is also accepted. Record the returned
   revision; the upload does not publish it.
4. Review the revision, then publish it only as the review requirements below
   allow. Read status again to confirm the new revision is active.

For example, after the upload returned revision 4:

```sh
restage surface publish welcome_flow --revision 4 \
  --reason "Clarify the introduction" --review-measurement
restage surface publish welcome_flow --revision 4 \
  --reason "Clarify the introduction"
restage surface status welcome_flow
```

### Review requirements

- Publish only with explicit user authorization for the target and action.
  Preparing or uploading a change does not authorize publication. Ask again
  when the proposed action or newly discovered impact falls outside that
  authorization.
- Publishing changes what apps receive at that target, subject to targeting,
  compatibility and experiment assignment.
- Run the `--review-measurement` invocation first and read the complete review.
  Live confirmation controls also apply to it.
- If warnings require acknowledgement, follow
  [Protect running experiments](experiments.md#protect-running-experiments).
  Pass `--reviewed-digest` only when the user has authorized that impact.
  General `--yes` consent does not acknowledge warnings.
- Choose a lowercase UUIDv4 for `--operation-id` before applying. Keep it with
  the exact operation and review digest. After an uncertain response, inspect
  status and history, then retry with the same operation ID. A new review can
  have a different digest; never change the operation ID to get past a retry
  refusal.
- Pass `--revision` explicitly. Without it, the command publishes the latest
  pushed revision, which may have changed since you inspected it.
- Inside the project, the generated build manifest supplies the family. Outside
  it, pass the family selectors that command help lists, such as
  `--source-kind` and `--contract-version`. Do not guess a family from the
  surface category alone.

MCP equivalents are `restage_surface_status`, `restage_surface_history`,
`restage_push_surface` and `restage_publish_surface`. Publication accepts
`reviewOnly`, `reviewedDigest` and `operationId` for the same review workflow.

For Git provenance, `--record-git` on surface push or publish writes and commits
local records under `.restage/receipts/`; it does not push Git. A recorded surface
upload requires committed app source and local dependencies in the repository,
regenerates, then checks that tracked output still matches. Publication uses the
revision's push receipt to identify its source; without it, the source is unknown.
Receipt recording can fail after the remote operation succeeds. Follow the
reported repair instructions and check status instead of repeating the upload
or publication solely because the command returned a nonzero exit code.

## Custom widgets and preview builds

An OTA version can use only the widget libraries and host contracts supported
by installed apps. Shipping a new native widget requires an app release;
uploading a dashboard preview build does not install it on devices.

After a custom-widget change, regenerate and run:

```sh
restage surface check-libraries --json
restage build push --personal
restage build list
```

The library check compares local `.restage/library-contracts` snapshots with
versions, routing destinations and experiment arms in use across the app's
environments. It detects older requirements the newest local library no longer
supports. It does not detect missing local libraries or requirements newer than
the local library. Inspect findings before releasing the app; a successful check,
including one with no snapshots, is not complete compatibility proof.
MCP: `restage_check_libraries`.

A personal preview build serves your dashboard preview. `restage build push
--env staging` moves the shared environment preview head and requires an admin
or a secret key with `renderBundlesPush` scope. `restage surface push welcome_flow
--build` attempts that build first, then uploads the surface even if the build
failed. Check the returned revision and history before retrying; a failed preview
build can be retried separately. MCP: `restage_push_build` and
`restage_list_builds`. Preview builds are separate from runtime surface bundles
and Flutter asset registration.

## Diagnose an unexpected version or fallback

Start with reads. Keep the app, environment, plane, surface family and app build
consistent while following this sequence:

```sh
restage surface status welcome_flow
restage surface history welcome_flow
restage where welcome_flow --json
restage delivery map --surface welcome_flow --json
restage delivery placements list --json
```

The map distinguishes routed resolutions from observed paints. A route reaching
a version does not prove it rendered. Inspect incompatibility flags, old paints,
missing observations and their coverage before changing the policy.

For a device-side discrepancy, pass `onSurfaceResolution` to `Restage.configure`
and inspect the reported source and route context. At the render deadline, the
mount uses eligible local content ready then, or its authored fallback. A direct
mount with neither can keep waiting for fresh content. Cached decisions must
still match the target, app build, identity and validity checks. Once a fallback
is shown, late content may become usable on a later mount or a safe live refresh.
Neither a successful fetch nor a resolution callback proves that it painted.

Delivery receipts record observed paint outcomes independently of Measurement.
They are batched, bounded and best-effort; observations may be incomplete or
duplicated, and do not cover every authored fallback. Check `deliveryReceiptsEnabled`
separately from `analyticsEnabled` and `measurementEnabled` when observations
are missing. Disabling receipts also disables placement reporting.

Take the exact placement key from the directory. Ordinary generated mounts
already declare default placements; do not add `.atPlacement()` to repair an
unrelated delivery failure.

```sh
restage delivery placements show --key default:onboarding:welcome_flow --json
restage delivery plan read --placement default:onboarding:welcome_flow --json
restage delivery plan fit --placement default:onboarding:welcome_flow --json
restage delivery plan timeline --placement default:onboarding:welcome_flow --json
```

Match publication compatibility to the actual installed build. Inspect audience,
schedule and experiment assignment when they govern the destination. Use
the [rule evaluation guide](routing.md) to distinguish placement selection,
surface-version selection, ordered rules and percentage rollouts. Use
`delivery simulate` or `delivery plan simulate` with explicit canonical public
inputs to test selection without enrollment. These are simulations, not proof
of a device render.

For observed served-default presentations and recorded server refusals:

```sh
restage surface routing delivery-diagnostics welcome_flow --type onboarding \
  --start-date 2026-10-01 --end-date-exclusive 2026-10-08 --json
```

Choose dates within the retained period. The two diagnostic sections have
separate coverage; neither is a census of people, devices or all requests.
Use [Analytics](analytics.md) to distinguish collection problems from delivery
problems. MCP counterparts include `restage_where`, `restage_read_delivery_map`,
`restage_placement_read`, `restage_delivery_policy_fit` and
`restage_read_delivery_diagnostics`.

## Roll back or stop delivery

First read history, identify the desired revision and preview its cohort impact:

```sh
restage surface rollback welcome_flow --to-version 2 --preview
```

The preview does not change state. It compares with the current active
publication; it is not a census of installed builds or a guarantee they can
render the revision. It is also not the experiment-impact review: use the
mutation's `--review-measurement` or MCP `reviewOnly` workflow separately.
Within the user's authorization, repeat without `--preview` and include an
audit `--reason`. Choose the resulting freeze state: `--freeze` blocks future
publishes; omitting it clears an existing freeze.
MCP: `restage_rollback_preflight`, then `restage_rollback_surface`.

Publish and rollback select one contract family. Freeze, kill and unfreeze apply
to the whole surface identity at the selected target:

- `surface freeze` blocks publishing without clearing active revisions or
  editing placement plans. Use a plan change to control a placement's routes.
- `surface kill` deactivates every contract family. A pinned version cannot
  bypass that surface's deactivation, but a placement may select another surface.
  Use `--frozen` to leave publishing blocked; omitting it clears an existing freeze.
- `surface unfreeze` permits publishing again; it does not reactivate revisions.

Kill does not immediately clear device caches or dismiss mounted content. Devices
follow their cache, fallback and refresh rules. Review the placement plan if the
intent is to stop that entire placement. Inspect measurement impact and verify
status after each change.
