# A2UI and Widgetbook integration

Write the Flutter widget first. Its constructor, defaults and annotations feed
the generators; the widget implementation is compiled into each consuming app.
Restage delivery, A2UI and Widgetbook then use separate outputs from that source.

## Build once, then choose the consumer

1. Write and annotate the widgets and screens. Declare each custom widget's
   library as described in [custom-widgets.md](custom-widgets.md). Add concise
   Dartdoc to classes and their public input fields. Both emitters require
   descriptions for catalog inputs, including screen inputs;
   `@RestageProperty(description: ...)` is an alternative. Custom-widget class
   descriptions may instead use `@RestageWidget(description: ...)`.
2. Add the dependencies for the outputs you want and enable their builders in
   the package containing the annotated source.
3. Run `dart run build_runner build` there. Restage emits the catalog and stories;
   Widgetbook's generator processes the stories in the same build graph.
4. Compile and run the consuming app. Widgetbook previews and A2UI catalogs work
   before any Restage upload or publication. Upload and publish only when using
   Restage's hosted delivery workflow.

| Consumer | Generated output | Next step |
| --- | --- | --- |
| Restage SDK | Generated `*Surface` mounts, catalog/factories and publication artifacts | Mount locally with compiled fallback; build and publish for OTA delivery |
| Flutter A2UI | `lib/generated/restage_a2ui_catalog.g.dart` and `.restage/build/a2ui/restage_a2ui_catalog.a2ui.json` | Register the catalog with A2UI and give its schema to the payload producer |
| Widgetbook | Per-class `restage.generated/*.stories.dart`, generated parts and `lib/components.g.dart` | Pass `components` to the workbench |

