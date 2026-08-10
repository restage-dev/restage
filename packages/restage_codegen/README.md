# restage_codegen

[![pub package](https://img.shields.io/pub/v/restage_codegen.svg)](https://pub.dev/packages/restage_codegen) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue.svg)](LICENSE)

The build-time code generator for the Restage SDK. It runs under
[`build_runner`](https://pub.dev/packages/build_runner) and translates
idiomatic Flutter widget source (annotated source classes and hand-authored
`.rfwtxt` files) into the `.rfwtxt` / `.rfw` artifacts and catalogs the SDK
runtime consumes.

Restage is server-driven UI for Flutter: a surface is authored in standard
Flutter syntax, compiled to a
[Remote Flutter Widget (RFW)](https://pub.dev/packages/rfw) blob, and delivered
to the app at runtime. This package is the source ->
blob half of that pipeline for surfaces authored as Dart. The same machinery
serves every surface type (paywalls, onboarding, in-app messages, surveys, or
any other surface), not one in particular.

You author in ordinary Flutter idioms, not a helper vocabulary or shim widgets. The generator
lowers a broad set faithfully (`Text.rich`, `Theme.of(context)`, `Navigator.push`,
`showModalBottomSheet`, `PageView`, `NumberFormat`, structured style values, the selection controls,
and pure-composition custom widgets) and fails loudly at build time on anything it can't represent,
never a silent partial render.

> **Emitting a genui A2UI catalog from your widgets?**
> The same generator projects a [genui](https://pub.dev/packages/genui) **A2UI**
> catalog from your `@RestageWidget` source. Follow the **[step-by-step A2UI
> walkthrough](https://pub.dev/packages/restage_a2ui#generate-an-a2ui-catalog-from-your-widgets--step-by-step)**.
> It covers the dependencies, the `build.yaml` setting, and the build command,
> with a worked example.

## How it's wired

You don't import this package's library API in app code. It is a set of
`build_runner` builders, declared in `build.yaml` and applied automatically to
dependents (`auto_apply: dependents`). You add it as a `dev_dependency` and run
`dart run build_runner build`; the builders pick up the right inputs by file
location and write their outputs alongside them.

The builders are:

- **`restageCodegenBuilder`** translates a surface authored as Flutter source
  (an annotated class) or as a hand-authored `.rfwtxt` under `lib/paywalls/`
  into the `.rfwtxt` + `.rfw` blob, a capability manifest, and a navigation
  plan.
- **`paywallFlowBuilder`** emits the declarative flow document for a
  surface whose source navigates across more than one screen.
- **`onboardingScreenBuilder`** translates an onboarding screen source into
  a typed screen descriptor (`.rsscreen.g.dart`) plus its `.rfwtxt` / `.rfw`
  blob and capability manifest.
- **`onboardingFlowBuilder`** emits the typed flow descriptor
  (`.rsflow.g.dart`) and flow document for a multi-screen flow.
- **`userCatalogBuilder`** walks a package for `@RestageWidget`-annotated
  classes and emits a single aggregated customer catalog.
- **`userA2uiCatalogBuilder`** is the opt-in A2UI target. It emits generated
  genui `CatalogItem`s and a standalone catalog document from the same
  annotated customer widgets.
- **`widgetbookStoryBuilder`** is the opt-in Widgetbook v4 target. It emits
  ordinary `*.stories.dart` source from those customer widgets; Widgetbook's
  bundled generator owns generated story plumbing, discovery, and UI.

(Two further internal builders register catalog factory functions and the
customer's widget factories for the runtime; these support the SDK's own
packages.)

## What it produces

From a single surface source, the generator emits:

- **`.rfwtxt`**: the human-readable Remote Flutter Widget text form.
- **`.rfw`**: the compiled binary blob the SDK runtime decodes and renders.
- **A capability manifest** (`.capability.json`): the capability floor the
  blob declares, so an older reader fails closed rather than misrendering.
- **A flow document / navigation plan**: the declarative multi-screen
  topology, for surfaces that move between screens.
- **Generated Dart descriptors**: typed screen/flow accessors for
  onboarding-style flows.

The OTA/runtime wire artifacts it emits contain only inert data: references
and literal values, never executable code. Generated Dart descriptors and
Widgetbook stories are ordinary build-time source. The widget capability set
and event handlers ship in your app release.

The generator transpiles standard Flutter widget trees, decomposes structured
Flutter types (`TextStyle`, `ButtonStyle`, `EdgeInsets`, `BoxDecoration`,
border radii, gradients, and others), folds constants, lowers theme reads to
declarative theme bindings, and derives the capability manifest from the
widgets a surface actually references.

It also has an **A2UI emit target**: from annotated Flutter widgets it projects
a content-addressed A2UI (genui) catalog with typed literal constraints, nested
data documentation, and controlled value sources. RFW remains Restage's native
delivery wire; the A2UI projection is
an additional, optional emit target. For the full opt-in setup, see the
[step-by-step A2UI walkthrough](https://pub.dev/packages/restage_a2ui#generate-an-a2ui-catalog-from-your-widgets--step-by-step).

It can also emit **Widgetbook v4 story source** for the same customer widget
catalog. Constructor inputs and Dartdoc are sufficient for one deterministic
native story; no Restage story sidecar or second build command is involved.
Enable `restage_codegen:widgetbook_stories` in `build.yaml`, keep Widgetbook's
ordinary `runWidgetbook(Config(...))` bootstrap, and run the normal
`build_runner` invocation. Restage does not generate stories for Flutter,
Material, Cupertino, or Restage built-ins.

Builder configuration selects targets for the package. An exceptional
`@RestageWidget` can opt out of one selected target with that target's
`Config(enabled: false)` or `Config.enabled(false)` annotation. Bare `@ignore`
still omits one safely omissible constructor input from every target;
`@Ignore({EmitTarget.a2ui, EmitTarget.widgetbook})`, for example, narrows the
omission to those targets without removing the property from RFW.

In watch mode, adding or removing another `@RestageWidget` in a file that
already contains one may require restarting `dart run build_runner watch` so
the package-wide story output is rescanned. The initial release does not claim
complete asset-graph invalidation for that annotation-set change. A normal
`dart run build_runner build` performs the complete scan.

## License

Licensed under the Functional Source License, Version 1.1, ALv2 Future License
(FSL-1.1-ALv2): free for all use except building a competing product; each
release automatically becomes Apache-2.0 two years after publication. See
[`LICENSE`](LICENSE) for the full terms.
