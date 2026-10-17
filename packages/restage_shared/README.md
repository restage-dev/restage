# restage_shared

[![pub package](https://img.shields.io/pub/v/restage_shared.svg)](https://pub.dev/packages/restage_shared) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

Part of [Restage](https://restage.dev), server-driven UI for Flutter.

Shared types, format schemas, validation, and catalog helpers used by the
Restage SDK and its build tools. It is plain Dart with no Flutter dependency,
so the same types compile in a Flutter app, in command-line tools, and on a
Dart server. A surface encoded on one side decodes byte-for-byte on the other.

It contains no networking, persistence, or credentials: only data shapes with
their codecs and validators.

## What's here

### Catalog and annotations

The main library re-exports the catalog types and the `@RestageWidget` /
`@RestageProperty` annotations from `package:rfw_catalog_schema`. Import that
package directly in new code. Custom-widget annotations for specific render
targets are in `package:restage_shared/a2ui.dart` and
`package:restage_shared/rfw.dart`.

A few catalog helpers are defined here:

- **`kSupportedCurveNames`**: the animation curve names the catalog, code
  generator, and runtime support.
- **`kRestageFormattedTextProps`**: the formatted-text property set.
- **`kMaxInlineSpanDepth`**: the nesting limit for rich-text spans.

### Surface and flow documents

The document formats for server-driven surfaces and for the multi-screen flows
behind onboarding, messages, and surveys:

- **`SurfaceDocument`** and its codec: the wrapper a surface is delivered in.
- **`FlowDocument`** and its codec, hash, validation, and compatibility check:
  the flow graph (screens, decisions, sub-flows, branches), its action schemas,
  and the content hash used to detect changes.

### Placements and delivery

Placement keys, host contracts, delivery requests and decisions describe which
content can render at an app location. Screen-capture records describe explicit
samples supplied to authoring tools. These types carry data only; the SDK owns
mounting and the CLI/MCP tools manage delivery plans.

### Theme contract

- **`kThemeContractPaths`**: the `data.theme.*` paths a delivered surface may
  read from the app's theme.

### Capabilities

- **`CapabilityManifest`**: the minimum capabilities a delivered document
  needs, so an older app refuses it instead of rendering it wrong.

## Vendored: `lib/src/rfw_formats/`

`lib/src/rfw_formats/` contains the pure-Dart `formats` library of
[`package:rfw`](https://pub.dev/packages/rfw) version 1.1.3, copied unchanged
apart from a note in each file's header comment. It lets pure-Dart programs
parse `.rfwtxt` and read and write `.rfw` blobs. `rfw` itself can't be used
there: its pubspec depends on the Flutter SDK, even though the formats code
uses only `dart:convert`, `dart:typed_data`, and `package:meta`.

Import it from `package:restage_shared/rfw_formats.dart`, which mirrors
`package:rfw/formats.dart`. It is kept out of the main library so it doesn't
clash with `package:rfw/rfw.dart` when you import both.

## License

BSD-3-Clause. See [LICENSE](LICENSE). The vendored `lib/src/rfw_formats/`
code is BSD-3-Clause by The Flutter Authors; see
[`lib/src/rfw_formats/LICENSE-rfw`](lib/src/rfw_formats/LICENSE-rfw).
