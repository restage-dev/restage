/// Deterministic, ZIP-compatible build-artifact bundles for Restage output.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';
import 'package:restage_shared/src/surface_contract/surface_publication_contract.dart';

/// The fixed metadata entry included in every Restage bundle.
const String kRestageBundleMetadataPath = 'META-INF/restage-bundle.json';

/// The current version of the deterministic Restage bundle metadata schema.
const int kRestageBundleSchemaVersion = 1;

/// The largest classic-ZIP value that does not signal ZIP64.
const int kRestageBundleMaxClassicZipValue = 0xFFFFFFFE;

/// The maximum payload-entry count, reserving one classic-ZIP entry for
/// [kRestageBundleMetadataPath].
const int kRestageBundleMaxPayloadEntries = 0xFFFE;

const int _zipLocalFileHeaderSignature = 0x04034B50;
const int _zipCentralDirectoryHeaderSignature = 0x02014B50;
const int _zipEndOfCentralDirectorySignature = 0x06054B50;
const int _zipVersionNeeded = 20;
const int _zipVersionMadeBy = 0x0314;
const int _zipUtf8Flag = 0x0800;
const int _zipStoreMethod = 0;
const int _zipMinimumDosTime = 0;
const int _zipMinimumDosDate = 0x0021;
const int _zipUnixRegularFile0644 = 0x81A40000;
const int _zipMaxFilenameBytes = 0xFFFF;
const int _zipMaxEntries = 0xFFFF;

/// The role of one [RestageBundleEntry].
///
/// A bundle carries every one of a library's delivery artifacts (the same
/// three roles [SurfacePublicationArtifactRoleV1] carries in the strict
/// publication manifest) plus its canonical `.rfwtxt` inspection text, which
/// is never part of the delivery manifest closure. This is therefore a
/// separate, bundle-scoped role vocabulary rather than a reuse of the
/// manifest's: the manifest's role enum is switched exhaustively wherever
/// delivery artifacts are validated, and a bundle-only role must never be
/// mistaken for one.
enum RestageBundleEntryRoleV1 {
  /// A canonical flow document. Wire-identical to
  /// [SurfacePublicationArtifactRoleV1.flowDocument].
  flowDocument('flowDocument'),

  /// A compiled screen blob. Wire-identical to
  /// [SurfacePublicationArtifactRoleV1.screenBlob].
  screenBlob('screenBlob'),

  /// A capability sidecar. Wire-identical to
  /// [SurfacePublicationArtifactRoleV1.capabilitySidecar].
  capabilitySidecar('capabilitySidecar'),

  /// The canonical human-readable `.rfwtxt` sibling of a compiled screen
  /// blob. Bundle-only; never a delivery-manifest artifact role.
  rfwText('rfw-text');

  const RestageBundleEntryRoleV1(this.wireName);

  /// The bundle-scoped counterpart of a strict manifest artifact role.
  factory RestageBundleEntryRoleV1.fromManifestRole(
    SurfacePublicationArtifactRoleV1 role,
  ) =>
      switch (role) {
        SurfacePublicationArtifactRoleV1.flowDocument => flowDocument,
        SurfacePublicationArtifactRoleV1.screenBlob => screenBlob,
        SurfacePublicationArtifactRoleV1.capabilitySidecar => capabilitySidecar,
      };

  /// The exact wire spelling, frozen to match the pre-refactor corpus.
  final String wireName;

  /// Decodes a bundle entry role from its exact wire spelling.
  static RestageBundleEntryRoleV1 fromWireName(String value) {
    for (final role in values) {
      if (role.wireName == value) return role;
    }
    throw FormatException('Unsupported bundle entry role "$value".');
  }

