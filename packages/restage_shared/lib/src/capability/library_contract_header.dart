import 'dart:convert';

import 'package:meta/meta.dart';

/// Directory, relative to the app's root, that holds library contract
/// snapshots: one `<namespace>/v<N>.json` per recorded capability version.
const String libraryContractSnapshotDirectory = '.restage/library-contracts';

/// File name of one snapshot: `v<N>.json` with a positive `N`.
final RegExp libraryContractSnapshotFileName =
    RegExp(r'^v([1-9][0-9]*)\.json$');

/// The capability version a snapshot file name records, or `null` when
/// [fileName] is not a snapshot file.
int? libraryContractSnapshotVersion(String fileName) {
  final match = libraryContractSnapshotFileName.firstMatch(fileName);
  return match == null ? null : int.parse(match.group(1)!);
}

/// The identifying keys of one library contract snapshot.
@immutable
final class LibraryContractHeader {
  /// Creates a header. `1 <= compatibleSince <= capabilityVersion`.
  LibraryContractHeader({
    required this.namespace,
    required this.capabilityVersion,
    required this.compatibleSince,
  }) {
    if (namespace.isEmpty ||
        capabilityVersion < 1 ||
        compatibleSince < 1 ||
        compatibleSince > capabilityVersion) {
      throw ArgumentError(
        'A library contract needs a namespace and '
        '1 <= compatibleSince <= capabilityVersion.',
      );
    }
  }

  /// Decodes the header keys of a snapshot file's [contents]; [source] names
  /// the file in errors. Other keys are the contract itself and are ignored.
  factory LibraryContractHeader.decode(String contents, String source) {
    final Object? json;
    try {
      json = jsonDecode(contents);
    } on FormatException catch (error) {
      throw FormatException('$source is not a library contract: $error');
    }
    return LibraryContractHeader.fromJson(json, source);
  }

  /// Reads the header keys of an already decoded snapshot [json].
  factory LibraryContractHeader.fromJson(Object? json, String source) {
    if (json is! Map<String, Object?>) {
      throw FormatException('$source is not a library contract.');
    }
    final namespace = json['namespace'];
    final capabilityVersion = json['capabilityVersion'];
    final compatibleSince = json['compatibleSince'];
    if (namespace is! String ||
        namespace.isEmpty ||
        capabilityVersion is! int ||
        compatibleSince is! int ||
        capabilityVersion < 1 ||
        compatibleSince < 1 ||
        compatibleSince > capabilityVersion) {
      throw FormatException(
        '$source needs namespace, capabilityVersion, and compatibleSince.',
      );
    }
    return LibraryContractHeader(
      namespace: namespace,
      capabilityVersion: capabilityVersion,
      compatibleSince: compatibleSince,
    );
  }

  /// The library namespace.
  final String namespace;

  /// The capability version this snapshot records.
  final int capabilityVersion;

  /// The oldest capability version this library still renders.
  final int compatibleSince;

  @override
  bool operator ==(Object other) =>
      other is LibraryContractHeader &&
      other.namespace == namespace &&
      other.capabilityVersion == capabilityVersion &&
      other.compatibleSince == compatibleSince;

  @override
  int get hashCode =>
      Object.hash(namespace, capabilityVersion, compatibleSince);
}
