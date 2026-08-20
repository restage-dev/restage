# restage_cli

[![pub package](https://img.shields.io/pub/v/restage_cli.svg)](https://pub.dev/packages/restage_cli) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

The `restage` command line. Use it to set up a project, publish surfaces,
manage what is live, and preview compiled artifacts. It works the same for a
person at a terminal, a CI job, and an agent.

## Status

Pre-release. The commands and the on-disk credential format can still change.

## Install

The package is not on pub.dev yet. Until it is, build the native binary from
the repo:

```sh
git clone https://github.com/restage-dev/restage.git
cd restage
melos run cli:install
```

That compiles the CLI and installs it at `$PUB_CACHE/bin/restage`. Make sure
`$HOME/.pub-cache/bin` is on your `PATH`.

Once published, `dart pub global activate restage_cli` installs a shell
wrapper at the same location. The native binary skips the wrapper's snapshot
rebuild on every run, which you notice on a home directory that contains
spaces. Switch between the two freely.

## Usage

```sh
restage --help

# Sign in and out (device-authorization flow).
restage login
restage whoami
restage logout

# Set up a Flutter project for Restage.
restage init

# List and publish the surfaces the build generated.
restage surface list --all
restage surface publish <id>
restage surface publish lib/screens/welcome.dart
restage surface publish lib/screens/onboarding.dart --all

# Manage one surface.
restage surface status <id>
restage surface history <id>
restage surface rollback <id> --to-version <version> --reason "<reason>"
restage surface freeze <id> --reason "<reason>"
restage surface unfreeze <id> --reason "<reason>"

# Open the desktop preview on a compiled .rfw.
restage preview path/to/paywall.rfw

# Check the local toolchain.
restage doctor
```

`init`, `preview`, and `doctor` work offline. `login` and the `surface`
commands talk to a Restage backend; hosted access is in private beta.

Every command accepts `--non-interactive` (or `--yes` / `-y`) to suppress
prompts. A required value with no default then exits non-zero with a
`required: --foo <value>` message.

## Publishing

After `dart run build_runner build`, the CLI reads the generated manifest at
`lib/generated/restage.publication.json` and uploads the artifacts it records
for the surface you name. `--type` is optional validation.

You can name the surface by id or by its `.dart` file:

```sh
restage surface publish welcome
restage surface publish lib/screens/welcome.dart
```

A file is resolved through the same manifest, so it selects what the build
produced for that file. Nothing is parsed and no directory is scanned. A screen
that belongs to a flow selects the flow, since the flow is what ships it. If a
file produced more than one surface, the CLI lists them and asks, or publishes
all of them under `--all`. A file that produced nothing is an error that names
the manifest. A run over several surfaces stops at the first failure and
reports what published and what was not attempted.

Surface categories are `paywall`, `onboarding`, `message`, `survey`, and
`general`.

`restage paywall publish <name>` still works for a `@Paywall` surface and reads
the same manifest. New scripts should use `restage surface publish` for every
category.

## Render bundles (pre-release)

`restage build push` builds a renderer for your custom widgets, uploads it, and
advances one channel. Each bundle is immutable and runs on its own derived
origin:

```sh
restage build push \
  --project <project-slug> \
  --channel main
```

`--channel` accepts `main` or a `user/<handle>` value. The command rejects an
invalid channel before it touches credentials, build work, or the network. It
builds twice and requires byte-identical output before it uploads, then
reports the channel's new version and content hash.

Configure the three origins in `restage_config.yaml`:

```yaml
endpoint: http://api.restage.localhost:8080
dashboardOrigin: http://dashboard.restage.localhost:8082
renderBundleOrigin: http://bundles.restage.localhost:8081
```

Local use needs those three `restage.localhost` roles on distinct, explicit
ports. `renderBundleOrigin` is the upload and control origin; a bundle runs on
its own derived origin, such as `http://b-42.restage.localhost:8081` for bundle
42. Deployed use needs three distinct HTTPS siblings under `restage.dev`. The
dashboard origin is the pinned parent origin. `--parent-origin` is accepted
only when it matches the configured dashboard origin, and `--bundle-origin`
may supply the bundle control member of the same triplet.

This lane is pre-release. It is not a public deployment or package-release
signal.

## License

BSD-3-Clause. See `LICENSE`.
