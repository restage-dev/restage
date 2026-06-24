import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_shared/src/capability/capability_manifest.dart';
import 'package:restage_shared/src/surface_document/surface_document.dart';

/// The surface document envelope format version written by the codec encoder.
///
/// The envelope header is strict (unknown fields are rejected), so this version
/// is the single forward-compatibility lever: any future envelope-shape change
/// bumps it, and older readers fail closed on a higher version rather than
/// silently mis-reading a shape they do not understand.
///
/// Version 2 adds the `requiredLibraries` capability manifest (header + hashed
/// payload). A version-1 reader fails closed on a version-2 envelope; a
/// version-2 reader decodes a version-1 envelope, defaulting the required
/// libraries to the empty list.
const int kSurfaceEnvelopeFormatVersion = 2;

/// The highest envelope format version this build can decode. An envelope
/// declaring a higher version is rejected (fail-closed), never guessed.
const int kMaxSupportedSurfaceEnvelopeVersion = 2;

/// Codec for the self-contained surface document envelope.
abstract final class SurfaceDocumentCodec {
  /// Encodes a surface document envelope.
  static Uint8List encode(SurfaceDocument document) {
    // Keys are written in ascending order (the header is a sorted-key JSON
    // object). `requiredLibraries` is ALWAYS emitted — including the empty list
    // — so a reader never distinguishes "absent" from "empty" within a known
    // version, and the encoding is deterministic for golden comparison.
    final headerBytes = utf8.encode(
      jsonEncode({
        'contentHash': document.contentHash,
        'formatVersion': kSurfaceEnvelopeFormatVersion,
        'minClient': document.minClient,
        'publishedAtMicros':
            document.publishedAt.toUtc().microsecondsSinceEpoch,
        'requiredLibraries':
            document.requiredLibraries.map((r) => r.toJson()).toList(),
        'surfaceSlug': document.surfaceSlug,
        'surfaceType': document.surfaceType.wireName,
        'version': document.version,
      }),
    );
    final builder = BytesBuilder()
      ..add(_u32be(headerBytes.length))
      ..add(headerBytes)
      ..add(document.payload.canonicalBytes);
    return builder.toBytes();
  }

  /// Decodes a surface document envelope.
  static SurfaceDocument decode(List<int> bytes) {
    try {
      final reader = _EnvelopeReader(bytes);
      final headerBytes = reader.readLengthPrefixedBytes('header');
      final payloadBytes = reader.remainingBytes();
      final header = _parseHeader(headerBytes);
      // The format version is read + gated FIRST — before unknown-key
      // rejection — so a reader meeting a newer envelope fails with a clean
      // "unsupported version" diagnostic rather than a misleading "unsupported
      // field" one for a key that version legitimately added.
      final formatVersion = _requiredInt(header, 'formatVersion');
      if (formatVersion < 1 ||
          formatVersion > kMaxSupportedSurfaceEnvelopeVersion) {
        throw FormatException(
          'Unsupported surface envelope format version $formatVersion.',
        );
      }
      // Within a supported version, the header is still strict.
      _rejectUnknownKeys(header, _allowedHeaderKeys);
      // The required-libraries manifest is version-scoped: a version-2 envelope
      // MUST carry it (a missing key would silently decode to the empty list);
      // a version-1 envelope MUST NOT (the key did not exist there). This is
      // the header twin of the payload-side version-strict decode below.
      final carriesManifest = header.containsKey('requiredLibraries');
      final requiresManifest = formatVersion >= 2;
      if (requiresManifest && !carriesManifest) {
        throw const FormatException(
          'A format-version-2 envelope is missing the "requiredLibraries" '
          'header.',
        );
      }
      if (!requiresManifest && carriesManifest) {
        throw const FormatException(
          'The "requiredLibraries" header requires format version 2.',
        );
      }

      final headerContentHash = _requiredString(header, 'contentHash');
      final expectedContentHash =
          'sha256:${crypto.sha256.convert(payloadBytes)}';
      if (headerContentHash != expectedContentHash) {
        throw const FormatException('Surface payload content hash mismatch.');
      }

      // Version-strict the payload: a version-2 envelope's payload must carry
      // its section, failing closed on a section-less version-2 frame.
      final payload = SurfacePayload.decode(
        payloadBytes,
        requireRequiredLibraries: requiresManifest,
      );
      final minClient = _requiredInt(header, 'minClient');
      if (minClient != payload.minClient) {
        throw const FormatException(
          'Header minClient does not match the payload.',
        );
      }

      // The header copy of the capability manifest is NOT inside the content
      // hash, so it is cross-checked against the hashed payload copy (which
      // is). Compared in wire order against the canonical payload list, so a
      // tampered or reordered header is detected (legit headers are canonical).
      final headerLibraries = _headerRequiredLibraries(header);
      if (!_libsEqual(headerLibraries, payload.requiredLibraries)) {
        throw const FormatException(
          'Header requiredLibraries do not match the payload.',
        );
      }

      return SurfaceDocument(
        surfaceType: SurfaceType.fromWireName(
          _requiredString(header, 'surfaceType'),
        ),
        surfaceSlug: _requiredString(header, 'surfaceSlug'),
        version: _requiredInt(header, 'version'),
        minClient: minClient,
        requiredLibraries: headerLibraries,
        payload: payload,
        publishedAt: DateTime.fromMicrosecondsSinceEpoch(
          _requiredInt(header, 'publishedAtMicros'),
          isUtc: true,
        ),
      );
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      if (error is ArgumentError) {
        throw FormatException('Invalid surface document: ${error.message}');
      }
      rethrow;
    }
  }
}