  /// The strict manifest role this bundle-scoped role corresponds to.
  ///
  /// Throws [StateError] for [rfwText], which is bundle-only and never a
  /// delivery-manifest artifact role — a caller reaching this on an
  /// inspection-text entry is asking a manifest question about something
  /// that was never a manifest artifact.
  SurfacePublicationArtifactRoleV1 toManifestRole() => switch (this) {
        flowDocument => SurfacePublicationArtifactRoleV1.flowDocument,
        screenBlob => SurfacePublicationArtifactRoleV1.screenBlob,
        capabilitySidecar => SurfacePublicationArtifactRoleV1.capabilitySidecar,
        rfwText => throw StateError(
            'rfw-text is a bundle-only role and has no manifest-role '
            'counterpart.',
          ),
      };
}

/// One exact delivery artifact stored inside a [RestageBundle].
@immutable
final class RestageBundleEntry {
  /// Creates an immutable payload entry.
  RestageBundleEntry({
    required this.logicalPath,
    required this.role,
    required List<int> bytes,
  }) : _bytes = _copyOctets(bytes, label: 'bundle entry bytes') {
    _validatePayloadPath(logicalPath);
  }

  /// The unchanged logical delivery path used by publication metadata.
  final String logicalPath;

  /// The bundle-scoped artifact role.
  final RestageBundleEntryRoleV1 role;

  final Uint8List _bytes;

  /// Exact artifact bytes, copied on every access.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// Exact artifact length in bytes.
  int get byteLength => _bytes.length;

  /// SHA-256 over [bytes] in the Restage wire spelling.
  String get sha256 => _sha256(_bytes);
}

/// A metadata record for one [RestageBundleEntry].
@immutable
final class RestageBundleMetadataEntry {
  /// Creates a strict payload metadata record.
  RestageBundleMetadataEntry({
    required this.logicalPath,
    required this.role,
    required this.byteLength,
    required this.sha256,
  }) {
    _validatePayloadPath(logicalPath);
    if (byteLength < 0 || byteLength > kRestageBundleMaxClassicZipValue) {
      throw FormatException(
        'Bundle entry "$logicalPath" has an unsupported byte length '
        '$byteLength.',
      );
    }
    SurfaceContractJson.requireSha256(sha256, 'bundle entry sha256');
  }

  /// The unchanged logical delivery path.
  final String logicalPath;

  /// The bundle-scoped artifact role.
  final RestageBundleEntryRoleV1 role;

  /// Exact payload length.
  final int byteLength;

  /// SHA-256 of the exact payload bytes.
  final String sha256;

  Map<String, Object?> toJson() => <String, Object?>{
        'path': logicalPath,
        'role': role.wireName,
        'byteLength': byteLength,
        'sha256': sha256,
      };
}

/// Strict canonical metadata stored at [kRestageBundleMetadataPath].
@immutable
final class RestageBundleMetadata {
  /// Creates canonical metadata from any payload-entry order.
  RestageBundleMetadata({
    required this.packageName,
    required this.authoredLibraryPath,
    required Iterable<RestageBundleMetadataEntry> entries,
  }) : entries = List.unmodifiable(_canonicalMetadataEntries(entries)) {
    _validatePackageName(packageName);
    _validateAuthoredLibraryPath(authoredLibraryPath);
  }

  /// The package that owns this build artifact.
  final String packageName;

  /// The package-relative authored Dart library that owns this bundle.
  final String authoredLibraryPath;

  /// Sorted payload records; metadata never describes or hashes itself.
  final List<RestageBundleMetadataEntry> entries;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': kRestageBundleSchemaVersion,
        'package': packageName,
        'authoredLibrary': authoredLibraryPath,
        'entries': <Object?>[
          for (final entry in entries) entry.toJson(),
        ],
      };
}

/// One deterministic ZIP-compatible Restage build artifact.
@immutable
final class RestageBundle {
  /// Creates a bundle from complete exact delivery artifacts.
  RestageBundle({
    required this.packageName,
    required this.authoredLibraryPath,
    required Iterable<RestageBundleEntry> entries,
  }) : entries = List.unmodifiable(_canonicalPayloadEntries(entries)) {
    _validatePackageName(packageName);
    _validateAuthoredLibraryPath(authoredLibraryPath);
  }

  /// The owning package name.
  final String packageName;

  /// The authored package-relative Dart library path.
  final String authoredLibraryPath;

