import 'package:meta/meta.dart';

/// Per-library metadata surfaced in the catalog envelope.
///
/// Per-kind entry counts are not stored here — they are denormalized
/// caches of the catalog's own entry lists. Read them as computed values
/// off [Catalog] instead (`catalog.widgetsIn(library).length`,
/// `structuredTypesIn`, `unionsIn`, `designTokensIn`).
@immutable
final class LibraryInfo {
  /// Const constructor.
  const LibraryInfo({required this.version, this.capabilityVersion});

  /// Semver of the library package this entry was generated from.
  final String version;

  /// The library's declared **capability version** — a monotonic integer that
  /// tracks the library's render-support line, used to derive a delivered
  /// surface's capability floor. This is **distinct from [version]**: it is
  /// NOT the pub package semantic version; it is the customer-declared
  /// `@RestageLibrary(capabilityVersion: …)` value.
  ///
  /// `null` means the library declared no capability version. Built-in
  /// libraries leave it `null` — their render-support line is carried per
  /// widget by `WidgetEntry.sinceVersion`, not per library. A custom library a
  /// surface references must declare it, or the build fails (fail-when-
  /// referenced); an unreferenced custom library that omits it is left alone.
  final int? capabilityVersion;

  @override
  bool operator ==(Object other) =>
      other is LibraryInfo &&
      other.version == version &&
      other.capabilityVersion == capabilityVersion;

  @override
  int get hashCode => Object.hash(version, capabilityVersion);
}
