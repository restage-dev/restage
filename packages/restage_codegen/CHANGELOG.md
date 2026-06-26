# Changelog

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
