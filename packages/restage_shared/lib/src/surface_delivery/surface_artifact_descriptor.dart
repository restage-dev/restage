/// THREE VERSION DOMAINS TRAVEL TOGETHER HERE AND NONE OF THEM IS THE OTHER.
/// They are numbered independently and they are currently different numbers, so
/// anything that reads one must say which one it means.
///
///  * [kSurfaceArtifactDescriptorVersion] — the shape of THIS metadata object.
///    Bumped when a field is added, removed, or re-meant.
///  * [kSurfaceArtifactPayloadFormatVersion] — the shape of the separately
///    fetched payload frame, and the partition its stored copy lives under. A
///    frame written under one value is a different artifact from the same bytes
///    written under another.
///  * The document envelope format version (`kSurfaceEnvelopeFormatVersion`) —
///    the shape of the SELF-CONTAINED document. It governs the frame's internal
///    strictness, which is why decoding a fetched frame has to translate from
///    the payload format version rather than assume the two agree.
///
/// The translation is stated once, in [surfaceArtifactFrameRequiresManifest],
/// so no caller re-derives it.
library;

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_shared/src/surface_document/surface_document.dart';

/// The descriptor shape this build writes.
const int kSurfaceArtifactDescriptorVersion = 1;

/// The highest descriptor shape this build can read. A descriptor declaring
/// more is refused, never guessed at.
const int kMaxSupportedSurfaceArtifactDescriptorVersion = 1;

/// The payload frame format this build writes.
const int kSurfaceArtifactPayloadFormatVersion = 1;

/// The highest payload frame format this build can read.
const int kMaxSupportedSurfaceArtifactPayloadFormatVersion = 1;

/// Whether a payload frame stored under [payloadFormatVersion] must carry a
/// capability-requirement section.
///
/// Payload format 1 is the frame shape that always carries one. Without this
/// translation a decoder would fall back to the tolerant reading, and a frame
/// whose section had been stripped would decode to "requires nothing" instead
/// of failing — turning a tampered artifact into a renderable one.
bool surfaceArtifactFrameRequiresManifest(int payloadFormatVersion) =>
    payloadFormatVersion >= 1;

