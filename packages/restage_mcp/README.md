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

You can sign in two ways — both write the same cached session, so you only sign
in once:

- **In your agent:** call the `restage_login` tool. It opens your browser and
  shows a short code; approve there, then call `restage_login` once more to
  finish. No CLI needed.
- **With the CLI:** run `restage login` once; the MCP server reuses that session.

If you are not signed in, tools return a clear message telling you to sign in.
Your session token is never returned by any tool. Use `restage_whoami` to check
who you are signed in as, and `restage_logout` to sign out.

> **Don't pass secrets as tool argument values.** If an argument fails schema
> validation (e.g. a key string where a numeric id is expected), the MCP host's
> validation error may echo the value you supplied back to you. Pass ids and
> slugs as arguments, not API keys or tokens.

### Choosing the backend to sign in against

The in-MCP login needs to know which backend to authenticate against when there
is no session yet. Out of the box the executable falls back to a local backend
at `http://localhost:8080/` (useful for development), so to sign in against the
hosted Restage backend set `RESTAGE_BACKEND_URL` in the host config:

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
there is no session yet). Once signed in, each tool uses the backend your
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

**Paywalls**

| Tool | What it does |
| --- | --- |
| `restage_list_paywalls` | List paywalls under a project + app. |
| `restage_get_paywall` | Download a paywall's compiled draft blob as base64 (backup / inspection). |
| `restage_publish_paywall` | Publish a paywall's draft to an environment (admin). |
| `restage_get_published_version` | The latest published version of a paywall in an environment. |

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
| `restage_upsert_product_slot` | Create/update a slot **and its complete product mapping** (admin). Full replace — see note below. |
| `restage_list_store_connections` | Store connections (non-secret metadata only). |

**App configuration**

| Tool | What it does |
| --- | --- |
| `restage_get_app_config` | An app's iOS bundle id / Android package / web domain. |
| `restage_update_app_config` | Update them (admin). Omit a field to leave it; pass an empty string to clear it. |

**API keys**

| Tool | What it does |
| --- | --- |
| `restage_list_api_keys` | List an environment's API keys (redacted — no hash or plaintext). |
| `restage_revoke_api_key` | Revoke a key by id (admin). |

> Minting API keys is intentionally not exposed here — it returns a one-time
> plaintext secret. Mint keys from the dashboard or the `restage` CLI.

> **`restage_upsert_product_slot` is a full replace.** It sets the slot's
> complete product mapping every call: a store id you pass as `null` is
> *unmapped*. To keep an existing mapping, pass its current product id — list
> the slots and products first to read the current mapping.

## Security posture

`restage_mcp` handles your Restage session, so it is built to keep secrets off
the channel it speaks to your agent. Concretely, it defends against:

- **Corrupt or crafted local data** — a malformed or hand-edited credentials
  file never leaks its bytes (e.g. a token embedded in the stored endpoint) into
  a tool result or error.
- **Its own bugs** — no exception, stack trace, or secret is ever forwarded to
  the client; an internal error returns a fixed, generic message (a one-line
  type breadcrumb goes to stderr only).
- **Untrusted agent input** — tool arguments are schema-validated; one caveat is
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
