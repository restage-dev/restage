# Restage + Widgetbook v4 example

This public example package compiles one customer authoring model into a
Restage RFW catalog, a customer-only A2UI catalog, and a Widgetbook v4
workbench. It is checked in as an executable example and is not published to
pub.dev.

## Authoring ladder

The examples progress from plain Flutter to the complete multi-target
screen flow:

1. `OpaqueScreenProof.build` is plain Flutter composition. Built-in Flutter
   widgets need no Restage annotation.
2. `BareCatalogCard` uses only `@RestageWidget()`. Its class name, exact export
   ownership, absent category, constructor inputs/defaults, and Dartdoc supply
   the catalog facts.
3. `CatalogShowcase` adds typed `wb.Config.allValues()` declarations to real
   bool and enum fields. The generated `RestageCatalog`, `EnabledFalse`, and
   `StatusProcessing` stories build the real class. Its `hero`, `details`, and
   `footer` inputs prove several arbitrary child-bearing names on one widget,
   with no slot annotation.
4. The same `CatalogShowcase` uses useful `a2ui.Config` producer guidance and
   write-back selection. Every customer A2UI component keeps `id` and
   `component` on the protocol envelope and nests exact constructor inputs
   under required `props`. RFW callback events remain automatic from supported
   constructor callback signatures, so the example configures no RFW-specific
   behavior.
5. `OpaqueScreenProof` uses the canonical `@Screen` declaration. One build keeps
   the RFW descriptor/text/binary/capability artifacts, adds an exact-ID opaque
   A2UI item, and adds a native Widgetbook story. The generated story is grouped
   at `Screens/opaque_screen_proof` in this example.

The full sources live under `lib/widgets/` and
`lib/onboarding/screens/opaque_screen_proof.dart`. They carry `#docregion`
markers so documentation can quote them from source rather than copy them.

Those paths describe this example's layout only. The canonical annotation and
generated metadata own surface category and identity.

## What one build produces

Run from this package:

```sh
dart run build_runner build
```

That one normal invocation produces or updates:

- RFW customer catalog/factory output and the screen descriptor, `.rfwtxt`,
  `.rfw`, and `.capability.json` artifacts;
- `lib/generated/restage_a2ui_catalog.g.dart` and
  `lib/generated/restage_a2ui_catalog.a2ui.json`;
- one Widgetbook `*.stories.dart` input per admitted customer widget or screen,
  Widgetbook's matching `*.stories.g.dart` plumbing, and
  `lib/components.g.dart`.

One build produces every target's output; there is no second pass and no
hand-written story. The screen story installs `RestageEventDispatcher` through
the generated `Defaults.setup`, which Widgetbook's generated `Story.setup`
forwards, so no `Config.appBuilder` is needed.

The A2UI catalog covers your own widgets only. Flutter, Material, Cupertino,
and Restage built-ins are not registered, and a screen appears as one opaque
component rather than a lowered widget tree.

## Build the workbench

```sh
cd ../../apps/widgetbook_example
flutter build web --no-tree-shake-icons
```

The flag is required because the Restage runtime constructs icon data from
runtime values.

## Watch mode

Edits to an already-known customer widget or screen regenerate its native A2UI
and Widgetbook outputs live in `build_runner watch`. Adding, removing, or
renaming an annotated class changes native generated output-file membership;
restart the watcher after that change. The next cold run cleans orphaned story
source, generated plumbing, and component registration. Multiple
`@RestageWidget` classes and canonical `@Screen` declarations may share a Dart
file. A generated Restage descriptor part, when present, is build plumbing for
the Restage output.

## Version

This example uses `widgetbook` 4.0.0-beta.10 and its bundled generator.
