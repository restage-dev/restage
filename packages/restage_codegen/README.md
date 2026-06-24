# restage_codegen

[![pub package](https://img.shields.io/pub/v/restage_codegen.svg)](https://pub.dev/packages/restage_codegen) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue.svg)](LICENSE)

The build-time code generator for the Restage SDK. It runs under
[`build_runner`](https://pub.dev/packages/build_runner) and translates
idiomatic Flutter widget source — annotated source classes and hand-authored
`.rfwtxt` files — into the `.rfwtxt` / `.rfw` artifacts and catalogs the SDK
runtime consumes.

Restage is server-driven UI for Flutter: a surface is authored in standard
Flutter syntax (or in the web editor), compiled to a
[Remote Flutter Widget (RFW)](https://pub.dev/packages/rfw) blob, and delivered
to the app at runtime. This package is the source ->
blob half of that pipeline for surfaces authored as Dart. The same machinery
serves every surface type — paywalls, onboarding, in-app messages, surveys, or
any other surface — not one in particular.

## How it's wired

You do not import this package's library API in app code. It is a set of
`build_runner` builders, declared in `build.yaml` and applied automatically to
dependents (`auto_apply: dependents`). You add it as a `dev_dependency` and run
`dart run build_runner build`; the builders pick up the right inputs by file
location and write their outputs alongside them.

The builders are:

- **`restageCodegenBuilder`** — translates a surface authored as Flutter source
  (an annotated class) or as a hand-authored `.rfwtxt` under `lib/paywalls/`
  into the `.rfwtxt` + `.rfw` blob, a capability manifest, and a navigation
  plan.
- **`paywallFlowBuilder`** — emits the declarative flow document for a
  surface whose source navigates across more than one screen.
- **`onboardingScreenBuilder`** — translates an onboarding screen source into
  a typed screen descriptor (`.rsscreen.g.dart`) plus its `.rfwtxt` / `.rfw`
  blob and capability manifest.
- **`onboardingFlowBuilder`** — emits the typed flow descriptor
  (`.rsflow.g.dart`) and flow document for a multi-screen flow.
- **`userCatalogBuilder`** — walks a package for `@RestageWidget`-annotated
  classes and emits a single aggregated customer catalog.

(Two further internal builders register catalog factory functions and the
customer's widget factories for the runtime; these support the SDK's own
packages.)

## What it produces

From a single surface source, the generator emits:

- **`.rfwtxt`** — the human-readable Remote Flutter Widget text form.
- **`.rfw`** — the compiled binary blob the SDK runtime decodes and renders.
- **A capability manifest** (`.capability.json`) — the capability floor the
  blob declares, so an older reader fails closed rather than misrendering.
- **A flow document / navigation plan** — the declarative multi-screen
  topology, for surfaces that move between screens.
- **Generated Dart descriptors** — typed screen/flow accessors for
  onboarding-style flows.

The generator transpiles standard Flutter widget trees, decomposes structured
Flutter types (`TextStyle`, `ButtonStyle`, `EdgeInsets`, `BoxDecoration`,
border radii, gradients, and others), folds constants, lowers theme reads to
declarative theme bindings, and derives the capability manifest from the
widgets a surface actually references.

It also has an **A2UI emit target**: from the same Flutter source it lowers to
RFW, it can project a versioned A2UI (genui) catalog carrying the same
capability contract. RFW remains the delivery wire; the A2UI projection is an
additional, optional emit target.

## License

Licensed under the Functional Source License, Version 1.1, ALv2 Future License
(FSL-1.1-ALv2): free for all use except building a competing product; each
release automatically becomes Apache-2.0 two years after publication. See
[`LICENSE`](LICENSE) for the full terms.
