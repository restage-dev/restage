# restage_measurement_schema example

`restage_measurement_schema` holds the contract types the Restage SDK and its
toolchain agree on: canonical bytes and digests, measurement targets and
identifiers, publication bindings and manifests, ingest envelopes, and the
governed-subject requests. The types are inert data. They compute nothing and
reach no network, so they compile in a Flutter app, in a command-line tool, or
on a server.

## Canonical bytes and a domain digest (pure Dart)

Two producers that build the same value get the same bytes, and the same digest
under the same domain:

```dart
import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';

void main() {
  final value = <String, Object?>{
    'kind': 'example',
    'fields': ['b', 'a'],
    'count': 2,
  };

  // Key order and formatting are fixed by the codec, so the bytes are the
  // same wherever the value is encoded.
  final bytes = CanonicalJsonCodec.encode(value);
  print(utf8.decode(bytes));

  // A digest is always taken under a named domain, so the same bytes hashed
  // for two purposes never collide.
  final digest = canonicalSha256(CanonicalHashDomain.artifactIdentity, bytes);
  print(digest.hex);

  // Decoding gives back the value the bytes were produced from.
  final decoded = CanonicalJsonCodec.decode(bytes);
  print(decoded);
}
```

Most apps never construct these types by hand: the `restage` package publishes
the ones its API hands you, and the `restage_codegen` build writes the
publication records. See the [package README](../README.md) for the full type
inventory.
