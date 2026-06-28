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
