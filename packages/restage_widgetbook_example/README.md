# Restage + Widgetbook v4 example

One set of annotated Flutter widgets and one annotated screen, built into three
outputs: a Restage catalog, an A2UI catalog, and a Widgetbook workbench. This
package is an example you run from source; it is not published to pub.dev.

Part of [Restage](https://restage.dev), server-driven UI for Flutter.

## What each example shows

The examples go from plain Flutter to a screen that feeds every output:

1. `GetStartedScreen.build` is plain Flutter. Built-in Flutter widgets need
   no Restage annotation.
2. `BareCatalogCard` has only `@RestageWidget()`. Its class name, constructor
   inputs and defaults, and doc comment supply everything the catalog needs.
3. `CatalogShowcase` adds `wb.Config.allValues()` to a `bool` and an `enum`
   field, so the build generates a Widgetbook story for each value. Its `hero`,
   `details`, and `footer` inputs show that a widget can take several child
   widgets under any names, with no slot annotation.
4. The same `CatalogShowcase` adds `a2ui.Config` guidance for the model and
   picks which value the A2UI component writes back. Restage events come from
   the constructor's callback types, so there is nothing Restage-specific to
   configure.
5. `GetStartedScreen` is a `@Screen`. One build produces its Restage screen
   artifacts, adds it to the A2UI catalog as a single component, and adds a
   Widgetbook story for it.

The sources live under `lib/widgets/` and in
`lib/onboarding/screens/get_started_screen.dart`. Folder names don't matter;
the annotations decide what each widget or screen is.

## What one build produces

Run from this package:

```sh
dart run build_runner build
```

That one command produces:

- the Restage custom-widget catalog and factories, plus the screen's compiled
  artifacts;
- the A2UI catalog: `lib/generated/restage_a2ui_catalog.g.dart`, and
  `.restage/build/a2ui/restage_a2ui_catalog.a2ui.json` for payload producers;
- one Widgetbook story file per custom widget or screen, and
  `lib/components.g.dart`.

You don't write any stories by hand. Stories come with Restage's event
handling already set up, so you don't need a custom `appBuilder`.

The A2UI catalog covers your own widgets only. Flutter, Material, Cupertino,
and Restage built-ins are not in it, and a screen appears as one component
rather than as its widget tree.

## Build the workbench

The workbench app is in `apps/widgetbook_example`:

```sh
cd ../../apps/widgetbook_example
flutter build web --no-tree-shake-icons
```

The flag is needed because the workbench includes the RFW runtime, which
builds icons from runtime values.

## Watch mode

- `build_runner watch` regenerates the A2UI and Widgetbook output when you edit
  an existing widget or screen.
- After you add, remove, or rename an annotated class, restart the watcher. The
  next full build removes stale story files.
- Several annotated widgets and screens can share one Dart file.

## Version

This example uses `widgetbook` 4.0.0-beta.14 and its bundled generator.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
