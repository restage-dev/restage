# Targets and tools

## Resolve the context

Run commands from the Flutter project directory containing
`restage_config.yaml`, or pass `--directory`. Inspect configuration before
changing it. CLI and MCP share saved credentials.

```sh
restage doctor
restage status
restage whoami
restage targets --json
```

If sign-in is needed, `restage login` opens a browser approval flow. Let the
user complete it; do not request their credentials. For automation, supply a
secret key through `RESTAGE_API_KEY`.

The config selects organization, project, app, default environment and plane.
CLI flags override it. A reproducible read can state each selector:

```sh
restage analytics overview --organization YOUR_ORG --project YOUR_PROJECT \
  --app YOUR_APP --env staging --plane sandbox --json
```

Replace example names and ids with discovery results. An environment name is
not a plane: `production` can exist on `sandbox` as well as `live`. An ambiguous
target must be resolved explicitly, never guessed from its name.

## MCP

Configure the `restage_mcp` executable as a stdio server in the agent host.
For Claude Code:

```sh
claude mcp add restage -- restage_mcp
```

Use `restage_login` if needed and follow its continuation instructions after
browser approval. Inspect the current tool schemas rather than inventing
argument names from CLI flags.

Many local and lifecycle tools accept `projectDirectory`, whose config supplies
omitted selectors. Analytics and funnel tools instead require these exact
target fields:

- `organizationId`
- `projectSlug` and `appSlug`
- `environmentSlug` and `environmentTargetId`
- `runtimePlane` (`sandbox` or `live`)

Discover them with `restage_list_organizations`, `restage_list_projects`,
`restage_list_apps` and `restage_list_environment_targets`. The service validates
that the declared ids and selectors name one authorized target. Do not copy a
target id between apps or planes.

## TUI

Open `restage console`. Its overview shows sessions, completions and revenue for
the target loaded from `restage_config.yaml`. Selecting another environment does
not refresh these figures; use an explicit analytics read for that target.

Press `/` and enter the full command, including `restage`:

```text
restage analytics health --json
restage analytics explore --dimension platform --json
```

Commands use `restage_config.yaml` defaults; they do not inherit the console's
selected environment. Pass explicit `--organization`, `--project`, `--app`,
`--env` and `--plane` selectors where supported to target another context. Sign-in runs in an external
terminal. The command prompt is non-interactive, so an operation that needs an
interactive confirmation must use the TUI's action or an external terminal.

CLI, TUI and MCP use the same analytics definitions. Preserve target, window,
filters, and unavailable states when moving between them; matching operation
coverage does not mean every interface has the same interaction controls.

## Authorization and confirmations

Check existing user authorization before asking again. A request to inspect
analytics does not authorize publication; an explicit request to publish a
particular reviewed revision need not be re-approved without a scope change.

Live changes have tool-level confirmation controls. The CLI accepts `--yes`
for most live mutations; live `surface kill` and `surface rollback` require
interactive confirmation. MCP live mutations require `confirmLive: true`.
Supply these only when the requested action is authorized. Some review
operations also retain server state and use the live guard.

Measurement warning acknowledgement is separate: preserve and inspect the
complete returned review, then provide its exact digest or acknowledgement
document as required. General live consent does not supply that evidence.
