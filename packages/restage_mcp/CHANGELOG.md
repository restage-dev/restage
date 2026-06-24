# Changelog

## 0.1.0 — unreleased

Initial release: an MCP server over stdio that wraps the Restage backend,
reusing the CLI's authenticated session.

- **Auth:** `restage_login` (in-server device-code sign-in — opens the
  browser, shows a code, completes on a second call), `restage_whoami`,
  `restage_logout`. Reuses any existing `restage login` session.
- **Paywalls:** `restage_list_paywalls`, `restage_get_paywall` (compiled blob
  as base64), `restage_publish_paywall`, `restage_get_published_version`.
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

No secret material (the session token, a key plaintext, a store credential)
is ever returned on any tool output, progress, or error path.
