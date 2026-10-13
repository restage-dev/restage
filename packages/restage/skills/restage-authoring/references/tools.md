# The restage CLI and MCP server

Both talk to Restage Cloud and share one saved sign-in. Neither is needed to write,
build or run surfaces locally.

## Rules for agents

- **Pushing is safe; publishing is not.** `restage surface push <id>` uploads a version
  and changes nothing users see. Publishing, rollback, kill, freeze, routing and
  experiment changes affect every installed app. Ask the user before running any of
  them, and state the surface, environment, plane and revision.
- **The live plane needs explicit consent.** On `live`, the CLI asks before these
  changes (pass `--yes` only after the user approved; kill and rollback on live never
  accept `--yes`), and MCP tools refuse unless you pass `confirmLive: true`. Set it only
  after the user approves that change.
- Run the build before pushing. Push reads the build's publication manifest.
- Never paste API keys or tokens into commands, tool arguments or chat. CI reads a
  secret key from `RESTAGE_API_KEY` in the environment.

## CLI

```sh
restage init          # add packages, config and a starter surface
restage doctor        # check the local setup
restage login         # sign in through the browser (a human step)
restage whoami
```

`restage_config.yaml` names the organization, project, app, environment and `plane`.
Each environment has a `sandbox` side for testing and a `live` side with real users.
`init` writes `plane: sandbox`; keep it there unless the user asks for live. API keys
name their side and environment (`rs_pk_sandbox_staging_…`).

Surfaces:

```sh
dart run build_runner build
restage surface push weekly_recap          # upload a version
restage surface push lib/onboarding/first_run.dart
restage surface publish weekly_recap       # make the latest pushed version live
restage surface status weekly_recap        # live version, frozen or not
restage surface history weekly_recap
restage surface results weekly_recap       # views, steps, drop-off, completions
restage surface rollback weekly_recap --to-version 2 --reason "..."
restage surface freeze weekly_recap --reason "..."   # keep the current version
```

`surface publish` without `--revision` publishes the latest pushed revision and prints
which one. `--reason "..."` records why in the audit log. Pass `--non-interactive` (or
`-y`) in scripts; a missing required value then fails with the flag's name.

App builds, needed so the dashboard can show surfaces that use custom widgets. The CLI
generates everything it needs under `.restage/build/`; don't add files to the app for it.

```sh
restage build push                 # your personal build
restage build push --env staging   # an environment's build
restage build list                 # what has been pushed
restage surface push weekly_recap --build   # push the build first, then the surface
```

Push a build again after adding or changing a custom widget.

## MCP server

`restage_mcp` runs over stdio. For Claude Code:

```sh
claude mcp add restage -- restage_mcp
```

Sign in with the `restage_login` tool (the user approves in the browser), then call it
again to finish. The MCP server can do everything the CLI can; each tool names the CLI
command it matches. Pass `projectDirectory` so `restage_config.yaml` supplies the
project, app, environment and plane. Useful tools while authoring:

| Tool | Use |
| --- | --- |
| `restage_list_surfaces` | What exists in a project and app |
| `restage_surface_status` | Live version, freeze state, delivery details |
| `restage_surface_history` | Pushed revisions, with the live one marked |
| `restage_read_surface_funnel` | Views, steps, drop-off and completions per version |
| `restage_push_surface` | Upload a version (doesn't publish) |
| `restage_publish_surface` | Make a pushed version live |
| `restage_push_build` / `restage_list_builds` | Push or list app builds |
| `restage_rollback_preflight` | Check a rollback without changing anything |

The same rule applies as for the CLI: publishing, rolling back, killing, freezing,
routing and experiment changes affect users, so ask first. On a live target these tools
also need `confirmLive: true`.

Use the MCP server for project context, such as what is live and how a version
performs, and write the surface in Dart as described in the main skill.
