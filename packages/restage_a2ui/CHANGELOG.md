## Unreleased

- Accept constructor-derived customer properties and canonical
  `a2ui.Config` usage/write-back metadata from the coordinated catalog
  authoring release.
- Derive callback identity from the exact constructor property name; customer
  widgets no longer declare events through an RFW event list.
- **Migrate the A2UI integration to genui 0.10.1 and `a2ui_core`.** The A2UI
  message model relocated into `package:a2ui_core` (`CreateSurfaceMessage`,
  `UpdateComponentsMessage`, …); the A2UI wire is unchanged (still `v0.9`).
- genui 0.10.1 requires `json_schema_builder` 0.1.6 (a required transitive
  bump). 0.1.6 serializes the JSON-schema default `additionalProperties: true`
  explicitly on the runtime schema value — a runtime-only detail that does not
  reach the emitted catalog document. The bundled generated catalog and its
  content-derived `catalogId` are UNCHANGED.
- genui 0.10.1 performs full JSON-schema validation of components (a tightening
  over 0.9.2's enum-only checks). Validation is report-only and does not change
  the fail-closed pre-render check, which remains the authoritative gate.

## 0.1.6

- Update the bundled generated catalog and documentation for content-derived
  catalog identity, typed constraints, controlled values, nested data
  descriptions, and automatic customer-widget generation.
- Keep genui pinned to 0.9.2. The package runtime is unchanged.

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
  customer data class (nested data classes, lists of objects, String-keyed maps, named records) generates a
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
