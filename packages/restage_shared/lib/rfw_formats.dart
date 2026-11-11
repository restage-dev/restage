// Top-level barrel for the pure-Dart rfw formats library: copies of a formats
// library derived from rfw 2.0.0's `lib/src/dart/`, kept identical to their
// source.
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
// See the upstream BSD-3 license at `src/rfw_formats/LICENSE-rfw`. The copies
// let pure Dart use the formats library without the Flutter SDK dependency.

export 'src/fonts/literal_icon_code_points.dart';
export 'src/rfw_catalog_occurrence.dart';
export 'src/rfw_formats.dart';
export 'src/rfw_preview_reservation.dart';
export 'src/rfw_split_island_placements.dart';
