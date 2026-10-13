# A2UI and Widgetbook integration

Write the Flutter widget first. Its constructor, defaults and annotations feed
the generators; the widget implementation is compiled into each consuming app.
Restage delivery, GenUI and Widgetbook then use separate outputs from that source.

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
4. Compile and run the consuming app. Widgetbook previews and GenUI catalogs work
   before any Restage upload or publication. Upload and publish only when using
   Restage's hosted delivery workflow.

| Consumer | Generated output | Next step |
| --- | --- | --- |
| Restage SDK | Generated `*Surface` mounts, catalog/factories and publication artifacts | Mount locally with compiled fallback; build and publish for OTA delivery |
| Flutter GenUI | `lib/generated/restage_a2ui_catalog.g.dart` and `.restage/build/a2ui/restage_a2ui_catalog.a2ui.json` | Register the catalog with GenUI and give its schema to the payload producer |
| Widgetbook | Per-class `restage.generated/*.stories.dart`, generated parts and `lib/components.g.dart` | Pass `components` to the workbench |

Local GenUI and Widgetbook previews need no `restage build push`. Restage Cloud's
[dashboard preview builds](setup-and-delivery.md#dashboard-preview-builds) are
a separate workflow. A preview build neither updates installed apps nor
activates a surface.

These are parallel consumers. Widgetbook does not generate the A2UI catalog,
and GenUI does not render Restage's RFW artifacts. Leave `bundled_runtime` at its
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
| A2UI | `genui: ^0.10.1`, `restage_a2ui: ^0.2.0`, `json_schema_builder: ^0.1.3`; `a2ui_core: ^0.1.0` for message handling |
| Widgetbook | `widgetbook: 4.0.0-beta.14`, which includes its generator |

Check the consumer's resolved versions before changing these APIs. Import
`package:restage/a2ui.dart` as `a2ui` and
`package:restage/widgetbook.dart` as `wb` for target-specific annotations.

## Connect the catalog to GenUI

`buildRestageCatalog()` returns a GenUI `Catalog` with generated item schemas,
widget builders and prompt guidance. The portable JSON contains `a2uiCatalog`
and available `restageCapability` metadata. Give the producer the catalog schema
and require the same `restageA2uiCatalogId` in its `createSurface` messages.

The catalog contains custom widgets and annotated screens. A screen is one native
component, not its decomposed Flutter tree. Built-in Flutter, Material and
Cupertino catalogs are separate. Constructor inputs live under `props`; child
inputs reference other component IDs.

After validating and unwrapping incoming messages, the GenUI connection is:

<!-- skill-check: skip needs the optional GenUI packages and emitter output -->
```dart
import 'package:a2ui_core/a2ui_core.dart' show A2uiMessage;
import 'package:flutter/widgets.dart';
import 'package:genui/genui.dart' as genui;

import 'generated/restage_a2ui_catalog.g.dart';

final catalog = buildRestageCatalog();
final controller = genui.SurfaceController(catalogs: [catalog]);

void receiveMessage(Map<String, Object?> message) {
  controller.handleMessage(A2uiMessage.fromJson(message));
}

Widget buildSurface(String surfaceId) =>
    genui.Surface(surfaceContext: controller.contextFor(surfaceId));
```

Own the controller in the app's widget or session and dispose it when that owner
ends. GenUI 0.10.1 uses `v0.9` message envelopes; the generated catalog's schema
metadata says `0.9.1`. They are different fields.

For a model conversation, GenUI's `PromptBuilder.chat(catalog: catalog)` builds
the prompt, including `@a2ui.Config.usage(...)` guidance. GenUI's `Conversation`
connects the controller to a transport such as `A2uiTransportAdapter`. The app
supplies the model connection, incoming messages and action handling; Restage's
emitter does not host or stream a model session.

Preserve the generated catalog ID for its exact item/schema set. To combine
`buildRestageCatalogItems()` with other items, assign the combined catalog a new
application-owned ID and give the producer the combined contract. Predefined
A2A catalog negotiation requires the server to register that exact catalog;
serializing an inline catalog alone does not establish server support.

For cached or externally produced payloads, optionally gate rendering with
`RestageA2uiPreRenderCheck` from `package:restage_a2ui/restage_a2ui.dart`. Pass the
same catalog and `restageA2uiCapability.installedCapability`. The check rejects
unknown components and unmet stamped capability requirements. A cached
`RestageA2uiSidecar` wraps the payload's required capabilities and `a2ui` messages;
check it before unwrapping. The generated catalog JSON describes available
capabilities and is not that payload sidecar. This check does not validate every
component field; handle GenUI parsing and rendering errors too.

Value/callback pairs can bind to GenUI's data model. Use
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
when the same source also serves Restage surfaces; a successful GenUI or
Widgetbook preview does not prove OTA rendering or host actions work.
