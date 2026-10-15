# rfw_catalog_schema

[![pub package](https://img.shields.io/pub/v/rfw_catalog_schema.svg)](https://pub.dev/packages/rfw_catalog_schema) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

The schema, annotations, catalog ID types, and JSON codecs for a
[Remote Flutter Widgets (RFW)](https://pub.dev/packages/rfw) widget catalog.

Part of [Restage](https://restage.dev), server-driven UI for Flutter.

This package describes what a catalog looks like. It is the shared format for
tools that produce catalogs (compilers, code generators), tools that read them
(editors, SDK runtimes, servers), and anything that stores or sends one.

## What this package contains

- **Catalog data types.** `Catalog`, `WidgetEntry`, `PropertyEntry`,
  `StructuredEntry`, `UnionEntry`, `FactoryVariant`, `DecompositionRecipe`,
  `DesignTokenEntry`, plus the enums and metadata structs they reference.
- **Catalog IDs.** `WireId` (a stable ID with a kind prefix, unique within a
  library), `WireIdKind`, and `WireIdRef` for references across libraries.
- **Default values.** The sealed `DefaultValueSource` family
  (`LiteralDefault`, `TokenRefDefault`, `ThemeBindingDefault`,
  `FlutterCtorDefault`).
- **Annotations.** `@RestageWidget`, the optional shared
  `@RestageProperty` overlay, target-specific `a2ui.Config`, `rfw.Config`, and
  `widgetbook.Config`, selective `@Ignore` routing through `EmitTarget`,
  `@RestageBuiltinLibrary`, `@RestageLibrary`, `@RestageStructuredType`,
  `@RestageUnionVariant`, `@RestageFactoryVariant`, `@StableWidget`,
  `@StableProperty`, `@RfwIncompatible`, and `@RestageDataField`.
- **Typed constraints.** `RestageConstraints` carries numeric bounds, allowed
  values, patterns, string lengths, and list lengths on `RestageProperty` and
  `PropertyEntry`, and keeps unknown JSON keywords so newer readers can use
  them.
- **JSON codecs.** `encodeCatalog` and `decodeCatalog`.
- **Lifecycle types.** `DeprecationInfo` (deprecated in source, in the
  catalog, or both), `CompatRule` for compatible and breaking changes, and
  `ValidationExpr`.

## Custom widget authoring

A custom widget's catalog inputs come from its unnamed constructor. Each
supported public parameter (including `super.` parameters) becomes an input,
in constructor order. Required parameters are required inputs. `key` is
skipped.

Doc comments become the widget and property descriptions. Add
`@RestageProperty` only for what Dart can't express, such as a default value
source or constraints. Declare the package's widget library once, in a file
that exports exactly the widgets it owns:

```dart
// lib/restage_imports.dart
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

export 'widgets/submit_button.dart';
export 'widgets/submit_control.dart';

final class AcmeWidgets extends WidgetLibrary {
  const AcmeWidgets();

  @override
  final String namespace = 'acme.widgets';
}

const WidgetLibrary acmeWidgets = AcmeWidgets();

@RestageLibrary(library: acmeWidgets, capabilityVersion: 1)
const restageCatalog = 0;
```

An exported widget usually needs only the bare annotation. Its class name is
its catalog name, the file that exports it sets its library, and with no
category it sits at the top level of the library:

```dart
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// An app-owned submit button.
@RestageWidget()
class SubmitButton extends StatelessWidget {
  const SubmitButton({super.key, required this.label, this.emphasized = true});

  /// Visible button label.
  final String label;

  /// Whether to use the emphasized treatment.
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Text(label);
}
```

A2UI-only settings come from a separate import. Callbacks need no
annotation: the constructor parameter's name is the event name.

```dart
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@a2ui.Config(
  usage: 'Use for the primary form action.',
  writeBackValues: {'onChanged': 'enabled'},
)
@RestageWidget()
class SubmitControl extends StatelessWidget {
  const SubmitControl({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  /// Whether the control is enabled.
  final bool enabled;

  /// Reports changes to [enabled].
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => onChanged(!enabled),
        child: Text(enabled ? 'Enabled' : 'Disabled'),
      );
}
```

Your build configuration picks which outputs are generated for the package.
One widget can turn off a single output with that output's config:

```dart
@RestageWidget()
@a2ui.Config.enabled(false)
class RfwAndWidgetbookCard extends StatelessWidget {
  const RfwAndWidgetbookCard({super.key, this.debugLabel = ''});

  /// Local diagnostic text that A2UI and Widgetbook should not expose.
  @Ignore({EmitTarget.a2ui, EmitTarget.widgetbook})
  final String debugLabel;

  @override
  Widget build(BuildContext context) => Text(debugLabel);
}
```

`@ignore` or `@Ignore()` leaves one optional input out of every output. Pass a
set of `EmitTarget` values to leave it out of those outputs only. Generation
fails if the selection is empty, if the input is required, or if leaving it out
would leave a gap in the positional arguments.

For advanced cases, set `library:` when a class is exported by more than one
library, `category:` to put a widget in a named group, or `name:` when the
catalog name must differ from the class name:

```dart
@RestageWidget(
  name: 'LegacySubmit',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.action,
)
class LegacySubmitControl extends StatelessWidget { /* ... */ }
```

The encoder writes catalog schema v5. The decoder also reads v4 catalogs and
upgrades them. `WireId.unallocated*` placeholders (`w0000`, `p0000`, and so
on) are for tooling only: `decodeCatalog` rejects them and `encodeCatalog`
refuses to write a catalog that still contains them.

## What it does not contain

- **No compiler.** Source analysis and ID assignment live in
  [`rfw_catalog_compiler`](https://pub.dev/packages/rfw_catalog_compiler).
- **No runtime.** Theme resolution, widget lookup, and decoding compiled
  `.rfw` files live in the SDK.
- **No Flutter dependency.** The package is pure Dart, so Dart-only servers
  and code generators can use it.

## Stability

See [CHANGELOG.md](CHANGELOG.md) for released API and format changes. Source
updates may precede a package release.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
