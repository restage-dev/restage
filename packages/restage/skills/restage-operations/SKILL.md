---
name: restage-operations
description: Use when inspecting, publishing, rolling back, routing or measuring Restage surfaces through the CLI, TUI or MCP server. Covers target selection, delivery diagnosis, analytics interpretation, reviewed policy changes and experiment authoring.
---

# Restage operations

Operate onboarding, messages, surveys, paywalls and other surfaces at an exact
app, environment and runtime plane. Use this skill independently of surface
authoring; it does not require another skill to be installed.

## Workflow

1. **Identify the target and question.** Read the local configuration and
   discover authorized targets. Distinguish `sandbox` from `live`, even when
   both use the same environment name. Record the surface identity, family
   and revision when relevant.
2. **Inspect before changing.** Read current status, delivery and data health.
   For a performance question, select an explicit period and keep it consistent
   across reads. Preserve the service's coverage and unavailable states.
3. **Choose the smallest supported operation.** An uploaded revision, a
   published revision, a placement policy and an experiment are different
   things. Change the one that owns the requested behavior.
4. **Prepare and review.** Build authored changes, check compatibility, inspect
   impact warnings and retain exact server review documents. Use current
   revision preconditions and stable retry identities.
5. **Apply within the user's authorization.** Existing authorization remains
   valid for its stated target and action. Ask only when the action or newly
   disclosed impact is outside it. Complete the reviewable preparation first.
6. **Verify the outcome.** Read the resulting status or policy and confirm the
   revision. Check delivery and measurement later using their reported windows;
   a successful publish alone does not prove that an app rendered it.

## Load the relevant reference

| Task | Reference |
| --- | --- |
| Sign in, select targets, use CLI/TUI/MCP | [Targets and tools](references/targets-and-tools.md) |
| Publish, check compatibility, diagnose delivery, roll back | [Delivery](references/delivery.md) |
| Investigate usage, funnels, taps or experiment results | [Analytics](references/analytics.md) |
| Change placement plans, audiences or experiments | [Routing and experiments](references/routing-and-experiments.md) |

## Operating rules

- Uploading a surface revision does not activate it. Publishing changes serving
  for the selected target and family; routing, compatibility and assignment
  still determine which apps receive it.
- Preserve canonical payloads, original reviews, expected revisions and warning
  acknowledgements. A general confirmation flag does not acknowledge measurement
  warnings. Read and review again after a stale-state refusal.
- Use the same logical operations through CLI, TUI and MCP. Match target,
  filters and time window before comparing their results. Inspect installed
  command help or tool schemas for version-specific availability.
- Experimental opt-in exposes tooling; it does not enable an unsupported backend.
- Never expose secret keys or access tokens in commands, payloads, logs or chat.
  Supply automation credentials through the environment.