/// Everything about a published surface EXCEPT the bytes that render it.
///
/// Delivery sends this inline and the payload frame separately. Every field
/// here is sourced from the publication record; nothing is echoed back from the
/// request, so a descriptor cannot be steered by asking for something else.
///
/// Two facts a reader might expect are deliberately absent: the minimum client
/// capability and the required custom libraries. Both live inside the payload
/// frame, covered by its content hash, and are read from there after the fetch.
/// Carrying a second copy here would create a claim that could disagree with
/// the hashed one — the disagreement this design removes by construction rather
/// than by checking.
@immutable
final class SurfaceArtifactDescriptorV1 {
  /// Creates a descriptor, validating every field it will later be trusted for.
  factory SurfaceArtifactDescriptorV1({
    required int payloadFormatVersion,
    required Surface surfaceType,
    required String surfaceSlug,
    required int version,
    required int publishedAtMicros,
    required String contentHash,
    required String artifactUrl,
    required String artifactPass,
    String? payloadKind,
  }) {
    if (payloadFormatVersion < 1) {
      throw const FormatException(
        'A payload format version must be positive.',
      );
    }
    if (payloadKind != null &&
        (payloadKind.isEmpty || payloadKind.trim() != payloadKind)) {
      throw const FormatException(
        'A payload kind must be a trimmed, non-empty discriminator, or '
        'absent.',
      );
    }
    if (surfaceSlug.isEmpty || surfaceSlug.trim() != surfaceSlug) {
      throw const FormatException('A surface slug must be a trimmed, '
          'non-empty identifier.');
    }
    if (version < 1) {
      throw const FormatException('A published version must be positive.');
    }
    if (!_contentHashPattern.hasMatch(contentHash)) {
      throw FormatException(
        'A content hash must be sha256:<64 lowercase hex>, got "$contentHash".',
      );
    }
    final parsed = Uri.tryParse(artifactUrl);
    if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
      throw const FormatException(
        'An artifact URL must be absolute.',
      );
    }
    if (parsed.userInfo.isNotEmpty) {
      throw const FormatException(
        'An artifact URL must not carry credentials.',
      );
    }
    if (artifactPass.isEmpty) {
      throw const FormatException('An artifact pass must not be empty.');
    }
    return SurfaceArtifactDescriptorV1._(
      payloadFormatVersion: payloadFormatVersion,
      surfaceType: surfaceType,
      surfaceSlug: surfaceSlug,
      version: version,
      publishedAtMicros: publishedAtMicros,
      contentHash: contentHash,
      artifactUrl: artifactUrl,
      artifactPass: artifactPass,
      payloadKind: payloadKind,
    );
  }

  const SurfaceArtifactDescriptorV1._({
    required this.payloadFormatVersion,
    required this.surfaceType,
    required this.surfaceSlug,
    required this.version,
    required this.publishedAtMicros,
    required this.contentHash,
    required this.artifactUrl,
    required this.artifactPass,
    required this.payloadKind,
  });

  /// The format the payload frame is stored under. NOT the descriptor's own
  /// version, and NOT the self-contained document's envelope version.
  final int payloadFormatVersion;

  /// Surface category, from the publication record.
  final Surface surfaceType;

  /// Surface identifier within its category, from the publication record.
  final String surfaceSlug;

  /// The published version being delivered.
  final int version;

  /// Publication time, microseconds since the Unix epoch, UTC.
  final int publishedAtMicros;

  /// What the payload frame must hash to. The integrity anchor for the fetch:
  /// bytes that do not hash to this are not the artifact, whatever served them.
  final String contentHash;

  /// Where to fetch the payload frame. Supplied per delivery, so the client
  /// needs no configured artifact origin of its own and a deployment can move
  /// its storage without a client release.
  final String artifactUrl;

  /// Short-lived authorisation for exactly one artifact fetch.
  final String artifactPass;

  /// The stored payload-shape discriminator this delivery was routed on, or
  /// null when no explicit discriminator drove the routing.
  ///
  /// Not a description of the bytes — a claim the record makes about them,
  /// carried so the reader can check the two agree. The publication record
  /// stores the shape alongside the bytes and routes on it; the bytes carry
  /// their own kind. When the record made that claim, the reader re-checks it
  /// against the frame it decoded, and a disagreement means the record and the
  /// bytes have diverged: refuse, rather than render something that arrived
  /// through the wrong route. Null carries "the record made no claim", which
  /// is the shape-agnostic route's own state, and skips the check exactly as
  /// it always did.
  ///
  /// Deliberately the raw discriminator rather than a closed enum: the check is
  /// a strict equality against the frame's own kind string, and widening either
  /// side into a parsed type would turn a value this build does not recognise
  /// into a decode failure of the descriptor instead of the frame-level refusal
  /// it has always been.
  final String? payloadKind;

  /// Publication time as a UTC instant.
  DateTime get publishedAt =>
      DateTime.fromMicrosecondsSinceEpoch(publishedAtMicros, isUtc: true);

  /// The descriptor as wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'artifactPass': artifactPass,
        'artifactUrl': artifactUrl,
        'contentHash': contentHash,
        'descriptorVersion': kSurfaceArtifactDescriptorVersion,
        'payloadFormatVersion': payloadFormatVersion,
        // Omitted rather than sent as an explicit null: "the record made no
        // shape claim" gets exactly one spelling on the wire, so a reader
        // never has to decide whether two spellings mean the same thing.
        if (payloadKind != null) 'payloadKind': payloadKind,
        'publishedAtMicros': publishedAtMicros,
        'surfaceSlug': surfaceSlug,
        'surfaceType': surfaceType.wireName,
        'version': version,
      };

  @override
  bool operator ==(Object other) =>
      other is SurfaceArtifactDescriptorV1 &&
      other.payloadFormatVersion == payloadFormatVersion &&
      other.surfaceType == surfaceType &&
      other.surfaceSlug == surfaceSlug &&
      other.version == version &&
      other.publishedAtMicros == publishedAtMicros &&
      other.contentHash == contentHash &&
      other.artifactUrl == artifactUrl &&
      other.artifactPass == artifactPass &&
      other.payloadKind == payloadKind;

  @override
  int get hashCode => Object.hash(
        payloadFormatVersion,
        surfaceType,
        surfaceSlug,
        version,
        publishedAtMicros,
        contentHash,
        artifactUrl,
        artifactPass,
        payloadKind,
      );
}