/// Header keys this build understands. Unknown-key rejection runs only AFTER
/// the format-version gate, so a newer version's added keys never masquerade as
/// "unsupported field" on an old reader (it fails the version gate first).
const Set<String> _allowedHeaderKeys = {
  'contentHash',
  'formatVersion',
  'minClient',
  'publishedAtMicros',
  'requiredLibraries',
  'surfaceSlug',
  'surfaceType',
  'version',
};

/// Parses the header JSON to a map WITHOUT rejecting unknown keys — that
/// rejection is deferred until after the format-version gate (see
/// [SurfaceDocumentCodec.decode]).
Map<String, Object?> _parseHeader(Uint8List bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Surface document header must be an object.');
  }
  return decoded;
}

/// Reads the header `requiredLibraries`, tolerant of a version-1 envelope
/// (absent key ⇒ empty list). Returned in wire order so the caller can detect a
/// reordered/tampered header against the canonical (hashed) payload copy.
List<LibraryRequirement> _headerRequiredLibraries(Map<String, Object?> header) {
  if (!header.containsKey('requiredLibraries')) return const [];
  final raw = header['requiredLibraries'];
  if (raw is! List) {
    throw const FormatException('Header "requiredLibraries" must be a list.');
  }
  return [
    for (final entry in raw)
      if (entry is Map<String, dynamic>)
        LibraryRequirement.fromJson(entry)
      else
        throw const FormatException(
          'Header "requiredLibraries" entries must be objects.',
        ),
  ];
}

/// Order-sensitive element equality for two requirement lists.
bool _libsEqual(List<LibraryRequirement> a, List<LibraryRequirement> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

void _rejectUnknownKeys(
  Map<String, Object?> json,
  Set<String> allowedKeys,
) {
  final unknownKeys = json.keys.where((key) => !allowedKeys.contains(key));
  if (unknownKeys.isEmpty) return;
  throw FormatException('Unsupported header field "${unknownKeys.first}".');
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = _required(json, key);
  if (value is String) return value;
  throw FormatException('Expected "$key" to be a string.');
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = _required(json, key);
  if (value is int) return value;
  if (value is double) {
    throw FormatException('Expected "$key" to be an integer, got double.');
  }
  throw FormatException('Expected "$key" to be an integer.');
}

Object? _required(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing required header field "$key".');
  }
  final value = json[key];
  if (value == null) {
    throw FormatException('Header field "$key" cannot be null.');
  }
  return value;
}

Uint8List _u32be(int value) {
  if (value < 0 || value > 0xFFFFFFFF) {
    throw ArgumentError.value(value, 'value', 'must fit in u32');
  }
  final bytes = Uint8List(4);
  ByteData.view(bytes.buffer).setUint32(0, value);
  return bytes;
}

final class _EnvelopeReader {
  _EnvelopeReader(List<int> bytes) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;
  int _offset = 0;

  Uint8List readLengthPrefixedBytes(String label) {
    final length = _readUint32('$label length');
    _ensureAvailable(length, label);
    final bytes = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return Uint8List.fromList(bytes);
  }

  Uint8List remainingBytes() {
    final bytes = Uint8List.sublistView(_bytes, _offset);
    _offset = _bytes.length;
    return Uint8List.fromList(bytes);
  }

  int _readUint32(String label) {
    _ensureAvailable(4, label);
    final value = ByteData.view(_bytes.buffer).getUint32(_offset);
    _offset += 4;
    return value;
  }

  void _ensureAvailable(int length, String label) {
    if (_offset + length > _bytes.length) {
      throw FormatException('Truncated $label.');
    }
  }
}