  /// Sorted payload entries. Empty payload bundles are valid.
  final List<RestageBundleEntry> entries;

  /// The metadata derived from the same exact bytes that are encoded.
  RestageBundleMetadata get metadata => RestageBundleMetadata(
        packageName: packageName,
        authoredLibraryPath: authoredLibraryPath,
        entries: <RestageBundleMetadataEntry>[
          for (final entry in entries)
            RestageBundleMetadataEntry(
              logicalPath: entry.logicalPath,
              role: entry.role,
              byteLength: entry.byteLength,
              sha256: entry.sha256,
            ),
        ],
      );
}

/// Strict canonical JSON codec for [RestageBundleMetadata].
abstract final class RestageBundleMetadataCodec {
  /// Encodes canonical metadata JSON with no whitespace or optional fields.
  static String encodeCanonicalJson(RestageBundleMetadata metadata) =>
      SurfaceContractJson.encode(metadata.toJson());

  /// Decodes and requires canonical metadata JSON.
  static RestageBundleMetadata decodeCanonicalJson(String source) {
    final decoded = SurfaceContractJson.decode(
      source,
      label: 'Restage bundle metadata',
    );
    final json = SurfaceContractJson.requireObject(decoded, r'$');
    SurfaceContractJson.exactKeys(
      json,
      const <String>{'schemaVersion', 'package', 'authoredLibrary', 'entries'},
      r'$',
    );
    final schemaVersion = SurfaceContractJson.requiredInt(
      json,
      'schemaVersion',
      r'$',
    );
    if (schemaVersion != kRestageBundleSchemaVersion) {
      throw FormatException(
        'Unsupported Restage bundle metadata schemaVersion $schemaVersion.',
      );
    }
    final packageName =
        SurfaceContractJson.requiredString(json, 'package', r'$');
    final authoredLibrary = SurfaceContractJson.requiredString(
      json,
      'authoredLibrary',
      r'$',
    );
    final rawEntries = SurfaceContractJson.requireList(
      SurfaceContractJson.requiredValue(json, 'entries', r'$'),
      r'$.entries',
    );
    final entries = <RestageBundleMetadataEntry>[];
    for (var index = 0; index < rawEntries.length; index += 1) {
      final entryPath = r'$.entries[' + index.toString() + ']';
      final entryJson = SurfaceContractJson.requireObject(
        rawEntries[index],
        entryPath,
      );
      SurfaceContractJson.exactKeys(
        entryJson,
        const <String>{'path', 'role', 'byteLength', 'sha256'},
        entryPath,
      );
      entries.add(
        RestageBundleMetadataEntry(
          logicalPath: SurfaceContractJson.requiredString(
            entryJson,
            'path',
            entryPath,
          ),
          role: RestageBundleEntryRoleV1.fromWireName(
            SurfaceContractJson.requiredString(entryJson, 'role', entryPath),
          ),
          byteLength: SurfaceContractJson.requiredInt(
            entryJson,
            'byteLength',
            entryPath,
          ),
          sha256: SurfaceContractJson.requiredString(
            entryJson,
            'sha256',
            entryPath,
          ),
        ),
      );
    }
    final metadata = RestageBundleMetadata(
      packageName: packageName,
      authoredLibraryPath: authoredLibrary,
      entries: entries,
    );
    if (!_sameMetadataEntryOrder(entries, metadata.entries)) {
      throw const FormatException(
        'Restage bundle metadata entries must be sorted by UTF-8 path bytes.',
      );
    }
    if (encodeCanonicalJson(metadata) != source) {
      throw const FormatException(
        'Restage bundle metadata is not canonical JSON.',
      );
    }
    return metadata;
  }
}

