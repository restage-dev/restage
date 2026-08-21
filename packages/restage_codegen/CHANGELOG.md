# Changelog

## 2.0.0

**Breaking: one generated handle per annotated class.** The build now emits a
single top-level `<className>Ref` for every annotated screen and flow, instead
of two different shapes depending on which frontend produced it.

| Source | Handle | Type |
|---|---|---|
| `@Screen(id:, surface:)` on `WelcomeScreen` | `welcomeScreenRef` | `SurfaceScreenRef<WelcomeScreenEvent>` |
| `@Screen()` on `QuestionScreen` | `questionScreenRef` | `NeutralFlowScreenRef` |
| `@FlowGraph(surface:)` on `FirstRunFlow` | `firstRunFlowRef` | `SurfaceFlowRef<FirstRunResult>` |

For neutral `@Screen()` screens and for flows, the previous
`<ClassName>Descriptor` holder is still emitted as a `@Deprecated` alias whose
`ref` forwards to the new handle, so existing source compiles through 2.x. It
is removed at 3.0.

A **categorized** `@Screen(surface:)` is the exception: its holder is deleted
outright rather than deprecated, because the reference it carried was the
in-flow neutral one described below, which a categorized screen no longer
generates at all.

A flow's `buildFlow()` accepts either spelling for its screen references
(`welcomeScreenRef` or the deprecated `WelcomeScreenDescriptor.ref`), and both
resolve to the same screen.

A categorized `@Screen(surface:)` no longer emits an in-flow neutral
reference; a screen used as a flow step is a neutral `@Screen()`.

The authored flow base class the compiler recognises is unchanged:
`RestageFlow`. A source that extends the host widget `RestageFlowGraph` by
mistake is already an analyzer error (the widget is a `final class`); the
compiler detects that supertype specifically to say which class was wanted.

Generated Dart changes; generated delivery artifacts do not.

### Also in 2.0.0

This section records the package side of a coordinated breaking release. The
release version and publication timing are assigned separately.

- Each generated output roster entry records the condition under which its
  path is written: for every lowering of its source, or only when the lowering
  produces one particular thing. Paths are reserved before the translator
  decides what a source lowers to, so this is how a consumer of the ledger
  tells which reservations are written together. Only paywall reservations are
  conditional; every screen and flow reservation is written for every lowering.
  The roster remains an output-ownership ledger, and the publication manifest
  remains the produced-output truth.
- Derive customer catalog properties, requiredness, order, constructor defaults,
  and descriptions from resolved constructor/Dartdoc facts across RFW, A2UI,
  and Widgetbook.
- Derive callback admission from resolved constructor shape: void return with
  zero arguments or one required positional payload in the target vocabulary.
  The exact callback property name is the event identity; no event declaration
  or rename annotation is used.
- Resolve only the sources that can declare something. All seven builders
  that scan a whole package (the five applied automatically, plus the A2UI
  catalog and Widgetbook story builders you opt into) now read raw source
  first and resolve just the files spelling a Restage annotation, so a package
  that declares nothing pays no analysis for them, the difference that matters
  on large codebases, where resolving every file also made every builder depend
  on every file. What you write is discovered as before: an annotation written
  on the declaration, behind an import prefix, in a `part`, or through a
  `const` or `typedef` alias declared in another file in the same package all
  reach the same place they always did. An alias declared in a *different*
  package is the one shape that is not followed: these builders scan only the
  package they are building, so they never see that declaration.
- A syntax error in a file that spells no Restage annotation is no longer
  reported by these builders. They no longer analyse such files; the Dart
  toolchain reports the error either way. The deprecated screen path
  `lib/<onboarding|message|survey>/screens/<id>.dart` keeps its diagnostics:
  the per-file screen builders still analyse a library there annotated or not,
  and the two opt-in package-wide builders still select it.
- Write the two roster ledger files into a package only once it declares a
  Restage source, or reports a problem with one, instead of into every
  dependent.
- Decode the surface publication compiler handoff once per package per build
  rather than once per Dart library.
- Consume `a2ui.Config` usage/write-back metadata.
- Generate ordinary native Widgetbook v4 story source for customer widgets in
  the same `build_runner` invocation, including customer structured values and
  read-only `description`/`usage` sidebar metadata.
- Emit the A2UI Dart catalog and standalone document together under
  `lib/generated/`, with no root-level compatibility aliases.
- Derive every customer `Widget` and `List<Widget>` constructor input as an
  independently named child-bearing property across the RFW, A2UI, and
  Widgetbook targets; several exact names may coexist on one class.
- **Breaking generated A2UI layout:** nest every customer widget and opaque
  native-screen constructor input under one required `props` object while
  leaving protocol `id` and `component` on the envelope. Exact source names,
  including envelope-collision names, are preserved without aliases.
