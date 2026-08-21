# restage_codegen

[![pub package](https://img.shields.io/pub/v/restage_codegen.svg)](https://pub.dev/packages/restage_codegen) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue.svg)](LICENSE)

The build-time code generator for [Restage](https://pub.dev/packages/restage).
It runs under [`build_runner`](https://pub.dev/packages/build_runner) and
compiles annotated Flutter widgets into the
[Remote Flutter Widgets](https://pub.dev/packages/rfw) artifacts, catalogs, and
typed descriptors that the Restage SDK renders. The same generator serves every
surface: paywalls, onboarding, in-app messages, surveys, and whole screens.

You write plain Flutter. The generator lowers a broad set of it (`Text.rich`,
`Theme.of(context)`, `Navigator.push`, `showModalBottomSheet`, `PageView`,
`NumberFormat`, structured style values, the selection controls, and
pure-composition custom widgets) and stops with an error at build time on
anything it cannot represent. It never emits a partial render.

## Setup

Add the package as a dev dependency and run the build:

```yaml
dev_dependencies:
  restage_codegen: ^1.0.0
  build_runner: ">=2.4.0 <3.0.0"
```

```sh
dart run build_runner build
restage surface publish <id>
```

You do not import this package in app code. Its builders are declared in
`build.yaml` and apply to dependents automatically. They find the supported
inputs and write the generated outputs next to them.

## Annotations

- `@Screen(surface: Surface.<category>)` publishes one screen.
- `@Paywall` publishes a paywall. A paywall can also be a step in a flow.
- `@FlowGraph(surface: Surface.<category>)` publishes a typed flow of screens.
- `@Screen()` with no category is a screen for use inside a flow.
- `@RestageWidget` registers one of your own widgets in the catalog.

The categories are `onboarding`, `message`, `survey`, `paywall`, and `general`.

## What it produces

From one annotated source file:

- **`.rfwtxt`**: the readable Remote Flutter Widgets text form.
- **`.rfw`**: the compiled binary artifact the SDK decodes and renders.
- **A capability manifest** (`.capability.json`): the capability floor the
  artifact declares, so an older reader fails closed instead of misrendering.
- **A flow document**: the declarative multi-screen topology, for surfaces
  that move between screens.
- **Generated Dart** (`restage.generated/<name>.restage.g.dart`): typed
  `SurfaceScreenRef<E>` and `SurfaceFlowRef<R>` accessors with the category,
  compatibility, and event or result contracts.
- **A publication manifest** (`lib/generated/restage.publication.json`): the
  exact set of generated artifacts for each surface id. `restage surface
  publish` reads it.

The wire artifacts contain only inert data: references and literal values,
never executable code. The generated Dart and Widgetbook stories are normal
build-time source that ships in your app release.

Under the hood, the generator transpiles the widget tree, decomposes structured
Flutter types (`TextStyle`, `ButtonStyle`, `EdgeInsets`, `BoxDecoration`,
border radii, gradients, and others), folds constants, lowers theme reads to
declarative theme bindings, and derives the capability manifest from the
widgets a surface references.

## Builders

- **`restageCodegenBuilder`** compiles `@Screen`, `@Paywall`, and
  `@FlowGraph` sources into the `.rfwtxt` and `.rfw` artifacts, the capability
  metadata, and a navigation plan. It also accepts hand-written `.rfwtxt`
  input for low-level work.
- **`paywallFlowBuilder`** emits the flow document for a surface whose source
  navigates across more than one screen.
- **`onboardingScreenBuilder`** compiles an onboarding screen into its typed
  descriptor, artifacts, and capability manifest.
- **`onboardingFlowBuilder`** emits the typed flow descriptor and flow
  document for a multi-screen flow.
- **`userCatalogBuilder`** walks a package for `@RestageWidget` classes and
  emits one aggregated catalog.
- **`userA2uiCatalogBuilder`** (opt-in) emits generated genui `CatalogItem`s
  and a standalone A2UI catalog document from the same annotated widgets.
- **`widgetbookStoryBuilder`** (opt-in) emits `*.stories.dart` source for
  Widgetbook v4 from the same annotated widgets.

Two further internal builders register catalog factory functions and your
widget factories for the runtime.

## Optional targets

**A2UI.** The generator can project your `@RestageWidget` source into a
content-addressed [genui](https://pub.dev/packages/genui) A2UI catalog with
typed literal constraints, nested data documentation, and controlled value
sources. RFW stays the native delivery format; A2UI is an additional target.
The [A2UI walkthrough](https://pub.dev/packages/restage_a2ui#generate-an-a2ui-catalog-from-your-widgets--step-by-step)
covers the dependencies, the `build.yaml` setting, and the build command.

**Widgetbook.** The generator can emit Widgetbook v4 story source for the same
widgets. Constructor inputs and Dartdoc are enough for one deterministic story
per widget. Enable `restage_codegen:widgetbook_stories` in `build.yaml`, keep
Widgetbook's normal `runWidgetbook(Config(...))` bootstrap, and run the same
`build_runner` command. Restage does not generate stories for Flutter,
Material, Cupertino, or Restage built-in widgets.

**Opting out.** Builder configuration selects targets for the package. One
`@RestageWidget` can opt out of a selected target with that target's
`Config(enabled: false)` or `Config.enabled(false)` annotation. Bare `@ignore`
omits one constructor input from every target;
`@Ignore({EmitTarget.a2ui, EmitTarget.widgetbook})` omits it from those targets
only and keeps it in RFW.

**Watch mode.** If you add or remove an `@RestageWidget` in a file that already
contains one, restart `dart run build_runner watch` so the package-wide story
output is rescanned. A normal `dart run build_runner build` always performs the
full scan.

## Large codebases

Seven builders look at the whole package rather than one file. Five run for
every dependent — the source roster, the package surface compiler, and the
three that aggregate `@RestageWidget` classes — and two more do the same once
you opt in: the A2UI catalog and the Widgetbook stories. On a large app,
resolving every Dart library just to ask whether it declares anything is the
dominant cost: not because analysis is slow, but because resolving a file pulls
in its transitive imports and makes all of them dependencies of that builder,
so any later edit re-triggers the whole scan.

So they read each file's raw source first and resolve only the files that can
declare something. A package with none pays no analysis at all; a package with
a handful of surfaces pays for that handful. Every file under `lib/` is still
scanned — including generated ones that already exist when the builder runs,
because a generated file can be a `part` — and a declaration inside a `part` is
still found through the library that owns it.

**What you write is discovered exactly as before.** An annotation written on
the declaration, behind an import prefix, in a `part`, or through a `const` or
`typedef` alias declared in another file **in the same package** all reach the
same place they always did.

One shape is not followed: an alias declared in a **different package** — a
shared annotations package that exports `const card = RestageWidget(...)`, used
as `@card` in yours. These builders scan only the package they are building, so
they never see that declaration and the annotated class is not discovered. Write
the annotation itself, or declare the alias in the same package.

Two things do change, and both are about diagnostics rather than discovery.

A syntax error in a file that spells no Restage annotation is no longer
reported by these seven builders, because they no longer analyse that file. The
Dart toolchain still reports it. The exception is the deprecated screen path
`lib/<onboarding|message|survey>/screens/<id>.dart`: the per-file screen
builders still analyse a library there whether or not it is annotated, and the
two opt-in package-wide builders still select it, so its errors are unchanged.

The two roster ledgers, `assets/restage/source-index.json` and
`assets/restage/output-roster.json`, are written into your package only once it
declares a Restage source, or reports a problem with one. A package that merely
depends on `restage_codegen` does not get them.

**Turning builders off.** If a package will never declare a customer widget or
a Restage surface — a data layer, a networking package, a generated-model
package — switch the package-wide builders off in that package's `build.yaml`
(the two opt-in builders are off unless you turned them on):

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
```

Restage's own registry-driven widget packages use the first two entries of that
recipe.

`generate_for` is not an alternative here. These builders take a `build_runner`
placeholder as their input — `$package$` for the source roster and the surface
compiler, `lib/$lib$` for the three widget aggregators — not your source files.
A glob narrowed to a subtree (`lib/widgets/**`) matches neither placeholder, so
it does not scope the builder, it stops it running. A broad glob (`lib/**`)
matches `lib/$lib$`, so it scopes nothing for the three widget aggregators —
and it does not match `$package$`, so it stops the source roster and the surface
compiler outright. `enabled: false` is the supported control.

## License

Functional Source License, Version 1.1, ALv2 Future License (FSL-1.1-ALv2):
free for all use except building a competing product. Each release becomes
Apache-2.0 two years after publication. See [`LICENSE`](LICENSE).
