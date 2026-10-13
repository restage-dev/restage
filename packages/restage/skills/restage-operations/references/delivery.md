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
   surface family before changing serving.
3. Upload with `restage surface push welcome_flow`. A source path, such as
   `lib/onboarding/welcome_flow.dart`, is also accepted. Record the returned
   revision; the upload does not publish it.
4. Review measurement impact and publish the chosen revision within the user's
   authorization. Read status again to verify activation.

For example, after the upload returned revision 4:

```sh
restage surface publish welcome_flow --revision 4 \
  --reason "Clarify the introduction" --review-measurement
restage surface publish welcome_flow --revision 4 \
  --reason "Clarify the introduction"
restage surface status welcome_flow
```

If warnings require acknowledgement, inspect the complete review and pass its
`--reviewed-digest`. For a retry, retain the same `--operation-id` UUID and
operation content. General `--yes` consent does not acknowledge warnings.
Live confirmation controls also apply to the review invocation.

Omitting `--revision` activates the latest pushed revision, which may have
changed since inspection. Prefer an explicit revision for a reviewed release.
Generated manifests identify source kind and standalone-screen contract version;
outside the project, use the explicit family selectors required by command help.
Do not guess a family from the surface category alone.

MCP equivalents are `restage_surface_status`, `restage_surface_history`,
`restage_push_surface` and `restage_publish_surface`. Publication accepts
`reviewOnly`, `reviewedDigest` and `operationId` for the same review workflow.

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
environments. Inspect findings before releasing the new app build. A project
with no snapshots has no library contracts to check; that is not proof of
general compatibility. MCP: `restage_check_libraries`.

A personal preview build serves your dashboard preview. `restage build push
--env staging` moves the shared environment preview head and requires an admin
or an API key. `restage surface push welcome_flow --build` pushes that
environment build before the surface. MCP: `restage_push_build` and
`restage_list_builds`. These preview builds are separate from runtime surface
bundles and Flutter asset registration.

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

The preview does not change state. Compatibility advice describes expected
impact; it does not guarantee every installed build can render the revision.
Within the user's authorization, repeat without `--preview` and include an
audit `--reason`. Add `--freeze` only if future publishes should be blocked.
MCP: `restage_rollback_preflight`, then `restage_rollback_surface`.

`surface freeze` prevents future publishing; it does not deactivate the current
revision. `surface kill` deactivates the surface at the selected target, leaving
the app's configured fallback behavior. `surface unfreeze` permits publishing
again. Inspect measurement impact and verify status after each change.