Local A2UI and Widgetbook previews need no `restage build push`. Restage Cloud's
[dashboard preview builds](setup-and-delivery.md#dashboard-preview-builds) are
a separate workflow. A preview build neither updates installed apps nor
activates a surface.

These are parallel consumers. Widgetbook does not generate the A2UI catalog,
and A2UI does not render Restage's RFW artifacts. Leave `bundled_runtime` at its
default, `false`; neither optional emitter needs RFW assets in `pubspec.yaml`.

```yaml
targets:
  $default:
    builders:
      restage_codegen:user_a2ui_catalog:
        enabled: true
      restage_codegen:widgetbook_stories:
        enabled: true
```

Enable either builder independently. Keep `restage_codegen` and `build_runner`
as development dependencies. Each emitter validates its supported inputs, so
run the build with every emitter you intend to use. These integrations use:

| Output | Additional dependencies in the source package |
| --- | --- |
| A2UI | `a2ui_flutter: ^0.3.0`, `a2ui_core: ^0.7.0`, `json_schema_builder: ^0.1.7`, `restage_a2ui` and `restage_codegen` |
| Widgetbook | `widgetbook: 4.0.0-beta.14`, which includes its generator |

Check the consumer's resolved versions before changing these APIs. Import
`package:restage/a2ui.dart` as `a2ui` and
`package:restage/widgetbook.dart` as `wb` for target-specific annotations.

## Connect the catalog to A2UI

`buildRestageCatalog()` returns an A2UI `CatalogImplementation` with generated item schemas,
widget builders and prompt guidance. The portable JSON contains `a2uiCatalog`
and available `restageCapability` metadata. Give the producer the catalog schema
and require the same `restageA2uiCatalogId` in its `createSurface` messages.

The catalog contains custom widgets and annotated screens. A screen is one native
component, not its decomposed Flutter tree. Built-in Flutter, Material and
Cupertino catalogs are separate. Constructor inputs live at top-level properties;
child inputs reference other component IDs.

Ordinary constructor names use `props_<DartName>` when that name is a valid
upstream UAX31 identifier and the source name does not start with `encoded_`.
Other names, including `$value`, and all source names starting with `encoded_`
use `props_encoded_<hex>`. The hex concatenates the source name's UTF-16 code
units as exactly four lowercase digits each; `$value` becomes
`props_encoded_002400760061006c00750065`. Reserving `encoded_` prevents a normal
source name from colliding with an encoded name. Producers must use the property
keys in the generated catalog schema and instructions. Dart constructor arguments
and nested rich-data keys keep their original names. Nested rich-data keys that start with `@` are written as `@@` on the wire; the runtime unescapes them.

After validating and unwrapping incoming messages, the A2UI connection is:

<!-- skill-check: skip needs the optional A2UI packages and emitter output -->
```dart
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/widgets.dart';
import 'generated/restage_a2ui_catalog.g.dart';

final catalog = buildRestageCatalog();
final processor = MessageProcessor<ComponentImplementation>(
  catalogs: [catalog], defaultVersion: A2uiProtocolVersion.v1_0,
  validationConfig: ValidationConfig.strict,
);
void receiveMessage(Map<String, Object?> message) => processor.processMessages(message);
Widget buildSurface(String surfaceId) =>
    A2uiSurface(surface: processor.model.getSurface(surfaceId)!);
```

Dispose the processor with its owner. Messages use `version: '1.0'`; create
the surface before updating it, or supply inline components on creation.
The standard catalog's `instructions` carries authored usage guidance. Give the
producer that document; the application owns transport and action handling.

The A2UI output requires the upstream versions above, Dart >=3.11.0 and
Flutter >=3.38.0.

Manual composition must merge `buildRestageCatalogDefinitions()` alongside
`buildRestageCatalogItems()`, preserve instructions and assign a new ID for a
changed schema set. Component type names obey upstream UAX31 rules and cannot
be `Surface`. Resolve widget identities with `@RestageWidget(name: ...)` and
native screen identities with their explicit `id:`, which becomes the component
type name.

Component instance `id` values must also be UAX31 identifiers. Migrate producers
and cached payloads together, updating each renamed instance ID and all child
and template references to it. For example, change `callout-body` to
`callout_body` in the component declaration and every reference. The `Surface`
reservation applies to component type names, not instance IDs. This migration
is explicit; the runtime does not automatically alias identities or references.

For cached bundles, use `RestageA2uiPreRenderCheck(catalogs: [catalog],
installed: restageA2uiCapability.installedCapability, validationConfig: config)`
before unwrapping a Restage sidecar, with the processor's own `config`. It
validates complete v1 message bundles and catalog schemas without executing
functions, applies that config to each message, and requires the finished
bundle to render. `installed` describes the registered Restage capability set.

Run `dart fix --apply` for the expressible `catalog: x` → `catalogs: [x]` edit.
Regeneration, cached payload `props_`/`@path`/`@call` edits, and handwritten
GenUI host changes remain manual. Ordinary business-data keys stay unchanged.

Value/callback pairs can bind to A2UI's data model. Use
`a2ui.Config.writeBackValues` when pairing is ambiguous. Outward actions still
need app handlers. Test both rendering and the intended interaction.

## Connect the stories to Widgetbook

In the source package, a workbench entry point under `lib/` can use:

<!-- skill-check: skip needs the optional Widgetbook package and emitter output -->
```dart
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart' as widgetbook;

import 'components.g.dart';

void main() => widgetbook.runWidgetbook(
  widgetbook.Config(
    components: components,
    lightTheme: ThemeData.light(useMaterial3: true),
    darkTheme: ThemeData.dark(useMaterial3: true),
  ),
);
```

A separate workbench app depends on Widgetbook and the source package, then
imports that package's `components.g.dart`. Generate the source package before
running the workbench. No hand-written stories or custom `appBuilder` are needed
for the generated previews.

Stories expose supported scalar and enum controls. Constructor defaults are
preserved; complex values and child slots are not universal visual editors.
Use `@wb.Config.allValues()` or `values(...)` on bool/enum properties to add finite
states. Expansion is independent by default; use
`@wb.Config(expansion: wb.StoryExpansion.cartesian, maxStories: 12)` when the
combinations matter.

Screen stories capture Restage events in their generated `previewEvents` list.
Custom-widget callback previews use no-op closures unless a constructor supplies
a default. Test real app actions separately. Restart `build_runner watch` after
adding, removing or renaming annotated classes, and do not edit generated stories.

Both previews instantiate native Dart widgets. Verify delivered RFW separately
when the same source also serves Restage surfaces; a successful A2UI or
Widgetbook preview does not prove OTA rendering or host actions work.

Code reading the removed public `.catalog` field must choose explicitly from
`.catalogs` (for example, `.catalogs.single` when exactly one is registered).
The Dart fix does not choose a catalog for a multi-catalog host.
