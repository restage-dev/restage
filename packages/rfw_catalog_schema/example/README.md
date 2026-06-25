# rfw_catalog_schema example

`rfw_catalog_schema` is the public schema, annotations, wire-identity types, and
JSON codecs for an RFW widget catalog — the durable contract shared between
catalog producers, consumers, and any tooling that decodes or transmits a
catalog.

## Annotate a custom widget for the catalog

Mark a widget with `@RestageWidget` and its configurable inputs with
`@RestageProperty` so the build-time toolchain can include it in a catalog:

```dart
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget()
class PriceBadge extends StatelessWidget {
  const PriceBadge({super.key, required this.label});

  @RestageProperty()
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(label),
    );
  }
}
```

This package defines only the schema — the annotations, the `Catalog` /
`WidgetEntry` / `PropertyEntry` data types, the `WireId` identity model, and the
`encodeCatalog` / `decodeCatalog` codecs. The compiler that reads these
annotations and emits the catalog is the companion compiler package.

See the [package README](../README.md) for the full type and annotation
inventory.
