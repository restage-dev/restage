import 'package:restage_measurement_schema/src/canonical.dart';

/// Maximum libraries one installed-libraries report may list.
const int sdkInstalledLibrariesMaximumLibraries = 32;

/// Maximum characters of one library namespace in the report.
const int sdkInstalledLibraryMaximumNamespaceCharacters = 128;

/// Maximum characters of the base64url report carrier on a request.
const int sdkInstalledLibrariesMaximumCarrierCharacters = 12288;

final RegExp _namespacePattern = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.-]*$');

/// One custom widget library installed in an SDK build.
final class SdkInstalledLibraryV1 extends CanonicalValue {
  /// Creates an installed library entry.
  ///
  /// [version] is null for a library registered without a capability version.
  /// [compatibleSince] is null for 1 and otherwise between 2 and [version].
  SdkInstalledLibraryV1({
    required this.namespace,
    required this.version,
    int? compatibleSince,
  }) : compatibleSince = compatibleSince == null || compatibleSince == 1
            ? null
            : compatibleSince {
    if (namespace.length > sdkInstalledLibraryMaximumNamespaceCharacters ||
        !_namespacePattern.hasMatch(namespace)) {
      throw ArgumentError.value(namespace, 'namespace', 'Invalid namespace');
    }
    final version = this.version;
    if (version != null &&
        (version < 1 || version > kMaximumPortableJsonInteger)) {
      throw ArgumentError.value(version, 'version', 'Expected a positive int');
    }
    final since = this.compatibleSince;
    if (since != null && (since < 1 || version == null || since > version)) {
      throw ArgumentError.value(
        since,
        'compatibleSince',
        'Expected 1..version',
      );
    }
  }

  factory SdkInstalledLibraryV1._fromJson(Object? value, String path) {
    if (value is! Map<String, Object?>) {
      throw CanonicalFormatException('$path must be an object');
    }
    final reader = CanonicalObjectReader(
      value,
      allowedKeys: const {'compatibleSince', 'namespace', 'version'},
      requiredKeys: const {'namespace', 'version'},
      path: path,
    );
    final version = reader.requiredNullableValue('version');
    if (version != null && version is! int) {
      throw CanonicalFormatException('$path.version must be null or an int');
    }
    final since = reader.optionalInteger('compatibleSince');
    if (since != null && since < 2) {
      throw CanonicalFormatException('$path.compatibleSince must exceed 1');
    }
    try {
      return SdkInstalledLibraryV1(
        namespace: reader.string('namespace'),
        version: version as int?,
        compatibleSince: since,
      );
    } on ArgumentError catch (error) {
      throw CanonicalFormatException('$path: ${error.message}');
    }
  }

  /// The library namespace.
  final String namespace;

  /// The declared capability version, or null when unversioned.
  final int? version;

  /// The oldest version whose content the library still renders, or null
  /// for 1.
  final int? compatibleSince;

  @override
  Map<String, Object?> toJson() => {
        if (compatibleSince != null) 'compatibleSince': compatibleSince,
        'namespace': namespace,
        'version': version,
      };
}

/// The custom widget libraries one SDK build has installed.
final class SdkInstalledLibrariesV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Creates a report of [libraries], held in namespace order.
  SdkInstalledLibrariesV1({required List<SdkInstalledLibraryV1> libraries})
      : libraries = List.unmodifiable(
          List<SdkInstalledLibraryV1>.of(libraries)
            ..sort((a, b) => a.namespace.compareTo(b.namespace)),
        ) {
    if (libraries.length > sdkInstalledLibrariesMaximumLibraries) {
      throw ArgumentError.value(
        libraries.length,
        'libraries',
        'Expected at most $sdkInstalledLibrariesMaximumLibraries',
      );
    }
    for (var i = 1; i < this.libraries.length; i++) {
      if (this.libraries[i].namespace == this.libraries[i - 1].namespace) {
        throw ArgumentError.value(
          this.libraries[i].namespace,
          'libraries',
          'Duplicate namespace',
        );
      }
    }
  }

  /// Decodes the closed report object.
  factory SdkInstalledLibrariesV1.fromJson(Map<String, Object?> json) {
    const path = 'sdkInstalledLibraries';
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: _keys,
      requiredKeys: _keys,
      path: path,
    );
    validateCanonicalDocument(reader, expectedKind: 'sdkInstalledLibraries');
    final raw = reader.list('libraries');
    if (raw.length > sdkInstalledLibrariesMaximumLibraries) {
      throw const CanonicalFormatException('$path.libraries is too long');
    }
    try {
      return SdkInstalledLibrariesV1(
        libraries: [
          for (var i = 0; i < raw.length; i++)
            SdkInstalledLibraryV1._fromJson(raw[i], '$path.libraries[$i]'),
        ],
      );
    } on ArgumentError catch (error) {
      throw CanonicalFormatException('$path: ${error.message}');
    }
  }

  /// Decodes exact canonical bytes for a report.
  factory SdkInstalledLibrariesV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        SdkInstalledLibrariesV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'sdkInstalledLibraries',
      );

  static const _keys = {'kind', 'libraries', 'schemaVersion'};

  /// The installed libraries, in namespace order.
  final List<SdkInstalledLibraryV1> libraries;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'sdkInstalledLibraries',
        'libraries': [for (final library in libraries) library.toJson()],
        'schemaVersion': kMeasurementSchemaVersion,
      };
}
