# restage_shared

[![pub package](https://img.shields.io/pub/v/restage_shared.svg)](https://pub.dev/packages/restage_shared) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

Pure-Dart shared types, format schemas, validation, and the catalog that the
Restage SDK and the build-time toolchain both depend on. Everything here is
plain Dart with no Flutter dependency, so the same types compile in the Flutter
app, in command-line tools, and in pure-Dart server environments. That shared
spine is what lets a surface authored on one side decode byte-for-byte on the
other.

It contains no networking, persistence, or credentials. It is a library of data
shapes, codecs, and validators.

## What's here

### Catalog and annotations

The widget catalog data types and the `@RestageWidget` / `@RestageProperty`
annotations now live in `package:rfw_catalog_schema`. This package re-exports
them from its main barrel for compatibility with existing call sites, so a
single `import 'package:restage_shared/restage_shared.dart';` still resolves
`Catalog`, `WidgetEntry`, `PropertyEntry`, `LibraryInfo`, and the annotations.
New code should import `package:rfw_catalog_schema/rfw_catalog_schema.dart`
directly.

A handful of catalog-adjacent helpers are defined here rather than in the schema
package:

- **`kSupportedCurveNames`** — the animation curve vocabulary the catalog,
  codegen, and runtime agree on.
- **`kRestageFormattedTextProps`** — the formatted-text property set.
- **`kMaxInlineSpanDepth`** — the inline-span nesting limit enforced when
  decoding rich text.

### Surface and flow documents

The wire format for server-driven surfaces and the multi-screen flows that drive
onboarding, messages, and surveys:

- **`SurfaceDocument`** and its codec — the envelope a surface is delivered in,
  with `SurfaceType` and the blob/flow payload split.
- **`FlowDocument`** and its codec, hash, validation, and compatibility diff —
  the declarative flow graph (screens, decisions, sub-flows, branches), plus the
  action schemas and the content hash used for change detection.

### Value types

- **`RestageProduct`** — a purchasable product (id, slot, entitlement),
  configured at app startup.
- **`RestageEntitlement`** — an abstract feature gate the user has access to
  (for example `'pro'`).
- **`EntitlementSource`** — how an entitlement was obtained (`purchase`,
  `restore`, `renewal`, `promotional`).

### Analytics taxonomy

The behavioral-analytics event contract every surface emits:

- **`AnalyticsEvent`** — the client event envelope.
- The reserved-key set, wire enums, skew bounds, and the taxonomy registry that
  define and validate that envelope.

These are the canonical field names and shapes for the event stream. The SDK
builds the client envelope and emits it; the destination service stamps and
stores it. Both sides read the same definitions from here, which is why the
ingest-side shapes live alongside the client ones.

### Theme contract

- **`kThemeContractPaths`** — the `data.theme.*` paths a delivered surface may
  read from the host's theme.

### Capability and metering

- **`CapabilityManifest`** — the capability floor a delivered document declares,
  so an older reader fails closed rather than misrendering.
- The metering fold types used to roll usage into reportable totals.

## Vendored: `lib/src/rfw_formats/`

`lib/src/rfw_formats/` contains the pure-Dart `formats` sublibrary of
[`package:rfw`](https://pub.dev/packages/rfw) version 1.1.3, vendored verbatim
(with only an added vendoring marker in each file's header comment). This lets
pure-Dart environments parse `.rfwtxt` and round-trip `.rfw` blobs without
depending on `package:rfw` directly. `rfw`'s pubspec declares a Flutter SDK
dependency that prevents `pub get` on Dart-only images, even though the formats
sublibrary itself uses only `dart:convert`, `dart:typed_data`, and
`package:meta`.

The vendored code is BSD-3-Clause licensed by The Flutter Authors. The upstream
license is reproduced verbatim at
[`lib/src/rfw_formats/LICENSE-rfw`](lib/src/rfw_formats/LICENSE-rfw); that
license travels with the vendored code and applies to it specifically.

The vendored API is re-exported via `lib/src/rfw_formats.dart`, which mirrors
upstream `package:rfw/formats.dart`. It is kept on a separate
`package:restage_shared/rfw_formats.dart` barrel rather than the main one, to
avoid symbol collisions for consumers that also import `package:rfw/rfw.dart`.

## License

BSD-3-Clause, see [`LICENSE`](LICENSE). The vendored `lib/src/rfw_formats/` subtree is
BSD-3-Clause (The Flutter Authors); see its `LICENSE-rfw`.
