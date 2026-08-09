# Restage + Widgetbook v4 example

This small design-system package uses one catalog annotation to produce the
Restage RFW catalog, an A2UI catalog, and a
[Widgetbook](https://pub.dev/packages/widgetbook) v4 workbench. It is part of
the public example set and is not published to pub.dev.

## What this shows

Each widget in `lib/widgets/` is annotated with `@RestageWidget`. Its unnamed
constructor defines the catalog inputs and Dartdoc supplies descriptions;
`@RestageProperty` appears only where a shared default or other overlay is
needed. The package enables
`restage_codegen:widgetbook_stories` in `build.yaml`, so one build produces:

- the Restage catalog and registration sources;
- the A2UI Dart catalog and JSON registration artifact;
- one Widgetbook v4 `*.stories.dart` file per annotated widget, plus its
  Widgetbook-generated `*.stories.g.dart` part; and
- `lib/components.g.dart`, the generated list of all story components.

The generated story files are ordinary Widgetbook v4 input. Widgetbook's bundled
generator reads them and the thin app in `apps/widgetbook_example/` passes the
resulting `components` list to `runWidgetbook(Config(...))`.

`CatalogShowcase` demonstrates bool/enum/callback, `Widget`, `List<Widget>`, and a
customer structured value through all three targets. Its RFW and A2UI config
annotations remain beside the widget; there is no Widgetbook-specific
annotation or hand-written story.

Literal defaults on a few smaller example properties let those widgets render
a useful default story without a separate hand-written use case. `PriceBadge`
keeps the explicit description and requiredness spelling accepted by earlier
Restage versions to demonstrate backward compatibility.

## Generate and run

Generate from this package:

```sh
dart run build_runner build
```

Then build the workbench app for web:

```sh
cd ../../apps/widgetbook_example
flutter build web --no-tree-shake-icons
```

The `--no-tree-shake-icons` flag is needed because the Restage render runtime
constructs icon data from runtime values.

## Watch mode

`build_runner watch` determines the class-named generated story outputs when it
starts. Restart it after adding or removing an annotated widget, whether that
change is in an existing file or a newly added file. Keeping one annotated
widget per Dart file can make ordinary widget edits easier to isolate, but it
does not remove the restart required for changes to the set of annotated
widgets.

## Version

This example uses `widgetbook` 4.0.0-beta.10 and its bundled generator.
