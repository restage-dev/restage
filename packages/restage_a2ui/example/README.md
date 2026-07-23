# restage_a2ui example

This example shows the whole `@RestageWidget` → A2UI catalog loop end to end: it
compiles annotated Flutter widgets into a [`genui`](https://pub.dev/packages/genui)
A2UI catalog, then gates payloads against that catalog with `restage_a2ui`'s
app-side, fail-closed **pre-render check** *before* handing them to genui — so a
payload the build can't render faithfully fails with a clean diagnostic instead of
throwing mid-render.

## What it generates

Two custom widget libraries, authored as ordinary annotated Flutter widgets, are
compiled by the build-time toolchain into a single genui A2UI catalog — no
hand-written `CatalogItem`s, no hand-authored JSON schemas:

- **`acme.widgets` (capability version 2)** — `CtaButton`, `IntegerListPicker`,
  `ProductCard`, `RatingPicker`, and `ScalarListPanel`.
- **`acme.lessons` (capability version 1)** — `SectionHeader`, `Callout`, `ComparisonPanel`, `QuizCheck`.

The generated catalog contains exactly these widgets — it is your own widgets, not
Flutter built-ins. Each library carries its own capability version in the emitted
stamp. The two outputs (`restage_a2ui_catalog.g.dart` + `restage_a2ui_catalog.a2ui.json`)
are regenerated from the annotated source. Ten validated JSON sidecars provide
canonical examples for all nine components, including controlled values, nullable
lists, nested data, and child references. The example has no app entrypoint:

```bash
dart run build_runner build   # regenerate the catalog + stamp from the @RestageWidget source
flutter test                  # render the generated widgets through genui 0.10.1
```

The tests render the generated catalog through genui's real surface runtime and
prove the pre-render check rejects a payload that references a component the
catalog does not contain (fail-closed). See the [package README](../README.md) for
the full step-by-step generation walkthrough.

## Gate a payload before rendering

Build the check once (it is immutable — reuse it for every payload), then gate
each payload before render:

```dart
import 'package:genui/genui.dart';
import 'package:restage_a2ui/restage_a2ui.dart';

// The genui catalog your build emitted, and what it provides.
final catalog = buildRestageCatalog();
final installed = A2uiInstalledCapability.fromStampJson(restageCapability);

// One instance, reused for every payload.
final check = RestageA2uiPreRenderCheck(catalog: catalog, installed: installed);

Widget? renderCached(Map<String, Object?> payload) {
  switch (check.check(payload)) {
    case A2uiRenderable():
      return renderWithGenui(payload); // your genui render call
    case A2uiRejected(:final diagnostic):
      // Do NOT render — fall back to a built-in surface and log why.
      debugPrint('A2UI rejected: $diagnostic');
      return null;
  }
}
```

The check fails **closed** for a malformed Restage sidecar envelope, an unknown
component type in a well-formed `{id, component}` entry, an unmet version, or
an unverifiable stamped payload. It does not validate every inner A2UI
component shape; malformed entries can still fail when genui parses them.

See the [package README](../README.md) for the capability sidecar, the version
satisfaction rules, and how the catalog and stamp are produced.

## Guiding notes on the example widgets

`Callout` (`acme.lessons`) declares both a `description` and a
`@RestageWidget(usage:)` note; `SectionHeader` declares only a `description`. The
generated `_restageA2uiSystemPromptFragments` in `restage_a2ui_catalog.g.dart`
shows the result: `Callout` gets its own `usage` line, `SectionHeader` falls back
to its `description`, and `buildRestageCatalog()` (used above) hands both to genui
as `Catalog.systemPromptFragments` — your own words, not generated.
