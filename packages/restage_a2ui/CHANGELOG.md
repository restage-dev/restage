## Unreleased

- **Breaking, A2UI 1.0 migration:** generate
  `ComponentImplementation` / `CatalogImplementation` for
  `a2ui_flutter ^0.3.0` and `a2ui_core ^0.7.0` (Dart >=3.10.0,
  Flutter >=3.38.0, json_schema_builder >=0.1.7). Regenerate catalogs and
  migrate cached/producer inputs to generated top-level properties and dynamic
  `@path`/`@call`. Ordinary names retain `props_<DartName>`; names invalid under
  upstream UAX31 and the reserved `encoded_` source prefix use
  `props_encoded_<hex>` (four lowercase digits per UTF-16 code unit). Use the
  generated schema keys; Dart arguments and nested business-data keys stay exact,
  except that keys starting with `@` are written as `@@` on the wire.
- Messages carry the A2UI 1.0 wire version `"1.0"`; `"v1.0"` is rejected.
- Use standard catalog `instructions` and catalog-level rich definitions. Each
  component's definitions are flat catalog `$defs` entries named
  `<Component>.<Definition>`, such as `ProductCard.Money`.
  Manual composition must merge `buildRestageCatalogDefinitions()` with items
  and use a new ID. Invalid component type identifiers and reserved `Surface`
  fail generation with annotation guidance; native screen IDs remain exact.
- Reading the removed public `.catalog` field requires explicit selection from
  `.catalogs` (such as `.single` for a single-catalog host); this is manual.
- Replace the single `catalog` preflight argument with `catalogs` and ship a
  tested `dart fix` wrapping its expression in a list. Host API migration and
  regeneration remain manual. Validate complete v1 cached bundles, explicit
  catalog overrides, schemas and capability stamps without executing functions.
  A finished bundle with no surface, an empty surface, a missing root or a
  dangling child reference is rejected; the `{"messages": [...]}` wrapper is
  accepted. Pass the processor's `validationConfig` so each message is checked
  as the processor checks it.
- A nullable input with a declared default uses it when omitted or when its
  binding resolves to nothing, including after a user clears a bound value; a
  literal `null` stays `null`. Without a declared default it is `null`, as Dart
  gives an omitted nullable parameter. Literal and call write-back values
  inside a template are stored per row.
- `json_schema_builder` is now a dev dependency; apps that build generated
  catalogs declare it themselves.
- Qualify real MessageProcessor/A2uiSurface rendering, strict rejection before
  component commit, controlled write-back, rich data and arbitrary children.
  Strict validation rejects a component property the catalog doesn't declare.
  A component that declares no properties refuses any property, under every
  validation config. A payload-supplied action never replaces a compile-fixed
  one.
- The pre-render check rejects a component property the catalog doesn't
  declare, also when it is given no `validationConfig`.

## 0.2.0

- Accept constructor-derived custom properties and canonical
  `a2ui.Config` usage/write-back metadata.
- Derive callback identity from the exact constructor property name; custom
  widgets no longer declare events through an RFW event list.
- **Migrate the A2UI integration to genui 0.10.1 and `a2ui_core`.** The A2UI
  message model relocated into `package:a2ui_core` (`CreateSurfaceMessage`,
  `UpdateComponentsMessage`, …); the A2UI wire is unchanged (still `v0.9`).
- genui 0.10.1 requires `json_schema_builder` 0.1.6 (a required transitive
  bump). 0.1.6 serializes the JSON-schema default `additionalProperties: true`
  explicitly on the runtime schema value — a runtime-only detail that does not
  reach the emitted catalog document. The bundled generated catalog and its
  content-derived `catalogId` are unchanged.
- genui 0.10.1 performs full JSON-schema validation of components (a tightening
  over 0.9.2's enum-only checks). Validation is report-only and does not change
  the fail-closed pre-render check, which remains the authoritative gate.
- **Breaking generated payload layout:** custom widgets and opaque native
  screens now keep protocol `id`/`component` on the envelope and nest every
  exact constructor input under one required `props` object. Regenerate the
  catalog and migrate producer/cached fixtures together. The runtime
  pre-render-check API and A2UI v0.9.1 protocol version are unchanged.
- Expand the executable example with several arbitrary child-bearing input
  names on one component and real genui render coverage for the uniform
  `props` layout.
- Update the bundled generated catalog and documentation for content-derived
  catalog identity, typed constraints, controlled values, nested data
  descriptions, and automatic custom-widget generation.

## 0.1.5

- Document the producer-facing catalog metadata: widget and property
  descriptions, plus the new optional `usage` steering text, now emit into the
  generated catalog's system-prompt fragments, so a model reading the catalog
  on its own knows when to reach for each widget (see `restage_codegen` 1.2.0).
- Expand the bundled example with a second catalog (callout, comparison panel,
  quiz check, section header) and add render-proof tests that build every
  component against the real SDK.
- This package is unchanged at runtime.

## 0.1.4

- Documentation: README refresh.

## 0.1.3

- Update the catalog walkthrough to drop the removed `build_runner` `--delete-conflicting-outputs` flag.
- Regenerate the bundled example catalog so its standalone A2UI document carries each component's full
  data schema (see `restage_codegen` 1.0.4). This package is unchanged at runtime.

## 0.1.2

- Document the A2UI emit target's **rich structured data** support: a `@RestageWidget` property typed as a
  custom data class (nested data classes, lists of objects, String-keyed maps, named records) generates a
  rich `genui` schema that reconstructs and renders the value, with a fail-safe on a missing required value.
- Document the opt-in `build_runner` builder workflow that produces the generated catalog and the capability
  stamp from `@RestageWidget` source.
- This package is unchanged at runtime; the rich-data support is in the build-time toolchain
  (`restage_codegen`). Sealed-class unions and native (RFW) delivery of custom structured data are tracked
  future capabilities.

## 0.1.1

- Add a usage example.

## 0.1.0

- Initial release: the app-side A2UI pre-render capability check and the Restage capability sidecar for
  cached A2UI payloads.
