# rfw_catalog_compiler example

`rfw_catalog_compiler` is the analyzer-backed compiler pipeline that turns a
Flutter widget library into a **catalog** — the versioned description of the
widgets and properties the Restage renderer understands. It walks the annotated
source, resolves each property's value shape, allocates stable wire IDs, and
lowers the result to the public catalog schema. It is the stage `restage_codegen`
drives when it compiles your custom widgets; you normally consume it through that
build step rather than calling it by hand.

## The input: an annotated widget

You expose a custom widget to the catalog by annotating it with `@RestageWidget`
and its configurable properties with `@RestageProperty`:

```dart
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'AcmeBorder',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.layout,
  description: 'Wraps a single child in a colored border.',
  childrenSlot: ChildrenSlot.single,
)
class AcmeBorder extends StatelessWidget {
  const AcmeBorder({super.key, required this.child, this.color});

  @RestageProperty(description: 'Wrapped child widget.', required: true)
  final Widget child;

  @RestageProperty(description: 'Border color.', defaultBrandToken: 'primary')
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
- each property's resolved value shape (here: a single child slot and an
  optional, brand-token-defaulted color),
- the metadata the editor and the renderer read.

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
