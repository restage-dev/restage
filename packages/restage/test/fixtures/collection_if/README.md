`filtered_rows.rfw` is compiled from the `filtered_rows.dart` surface in
`restage_codegen/test/fixtures/measurement_item_identity`. The compiler test checks
its exact bytes; the SDK test renders them and verifies filtering and item events.

To regenerate from `packages/restage_codegen`:

```sh
REGEN_COLLECTION_IF_FIXTURE=1 dart test test/measurement/measurement_item_identity_fixture_test.dart
```
