# restage_mcp

[![pub package](https://img.shields.io/pub/v/restage_mcp.svg)](https://pub.dev/packages/restage_mcp) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

A [Model Context Protocol](https://modelcontextprotocol.io) server for Restage.
It lets an MCP-capable agent or IDE (such as Claude Code, Claude Desktop, or
Cursor) manage your Restage surfaces, products, and app configuration
programmatically, over the same backend the `restage` CLI uses.

The server speaks MCP over **stdio**: your MCP host launches `restage_mcp` as a
subprocess and talks to it over standard input/output.

## Install

```sh
dart pub global activate restage_mcp
```

> **Note:** `restage_mcp` isn't on pub.dev yet; until it's published, activate
> it from a source checkout with
> `dart pub global activate --source path <checkout>/packages/restage_mcp`.

This puts the `restage_mcp` executable on your `PATH` (via `~/.pub-cache/bin`;
make sure that directory is on your `PATH`).

## Configure your MCP host

Each host launches the same `restage_mcp` command over stdio. Pick yours:

### Claude Code

```sh
claude mcp add restage -- restage_mcp
```

### Claude Desktop

Add to `claude_desktop_config.json` (Settings → Developer → Edit Config):

```json
{
  "mcpServers": {
    "restage": {
      "command": "restage_mcp"
    }
  }
}
```

### Cursor

Add to `.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (global):

```json
{
  "mcpServers": {
    "restage": {
      "command": "restage_mcp"
    }
  }
}
```

## Authentication

You can sign in two ways; both write the same cached session, so you only sign
in once:

- **In your agent:** call the `restage_login` tool. It opens your browser and
  shows a short code; approve there, then call `restage_login` once more to
  finish. No CLI needed.
- **With the CLI:** run `restage login` once; the MCP server reuses that session.

If you're not signed in, tools return a clear message telling you to sign in.
Your session token is never returned by any tool. Use `restage_whoami` to check
who you're signed in as, and `restage_logout` to sign out.

> **Don't pass secrets as tool argument values.** If an argument fails schema
> validation (e.g. a key string where a numeric id is expected), the MCP host's
> validation error may echo the value you supplied back to you. Pass ids and
> slugs as arguments, not API keys or tokens.

### Choosing the backend to sign in against

The in-MCP login needs to know which backend to authenticate against when
there's no session yet. Out of the box the executable falls back to a local
backend at `http://localhost:8080/` (useful for development), so to sign in
against the hosted Restage backend (hosted access is in private beta) set
`RESTAGE_BACKEND_URL` in the host config:

```json
{
  "mcpServers": {
    "restage": {
      "command": "restage_mcp",
      "env": { "RESTAGE_BACKEND_URL": "https://api.restage.dev/" }
    }
  }
}
```

`RESTAGE_BACKEND_URL` is a **login-time** setting (where to authenticate when
there's no session yet). Once signed in, each tool uses the backend your
session was minted against, regardless of this value. Point it at your own URL
to sign in against a self-hosted or staging backend instead.

> If you signed in with the `restage` CLI first, the MCP server reuses that
> session and this setting is not consulted.

## Tools

**Identity**

| Tool | What it does |
| --- | --- |
| `restage_login` | Sign in with the device-code flow (call once to start, again to finish). |
| `restage_whoami` | Report the signed-in account. |
| `restage_logout` | Sign out and remove the local session. |

**Surface-family lifecycle (normal path)**

| Tool | What it does |
| --- | --- |
| `restage_list_surfaces` | List surfaces for a `surfaceType` under a project + app. Use the closed values `onboarding`, `message`, `survey`, `paywall`, or `general`. |
| `restage_surface_status` | Show the live version, lock state, delivery shape, and lifecycle state for one surface. |
| `restage_surface_history` | Show the audit timeline for one surface. |
| `restage_publish_surface` | Publish one surface's current draft to an environment (admin). |
| `restage_rollback_preflight` | Preview the expected client-impact classification for a rollback without changing state. |
| `restage_rollback_surface` | Roll a surface back to a published version, with an audit reason (admin). |

Use these surface-family tools for normal discovery, publication, status, and
lifecycle operations. Pass `surfaceType` and `surfaceSlug` explicitly; the
surface family is part of the identity, so paywalls and non-paywall surfaces use
the same lifecycle path.

**Paywall-specific compatibility tools**

These tools remain for specialized paywall draft and blob workflows. For normal
publication, use the surface-family tools above:

| Tool | What it does |
| --- | --- |
| `restage_list_paywalls` | List specialized paywalls under a project + app. |
| `restage_get_paywall` | Download a specialized paywall's compiled draft blob as base64 for backup or inspection. |
| `restage_publish_paywall` | Publish a specialized paywall draft to an environment (admin). Prefer `restage_publish_surface` for normal lifecycle publication. |
| `restage_get_published_version` | Read the latest published version of a specialized paywall in an environment. |

**Discovery**

| Tool | What it does |
| --- | --- |
| `restage_list_organizations` | The organizations you belong to. |
| `restage_list_projects` | Projects under an organization. |
| `restage_list_apps` | Apps under a project. |
| `restage_list_environments` | Environments under a project. |

**Products & store**

| Tool | What it does |
| --- | --- |
| `restage_list_products` | Store products (SKUs) for an app, optionally filtered by store. |
| `restage_import_products` | Re-fetch a store's catalog and upsert products (admin). |
| `restage_list_product_slots` | Product slots (the surface-facing entitlement handles). |
| `restage_upsert_product_slot` | Create/update a slot **and its complete product mapping** (admin). Full replace. See the note below. |
| `restage_list_store_connections` | Store connections (non-secret metadata only). |

**App configuration**

| Tool | What it does |
| --- | --- |
| `restage_get_app_config` | An app's iOS bundle id / Android package / web domain. |
| `restage_update_app_config` | Update them (admin). Omit a field to leave it; pass an empty string to clear it. |

**API keys**

| Tool | What it does |
| --- | --- |
| `restage_list_api_keys` | List an environment's API keys (redacted: no hash or plaintext). |
| `restage_revoke_api_key` | Revoke a key by id (admin). |

> Minting API keys is intentionally not exposed here: it returns a one-time
> plaintext secret. Mint keys from the dashboard or the `restage` CLI.

> **`restage_upsert_product_slot` is a full replace.** It sets the slot's
> complete product mapping every call: a store id you pass as `null` is
> *unmapped*. To keep an existing mapping, pass its current product id; list
> the slots and products first to read the current mapping.

## Security posture

`restage_mcp` handles your Restage session, so it's built to keep secrets off
the channel it speaks to your agent. Concretely, it defends against:

- **Corrupt or crafted local data.** A malformed or hand-edited credentials
  file never leaks its bytes (e.g. a token embedded in the stored endpoint) into
  a tool result or error.
- **Its own bugs.** No exception, stack trace, or secret is ever forwarded to
  the client; an internal error returns a fixed, generic message (a one-line
  type breadcrumb goes to stderr only).
- **Untrusted agent input.** Tool arguments are schema-validated; one caveat is
  documented above (don't pass secrets as argument values).

As defense-in-depth it also scrubs your session token and the device-login grant
from every tool result, so even a *buggy* backend response cannot put them into
your agent's chat history. It does **not**, however, claim to defend against a
**maliciously compromised first-party Restage backend** actively trying to
exfiltrate a secret it already holds: such a backend already has your session,
your data, and everything the API can reach, independent of this server. That
threat is out of scope by design.

## License

BSD-3-Clause. See [LICENSE](./LICENSE).