/// Deterministic strict encoder and decoder for `.rsbundle` files.
abstract final class RestageBundleCodec {
  /// Encodes [bundle] into the narrow, store-only ZIP profile.
  static Uint8List encode(RestageBundle bundle) {
    final metadata = bundle.metadata;
    final metadataBytes = Uint8List.fromList(
      utf8.encode(RestageBundleMetadataCodec.encodeCanonicalJson(metadata)),
    );
    final entries = <_ZipEntry>[
      _ZipEntry(path: kRestageBundleMetadataPath, bytes: metadataBytes),
      for (final entry in bundle.entries)
        _ZipEntry(path: entry.logicalPath, bytes: entry.bytes),
    ]..sort(_compareZipEntries);
    if (entries.length > _zipMaxEntries) {
      throw FormatException(
        'A Restage bundle cannot exceed $kRestageBundleMaxPayloadEntries '
        'payload entries.',
      );
    }

    final local = BytesBuilder(copy: false);
    final centralEntries = <_CentralDirectoryEntry>[];
    var localOffset = 0;
    for (final entry in entries) {
      final name = _utf8PathBytes(entry.path);
      final bytes = entry.bytes;
      _requireClassicZipValue(bytes.length, 'entry length for ${entry.path}');
      _requireClassicZipValue(localOffset, 'entry offset for ${entry.path}');
      final crc = _crc32(bytes);
      _writeUint32(local, _zipLocalFileHeaderSignature);
      _writeUint16(local, _zipVersionNeeded);
      _writeUint16(local, _zipUtf8Flag);
      _writeUint16(local, _zipStoreMethod);
      _writeUint16(local, _zipMinimumDosTime);
      _writeUint16(local, _zipMinimumDosDate);
      _writeUint32(local, crc);
      _writeUint32(local, bytes.length);
      _writeUint32(local, bytes.length);
      _writeUint16(local, name.length);
      _writeUint16(local, 0);
      local
        ..add(name)
        ..add(bytes);
      centralEntries.add(
        _CentralDirectoryEntry(
          path: entry.path,
          name: name,
          bytes: bytes,
          crc: crc,
          localOffset: localOffset,
          declaredLength: bytes.length,
        ),
      );
      localOffset += 30 + name.length + bytes.length;
      _requireClassicZipValue(localOffset, 'local ZIP section length');
    }

    final central = BytesBuilder(copy: false);
    for (final entry in centralEntries) {
      _writeUint32(central, _zipCentralDirectoryHeaderSignature);
      _writeUint16(central, _zipVersionMadeBy);
      _writeUint16(central, _zipVersionNeeded);
      _writeUint16(central, _zipUtf8Flag);
      _writeUint16(central, _zipStoreMethod);
      _writeUint16(central, _zipMinimumDosTime);
      _writeUint16(central, _zipMinimumDosDate);
      _writeUint32(central, entry.crc);
      _writeUint32(central, entry.bytes.length);
      _writeUint32(central, entry.bytes.length);
      _writeUint16(central, entry.name.length);
      _writeUint16(central, 0);
      _writeUint16(central, 0);
      _writeUint16(central, 0);
      _writeUint16(central, 0);
      _writeUint32(central, _zipUnixRegularFile0644);
      _writeUint32(central, entry.localOffset);
      central.add(entry.name);
    }
    final centralBytes = central.takeBytes();
    _requireClassicZipValue(
        centralBytes.length, 'central ZIP directory length');
    final archiveLength = localOffset + centralBytes.length + 22;
    _requireClassicZipValue(archiveLength, 'Restage bundle length');

    final output = BytesBuilder(copy: false)
      ..add(local.takeBytes())
      ..add(centralBytes);
    _writeUint32(output, _zipEndOfCentralDirectorySignature);
    _writeUint16(output, 0);
    _writeUint16(output, 0);
    _writeUint16(output, entries.length);
    _writeUint16(output, entries.length);
    _writeUint32(output, centralBytes.length);
    _writeUint32(output, localOffset);
    _writeUint16(output, 0);
    return output.takeBytes();
  }

