# restage_cli

[![pub package](https://img.shields.io/pub/v/restage_cli.svg)](https://pub.dev/packages/restage_cli) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

The Restage command-line interface: the universal agent, human, and CI
surface for building, previewing, and publishing your Restage surfaces.

## Status

Pre-release. The command surface and on-disk credential format are not yet
stable.

## Install

Two install paths are supported. Both produce the same `restage` binary
on your `PATH`; pick the one that suits your environment.

### From pub.dev (once published)

```sh
dart pub global activate restage_cli
```

> **Note:** `restage_cli` isn't on pub.dev yet; use the native-binary install
> below until it's published.

After activation, the `restage` shell wrapper is on your `PATH` (assuming
`$HOME/.pub-cache/bin` is in your shell's `PATH`). Once published, this is the
right install path for most users.

### Native binary

```sh
git clone https://github.com/restage-dev/restage.git
cd restage
melos run cli:install
```

The melos script compiles the CLI to a native binary and installs it at
`$PUB_CACHE/bin/restage` (overriding the pub-global shell wrapper). The
native binary skips the wrapper's per-invocation snapshot rebuild, which
is noticeable on a home directory that contains spaces. Switch between
the two install paths freely.

## Usage

```sh
restage --help

# Sign in / out and check identity (device-authorization flow).
restage login
restage whoami
restage logout

# Bootstrap a Flutter project for Restage.
restage init

# List and publish paywalls.
restage paywall list
restage paywall publish <name>

# Publish an engagement surface (onboarding / message / survey).
restage surface publish <name>

# Launch the desktop preview against a compiled .rfw.
restage preview path/to/paywall.rfw

# Diagnose the local toolchain setup.
restage doctor
```

`init`, `preview`, and `doctor` work fully offline. `login` and the publish
commands talk to a Restage backend; hosted access is in private beta.

Every command accepts `--non-interactive` (or `--yes` / `-y`) to suppress
prompts; missing required values without a default exit non-zero with a
clear `required: --foo <value>` message.

## Isolated render bundles

The pre-release render-bundle lane deterministically builds a customer-widget
renderer, uploads it through a pinned control origin, and advances one selected
channel. Each immutable bundle executes on a separate derived origin:

```sh
restage build push \
  --project <project-slug> \
  --channel main
```

`--channel` accepts `main` or a canonical `user/<handle>` value. An invalid
channel is rejected before credentials, build work, or network access. The
command builds twice and requires byte-identical output before it uploads,
then reports the selected channel's immutable version and content hash.

Configure all three non-secret origins in `restage_config.yaml`:

```yaml
endpoint: http://api.restage.localhost:8080
dashboardOrigin: http://dashboard.restage.localhost:8082
renderBundleOrigin: http://bundles.restage.localhost:8081
```

Local use requires those exact three `restage.localhost` roles on distinct,
explicit ports. `renderBundleOrigin` is the upload and control origin; an
immutable bundle executes on its own derived origin, such as
`http://b-42.restage.localhost:8081` for bundle 42. Deployed use requires three
distinct direct HTTPS siblings under `restage.dev`. The dashboard origin is the
default pinned parent origin. `--parent-origin` is accepted only when it exactly
matches the configured dashboard origin; `--bundle-origin` may supply the
bundle control member of the same validated triplet.

This lane is pre-release and is not a public deployment or package-release
signal.

## License

BSD-3-Clause. See `LICENSE`.
