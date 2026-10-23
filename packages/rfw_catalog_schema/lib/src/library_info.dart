import 'package:meta/meta.dart';

/// Per-library metadata surfaced in the catalog envelope.
///
/// Per-kind entry counts are not stored here — they are denormalized
/// caches of the catalog's own entry lists. Read them as computed values
/// off `Catalog` instead (`catalog.widgetsIn(library).length`,
/// `structuredTypesIn`, `unionsIn`, `designTokensIn`).
@immutable
final class LibraryInfo {
  /// Const constructor.
  const LibraryInfo({
    required this.version,
    this.capabilityVersion,
    this.compatibleSince = 1,
    this.generatedVersion,
  });

  /// Semver of the library package this entry was generated from.
  final String version;

  /// The library's declared **capability version** — a monotonic integer that
  /// tracks the library's render-support line, used to derive a delivered
  /// surface's capability floor. This is **distinct from [version]**: it is
  /// NOT the pub package semantic version; it is the app-declared
  /// `@RestageLibrary(capabilityVersion: …)` value.
  ///
  /// `null` means the library declared no capability version. Built-in
  /// libraries leave it `null` — their render-support line is carried per
  /// widget by `WidgetEntry.sinceVersion`, not per library. A custom library a
  /// surface references must declare it, or the build fails (fail-when-
  /// referenced); an unreferenced custom library that omits it is left alone.
  final int? capabilityVersion;

  /// The oldest capability version this build still renders, from
  /// `@RestageLibrary(compatibleSince: …)`. `1` means no declared break.
  final int compatibleSince;

  /// The version of the generated widget code the library's factories come
  /// from, or `null` for 1. Stamped by the code generator on package catalogs.
  final int? generatedVersion;

  @override
  bool operator ==(Object other) =>
      other is LibraryInfo &&
      other.version == version &&
      other.capabilityVersion == capabilityVersion &&
      other.compatibleSince == compatibleSince &&
      other.generatedVersion == generatedVersion;

  @override
  int get hashCode => Object.hash(
        version,
        capabilityVersion,
        compatibleSince,
        generatedVersion,
      );
}