  /// Decodes only the deterministic store-only ZIP profile emitted by [encode].
  static RestageBundle decode(List<int> source) {
    final bytes = _copyOctets(source, label: 'Restage bundle bytes');
    if (bytes.length < 22) {
      throw const FormatException('Restage bundle is missing its ZIP footer.');
    }
    _requireClassicZipValue(bytes.length, 'Restage bundle length');
    final footer = bytes.length - 22;
    _expectUint32(
      bytes,
      footer,
      _zipEndOfCentralDirectorySignature,
      'ZIP footer signature',
    );
    if (_readUint16(bytes, footer + 4, 'ZIP disk number') != 0 ||
        _readUint16(bytes, footer + 6, 'ZIP central disk number') != 0) {
      throw const FormatException('Restage bundle must use one ZIP disk.');
    }
    final entriesOnDisk = _readUint16(bytes, footer + 8, 'ZIP entry count');
    final entryCount = _readUint16(bytes, footer + 10, 'ZIP entry count');
    if (entriesOnDisk != entryCount || entryCount == 0) {
      throw const FormatException(
          'Restage bundle has an invalid ZIP entry count.');
    }
    final centralLength =
        _readUint32(bytes, footer + 12, 'central directory length');
    final centralOffset =
        _readUint32(bytes, footer + 16, 'central directory offset');
    final commentLength = _readUint16(bytes, footer + 20, 'ZIP comment length');
    if (commentLength != 0 || centralOffset + centralLength != footer) {
      throw const FormatException(
        'Restage bundle ZIP directory or comment is not canonical.',
      );
    }

    final centralEntries = <_CentralDirectoryEntry>[];
    var cursor = centralOffset;
    String? previousPath;
    final seenPaths = <String>{};
    for (var index = 0; index < entryCount; index += 1) {
      _expectUint32(
        bytes,
        cursor,
        _zipCentralDirectoryHeaderSignature,
        'central directory entry $index signature',
      );
      _expectUint16(bytes, cursor + 4, _zipVersionMadeBy, 'version made by');
      _expectUint16(bytes, cursor + 6, _zipVersionNeeded, 'version needed');
      _expectUint16(
          bytes, cursor + 8, _zipUtf8Flag, 'ZIP general-purpose flags');
      _expectUint16(
          bytes, cursor + 10, _zipStoreMethod, 'ZIP compression method');
      _expectUint16(bytes, cursor + 12, _zipMinimumDosTime, 'ZIP timestamp');
      _expectUint16(bytes, cursor + 14, _zipMinimumDosDate, 'ZIP timestamp');
      final crc = _readUint32(bytes, cursor + 16, 'central entry CRC-32');
      final compressedLength = _readUint32(
        bytes,
        cursor + 20,
        'central entry compressed length',
      );
      final uncompressedLength = _readUint32(
        bytes,
        cursor + 24,
        'central entry uncompressed length',
      );
      if (compressedLength != uncompressedLength) {
        throw const FormatException(
            'Restage bundle entries must use ZIP store mode.');
      }
      final nameLength =
          _readUint16(bytes, cursor + 28, 'central entry name length');
      final extraLength =
          _readUint16(bytes, cursor + 30, 'central entry extra length');
      final entryCommentLength = _readUint16(
        bytes,
        cursor + 32,
        'central entry comment length',
      );
      if (nameLength == 0 ||
          extraLength != 0 ||
          entryCommentLength != 0 ||
          _readUint16(bytes, cursor + 34, 'central entry disk number') != 0 ||
          _readUint16(bytes, cursor + 36, 'central entry attributes') != 0 ||
          _readUint32(bytes, cursor + 38, 'central entry attributes') !=
              _zipUnixRegularFile0644) {
        throw const FormatException(
            'Restage bundle has non-canonical ZIP metadata.');
      }
      final localOffset = _readUint32(bytes, cursor + 42, 'local entry offset');
      final next = cursor + 46 + nameLength;
      if (next > centralOffset + centralLength) {
        throw const FormatException(
            'Restage bundle central directory is truncated.');
      }
      final name = Uint8List.sublistView(bytes, cursor + 46, next);
      final path = _decodeUtf8Path(name, 'central directory entry $index');
      _validateZipPath(path);
      if (!seenPaths.add(path) ||
          (previousPath != null &&
              SurfaceContractJson.compareUtf8(previousPath, path) >= 0)) {
        throw const FormatException(
          'Restage bundle entry paths must be unique and UTF-8-byte sorted.',
        );
      }
      previousPath = path;
      centralEntries.add(
        _CentralDirectoryEntry(
          path: path,
          name: name,
          bytes: Uint8List(0),
          crc: crc,
          localOffset: localOffset,
          declaredLength: uncompressedLength,
        ),
      );
      cursor = next;
    }
    if (cursor != centralOffset + centralLength) {
      throw const FormatException(
          'Restage bundle central directory has trailing data.');
    }

    var localCursor = 0;
    final bytesByPath = <String, Uint8List>{};
    for (final entry in centralEntries) {
      if (entry.localOffset != localCursor) {
        throw const FormatException(
          'Restage bundle local ZIP entries are not contiguous and ordered.',
        );
      }
      _expectUint32(
        bytes,
        localCursor,
        _zipLocalFileHeaderSignature,
        'local ZIP entry signature',
      );
      _expectUint16(
          bytes, localCursor + 4, _zipVersionNeeded, 'version needed');
      _expectUint16(
          bytes, localCursor + 6, _zipUtf8Flag, 'ZIP general-purpose flags');
      _expectUint16(
          bytes, localCursor + 8, _zipStoreMethod, 'ZIP compression method');
      _expectUint16(
          bytes, localCursor + 10, _zipMinimumDosTime, 'ZIP timestamp');
      _expectUint16(
          bytes, localCursor + 12, _zipMinimumDosDate, 'ZIP timestamp');
      final crc = _readUint32(bytes, localCursor + 14, 'local entry CRC-32');
      final compressedLength = _readUint32(
        bytes,
        localCursor + 18,
        'local entry compressed length',
      );
      final uncompressedLength = _readUint32(
        bytes,
        localCursor + 22,
        'local entry uncompressed length',
      );
      final nameLength =
          _readUint16(bytes, localCursor + 26, 'local entry name length');
      final extraLength =
          _readUint16(bytes, localCursor + 28, 'local entry extra length');
      if (crc != entry.crc ||
          compressedLength != entry.declaredLength ||
          uncompressedLength != entry.declaredLength ||
          extraLength != 0 ||
          nameLength != entry.name.length) {
        throw const FormatException(
            'Restage bundle local ZIP entry disagrees with directory.');
      }
      final nameStart = localCursor + 30;
      final contentStart = nameStart + nameLength;
      final contentEnd = contentStart + entry.declaredLength;
      if (contentEnd > centralOffset ||
          !_sameBytes(Uint8List.sublistView(bytes, nameStart, contentStart),
              entry.name)) {
        throw const FormatException(
            'Restage bundle local ZIP entry is malformed.');
      }
      final content =
          Uint8List.fromList(bytes.sublist(contentStart, contentEnd));
      if (_crc32(content) != entry.crc) {
        throw FormatException(
            'Restage bundle entry "${entry.path}" has an invalid CRC-32.');
      }
      bytesByPath[entry.path] = content;
      localCursor = contentEnd;
    }
    if (localCursor != centralOffset) {
      throw const FormatException(
          'Restage bundle has unexpected bytes before its directory.');
    }

    final metadataBytes = bytesByPath.remove(kRestageBundleMetadataPath);
    if (metadataBytes == null) {
      throw const FormatException(
          'Restage bundle is missing its metadata entry.');
    }
    final metadataSource =
        _decodeUtf8(metadataBytes, 'Restage bundle metadata');
    final metadata =
        RestageBundleMetadataCodec.decodeCanonicalJson(metadataSource);
    if (metadata.entries.length != bytesByPath.length) {
      throw const FormatException(
          'Restage bundle metadata does not describe every payload entry.');
    }

    final entries = <RestageBundleEntry>[];
    for (final metadataEntry in metadata.entries) {
      final payload = bytesByPath.remove(metadataEntry.logicalPath);
      if (payload == null ||
          payload.length != metadataEntry.byteLength ||
          _sha256(payload) != metadataEntry.sha256) {
        throw FormatException(
          'Restage bundle metadata does not match "${metadataEntry.logicalPath}".',
        );
      }
      entries.add(
        RestageBundleEntry(
          logicalPath: metadataEntry.logicalPath,
          role: metadataEntry.role,
          bytes: payload,
        ),
      );
    }
    if (bytesByPath.isNotEmpty) {
      throw const FormatException(
          'Restage bundle contains an unlisted payload entry.');
    }
    final bundle = RestageBundle(
      packageName: metadata.packageName,
      authoredLibraryPath: metadata.authoredLibraryPath,
      entries: entries,
    );
    if (RestageBundleMetadataCodec.encodeCanonicalJson(bundle.metadata) !=
        metadataSource) {
      throw const FormatException(
          'Restage bundle metadata changed during decoding.');
    }
    return bundle;
  }
}

