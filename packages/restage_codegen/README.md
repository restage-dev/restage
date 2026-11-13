# restage_codegen

[![pub package](https://img.shields.io/pub/v/restage_codegen.svg)](https://pub.dev/packages/restage_codegen) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue.svg)](LICENSE)

Annotate a Flutter screen you already wrote, and `build_runner` compiles it
into a surface Restage can deliver: onboarding, messages, surveys, paywalls,
or any other screen.

Part of [Restage](https://restage.dev), server-driven UI for Flutter.

This README describes the `main` branch. For a released version, see its page on pub.dev.

You write plain Flutter. The generator handles a broad set of it (`Text.rich`,
`Theme.of(context)`, `Navigator.push`, `showModalBottomSheet`, `PageView`,
`NumberFormat`, style values such as `TextStyle` and `BoxDecoration`, the
selection controls, and custom widgets built by composing other widgets).
Code it can't represent renders from the app instead, and a design can still
change what's around it. A short list of things stops the build with an error.
[What renders from your app](https://docs.restage.dev/authoring/islands) lists
both.

The output is [Remote Flutter Widgets](https://pub.dev/packages/rfw) artifacts,
a widget catalog, and typed Dart accessors that the
[Restage SDK](https://pub.dev/packages/restage) renders.

## Setup

Add the packages from the repository's `main` branch, with overrides so every
Restage package resolves to the same copy. `restage init` writes the same
entries:

```yaml
dependencies:
  flutter:
    sdk: flutter
  restage:
    git:
      url: https://github.com/restage-dev/restage.git
      ref: main
      path: packages/restage
  restage_material:
    git:
      url: https://github.com/restage-dev/restage.git
      ref: main
      path: packages/restage_material

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ">=2.15.1 <3.0.0"
  restage_codegen:
    git:
      url: https://github.com/restage-dev/restage.git
      ref: main
      path: packages/restage_codegen

dependency_overrides:
  restage:
    git:
      url: https://github.com/restage-dev/restage.git
      ref: main
      path: packages/restage
  restage_material:
    git:
      url: https://github.com/restage-dev/restage.git
      ref: main
      path: packages/restage_material
  rfw_catalog_schema:
    git:
      url: https://github.com/restage-dev/restage.git
      ref: main
      path: packages/rfw_catalog_schema
```

Then generate the local outputs:

```sh
dart run build_runner build
```

Mount a generated `*Surface` widget to use its compiled fallback locally. When
using hosted delivery, `restage surface push <id>` uploads a revision and
`restage surface publish <id>` makes it live.

You don't import this package in app code. Its builders apply to your package
automatically and write their outputs next to the sources they read. The one
`build.yaml` entry the build asks for lists the state files it reads. An
edit to one of them triggers a rebuild. `restage init` adds it:

```yaml
additional_public_assets:
  - .restage/measurement-state.json
  - .restage/wire-ids.events.jsonl
  - .restage/receipts/**
  - .restage/library-contracts/**
```

Add `--verbose` to the build to print a summary of
the surfaces it compiled.

A surface that draws icons ships a subset of their icon font, cut with the
Flutter SDK's `font-subset` tool. Run the build with your app's Flutter SDK.
The CLI also resolves the app-selected SDK for `restage build push`; see the
[toolchain selection order](../restage_cli/README.md#builds-pre-release).

## Annotations

- `@Screen(surface: Surface.<type>)` publishes one screen.
- `@Screen()` with no type is a screen for use inside a flow.
- `@FlowGraph(surface: Surface.<type>)` publishes a flow of screens. Flows are
  typed by default. Pass `delivery: FlowDeliveryMode.general` for a flow whose
  structure can change over the air.
- `@Paywall` publishes a paywall. A paywall can also be a step in a flow.
- `@RestageWidget` adds one of your own widgets to the catalog.

The surface types are `onboarding`, `message`, `survey`, `paywall`, and
`general`.

## What it produces

From one annotated source file:

- **`.rfwtxt`**: the readable Remote Flutter Widgets text form.
- **`.rfw`**: the compiled binary the SDK decodes and renders.
- **A capability manifest** (`.capability.json`): what the surface needs from
  the app, so an older app refuses it cleanly instead of rendering it wrong.
- **A flow document**: the screens of a multi-screen surface and how they
  connect.
- **Generated Dart** (`restage.generated/<name>.restage.g.dart`): typed
  `SurfaceScreenRef<E>` and `SurfaceFlowRef<R>` accessors, plus typed
  `<Screen>Surface` widgets for eligible screens.
- **A surface list** (`lib/restage_surfaces.g.dart`): `restageSurfaces`, every
  surface the package compiles. Pass it to
  `Restage.configure(surfaces: restageSurfaces)` to fetch their latest content
  in the background at startup.
- **Startup request templates** (`android/app/src/main/assets/restage_early.json`,
  `ios/Runner/restage_early.json`): the first placement request, which the
  platform sends at app launch before Dart starts. Set `api_key`, `base_url`
  and optionally `channel` under the `restage_codegen:user_factories` builder
  options in `build.yaml`, next to `delivery_keys`, the keys delivered content
  must be signed with. A signed-in `restage init` writes all of them, and
  `restage keys delivery` prints the delivery keys. `restage init --sdk-key
  rs_pk_...` without a sign-in writes only `api_key` and `base_url`. The
  generated `kRestageWidgetRegistration` carries these options, and
  `Restage.configure(registerWidgets: kRestageWidgetRegistration)` reads them.
  Without delivery keys, every delivered version is refused and mounts show
  the compiled widget. Without a key the build writes no template and says so
  in one line; the app then runs offline. `analytics: false` in the same
  options starts the app with analytics off: the template's first launch sends
  no install id, registration or assignment, until the app passes
  `analyticsEnabled: true`. On iOS, list
  `ios/Runner/restage_early.json` under `flutter: assets:` in `pubspec.yaml`
  (`restage init` adds it); the build warns when it is missing.
- **A publication manifest** (`.restage/build/metadata/restage.publication.json`):
  the generated files for each surface id. `restage surface push` reads it.

What ships is a description your app's widgets draw, in a small closed
language the compiler checks. It can carry simple logic, like conditions over
data your app supplies. Gestures, drawing, network calls and native work stay
in Dart compiled into your app. New kinds of behavior need an app release.

Every generated `<Name>Surface(...)` mount declares a placement automatically. Use the
ordinary constructor for screens, paywalls and flows. The generated
`.atPlacement('name', ...)` constructor is an optional override for an explicit
placement name.

## Generated files

Generated Dart sits next to its source in `restage.generated/`. Everything
else goes under `.restage/build/`:

- `bundles/` mirrors your `lib/` folders.
- `metadata/` holds the publication manifest and `restage.build.json`, which
  records whether the last build succeeded. A failed build keeps the previous
  outputs, and `restage surface push` refuses them with the build's first
  error.
- `widget_catalog/` holds your custom widget catalog.
- `a2ui/` holds the A2UI catalog, if you turn it on.

Add `.restage/build/` to `.gitignore`. Commit
`.restage/measurement-state.json`, `.restage/wire-ids.events.jsonl`,
`.restage/receipts/` and `.restage/library-contracts/`. They keep analytics
IDs, catalog IDs, release receipts and recorded library versions stable across
clean builds.

If you edit one of these files by hand while `build_runner watch` is running, restart
the watch or clean the build cache so the change is picked up.

## Renaming custom widgets

`.restage/wire-ids.events.jsonl` records the catalog ID of every custom widget
and property. Commit it with the source it describes.

When you rename or move a `@RestageWidget` class, the build stops before it
assigns a new ID and prints the exact `rename` line to add to that file. Add
the line and rebuild. The widget and all its properties keep their IDs. The
same applies to structured types and their fields.

A move to another file with the same class name uses the same value for `from`
and `to`:

```json
{"kind":"rename","type":"widget","id":"w0042","from":"StatusPanel","to":"StatusPanel","fromSource":"package:acme/widgets/old.dart#StatusPanel","toSource":"package:acme/widgets/new.dart#StatusPanel","cascade":true,"at":"2026-05-26T00:00:00.000Z","by":"restage-codegen-user-catalog-allocator"}
```

If the new class really is a different widget, add the `deprecate` line the
build prints instead, and the next build assigns a new ID. Only append to the
file; don't edit earlier lines.

## Optional targets

Widgetbook and A2UI work independently of RFW bundling. Enable either emitter
without setting `bundled_runtime` or adding surface assets to `pubspec.yaml`.
The order is annotated Flutter source → `build_runner` generation → the
consuming app. Neither consumer needs hosted publication or `restage build push`;
that command creates dashboard previews.

**A2UI.** The generator can turn your `@RestageWidget` and `@Screen` classes into a
[a2ui_flutter](https://pub.dev/packages/a2ui_flutter) A2UI catalog. Restage still delivers
surfaces as RFW; A2UI is an extra output. The
[A2UI walkthrough](../restage_a2ui/README.md#generate-an-a2ui-catalog-from-your-widgets)
covers dependencies, the builder, and wiring `buildRestageCatalog()` into an
A2UI `MessageProcessor` and `A2uiSurface`. The app supplies the model transport,
messages and action handling. The A2UI output requires `a2ui_flutter ^0.3.0`
and `a2ui_core ^0.7.0`.

Ordinary constructor names use `props_<DartName>` when that name is a valid
upstream UAX31 identifier and the source name does not start with `encoded_`.
Other names, including `$value`, and all source names starting with `encoded_`
use `props_encoded_<hex>`. The hex concatenates the source name's UTF-16 code
units as exactly four lowercase digits each; `$value` becomes
`props_encoded_002400760061006c00750065`. Reserving `encoded_` prevents a normal
source name from colliding with an encoded name. Producers must use the property
keys in the generated catalog schema and instructions. Dart constructor arguments
and nested rich-data keys keep their original names. Nested rich-data keys that start with `@` are written as `@@` on the wire; the runtime unescapes them.

**Widgetbook.** The generator can write a Widgetbook v4 story for each of your
widgets and annotated screens from their constructors and doc comments. Add
`widgetbook: 4.0.0-beta.14` to the source package's dependencies and enable
`restage_codegen:widgetbook_stories` in `build.yaml`. The same `build_runner`
command runs both Restage and Widgetbook generation. Pass the resulting
`components` from `components.g.dart` to `runWidgetbook(Config(...))`; see the
[workbench example](../../apps/widgetbook_example/README.md). Stories are not
generated for Flutter, Material, Cupertino, or Restage built-in widgets.

**Opting out.** One `@RestageWidget` can skip a target with that target's
`Config(enabled: false)` or `Config.enabled(false)` annotation. `@ignore` on a
constructor input leaves it out of every target;
`@Ignore({EmitTarget.a2ui, EmitTarget.widgetbook})` leaves it out of those
targets only.

**Watch mode.** If you add or remove a `@RestageWidget` in a file that already
has one, restart `dart run build_runner watch`. A normal
`dart run build_runner build` always sees the change.

## Shared widget packages

Surfaces can import widgets and helpers from packages your app depends on.
The compiler follows referenced package sources and tracks them as build
inputs, so edits to those sources rebuild the surface. Keep those packages in
your resolved dependency graph. Code in a dependency follows the same rules:
what the compiler can't represent renders from the app.

Generated screen mounts accept an optional `fallbackBuilder` and
`errorBuilder`. By default they retain the original widget as a compiled
fallback. Rebuilding unchanged
sources keeps each surface's id and its measurement history.

## Large codebases

A few builders scan your whole package for Restage annotations. They read each
file's source first and only analyze files that mention an annotation, so a
package with no surfaces costs almost nothing.

One case is not found: an annotation alias declared in a **different
package**, such as a shared package that exports
`const card = RestageWidget(...)` for use as `@card`. Write the annotation
itself, or declare the alias in the same package.

A syntax error in a file with no Restage annotation is not reported by
these eleven builders, because they skip that file. The Dart analyzer still
reports it.

If a package will never declare a custom widget or a surface (a data layer or
networking package, for example), turn these builders off in its `build.yaml`:

```yaml
targets:
  $default:
    builders:
      restage_codegen:user_catalog:
        enabled: false
      restage_codegen:user_catalog_json:
        enabled: false
      restage_codegen:user_factories:
        enabled: false
      restage_codegen:restage_source_roster:
        enabled: false
      restage_codegen:restage_package_surface_compiler:
        enabled: false
      restage_codegen:restage_surfaces:
        enabled: false
      restage_codegen:restage_early_template:
        enabled: false
      restage_codegen:generated_dart:
        enabled: false
      restage_codegen:generated_check:
        enabled: false
      restage_codegen:outputs:
        enabled: false
      restage_codegen:render_catalog:
        enabled: false
```

Use `enabled: false` rather than `generate_for`. Most of these builders take a
placeholder as their input:

- `$package$`: `restage_source_roster`, `restage_package_surface_compiler`,
  `render_catalog`, `restage_early_template` and `generated_check`.
- `lib/$lib$`: `user_catalog`, `user_catalog_json`, `user_factories` and
  `restage_surfaces`.

For these nine builders, a `generate_for` glob either stops them entirely or
has no effect. `restage_codegen:generated_dart` and `restage_codegen:outputs`
run on each library and read the surface compiler's result. With the compiler
off, `restage_codegen:outputs` fails the build.

## License

FSL-1.1-ALv2. See [LICENSE](LICENSE).