/// Strict codec for [SurfaceArtifactDescriptorV1].
abstract final class SurfaceArtifactDescriptorV1Codec {
  /// Decodes a descriptor, gating BOTH version domains before anything else.
  ///
  /// The ordering is the contract, not an implementation detail. Both versions
  /// are read and refused first, so a build meeting a newer delivery says
  /// "I do not understand this version" rather than reporting whichever field
  /// it happened to trip over — and, more importantly, so it never decodes a
  /// shape it does not understand far enough to act on it.
  ///
  /// Unknown-key rejection deliberately runs AFTER the version gates. Running
  /// it first would report a key a newer version legitimately added as an
  /// unsupported field, which sends a reader hunting a corruption that is not
  /// there.
  static SurfaceArtifactDescriptorV1 decode(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('A surface artifact descriptor must be an '
          'object.');
    }

    final descriptorVersion = _requiredInt(value, 'descriptorVersion');
    if (descriptorVersion < 1 ||
        descriptorVersion > kMaxSupportedSurfaceArtifactDescriptorVersion) {
      throw FormatException(
        'Unsupported artifact descriptor version $descriptorVersion.',
      );
    }

    final payloadFormatVersion = _requiredInt(value, 'payloadFormatVersion');
    if (payloadFormatVersion < 1 ||
        payloadFormatVersion >
            kMaxSupportedSurfaceArtifactPayloadFormatVersion) {
      throw FormatException(
        'Unsupported payload format version $payloadFormatVersion.',
      );
    }

    _rejectUnknownKeys(value);

    return SurfaceArtifactDescriptorV1(
      payloadFormatVersion: payloadFormatVersion,
      surfaceType: Surface.fromWireName(_requiredString(value, 'surfaceType')),
      surfaceSlug: _requiredString(value, 'surfaceSlug'),
      version: _requiredInt(value, 'version'),
      publishedAtMicros: _requiredInt(value, 'publishedAtMicros'),
      contentHash: _requiredString(value, 'contentHash'),
      artifactUrl: _requiredString(value, 'artifactUrl'),
      artifactPass: _requiredString(value, 'artifactPass'),
      payloadKind: value.containsKey('payloadKind')
          ? _requiredString(value, 'payloadKind')
          : null,
    );
  }

  /// Decodes a descriptor from a JSON document.
  static SurfaceArtifactDescriptorV1 decodeJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException(
        'A surface artifact descriptor was not valid JSON: ${error.message}',
      );
    }
    return decode(decoded);
  }

  /// Encodes a descriptor to wire JSON.
  static Map<String, Object?> encode(SurfaceArtifactDescriptorV1 descriptor) =>
      descriptor.toJson();
}

const Set<String> _allowedDescriptorKeys = <String>{
  'artifactPass',
  'artifactUrl',
  'contentHash',
  'descriptorVersion',
  'payloadFormatVersion',
  'payloadKind',
  'publishedAtMicros',
  'surfaceSlug',
  'surfaceType',
  'version',
};

final RegExp _contentHashPattern = RegExp(r'^sha256:[0-9a-f]{64}$');

void _rejectUnknownKeys(Map<String, Object?> json) {
  for (final key in json.keys) {
    if (!_allowedDescriptorKeys.contains(key)) {
      throw FormatException('Unsupported descriptor field "$key".');
    }
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = _required(json, key);
  if (value is String) return value;
  throw FormatException('Expected descriptor "$key" to be a string.');
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = _required(json, key);
  if (value is int) return value;
  if (value is double) {
    throw FormatException(
      'Expected descriptor "$key" to be an integer, got a double.',
    );
  }
  throw FormatException('Expected descriptor "$key" to be an integer.');
}

Object _required(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing required descriptor field "$key".');
  }
  final value = json[key];
  if (value == null) {
    throw FormatException('Descriptor field "$key" cannot be null.');
  }
  return value;
}
