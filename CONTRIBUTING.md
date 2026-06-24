# Contributing to Restage

Thanks for your interest in Restage — the open-source SDK for server-driven
Flutter UI: the runtime that renders surfaces, the widget catalog, the build-time
toolchain, the CLI, and the examples. Contributions are welcome.

## Before you start: one gated area

Most of the SDK is open for pull requests right now — the widget catalog
(`restage_core` / `restage_material` / `restage_cupertino`), the runtime SDK
(`restage`), the CLI, and the examples.

**The two exceptions are the build-time toolchain packages, `restage_codegen` and
`rfw_catalog_compiler`.** They're licensed FSL-1.1-ALv2 (with a scheduled
conversion to Apache-2.0), which means contributions to them require a Contributor
License Agreement — and we're still putting the CLA signing flow (and the bot that
checks it) in place. **A pull request that changes either of those packages will be
closed automatically until that's live.** If you have a toolchain idea in the
meantime, please [open an issue](https://github.com/restage-dev/restage/issues);
otherwise keep your pull request to the other packages and it'll be reviewed
normally.

## Setup

The repository is a Dart and Flutter workspace managed with
[Melos](https://melos.invertase.dev/). You need the Flutter SDK installed, then:

```sh
dart pub global activate melos
melos bootstrap
```

`melos bootstrap` runs `pub get` across every package and links the local path
dependencies together.

## Running tests

A single package directly, which is usually what you want while working on one:

```sh
cd packages/restage_core
flutter test
```

Before opening a pull request, run the analyzer and the formatter — the same two
checks the project runs:

```sh
dart analyze
dart format .
```

## Where to contribute

The most welcome and easiest place to start is the **widget catalog**:
`restage_core`, `restage_material`, and `restage_cupertino`. These libraries
decide which Flutter widgets a surface can use. Adding a widget is a small,
self-contained change with no deep internals involved.

Each catalog library has a curation file (`lib/registry_curation.dart`) that lists
the widgets in that library. To add a widget, you add one entry naming the Flutter
widget and only the things that cannot be read off its constructor, such as its
category and any property it should not expose. The toolchain reads the rest from
the Flutter constructor itself (parameter names, types, defaults). Then you
regenerate:

```sh
cd packages/restage_material   # or restage_core / restage_cupertino
dart run build_runner build
```

That regenerates the registry and the registration code from your curation entry.
A good change here is: one new curation entry, the regenerated files, and a test
that the new widget renders the way you expect. Copying an existing nearby entry
is the fastest way in.

Other good areas:

- **Examples** (`apps/examples`): new example surfaces, or improvements to the
  existing ones. These ship with the SDK and are the first thing people copy.
- **The SDK and CLI** (`packages/restage`, `packages/restage_cli`): bug fixes
  and focused improvements. For anything larger, open an issue first so we can
  talk through the shape before you build it.
- **The build-time toolchain** (`packages/restage_codegen`,
  `packages/rfw_catalog_compiler`): gated for now (see above) — open an issue
  rather than a pull request until the CLA flow is live.

A note on the SDK's dependencies: `packages/restage` is intentionally
self-contained and depends only on pub.dev packages and the shared package. Please
keep it that way, and keep any backend URLs or hostnames out of it, since those
come through configuration.

## Pull requests

- Keep changes focused. One widget, one fix, or one example per pull request is
  ideal.
- Make sure `dart analyze`, `dart format .`, and the relevant tests pass.
- Describe what you changed and why. If it changes behavior, say how you verified
  it.

## Contributor License Agreement

You only need to think about this if you're contributing to the **FSL-licensed
build toolchain** (`restage_codegen` / `rfw_catalog_compiler`) — and that's gated
until the signing flow is live anyway. The rest of the SDK is BSD-3-Clause and
requires no CLA.

When the toolchain opens for contributions, we'll publish the Contributor License
Agreement here, and a bot will ask you to sign it on your first such pull request
(one individual signature covers your future contributions; if your employer or
another organization owns rights in your contribution, an authorized
representative signs a corporate agreement). The CLA keeps the toolchain's
licensing consistent over time, including its scheduled FSL-1.1-ALv2 to Apache-2.0
conversion.

## Code of conduct

Be respectful and constructive. We want this to be a good place to work together
and to have fun building it.
