import 'package:flutter/foundation.dart';

/// One custom widget library an installed A2UI catalog provides, with the
/// capability [version] of that library the catalog has.
///
/// This is the *available* (present) side of the capability relation — the
/// app-side counterpart to a payload's required `LibraryRequirement`. Same
/// shape (namespace + a monotonic int), distinct semantics: this is the version
/// the registered catalog HAS, against which a payload's required `minVersion`
/// is satisfied.
@immutable
final class A2uiAvailableLibrary {
  /// Creates an available-library entry. [namespace] must be non-empty and
  /// [version] a positive capability version.
  const A2uiAvailableLibrary({required this.namespace, required this.version})
    : assert(namespace.length > 0, 'namespace must not be empty'),
      assert(version >= 1, 'version must be a positive capability version');

  /// The custom library's namespace, e.g. `acme.widgets`.
  final String namespace;

  /// The capability version of the library the catalog provides.
  final int version;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is A2uiAvailableLibrary &&
          other.namespace == namespace &&
          other.version == version;

  @override
  int get hashCode => Object.hash(namespace, version);
}

/// What the A2UI catalog an app registered PROVIDES — the *available* side the
/// pre-render check compares a Restage-stamped payload's required capability
/// against.
///
/// The app supplies this, normally from the `restageCapability` stamp block of
/// the catalog it registered (see [A2uiInstalledCapability.fromStampJson]). For
/// the A2UI path the render truth is the registered genui catalog, not the
/// app's native widget registry — so the available side comes from THAT
/// catalog's stamp.
///
/// A client can render a stamped payload iff its [catalogContentVersion] is at
/// least the payload's built-in floor AND every required library is matched by
/// an entry in [availableLibraries] at or above its required version — the same
/// two-axis relation the native delivery path uses.
@immutable
final class A2uiInstalledCapability {
  /// Creates an installed-capability descriptor. [availableLibraries] is
  /// canonicalized to namespace order so comparison is order-independent.
  A2uiInstalledCapability({
    required this.catalogContentVersion,
    required List<A2uiAvailableLibrary> availableLibraries,
  }) : assert(
         catalogContentVersion >= 1,
         'catalogContentVersion must be a positive content version',
       ),
       availableLibraries = List.unmodifiable(
         List<A2uiAvailableLibrary>.of(availableLibraries)
           ..sort((a, b) => a.namespace.compareTo(b.namespace)),
       );

  /// Parses the descriptor from a Restage catalog capability stamp block — the
  /// `restageCapability` object the toolchain emits next to an A2UI catalog
  /// (`{catalogContentVersion, availableLibraries:[{namespace,version}],
  /// perItemSinceVersion}`). `perItemSinceVersion` is not read here; the
  /// available side needs only the content version and the library set.
  ///
  /// Fails closed: a malformed stamp throws [FormatException] rather than
  /// yielding a partial descriptor.
  factory A2uiInstalledCapability.fromStampJson(Map<String, Object?> json) {
    final version = json['catalogContentVersion'];
    if (version is! int) {
      throw FormatException(
        'malformed A2UI capability stamp: catalogContentVersion must be an '
        'int, got ${version.runtimeType}',
      );
    }
    final rawLibraries = json['availableLibraries'];
    final List<A2uiAvailableLibrary> libraries;
    if (rawLibraries == null) {
      libraries = const [];
    } else if (rawLibraries is List) {
      libraries = [for (final entry in rawLibraries) _libraryFromJson(entry)];
    } else {
      throw FormatException(
        'malformed A2UI capability stamp: availableLibraries must be a list, '
        'got ${rawLibraries.runtimeType}',
      );
    }
    return A2uiInstalledCapability(
      catalogContentVersion: version,
      availableLibraries: libraries,
    );
  }

  static A2uiAvailableLibrary _libraryFromJson(Object? entry) {
    if (entry is! Map<String, Object?>) {
      throw FormatException(
        'malformed A2UI available library: expected an object, got '
        '${entry.runtimeType}',
      );
    }
    final namespace = entry['namespace'];
    final version = entry['version'];
    if (namespace is! String || version is! int) {
      throw FormatException('malformed A2UI available library: $entry');
    }
    return A2uiAvailableLibrary(namespace: namespace, version: version);
  }

  /// The built-in content version the registered catalog provides.
  final int catalogContentVersion;

  /// The custom libraries the registered catalog provides, sorted by namespace.
  /// Possibly empty.
  final List<A2uiAvailableLibrary> availableLibraries;
}
