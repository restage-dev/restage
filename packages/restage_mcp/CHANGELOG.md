# Changelog

## 0.1.0 — unreleased

Initial release: an MCP server over stdio that wraps the Restage backend,
reusing the CLI's authenticated session.

`restage_login` signs in to Restage Cloud (`https://api.restage.dev/`) unless
`RESTAGE_BACKEND_URL` names another backend.

`restage_push_surface_draft` accepts `acceptUnhandledEvents: true` to push a
flow draft whose screens emit events the flow does not handle; without it the
push is refused with each unhandled event listed. `restage_surface_status`
returns the draft origin (`code` or `editor`) and `editedAfterCode`.

`restage_docs_search` and `restage_docs_read` search and read the Restage
documentation; they need no sign-in.

`restage_experiment_apply`, `restage_apply_canonical_mutation` and
`restage_activate_experiment` are **experimental** and are not listed by
default because their hosted endpoints are not yet available. Set
`RESTAGE_EXPERIMENTAL=1` on the server process to register them. Their interfaces
may change without deprecation.

`restage_experiment_apply` accepts one of fifteen experiment operations with
its typed document. `replaceDraft` takes an accepted draft result with edited
`response.choices`. The tool rejects base64 payloads and unknown properties
before sending a request. Service refusals return their refusal codes.

Every tool matches a `restage` CLI command, and a census test keeps the two
in step. A target-scoped call names the runtime plane when its environment
exists on both planes; it is refused rather than sent to either.

- **Auth:** `restage_login` (in-server device-code sign-in — opens the
  browser, shows a code, completes on a second call), `restage_whoami`,
  `restage_logout`. Reuses any existing `restage login` session.
- **Project setup:** `restage_status`, `restage_init`, `restage_doctor`.
- **Surfaces:** `restage_list_surfaces`, `restage_list_paywalls`,
  `restage_surface_status`, `restage_surface_history`, `restage_surface_audit`,
  `restage_read_surface_funnel`, `restage_push_surface`,
  `restage_publish_surface`, `restage_push_surface_draft`,
  `restage_pull_surface_draft`, `restage_rollback_preflight`,
  `restage_rollback_surface`, `restage_kill_surface`,
  `restage_freeze_surface`, `restage_unfreeze_surface`.
- **Builds:** `restage_list_builds`, `restage_push_build`,
  `restage_push_catalog`.
- **Audit:** `restage_audit_log`, `restage_audit_export`,
  `restage_audit_verdict`.
- **Discovery:** `restage_list_organizations`, `restage_list_projects`,
  `restage_list_apps`, `restage_list_environments`,
  `restage_list_environment_targets`.
- **Products & store:** `restage_list_products`, `restage_import_products`,
  `restage_list_product_slots`, `restage_upsert_product_slot` (full replace —
  both store ids required, pass null to unmap), `restage_list_store_connections`
  (summaries only).
- **App configuration:** `restage_get_app_config`, `restage_update_app_config`
  (omit a field to leave it; empty string to clear it).
- **API keys:** `restage_list_api_keys`, `restage_revoke_api_key` (redacted
  views only — no key hash or plaintext; minting is intentionally not exposed).
- **Experiments:** `restage_experiment_apply` — one semantic operation at one
  exact target (experimental).

No secret material (the session token, a key plaintext, a store credential)
is ever returned on any tool output, progress, or error path.
