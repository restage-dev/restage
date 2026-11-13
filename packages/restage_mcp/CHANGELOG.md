# Changelog

## 0.1.0 — unreleased

`restage_upsert_product_slot` maps products with `add`, `remove` and `move` at a
`catalogRevision`; `restage_set_product_slot` is removed.

Initial release: an MCP server over stdio that wraps the Restage backend,
reusing the CLI's authenticated session.

Install it from the repository with `dart pub global activate --source git
https://github.com/restage-dev/restage.git --git-path packages/restage_mcp`.
Its Restage dependencies come from the same commit.

**Breaking:** `restage_init` no longer takes `earlyRequest`. Without `sdkKey`
it keeps the publishable key `build.yaml` has, or mints a public key for the
environment when it has none.

`restage_read_surface_funnel` takes optional `revisionOrdinals`, version numbers
matched in the reading. It takes an optional `surfaceType` and refuses a
surface of another type.

`restage_login` signs in to the backend `RESTAGE_BACKEND_URL` names, else the
one the project's `restage_config.yaml` or `build.yaml` names (from
`projectDirectory`, or the server's working directory), else Restage Cloud
(`https://api.restage.dev/`). Its result names the backend. A project file can
send sign-in only to Restage's own servers or this machine; any other server it
names is refused, with the refused origin in the result.

`restage_push_surface_draft` accepts `acceptUnhandledEvents: true` to push a
flow draft whose screens emit events the flow does not handle; without it the
push is refused with each unhandled event listed. `restage_surface_status`
returns the draft origin (`code` or `editor`) and `editedAfterCode`.

`restage_docs_search` and `restage_docs_read` search and read the Restage
documentation; they need no sign-in.

`restage_apply_canonical_mutation` and `restage_activate_experiment` are
**experimental** and aren't listed by default. Set `RESTAGE_EXPERIMENTAL=1` on
the server process to register them. `restage_activate_experiment` also needs
an activation API that a host embedding the server supplies, and the
`restage_mcp` executable never registers it. Their interfaces may change
without deprecation.
`restage_experiment_apply` is registered by default.

`restage_experiment_apply` accepts one of nineteen experiment operations with
its typed document. `replaceDraft` takes an accepted draft result with edited
`response.choices`. The tool rejects base64 payloads and unknown properties
before sending a request. Service refusals return their refusal codes.

Every tool matches a `restage` CLI command, and a census test keeps the two
in step. A target-scoped call names the runtime plane when its environment
exists on both planes; it is refused rather than sent to either.

The [README](README.md#tools) lists every tool. They cover:

- **Auth:** `restage_login` (in-server device-code sign-in: it opens the
  browser, shows a code, and completes on a second call), `restage_whoami`,
  `restage_logout`. Reuses any existing `restage login` session.
- **Project setup:** `restage_status`, `restage_init`, `restage_doctor`.
- **Surfaces:** `restage_list_surfaces`, `restage_list_paywalls`,
  `restage_surface_status`, `restage_surface_history`, `restage_surface_audit`,
  `restage_read_surface_funnel`, `restage_push_surface`,
  `restage_publish_surface`, `restage_push_surface_draft`,
  `restage_pull_surface_draft`, `restage_rollback_preflight`,
  `restage_rollback_surface`, `restage_kill_surface`,
  `restage_freeze_surface`, `restage_unfreeze_surface`,
  `restage_rename_surface_version`, `restage_archive_surface`,
  `restage_restore_surface`, `restage_delete_surface`,
  `restage_check_libraries`, `restage_record_libraries`.
- **Delivery:** the routing tools, `restage_read_delivery_diagnostics`,
  `restage_read_delivery_flow`, and the `restage_placement_*` and
  `restage_delivery_policy_*` tools.
- **Builds:** `restage_list_builds`, `restage_push_build`,
  `restage_push_catalog`, `restage_build_report`, `restage_widget_promote`.
- **Audit:** `restage_audit_log`, `restage_audit_export`,
  `restage_audit_verdict`.
- **Discovery:** `restage_list_organizations`, `restage_list_projects`,
  `restage_list_apps`, `restage_list_environments`,
  `restage_list_environment_targets`, `restage_list_components`,
  `restage_get_component`, `restage_rename_organization`,
  `restage_rename_app`, `restage_delete_app`.
- **Products & store:** `restage_list_products`, `restage_import_products`,
  `restage_list_product_slots`, `restage_upsert_product_slot` (a patch of keys
  and product mappings), `restage_list_store_connections`
  (summaries only), `restage_read_commerce_catalog`,
  `restage_save_commerce_offering`, `restage_set_current_commerce_offering`,
  `restage_retire_commerce_offering`, `restage_save_entitlement_definition`,
  `restage_configure_product_fulfillment`.
- **App configuration:** `restage_get_app_config`, `restage_update_app_config`
  (omit a field to leave it; empty string to clear it), `restage_read_platforms`.
- **API keys:** `restage_list_api_keys` (redacted: no key hash or plaintext),
  `restage_mint_api_key` (public keys only, returned in full),
  `restage_revoke_api_key`, `restage_resolve_api_key`, `restage_delivery_keys`.
- **Experiments:** `restage_experiment_apply`, one semantic operation at one
  exact target, and the analytics and experiment reads.
- **Docs:** `restage_docs_search`, `restage_docs_read`.

No secret material (the session token, a key plaintext, a store credential)
is ever returned on any tool output, progress, or error path.
