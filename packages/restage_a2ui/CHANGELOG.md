## 0.1.6

- Update the bundled generated catalog and documentation for content-derived
  catalog identity, typed constraints, controlled values, nested data
  descriptions, and canonical authored examples.
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
