import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';

/// One installed custom widget library and its declared capability version.
@immutable
final class InstalledLibrary {
  /// Creates an installed library entry.
  const InstalledLibrary({required this.namespace, this.version});

  /// Decodes an installed library entry from its JSON wire form.
  factory InstalledLibrary.fromJson(Map<String, dynamic> json) {
    final namespace = json['namespace'];
    if (namespace is! String) {
      throw FormatException('malformed InstalledLibrary: $json');
    }

    final version = json['version'];
    if (version != null && version is! int) {
      throw FormatException('malformed InstalledLibrary: $json');
    }

    return InstalledLibrary(namespace: namespace, version: version as int?);
  }

  /// The library namespace.
  final String namespace;

  /// The declared capability version, or `null` when unversioned.
  final int? version;

  /// JSON wire form.
  Map<String, dynamic> toJson() => {
        'namespace': namespace,
        'version': version,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstalledLibrary &&
          other.namespace == namespace &&
          other.version == version;

  @override
  int get hashCode => Object.hash(namespace, version);
}

/// The built-in and custom library capabilities installed in a renderer.
@immutable
final class InstalledCapability {
  /// Creates an installed capability snapshot.
  ///
  /// [installedLibraries] is canonicalized to namespace order so JSON and
  /// value equality are independent of input order.
  factory InstalledCapability({
    required int builtInCatalogVersion,
    required List<InstalledLibrary> installedLibraries,
  }) =>
      InstalledCapability._(
        builtInCatalogVersion: builtInCatalogVersion,
        installedLibraries: installedLibraries,
      );

  InstalledCapability._({
    required this.builtInCatalogVersion,
    required List<InstalledLibrary> installedLibraries,
  }) : installedLibraries = List.unmodifiable(
          List<InstalledLibrary>.of(installedLibraries)
            ..sort((a, b) => a.namespace.compareTo(b.namespace)),
        );

  /// Decodes an installed capability snapshot from its JSON wire form.
  factory InstalledCapability.fromJson(Map<String, dynamic> json) {
    final builtInCatalogVersion = json['builtInCatalogVersion'];
    if (builtInCatalogVersion is! int) {
      throw FormatException('malformed InstalledCapability: $json');
    }

    final raw = json['installedLibraries'];
    final List<InstalledLibrary> installedLibraries;
    if (raw == null) {
      installedLibraries = const [];
    } else if (raw is List) {
      installedLibraries = [
        for (final entry in raw)
          InstalledLibrary.fromJson(entry as Map<String, dynamic>),
      ];
    } else {
      throw FormatException('installedLibraries must be a list: $raw');
    }

    return InstalledCapability(
      builtInCatalogVersion: builtInCatalogVersion,
      installedLibraries: installedLibraries,
    );
  }

  /// The installed built-in catalog content version.
  final int builtInCatalogVersion;

  /// Installed custom libraries, sorted by namespace.
  final List<InstalledLibrary> installedLibraries;

  /// Returns the installed version for [namespace], or `null` if the library
  /// is absent or unversioned.
  int? versionOf(String namespace) {
    for (final library in installedLibraries) {
      if (library.namespace == namespace) return library.version;
    }
    return null;
  }

  /// JSON wire form.
  Map<String, dynamic> toJson() => {
        'builtInCatalogVersion': builtInCatalogVersion,
        'installedLibraries':
            installedLibraries.map((library) => library.toJson()).toList(),
      };

  /// SHA-256 content hash for the canonical JSON wire form.
  ///
  /// The `sha256:` prefix is a required algorithm discriminator so the hashing
  /// scheme can evolve unambiguously.
  String get contentHash =>
      'sha256:${crypto.sha256.convert(utf8.encode(jsonEncode(toJson())))}';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InstalledCapability) return false;
    if (other.builtInCatalogVersion != builtInCatalogVersion) return false;
    if (other.installedLibraries.length != installedLibraries.length) {
      return false;
    }
    for (var i = 0; i < installedLibraries.length; i++) {
      if (other.installedLibraries[i] != installedLibraries[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(builtInCatalogVersion, Object.hashAll(installedLibraries));
}
