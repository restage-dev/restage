# Restage + Widgetbook v4 example

This public example package compiles one customer authoring model into a
Restage RFW catalog, a customer-only A2UI catalog, and a Widgetbook v4
workbench. It is checked in as an executable example and is not published to
pub.dev.

## Authoring ladder

The examples progress from ordinary Flutter to the complete multi-target
screen flow:

1. `OpaqueScreenProof.build` is ordinary Flutter composition. Built-in Flutter
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
   constructor callback signatures; `rfw.Config` is currently an empty marker,
   so the example does not present it as behavior configuration.
5. `OpaqueScreenProof` proves the complete `ScreenSource` path. One build keeps
   the established RFW descriptor/text/binary/capability artifacts, adds an
   exact-ID opaque A2UI item, and adds a native Widgetbook story at
   `Screens/opaque_screen_proof`.

The full sources live under `lib/widgets/` and
`lib/onboarding/screens/opaque_screen_proof.dart`. Documentation snippets are
extracted from those compiled files, so a snippet cannot drift from code that
builds.

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

There is no target-specific second pass, hand-written story, scenario sidecar,
or customer host. The screen story places `RestageSurfaceEventDispatcher` in
generated `Defaults.setup`; Widgetbook's generated `Story.setup` forwards it.
No customer `Config.appBuilder` is required.

A2UI output is customer-only. It does not register Flutter, Material,
Cupertino, or Restage built-ins, and it treats a screen as an opaque native
component rather than lowering its Flutter tree. `FlowSource` and
`PaywallSource` do not receive native sibling projections. RFW continues to use
only its existing blueprint/state/event source surface and gains no constructor
binding from this integration.

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
`@RestageWidget` classes may share a file. `ScreenSource` additionally follows
RFW's existing surface-kind screen directory, ID/file-stem, generated-part, and
exactly-one-source-per-input-library boundaries; invalid topology emits no
native sibling. Changing that topology is a separate compiler follow-up.

## Version

This example uses `widgetbook` 4.0.0-beta.10 and its bundled generator.
