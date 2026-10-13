---
name: restage-operations
description: Use when inspecting, publishing, rolling back, routing or measuring Restage surfaces through the CLI, TUI or MCP server. Covers target selection, delivery diagnosis, analytics interpretation, reviewed policy changes and experiment design, authoring and results.
---

# Restage operations

Operate onboarding, messages, surveys, paywalls and other surfaces for one app,
environment and runtime plane. The runtime plane is `sandbox` or `live`. Use
this skill on its own; it does not need another skill installed.

## Common tasks

`welcome_flow` is an example surface slug. Run CLI commands from the Flutter
project that holds `restage_config.yaml`. MCP tools take the same target.

| Task | CLI | MCP tool |
| --- | --- | --- |
| Inspect status | `restage surface status welcome_flow` | `restage_surface_status` |
| Upload a revision | `restage surface push welcome_flow` | `restage_push_surface` |
| Review its impact | `restage surface publish welcome_flow --revision 4 --reason "..." --review-measurement` | `restage_publish_surface` with `reviewOnly: true` |
| Publish it | `restage surface publish welcome_flow --revision 4 --reason "..."` | `restage_publish_surface` |

Before publishing, meet the [review requirements](references/delivery.md#review-requirements).
The references hold the full workflows.

## Workflow

1. **Identify the target and question.** Read the local configuration and list
   the targets the user can access. Check whether the target is `sandbox` or
   `live`; both can use the same environment name. Note the surface slug, its
   family and the revision when they matter. A family is the surface's source
   kind (screen, flow or paywall) and, for a screen, its contract version.
2. **Inspect before changing.** Read current status, delivery and data health.
   For a performance question, pick one explicit period and use it for every
   read. Report the coverage and unavailable states the service returns.
3. **Choose the smallest supported operation.** An uploaded revision, a
   published revision, a placement policy and an experiment are different
   things. Change the one that owns the requested behavior.
4. **Prepare and review.** Build authored changes, check compatibility, read
   impact warnings and keep the exact review documents the server returns.
   Pass the current revision the command expects. Reuse the same operation ID
   when retrying an operation.
5. **Publish only with authorization.** See the rule below. Finish the review
   first so the user can decide on the prepared change.
6. **Verify the outcome.** Read the resulting status or policy and confirm the
   revision. Check delivery and measurement later in their reported windows.
   A successful publish does not prove that an app rendered it.

## Load the relevant reference

| Task | Reference |
| --- | --- |
| Sign in, select targets, use CLI/TUI/MCP | [Targets and tools](references/targets-and-tools.md) |
| Publish, check compatibility, diagnose delivery, roll back | [Delivery](references/delivery.md) |
| Investigate usage, funnels, taps or experiment results | [Analytics](references/analytics.md) |
| Target audiences, roll out versions, schedule or restore delivery plans | [Routing](references/routing.md) |
| Design, run and interpret experiments | [Experiments](references/experiments.md) |

## Operating rules

- Publish only with explicit user authorization for the target and action.
  Preparing or uploading a change does not authorize publication. Ask again
  when the proposed action or newly discovered impact falls outside that
  authorization.
- Uploading a revision does not serve it. Publishing changes what apps receive
  at the selected target, subject to targeting, compatibility and experiment
  assignment.
- Keep the server's documents exactly as returned. Send review files, canonical
  payloads, expected revisions and warning acknowledgements back unchanged. A
  general confirmation flag does not acknowledge measurement warnings. After a
  refusal for stale state, read and review again.
- Before applying a change with newly disclosed experiment impact, explain the
  affected experiments, metrics and consequences. Do not copy a review digest
  only to clear a warning. Follow
  [Protect running experiments](references/experiments.md#protect-running-experiments)
  for publication, recovery, routing and changes outside the review mechanism.
- CLI, TUI and MCP run the same operations. Match target, filters and time
  window before comparing their results. Check installed command help or tool
  schemas for what a version supports.
- Never expose secret keys or access tokens in commands, payloads, logs or chat.
  Supply automation credentials through the environment.
