# Changelog

## 0.1.0 — unreleased

Initial release: an MCP server over stdio that wraps the Restage backend,
reusing the CLI's authenticated session.

`restage_experiment_apply`, `restage_apply_canonical_mutation` and
`restage_activate_experiment` are **experimental** and are not listed by
default. They call endpoints the hosted service does not serve yet, and a tool
list is the only inventory a client consults before calling, so advertising them
would offer an operation that cannot succeed. Set `RESTAGE_EXPERIMENTAL=1` on
the server process to register them; expect their interfaces to change without
a deprecation.

`restage_experiment_apply` asks what you mean, not how to spell it: the
operation is a closed choice of the fifteen experiment operations and the
payload is that operation's own document. It takes no base64 and rejects an
unknown property, so a malformed request is refused before it reaches the
network. A refusal from the service comes back as a refusal with its code, not
as a tool error — being told an operation is not permitted is an answer.

- **Auth:** `restage_login` (in-server device-code sign-in — opens the
  browser, shows a code, completes on a second call), `restage_whoami`,
  `restage_logout`. Reuses any existing `restage login` session.
- **Paywalls:** `restage_list_paywalls`, `restage_get_paywall` (compiled blob
  as base64), `restage_push_paywall`, `restage_get_published_version`.
- **Discovery:** `restage_list_organizations`, `restage_list_projects`,
  `restage_list_apps`, `restage_list_environments`.
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
