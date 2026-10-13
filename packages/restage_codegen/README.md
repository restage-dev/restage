# restage_codegen

[![pub package](https://img.shields.io/pub/v/restage_codegen.svg)](https://pub.dev/packages/restage_codegen) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue.svg)](LICENSE)

Annotate a Flutter screen you already wrote, and `build_runner` compiles it
into a surface Restage can deliver: onboarding, messages, surveys, paywalls,
or any other screen.

Part of [Restage](https://restage.dev), server-driven UI for Flutter.

You write plain Flutter. The generator handles a broad set of it (`Text.rich`,
`Theme.of(context)`, `Navigator.push`, `showModalBottomSheet`, `PageView`,
`NumberFormat`, style values such as `TextStyle` and `BoxDecoration`, the
selection controls, and custom widgets built by composing other widgets). On
anything it can't represent, the build fails with an error. It never produces
a partial surface.

The output is [Remote Flutter Widgets](https://pub.dev/packages/rfw) artifacts,
a widget catalog, and typed Dart accessors that the
[Restage SDK](https://pub.dev/packages/restage) renders.

## Setup

Add the package as a dev dependency, build, then push and publish with the
`restage` CLI:

```yaml
dev_dependencies:
  restage_codegen: ^2.0.0
  build_runner: ^2.16.1
```

```sh
dart run build_runner build
restage surface push <id>
restage surface publish <id>
```

You don't import this package in app code. Its builders apply to your package
automatically and write their outputs next to the sources they read. No
`build.yaml` is needed. Add `--verbose` to the build to print a summary of
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
- **A publication manifest** (`.restage/build/metadata/restage.publication.json`):
  the generated files for each surface id. `restage surface push` reads it.

What ships is data the app renders. Your widgets carry the logic, as real Dart
compiled into your app. A surface composes and configures them over the air.
New behavior needs an app release.

Every generated `<Name>Surface(...)` mount has an implicit placement. Use the
ordinary constructor for screens, paywalls and flows. The generated
`.atPlacement('name', ...)` constructor is an optional override for an explicit
placement name.

## Generated files

Generated Dart sits next to its source in `restage.generated/`. Everything
else goes under `.restage/build/`:

- `bundles/` mirrors your `lib/` folders.
- `metadata/` holds the publication manifest.
- `widget_catalog/` holds your custom widget catalog.
- `a2ui/` holds the A2UI catalog, if you turn it on.

Add `.restage/build/` to `.gitignore`. Commit
`.restage/measurement-state.json` and `.restage/wire-ids.events.jsonl`: they
keep analytics IDs and catalog IDs stable across clean builds.

If you edit either file by hand while `build_runner watch` is running, restart
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

**A2UI.** The generator can turn your `@RestageWidget` classes into a
[genui](https://pub.dev/packages/genui) A2UI catalog. Restage still delivers
surfaces as RFW; A2UI is an extra output. The
[A2UI walkthrough](../restage_a2ui/README.md#generate-an-a2ui-catalog-from-your-widgets)
covers the dependencies, the `build.yaml` setting, and the build command.

**Widgetbook.** The generator can write a Widgetbook v4 story for each of your
widgets from its constructor and doc comments. Enable
`restage_codegen:widgetbook_stories` in `build.yaml`, keep Widgetbook's usual
`runWidgetbook(Config(...))` setup, and run the same `build_runner` command.
Stories are not generated for Flutter, Material, Cupertino, or Restage
built-in widgets.

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
your resolved dependency graph. Unsupported expressions still produce build
diagnostics; a dependency does not bypass the compiler's authoring limits.

Generated screen mounts accept an optional `unavailable` policy. By default
they retain the original widget as a compiled fallback. Publication identity
and measurement lineage remain stable when rebuilding unchanged sources.

## Large codebases

A few builders scan your whole package for Restage annotations. They read each
file's source first and only analyze files that mention an annotation, so a
package with no surfaces costs almost nothing.

One case is not found: an annotation alias declared in a **different
package**, such as a shared package that exports
`const card = RestageWidget(...)` for use as `@card`. Write the annotation
itself, or declare the alias in the same package.

A syntax error in a file with no Restage annotation is not reported by
these eight builders, because they skip that file. The Dart analyzer still
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
```

Use `enabled: false` rather than `generate_for`. These builders take a
placeholder as their input: `$package$` for the source roster and surface
compiler, and `lib/$lib$` for the catalog JSON, catalog Dart, factory Dart
and surface list builders. A `generate_for` glob either stops them entirely or
has no effect.

## License

FSL-1.1-ALv2. See [LICENSE](LICENSE).
