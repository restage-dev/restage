# restage_cli

[![pub package](https://img.shields.io/pub/v/restage_cli.svg)](https://pub.dev/packages/restage_cli) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

The Restage command-line interface — the universal agent, human, and CI
surface for building, previewing, and publishing your Restage surfaces.

## Status

Pre-release. The command surface and on-disk credential format are not yet
stable.

## Install

Two install paths are supported. Both produce the same `restage` binary
on your `PATH`; pick the one that suits your environment.

### From pub.dev (canonical)

```sh
dart pub global activate restage_cli
```

After activation, the `restage` shell wrapper is on your `PATH` (assuming
`$HOME/.pub-cache/bin` is in your shell's `PATH`). This is the right
install path for most users.

### Native binary

```sh
git clone https://github.com/restage-dev/restage.git
cd restage
melos run cli:install
```

The melos script compiles the CLI to a native binary and installs it at
`$PUB_CACHE/bin/restage` (overriding the pub-global shell wrapper). The
native binary skips the wrapper's per-invocation snapshot rebuild — which
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

Every command accepts `--non-interactive` (or `--yes` / `-y`) to suppress
prompts; missing required values without a default exit non-zero with a
clear `required: --foo <value>` message.

## License

BSD-3-Clause — see `LICENSE`.