@immutable
final class _ZipEntry {
  _ZipEntry({required this.path, required List<int> bytes})
      : bytes = _copyOctets(bytes, label: 'ZIP entry bytes');

  final String path;
  final Uint8List bytes;
}

@immutable
final class _CentralDirectoryEntry {
  const _CentralDirectoryEntry({
    required this.path,
    required this.name,
    required this.bytes,
    required this.crc,
    required this.localOffset,
    required this.declaredLength,
  });

  final String path;
  final Uint8List name;
  final Uint8List bytes;
  final int crc;
  final int localOffset;
  final int declaredLength;
}

List<RestageBundleEntry> _canonicalPayloadEntries(
  Iterable<RestageBundleEntry> values,
) =>
    _canonicalEntries(
      values,
      (entry) => entry.logicalPath,
      duplicateLabel: 'Restage bundle path',
    );

List<RestageBundleMetadataEntry> _canonicalMetadataEntries(
  Iterable<RestageBundleMetadataEntry> values,
) =>
    _canonicalEntries(
      values,
      (entry) => entry.logicalPath,
      duplicateLabel: 'Restage bundle metadata path',
    );

/// Sorts [values] into the one canonical bundle order — ascending UTF-8 path
/// bytes — and rejects an over-long or path-duplicating set.
///
/// Payload entries and their metadata records are ordered and bounded by the
/// same rule, so both resolve through this; only the label distinguishing the
/// two duplicate diagnostics differs.
List<T> _canonicalEntries<T>(
  Iterable<T> values,
  String Function(T entry) pathOf, {
  required String duplicateLabel,
}) {
  final entries = List<T>.of(values)
    ..sort((left, right) =>
        SurfaceContractJson.compareUtf8(pathOf(left), pathOf(right)));
  if (entries.length > kRestageBundleMaxPayloadEntries) {
    throw FormatException(
      'A Restage bundle cannot exceed $kRestageBundleMaxPayloadEntries '
      'payload entries.',
    );
  }
  final paths = <String>{};
  for (final entry in entries) {
    if (!paths.add(pathOf(entry))) {
      throw FormatException('Duplicate $duplicateLabel "${pathOf(entry)}".');
    }
  }
  return entries;
}

