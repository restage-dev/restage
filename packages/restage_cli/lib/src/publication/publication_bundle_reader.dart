import 'dart:io';
import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';

import 'publication_errors.dart';

/// The decoded metadata and exact bytes for one requested bundle entry.
///
/// The decoding is supplied by the shared bundle codec. Keeping this result
/// small means the publication layer never needs to know how a `.rsbundle` is
/// encoded or extract the archive as a whole.
final class PublicationBundleEntry {
  /// Construct one decoded bundle entry.
  PublicationBundleEntry({
    required this.path,
    required this.role,
    required this.size,
    required this.sha256,
    required List<int> bytes,
  }) : bytes = Uint8List.fromList(bytes);

  /// The path recorded by the bundle metadata.
  final String path;

  /// The closed publication role recorded by the bundle metadata.
  final SurfacePublicationArtifactRoleV1 role;

  /// The byte length recorded by the bundle metadata.
  final int size;

  /// The SHA-256 recorded by the bundle metadata.
  final String sha256;

  /// The exact bytes stored under [path].
  final Uint8List bytes;
}

/// Reads one exact entry from a deterministic bundle.
///
/// This interface deliberately does not expose archive bytes or an archive
/// parser to the publication code.
abstract interface class PublicationBundleReader {
  /// Read [entryPath] from [bundleFile] and return its verified metadata.
  Future<PublicationBundleEntry> readEntry({
    required File bundleFile,
    required String entryPath,
  });
}

/// Default-reader seam used by command construction and focused tests.
///
/// Tests may assign [override] for one in-memory fixture without changing the
/// command's public flags.
final class PublicationBundleReaderProvider {
  const PublicationBundleReaderProvider._();

  /// Optional process-local test or integration override.
  static PublicationBundleReader? override;

  /// The reader used when a command does not receive an explicit reader.
  static PublicationBundleReader get current =>
      override ?? RestageBundlePublicationReader();
}

/// Adapter over the shared deterministic bundle codec.
///
/// The adapter decodes the bundle only to obtain the requested exact entry;
/// the caller still uploads the assembled delivery payload, never the bundle
/// file itself.
final class RestageBundlePublicationReader implements PublicationBundleReader {
  /// Construct the shared-codec adapter.
  RestageBundlePublicationReader();

  /// Bundles already decoded by this reader, keyed by absolute path.
  ///
  /// One `.rsbundle` holds every artifact of every publication compiled from
  /// one authored library, and decoding it verifies a CRC-32 and a SHA-256
  /// over every entry. Decoding per artifact therefore re-reads and re-hashes
  /// the whole file once per artifact, and publishing several surfaces from
  /// one file multiplies that again. One reader serves one command, so this
  /// collapses the work to one read per distinct bundle without widening any
  /// lifetime.
  final Map<String, Future<RestageBundle>> _decoded =
      <String, Future<RestageBundle>>{};

  @override
  Future<PublicationBundleEntry> readEntry({
    required File bundleFile,
    required String entryPath,
  }) async {
    final bundle = await _decode(bundleFile);
    for (final entry in bundle.entries) {
      if (entry.logicalPath == entryPath) {
        final SurfacePublicationArtifactRoleV1 role;
        try {
          role = entry.role.toManifestRole();
        } on StateError {
          throw PublicationBundleException(
            'The bundle entry "$entryPath" is recorded as '
            '${entry.role.wireName}, which is not a valid publication '
            'manifest role.',
          );
        }
        return PublicationBundleEntry(
          path: entry.logicalPath,
          role: role,
          size: entry.byteLength,
          sha256: entry.sha256,
          bytes: entry.bytes,
        );
      }
    }
    throw PublicationBundleException(
      'The bundle does not contain declared entry "$entryPath".',
    );
  }

  Future<RestageBundle> _decode(File bundleFile) {
    final key = bundleFile.absolute.path;
    final existing = _decoded[key];
    if (existing != null) return existing;
    // A failed decode evicts itself, so a transient read failure cannot
    // poison the rest of the run. Eviction happens inside this future rather
    // than on a derived one, which would surface the error twice.
    final decoded = () async {
      try {
        return RestageBundleCodec.decode(await bundleFile.readAsBytes());
      } on FileSystemException {
        _decoded.remove(key);
        rethrow;
      } on Object catch (error) {
        _decoded.remove(key);
        throw PublicationBundleException(
          'The bundle could not be decoded: $error',
        );
      }
    }();
    _decoded[key] = decoded;
    return decoded;
  }
}
