# restage_shared example

`restage_shared` is the pure-Dart spine shared between the Restage SDK and the
build-time toolchain: catalog format types, surface/flow documents, value
types, the analytics taxonomy, validation, and codecs — no Flutter dependency,
so the same types compile in a Flutter app, in a command-line tool, or in a
pure-Dart server.

## Decode and inspect a catalog (pure Dart)

Because there is no Flutter dependency, you can decode and walk a catalog
anywhere — for example in a command-line tool or a server:

```dart
import 'dart:io';

import 'package:restage_shared/restage_shared.dart';

void main(List<String> args) {
  final json = File(args.first).readAsStringSync();

  // decodeCatalog validates the canonical JSON as it parses; an invalid
  // catalog throws rather than producing a malformed Catalog.
  final Catalog catalog = decodeCatalog(json);

  for (final WidgetEntry widget in catalog.widgets) {
    stdout.writeln(widget.name);
  }
}
```

The package also carries the shared value types (`RestageProduct`,
`RestageEntitlement`, `EntitlementSource`), the `SurfaceDocument` /
`FlowDocument` wire formats, and the analytics event taxonomy — the same
definitions both sides read so a surface authored on one decodes byte-for-byte
on the other.

See the [package README](../README.md) for the full type inventory.
