// Top-level barrel for the vendored `package:rfw/formats.dart` sublibrary.
//
// Consumers (the backend / pure-Dart server-side compilation) import this
// barrel directly:
//
//   import 'package:restage_shared/rfw_formats.dart';
//
// This is intentionally a SEPARATE barrel from `package:restage_shared/
// restage_shared.dart` (which exports the catalog, annotations, products).
// Keeping rfw symbols out of the default barrel prevents name collisions
// for consumers (e.g. the SDK) that already import `package:rfw/rfw.dart`
// — the two define identical `LibraryName`, `decodeLibraryBlob`,
// `WidgetLibrary`, etc.
//
// See the upstream BSD-3 license at `src/rfw_formats/LICENSE-rfw`. The formats
// sublibrary is vendored so it can be used from pure Dart (where rfw's Flutter
// SDK dependency would otherwise block resolution).

export 'src/rfw_formats.dart';