bool _sameMetadataEntryOrder(
  List<RestageBundleMetadataEntry> left,
  List<RestageBundleMetadataEntry> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    final leftEntry = left[index];
    final rightEntry = right[index];
    if (leftEntry.logicalPath != rightEntry.logicalPath ||
        leftEntry.role != rightEntry.role ||
        leftEntry.byteLength != rightEntry.byteLength ||
        leftEntry.sha256 != rightEntry.sha256) {
      return false;
    }
  }
  return true;
}

int _compareZipEntries(_ZipEntry left, _ZipEntry right) =>
    SurfaceContractJson.compareUtf8(left.path, right.path);

void _validatePackageName(String value) {
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value)) {
    throw FormatException('Invalid Restage bundle package name "$value".');
  }
}

void _validateAuthoredLibraryPath(String value) {
  _validateZipPath(value);
  if (!value.startsWith('lib/') ||
      !value.endsWith('.dart') ||
      value.length <= 'lib/.dart'.length) {
    throw FormatException(
      'Restage bundle authored library must be a non-empty lib/*.dart path.',
    );
  }
}

void _validatePayloadPath(String value) {
  _validateZipPath(value);
  if (value == kRestageBundleMetadataPath) {
    throw const FormatException(
      'A Restage bundle payload cannot use the reserved metadata path.',
    );
  }
}

