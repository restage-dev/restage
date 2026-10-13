# restage_mcp

[![pub package](https://img.shields.io/pub/v/restage_mcp.svg)](https://pub.dev/packages/restage_mcp) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

A [Model Context Protocol](https://modelcontextprotocol.io) server for Restage.
It lets an MCP-capable agent or IDE (such as Claude Code, Claude Desktop, or
Cursor) manage your Restage surfaces, products, and app configuration through
the same backend the `restage` CLI uses.

Part of [Restage](https://restage.dev), server-driven UI for Flutter.

The server speaks MCP over **stdio**: your MCP host launches `restage_mcp` as a
subprocess and talks to it over standard input and output.

## Install

The package is not on pub.dev yet. From a source checkout, resolve the
workspace and compile the executable:

```sh
flutter pub get
mkdir -p "$HOME/.pub-cache/bin"
dart compile exe packages/restage_mcp/bin/restage_mcp.dart -o "$HOME/.pub-cache/bin/restage_mcp"
```

This puts the `restage_mcp` executable in `~/.pub-cache/bin`. Make sure that
directory is on your `PATH`.

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

You can sign in two ways. Both write the same cached session, so you only sign
in once:

- **In your agent:** call the `restage_login` tool. It opens your browser and
  shows a short code. Approve there, then call `restage_login` again to
  finish. No CLI needed.
- **With the CLI:** run `restage login` once; the MCP server reuses that session.

If you're not signed in, tools tell you to sign in. No tool ever returns your
session token. Use `restage_whoami` to check who you're signed in as, and
`restage_logout` to sign out.

> **Don't pass secrets as tool arguments.** If an argument fails validation
> (for example a key string where a numeric id is expected), your MCP host's
> error message may repeat the value back. Pass ids and slugs, not API keys or
> tokens.

### Choosing the backend to sign in against

With no session yet, the in-agent login needs to know which backend to use.
By default the executable uses a local backend at `http://localhost:8080/`,
for development. To sign in to Restage Cloud, set `RESTAGE_BACKEND_URL` in the
host config:

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

`RESTAGE_BACKEND_URL` is only read at sign-in. After that, each tool uses the
backend your session was created against. Set it to another URL to sign in to
a different Restage backend.

> If you signed in with the `restage` CLI first, the MCP server reuses that
> session and ignores this setting.

## Tools

The tools do what the `restage` CLI does. Each description names the
command it matches.

**Identity and project setup**

| Tool | What it does |
| --- | --- |
| `restage_login` | Sign in with the device-code flow (call once to start, again to finish). |
| `restage_whoami` | Report the signed-in account. |
| `restage_logout` | Sign out and remove the local session. |
| `restage_status` | Report the account, endpoint, and the project a local `restage_config.yaml` points at, and name any organization, project, app, or environment in it that does not exist. |
| `restage_init` | Set up a Flutter project for Restage (`dryRun` shows the plan first). |
| `restage_doctor` | Check a Flutter project for common setup issues, including a `restage_config.yaml` that names things that do not exist. |

**Choosing a target**

Tools that act on an environment take `environmentSlug`, plus `runtimePlane`
(`sandbox` or `live`) when that environment exists on both planes. A call
that leaves the plane out for such an environment is refused, so it never
reaches the wrong plane. `environmentTargetId` names a target exactly. `organizationId` is
needed only when you belong to more than one organization.

The list tools read what you can access right now and filter it by project,
app, environment, target, and surface. A target ID is checked against what you
can access on each call.

Every tool that names a project also takes `projectDirectory`. The
`restage_config.yaml` there supplies the project, app, environment,
organization, and plane the call leaves out. An argument you pass wins over
the config.

**Changes to a live target**

A call that changes what a live target serves requires `confirmLive: true`.
An agent sets it only after the user approves that change. Where a tool records
a `reason`, a live change needs one. Surface changes still need it with
`reviewOnly: true`, even though that call only returns the impact review.
Ordinary reads and sandbox targets do not need `confirmLive`.

The tools that change what a target serves are `restage_publish_surface`,
`restage_rollback_surface`, `restage_kill_surface`,
`restage_freeze_surface`, `restage_unfreeze_surface`,
`restage_publish_routing`, `restage_rollback_route`,
`restage_apply_canonical_mutation`, and `restage_activate_experiment`. Two
more ask only for some calls: `restage_experiment_apply` for
`activateDraft`, `pauseExperiment`, `resumeExperiment`, and
`concludeExperiment`, and `restage_rebuild_serving_records` for a full
rebuild (not `readinessOnly`). The CLI asks for the same changes. Most accept
`--yes` after approval; live surface kill and rollback require an interactive
confirmation.

Measurement warnings need their own approval on either plane. Surface publish,
rollback, kill, freeze and unfreeze accept `reviewOnly` to inspect impact and
`reviewedDigest` to acknowledge the exact set of warnings. An agent must explain
new experiment impact and stop unless the user has already approved it.
`confirmLive` does not acknowledge warnings. Refusals block the change; an
out-of-date review must be redone. See the
[review workflow](https://docs.restage.dev/tools/mcp-server#review-experiment-impact)
for response fields and retry options.

**Surfaces**

| Tool | What it does |
| --- | --- |
| `restage_list_surfaces` | List surfaces under a project and app, of one `surfaceType` or of every type. |
| `restage_surface_status` | Show the live version, lock state, delivery shape, and lifecycle state for one surface. |
| `restage_surface_history` | List the revisions pushed to one surface, marking the active one. |
| `restage_surface_audit` | Show the audit timeline for one surface. |
| `restage_read_surface_funnel` | Read one surface's funnel over a time window: views, steps, drop-off, and completions per published version. |
| `restage_push_surface` | Push generated surfaces from a local Flutter project (by id or by `.dart` file). This does not make them live. |
| `restage_publish_surface` | Publish a pushed revision so it serves (admin). Without `revision`, publishes the latest one pushed. `showInApp` says how to mount it in an app. |
| `restage_push_surface_draft` | Push a surface's saved dashboard draft as a new revision (admin). This does not make it live. |
| `restage_pull_surface_draft` | Download a surface's saved dashboard draft as base64. |
| `restage_rollback_preflight` | Compare a rollback's compatibility with the current active version without changing anything. |
| `restage_rollback_surface` | Make an earlier published version live again, with an audit reason (admin). Can also freeze the surface against new publishes. |
| `restage_kill_surface` | Stop hosted delivery; devices use content they saved earlier or their fallback (admin, audit reason). |
| `restage_freeze_surface` / `restage_unfreeze_surface` | Stop or allow new publishes of a surface (admin, audit reason). |
| `restage_list_paywalls` | List paywalls under a project and app. |

**Pushing does not make a version live.** Push a revision with
`restage_push_surface` (or `restage_push_surface_draft`), then publish it with
`restage_publish_surface`. Routing, below, decides which published version
each audience receives.

After a kill, devices may use content they saved earlier that still qualifies,
or their configured fallback. Content already displayed is not necessarily removed immediately.
Generated mounts include the original Flutter widgets as fallback.

**Delivery routing (beta)**

Routing decides which published version each request receives.

| Tool | What it does |
| --- | --- |
| `restage_read_routing` | Read the routing rules stored for one surface in one environment, with the revision to pass back when you publish. |
| `restage_read_routing_revision` | Read an earlier revision of those rules, to review before restoring it. |
| `restage_preview_routing` | Evaluate routing rules against a sample request without publishing them. |
| `restage_review_routing` | Review a complete candidate policy and return its original impact review. |
| `restage_publish_routing` | Publish the exact policy from the original server review. |
| `restage_review_route_rollback` | Review restoring one route from an earlier policy revision. |
| `restage_rollback_route` | Restore one route to an earlier revision and leave the rest unchanged. |
| `restage_list_routing_audiences` | List the audiences a routing rule can name. |
| `restage_routing_audience_usage` | List the experiments and routing rules that use one audience. |
| `restage_read_delivery_diagnostics` | Read one surface's delivery diagnostics for a date range: default versions served and requests the server refused. |
| `restage_read_delivery_flow` | Who saw which version of a surface, by rule, experiment and everyone else. |

**Surface lifecycle and library compatibility**

| Tool | What it does |
| --- | --- |
| `restage_rename_surface_version` | Set or clear a version label. |
| `restage_archive_surface` / `restage_restore_surface` | Archive a surface across environments, or restore it to the list for publication. |
| `restage_check_libraries` | List live versions, delivery rules and experiment arms that the local build would stop rendering, based on its recorded library versions. |

**Documentation**

| Tool | What it does |
| --- | --- |
| `restage_docs_search` | Search the Restage docs. Returns ranked sections with their URLs and a snippet. |
| `restage_docs_read` | Read a docs page, or one section with `#anchor`, as Markdown. |

**Placements and delivery plans**

| Tool | What it does |
| --- | --- |
| `restage_read_delivery_map` / `restage_where` | Read routing and renders by app build, or find where a surface version is being served. |
| `restage_placement_list` / `restage_placement_read` | List app placements or read one. |
| `restage_placement_observed_history` | Read observed placement mounts. |
| `restage_placement_simulate` | Preview placement decisions for supplied inputs. |
| `restage_delivery_policy_read` / `restage_delivery_policy_timeline` / `restage_delivery_policy_history` | Inspect the current plan and its revisions. |
| `restage_delivery_policy_fit` / `restage_delivery_policy_simulate` | Check content compatibility and preview a plan's decisions. |
| `restage_delivery_policy_review` / `restage_delivery_policy_publish` | Review a complete plan and publish the exact reviewed change. |
| `restage_delivery_policy_undo_review` | Review a plan rollback before publishing it. |
| `restage_placement_sample_import` / `restage_placement_sample_prepare` / `restage_placement_sample_store` / `restage_placement_sample_bind` | Validate an explicitly supplied capture and PNG, review, upload and bind it. |
| `restage_placement_sample_read` / `restage_placement_sample_read_image` / `restage_placement_sample_delete` | Read or delete a stored sample. |

These tools need an exact target. Plan and sample changes need the same
live-target approval as other writes. Reading placements never captures
or uploads a screen.

**Builds and the widget catalog**

A surface that uses widgets from your app can only be displayed in the
dashboard with a build of that app. `restage_push_surface_draft` adds a
`buildNotice` when the environment's build can't draw the surface, with the
command that fixes it.

| Tool | What it does |
| --- | --- |
| `restage_list_builds` | List an app's builds (one per environment and one per user), with the version, the commit it was built from, and the widget libraries it includes. |
| `restage_push_build` | Build the app's widgets and push the build: to an environment with `environmentSlug`, or to your own build without it. Runs a Flutter web build, so it can take minutes. |
| `restage_push_catalog` | Upload the app's generated widget catalog, which lists your own widgets in the dashboard editor's palette. Devices and previews do not need it. |

**Discovery**

| Tool | What it does |
| --- | --- |
| `restage_list_organizations` | The organizations you belong to, with your role. |
| `restage_list_projects` | Projects under an organization. |
| `restage_list_apps` | Apps under a project. |
| `restage_list_environments` | Environments under a project. |
| `restage_list_environment_targets` | Environment targets under an app. |

**Products and stores**

| Tool | What it does |
| --- | --- |
| `restage_list_products` | Store products (SKUs) for an app, optionally filtered by store. |
| `restage_import_products` | Re-fetch a store's catalog and update products (admin). |
| `restage_list_product_slots` | Product slots: the handles surfaces use to refer to products. |
| `restage_upsert_product_slot` | Create or update a slot **and its complete product mapping** (admin). See the note below. |
| `restage_list_store_connections` | Store connections (non-secret details only). |

> **`restage_upsert_product_slot` replaces the whole mapping.** A store id you
> pass as `null` is unmapped. To keep an existing mapping, pass its current
> product id. List the slots and products first to read the current mapping.

**App configuration**

| Tool | What it does |
| --- | --- |
| `restage_get_app_config` | An app's iOS bundle id, Android package, and web domain. |
| `restage_update_app_config` | Update them (admin). Omit a field to leave it; pass an empty string to clear it. |

**API keys**

| Tool | What it does |
| --- | --- |
| `restage_list_api_keys` | List an environment's API keys (redacted: no hash or plaintext). |
| `restage_revoke_api_key` | Revoke a key by id (admin). |
| `restage_resolve_api_key` | Find the organization, project, app, environment, and plane a key belongs to. The key is matched locally against key prefixes and never sent. |

> Neither this server nor the CLI creates API keys, because a new key's secret
> is shown only once. Create keys in the dashboard.

**Audit**

| Tool | What it does |
| --- | --- |
| `restage_audit_log` | The organization's server audit log. Each row's `chain` is `pending`, `chained` (not yet reached by a verification run), or `verified`. |
| `restage_audit_export` | The organization's compliance audit rows. |
| `restage_audit_verdict` | Whether the organization's audit chain verifies. |

**Analytics and experiment reads**

These tools are always registered. Each reads one page for an exact target and
returns the service's reply unchanged. Most analytics default to the last 30 days;
experiment results default to the whole current run. A date window filters only
the traffic breakdowns; the statistical result always covers the whole run as
designed.

| Tool | What it does |
| --- | --- |
| `restage_read_analytics_overview` | Totals for one app and period. |
| `restage_read_explore` | Views and users by one dimension. |
| `restage_read_surface_analytics` | One surface's versions, steps and metrics. |
| `restage_read_surface_taps` | Taps per element on one published version. |
| `restage_read_data_health` | What the app is sending. |
| `restage_read_experiments` | Experiments with their status. |
| `restage_read_experiment` | One experiment's summary, variants and safety metrics. |

**Experiments**

These tools are registered by default. Create and edit a draft at the selected
target, validate it, review the current revision, then activate that reviewed
revision. Read results before deciding whether to pause, resume or conclude it.

| Tool | What it does |
| --- | --- |
| `restage_experiment_apply` | Apply one experiment operation at a target: drafting, validation, review, activation, pausing, concluding, archiving, and reads. |
| `restage_rebuild_serving_records` | Create any serving records an experiment target is missing, and report what is still missing. |

`restage_experiment_apply` takes an `operation` chosen from a fixed list and
a `payload`. For `replaceDraft`, pass the full response from any draft
operation as `payload`, after editing `response.choices`. Leave the returned
target, draft id, revision, and compare-and-set token as they are. The tool
uses them to save the draft at the selected target. For
other operations, `payload` is the operation's own document. Unknown
properties are rejected before a request is sent. Pass `idempotencyKey` for
an operation that changes state. A service refusal returns its code.

The `readExperimentResults` operation returns unrounded decimal results and their
supporting counts. It requires `experimentId`, `activationOrdinal` and
`resultDigest`; take the latter two from the `readExperiment` response's
`summary.activationOrdinal` and `inferenceReference.resultDigest`. This is separate
from the `restage_read_experiment` analytics page.

An agent can work in a loop: read results with
`restage_read_experiments` or `restage_read_experiment`, read a
surface's funnel with `restage_read_surface_funnel`, push the next onboarding
flow, survey, message, or paywall with `restage_push_surface`, publish it with
`restage_publish_surface`, and roll back with `restage_rollback_surface` if the numbers say so.

Activation, pause, resume and conclusion at a live target require
`confirmLive: true`. A full serving-record rebuild does too; a readiness-only
check does not.

The low-level `restage_apply_canonical_mutation` and `restage_activate_experiment`
tools still need `RESTAGE_EXPERIMENTAL=1`. The first accepts requests that are
already encoded; the second also needs an activation API supplied by the host.
Normal experiment work uses `restage_experiment_apply` instead.

## Security

`restage_mcp` handles your Restage session, so it keeps secrets out of what it
sends to your agent:

- **Damaged local data.** A malformed or hand-edited credentials file never
  leaks its contents (for example a token stored in the endpoint) into a tool
  result or error.
- **Internal errors.** No exception, stack trace, or secret is forwarded to
  the client. An internal error returns a fixed message; a one-line error type
  goes to stderr only.
- **Agent input.** Tool arguments are validated against a schema. See the note
  above about not passing secrets as arguments.

It also removes your session token and the device-login code from every tool
result, so even a faulty backend response can't put them into your agent's
chat history. It does not protect against a compromised Restage backend, which
already holds your session.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
