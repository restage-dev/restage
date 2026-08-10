# rfw_catalog_compiler example

`rfw_catalog_compiler` is the analyzer-backed compiler pipeline that turns a
Flutter widget library into a **catalog** — the versioned description of the
widgets and properties the Restage renderer understands. It walks the annotated
source, resolves each property's value shape, allocates stable wire IDs, and
lowers the result to the public catalog schema. It is the stage `restage_codegen`
drives when it compiles your custom widgets; you normally consume it through that
build step rather than calling it by hand.

## Declare the library once

One exporting barrel declares the catalog library and the widgets it owns:

```dart
// lib/restage_imports.dart
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

export 'widgets/acme_border.dart';

final class AcmeWidgets extends WidgetLibrary {
  const AcmeWidgets();

  @override
  final String namespace = 'acme.widgets';
}

const WidgetLibrary acmeWidgets = AcmeWidgets();

@RestageLibrary(
  library: acmeWidgets,
  capabilityVersion: 1,
)
const restageCatalog = 0;
```

## Mark the widget

The widget itself keeps ordinary Flutter constructor syntax. Constructor-bound
inputs and Dart documentation are inferred. `@RestageProperty` is optional
metadata or an override for catalog facts that Dart cannot express:

```dart
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Wraps a child in a colored border.
@RestageWidget()
class AcmeBorder extends StatelessWidget {
  const AcmeBorder({super.key, required this.child, this.color});

  /// Widget displayed inside the border.
  final Widget child;

  /// Border color, or the theme primary color when omitted.
  @RestageProperty(defaultBrandToken: 'primary')
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: color ?? scheme.primary, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
```

## What the compiler produces

From that source, `rfw_catalog_compiler` emits a catalog entry that records:

- the widget's identity and a **stable wire ID** (so a published surface keeps
  rendering across catalog revisions),
- each property's resolved value shape (here: the exact constructor-derived
  `Widget` property named `child` and an optional, brand-token-defaulted
  color),
- class and property descriptions inferred from Dart documentation, plus the
  optional color metadata.

The compiled catalog is what lets a `.rfw` blob refer to `AcmeBorder` by a small
inert identifier instead of shipping any widget code.

## Running it

In a normal project you don't invoke the compiler directly — add
[`restage_codegen`](https://pub.dev/packages/restage_codegen) as a dev dependency
and run `dart run build_runner build`; it drives this pipeline over your
`@RestageWidget` library and writes the catalog alongside your generated
factories. The library's public API (the structured walker, wire-ID allocator,
IR lowering, and catalog-diff helpers) is exposed for catalog tooling that needs
to embed a compiler stage of its own. A complete custom-widget example is in
[`apps/examples`](https://github.com/restage-dev/restage/tree/main/apps/examples).
