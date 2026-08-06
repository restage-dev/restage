# Changelog

## 1.3.0

- Give generated A2UI catalogs a deterministic content-derived catalog ID and
  carry that same identity through the generated Dart and standalone document.
- Project typed constraints onto literal schema arms, preserve controlled
  literal, path, and call value sources, and keep application-side runtime
  validation responsible for resolved values.
- Preserve nested structured-data descriptions and emit deterministic
  definition/reference documentation.
- Validate canonical `@RestageA2uiExample` sidecars and emit an ordered neutral
  example registry alongside genui `CatalogItem.exampleData` callbacks.

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
  logged exclusion) — it renders via the A2UI emit target; native (RFW) rendering of custom structured data
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
