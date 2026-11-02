# restage_a2ui example

This example shows the whole `@RestageWidget` → A2UI catalog loop end to end: it
compiles annotated Flutter widgets into a [`a2ui_flutter`](https://pub.dev/packages/a2ui_flutter)
A2UI catalog, then gates payloads against that catalog with `restage_a2ui`'s
app-side, fail-closed **pre-render check** *before* handing them to a2ui_flutter. The check rejects unknown components and unmet capability versions before
rendering; a2ui_flutter still validates each component’s fields.

> **Unreleased A2UI 1.0 candidate integration.** These instructions describe the
> repository/workspace packages, not the published `restage_a2ui 0.2.0` or
> `restage_codegen 2.0.0` releases. Use the repository example while qualifying
> the candidate. Upstream pins are `a2ui_flutter: 0.0.1-wip003` and
> `a2ui_core: ^0.4.0`, with Dart >=3.11.0, Flutter >=3.38.0 and
> `json_schema_builder` >=0.1.7. Recheck upstream and reconcile hosted package
> constraints before release; protocol 1.0 is not declared stable here.

## What it generates

Two custom widget libraries, authored as plain annotated Flutter widgets, are
compiled by the build-time toolchain into a single a2ui_flutter A2UI catalog. The build
writes the `ComponentImplementation`s and the JSON schemas for you:

- **`acme.widgets` (capability version 3)**: `CtaButton`, `IntegerListPicker`,
  `ProductCard`, `RatingPicker`, and `ScalarListPanel`.
- **`acme.lessons` (capability version 1)**: `SectionHeader`, `Callout`, `ComparisonPanel`, `QuizCheck`.

The generated catalog contains exactly these widgets, all of them your own. Each
library carries its own capability version in the emitted
stamp. The build writes the catalog to
`lib/generated/restage_a2ui_catalog.g.dart` and the stamp to
`.restage/build/a2ui/restage_a2ui_catalog.a2ui.json`, both from the annotated
source. A copy of the stamp is committed at
`lib/generated/restage_a2ui_catalog.a2ui.json` for the tests. The example has
no app entrypoint:

```bash
dart run build_runner build   # regenerate the catalog + stamp from the @RestageWidget source
cp .restage/build/a2ui/restage_a2ui_catalog.a2ui.json lib/generated/restage_a2ui_catalog.a2ui.json
flutter test test/full_surface_render_test.dart test/example_render_test.dart test/a2ui_v1_generated_document_test.dart
```

The tests render the generated catalog through a2ui_flutter's real surface runtime and
prove the pre-render check rejects a payload that references a component the
catalog does not contain (fail-closed). See the [package README](../README.md) for
the full step-by-step generation walkthrough.

The lesson surface also executes the generated custom payload convention:
protocol-owned `id` and `component` stay on the envelope, while each
ordinary constructor input has a top-level `props_<DartName>` name. Names that
fail upstream UAX31 validation or begin with `encoded_` use the reserved
`props_encoded_<hex>` form: four lowercase hex digits per UTF-16 code unit. Use
the generated schema keys, including encoded keys, when producing payloads;
Dart arguments and nested rich-data keys retain their original names.
`ComparisonPanel` proves three independently named child-bearing inputs (`introduction`, `examples`,
and `conclusion`) on one class, and `Callout.detail` proves that no input needs
to be named `child` or `children`.

```json
{
  "id": "root",
  "component": "ComparisonPanel",
  "props_heading": "Grammar showcase",
  "props_introduction": "header",
  "props_examples": ["callout", "quiz"],
  "props_conclusion": "summary"
}
```

The build output under `.restage/build/a2ui/` is the source for the committed
producer-document snapshot. The copy step above is intentional: a normal build
does not update `lib/generated/*.a2ui.json`. CI compares the two and the document
proof compares the snapshot with `buildRestageCatalog().toJson()` exactly.

The tests use real `MessageProcessor` / `A2uiSurface`, exercise write-back,
compile-fixed actions, rich constructors and arbitrary children, and reject
missing components before rendering. See the [package README](../README.md)
for complete-bundle preflight, manual catalog definitions, and Dart fix limits.

`Callout` supplies authored usage guidance; `SectionHeader` falls back to its
description. These appear in the standard catalog `instructions`.