- Share one analyzer-backed `ScreenSource` admission contract between RFW and
  native A2UI/Widgetbook siblings; invalid path, ID, part, or source count fails
  before any sibling output is written.
- Let one `@RestageWidget` opt out of selected package-enabled targets and let
  one safely omissible constructor input use `@Ignore` for selected targets,
  without suppressing diagnostics or properties in its siblings.
- Fix `paywallPriceFor(productId: ...)` for real store ids: a product key that
  is not a bare identifier (a reverse-DNS id such as `com.example.pro.annual`,
  an all-digit id, or one containing a hyphen or space) is now emitted as a
  quoted reference part, so it stays a single key instead of splitting at each
  dot, decoding as an integer, or failing to parse. Identifier-shaped keys and
  slots are unchanged, so any output that previously parsed is byte-for-byte
  identical. A blank key is now rejected with a diagnostic naming the helper.

## 1.3.0

- Give generated A2UI catalogs a deterministic content-derived catalog ID and
  carry that same identity through the generated Dart and standalone document.
- Project typed constraints onto literal schema arms, preserve controlled
  literal, path, and call value sources, and keep application-side runtime
  validation responsible for resolved values.
- Preserve nested structured-data descriptions and emit deterministic
  definition/reference documentation.
- Generate native Widgetbook v4 story inputs for customer `@RestageWidget`s
  during the ordinary `build_runner` invocation, without auxiliary authoring.

## 1.2.0

- Compile customer `@RestageWidget` code into a standalone A2UI catalog: the
  customer-only builder emits an A2UI document + generated Dart for the app's
  own widgets, alongside the built-in catalog.
- Carry producer-facing metadata into generated A2UI catalogs: widget and
  property descriptions, plus the new optional `usage` steering text, emit
  into the document's system-prompt fragments.
- Support general-delivery flows:
  `@FlowSource(delivery: FlowDeliveryMode.general)` generates flows with
  untyped `Map` results, checked by build-time validators.
- Add message and survey screen/flow builders: flow and screen codegen is now
  surface-parameterized, so message and survey surfaces reuse the onboarding
  builders.
- Encode opaque lists of structured values in the customer catalog (pairs
  with `rfw_catalog_schema` 1.1.0 / `rfw_catalog_compiler` 1.1.0).

## 1.1.0

- Emit the customer widget catalog (`catalog.json`) so registered custom widgets resolve in authored surfaces.
- Additive codegen support for upcoming surface work; no breaking changes.

## 1.0.4

- Carry each component's full data schema in the standalone A2UI catalog document, not only the
  component discriminator, so a consumer reading the document alone (without the generated Dart) sees
  every component's fields and can generate rich payloads against it.
- Suppress `unused_element` in the generated A2UI catalog so a catalog that references only some of the
  shared helpers analyzes clean in the consumer's project.

## 1.0.3

- Emit a rich A2UI catalog for a customer `@RestageWidget` whose property is typed as a data class: nested
  data classes, lists of objects, String-keyed maps, and named records each generate a `genui` schema that
  reconstructs and renders the value, with a fail-safe on a missing required value.
- Infer a structured property's required-ness from the widget's default constructor, so a value the
  constructor requires is marked required even when the annotation omits it.
- Exclude a customer widget carrying a structured property from the RFW catalog/factory build (a non-fatal,
  logged exclusion); it renders via the A2UI emit target; native (RFW) rendering of custom structured data
  is a tracked future capability.

## 1.0.2

- Lower the `analyzer` ceiling to `>=10.0.0 <13.0.0`. `NamedExpression` was
  removed and `ArgumentList.arguments` changed to `NodeList<Argument>` in
  analyzer 13.0.0 (not 14.0.0 as the 1.0.1 note stated), so the previous
  `<14.0.0` constraint admitted analyzer 13.x, which this package's
  argument-list lowering does not compile against. The `build_runner`
  toolchain resolves analyzer 12.x anyway, so this matches what consumers
  actually use.

## 1.0.1

- Widen the `analyzer` dependency constraint to `>=10.0.0 <14.0.0`: raise the
  floor to a verified-compiling version and admit analyzer 13.x. The ceiling
  stays below 14.0.0 because analyzer 14 removed `NamedExpression` and reshaped
  argument lists, which this package's lowering relies on; the `build_runner`
  toolchain (`build`) likewise does not yet support analyzer 14.
- Add an example.

## 1.0.0

- Initial release of the Restage build-time code generator: the `build_runner`
  builders that compile Flutter-authored surfaces (annotated source classes and
  hand-authored `.rfwtxt`) into `.rfwtxt` / `.rfw` blobs, capability manifests,
  flow documents, and generated screen/flow descriptors. Includes
  structured-type decomposition, constant folding, theme-binding lowering,
  capability derivation, and the optional A2UI (genui) emit target.