void _validateZipPath(String value) {
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.contains('\\') ||
      value.contains('\u0000') ||
      RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(value)) {
    throw FormatException('Invalid Restage bundle path "$value".');
  }
  SurfaceContractJson.requireUnicodeScalars(value, 'Restage bundle path');
  final segments = value.split('/');
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    throw FormatException('Invalid Restage bundle path "$value".');
  }
  _utf8PathBytes(value);
}

Uint8List _utf8PathBytes(String value) {
  final bytes = Uint8List.fromList(utf8.encode(value));
  if (bytes.isEmpty || bytes.length > _zipMaxFilenameBytes) {
    throw FormatException(
        'Restage bundle path "$value" has an invalid length.');
  }
  return bytes;
}

Uint8List _copyOctets(List<int> values, {required String label}) {
  if (values.length > kRestageBundleMaxClassicZipValue) {
    throw FormatException('$label exceeds the classic-ZIP limit.');
  }
  for (final value in values) {
    if (value < 0 || value > 255) {
      throw FormatException('$label must contain only unsigned octets.');
    }
  }
  return Uint8List.fromList(values);
}

String _sha256(List<int> bytes) => 'sha256:${crypto.sha256.convert(bytes)}';

int _crc32(List<int> bytes) {
  var value = 0xFFFFFFFF;
  for (final byte in bytes) {
    value ^= byte;
    for (var bit = 0; bit < 8; bit += 1) {
      value = (value & 1) == 0 ? value >>> 1 : (value >>> 1) ^ 0xEDB88320;
    }
  }
  return (value ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

void _requireClassicZipValue(int value, String label) {
  if (value < 0 || value > kRestageBundleMaxClassicZipValue) {
    throw FormatException('$label exceeds the no-ZIP64 limit.');
  }
}

void _writeUint16(BytesBuilder output, int value) {
  if (value < 0 || value > 0xFFFF) {
    throw RangeError.range(value, 0, 0xFFFF, 'value');
  }
  output
    ..addByte(value & 0xFF)
    ..addByte((value >>> 8) & 0xFF);
}

void _writeUint32(BytesBuilder output, int value) {
  _requireClassicZipValue(value, 'ZIP integer');
  output
    ..addByte(value & 0xFF)
    ..addByte((value >>> 8) & 0xFF)
    ..addByte((value >>> 16) & 0xFF)
    ..addByte((value >>> 24) & 0xFF);
}

int _readUint16(Uint8List bytes, int offset, String label) {
  if (offset < 0 || offset + 2 > bytes.length) {
    throw FormatException('Restage bundle is truncated while reading $label.');
  }
  return bytes[offset] | (bytes[offset + 1] << 8);
}

int _readUint32(Uint8List bytes, int offset, String label) {
  if (offset < 0 || offset + 4 > bytes.length) {
    throw FormatException('Restage bundle is truncated while reading $label.');
  }
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

void _expectUint16(Uint8List bytes, int offset, int expected, String label) {
  final actual = _readUint16(bytes, offset, label);
  if (actual != expected) {
    throw FormatException('Restage bundle has non-canonical $label.');
  }
}

void _expectUint32(Uint8List bytes, int offset, int expected, String label) {
  final actual = _readUint32(bytes, offset, label);
  if (actual != expected) {
    throw FormatException('Restage bundle has non-canonical $label.');
  }
}

String _decodeUtf8Path(Uint8List bytes, String label) {
  final value = _decodeUtf8(bytes, label);
  if (!_sameBytes(Uint8List.fromList(utf8.encode(value)), bytes)) {
    throw FormatException('Restage bundle $label is not canonical UTF-8.');
  }
  return value;
}

String _decodeUtf8(Uint8List bytes, String label) {
  try {
    return utf8.decode(bytes);
  } on FormatException catch (error) {
    throw FormatException('Invalid UTF-8 in $label: ${error.message}');
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
