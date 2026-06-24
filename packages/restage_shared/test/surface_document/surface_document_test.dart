import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

/// The published-surface delivery contract: the type-general [SurfaceDocument]
/// envelope + the sealed [SurfacePayload] (only [FlowSurfacePayload] defined),
/// the canonical payload/envelope byte framing, the content-hash domain, the
/// isomorphism invariant, value-equality, deep-freeze, and the committed
/// byte-goldens.
///
/// Locked byte layout.
///
/// PAYLOAD canonical bytes — the stored published-surface payload bytes and
/// the content-hash domain (the envelope's own hash is NEVER inside these):
///   [u32be kindLen][kind utf8]                 kind == "flow"
///   [u32be flowDocJsonLen][flowDocJson utf8]   canonical flow JSON
///   [u32be screenCount]
///   repeat screenCount, screenId ascending (String.compareTo):
///     [u32be idLen][id utf8]
///     [u32be blobLen][blob bytes]
///
/// ENVELOPE wire — the single self-contained server-deliverable blob:
///   [u32be headerLen][headerJson utf8 (sorted keys)][payloadBytes...]
///   headerJson keys: contentHash, minClient, publishedAtMicros, surfaceSlug,
///   surfaceType, version
void main() {
  group('SurfaceType', () {
    test('wireName round-trips', () {
      for (final type in SurfaceType.values) {
        expect(SurfaceType.fromWireName(type.wireName), type);
      }
    });

    test('the four surface kinds have stable wire names', () {
      expect(SurfaceType.onboarding.wireName, 'onboarding');
      expect(SurfaceType.message.wireName, 'message');
      expect(SurfaceType.survey.wireName, 'survey');
      expect(SurfaceType.paywall.wireName, 'paywall');
    });

    test('an unknown wire name is a FormatException', () {
      expect(
        () => SurfaceType.fromWireName('not_a_surface'),
        throwsFormatException,
      );
    });
  });

  group('FlowSurfacePayload', () {
    test('constructs from a flow document + an isomorphic screen-blob bundle',
        () {
      final payload = _announcementPayload();
      expect(payload.payloadKind, 'flow');
      expect(payload.flowDocument.flow, 'announcement');
      expect(payload.screenBlobs.keys, unorderedEquals(['announcement']));
    });

    test('screenBlobs.keys are isomorphic to flowDocument.screenArtifacts.keys',
        () {
      final payload = _announcementPayload();
      expect(
        payload.screenBlobs.keys.toSet(),
        payload.flowDocument.screenArtifacts.keys.toSet(),
      );
    });

    test('rejects a screen-blob bundle with an EXTRA key (not isomorphic)', () {
      final doc = _loadFlowDocument();
      expect(
        () => FlowSurfacePayload(
          flowDocument: doc,
          screenBlobs: {
            'announcement': _loadBlob(),
            'ghost': Uint8List.fromList(const [1, 2, 3]),
          },
        ),
        throwsArgumentError,
      );
    });

    test('rejects a screen-blob bundle with a MISSING key (not isomorphic)',
        () {
      final doc = _loadFlowDocument();
      expect(
        () => FlowSurfacePayload(flowDocument: doc, screenBlobs: const {}),
        throwsArgumentError,
      );
    });

    test('rejects a blob whose sha256 does not match the artifact contentHash',
        () {
      final doc = _loadFlowDocument();
      expect(
        () => FlowSurfacePayload(
          flowDocument: doc,
          screenBlobs: {
            'announcement': Uint8List.fromList(const [0, 0, 0]),
          },
        ),
        throwsArgumentError,
      );
    });

    test('contentHash is sha256 over the canonical payload bytes', () {
      final payload = _announcementPayload();
      final expected =
          'sha256:${crypto.sha256.convert(payload.canonicalBytes)}';
      expect(payload.contentHash, expected);
    });

    test('canonical bytes begin with the "flow" kind discriminator frame', () {
      final bytes = _announcementPayload().canonicalBytes;
      final reader = _ByteReader(bytes);
      expect(reader.readLengthPrefixedUtf8(), 'flow');
    });

    test('canonical bytes carry the canonical FlowDocument JSON verbatim', () {
      final payload = _announcementPayload();
      final reader = _ByteReader(payload.canonicalBytes)
        ..readLengthPrefixedUtf8(); // kind
      final flowJson = reader.readLengthPrefixedUtf8();
      expect(
        flowJson,
        utf8.decode(
          FlowDocumentCodec.encodeCanonicalJson(payload.flowDocument),
        ),
      );
    });

    test('canonical bytes carry screens in screenId-ascending order', () {
      // A two-screen flow proves the ordering is by id, not insertion order.
      final twoScreen = _twoScreenPayload(
        // Insert 'b' before 'a' on purpose.
        screenBlobs: {
          'b_screen': _blobFor('b-bytes'),
          'a_screen': _blobFor('a-bytes'),
        },
      );
      final reader = _ByteReader(twoScreen.canonicalBytes)
        ..readLengthPrefixedUtf8() // kind
        ..readLengthPrefixedUtf8(); // flow json
      final count = reader.readUint32();
      expect(count, 2);
      expect(reader.readLengthPrefixedUtf8(), 'a_screen');
      reader.readLengthPrefixedBytes(); // a blob
      expect(reader.readLengthPrefixedUtf8(), 'b_screen');
    });

    test('screenBlobs is an unmodifiable map', () {
      final payload = _announcementPayload();
      expect(
        () => payload.screenBlobs['x'] = Uint8List(0),
        throwsUnsupportedError,
      );
    });

    test('mutating the returned canonical bytes does not corrupt the payload',
        () {
      final payload = _announcementPayload();
      final first = payload.canonicalBytes;
      final originalHash = payload.contentHash;
      if (first.isNotEmpty) {
        first[0] = first[0] ^ 0xFF;
      }
      // A second read is unaffected, and the hash is stable.
      expect(payload.contentHash, originalHash);
      expect(
        'sha256:${crypto.sha256.convert(payload.canonicalBytes)}',
        originalHash,
      );
    });

    test('value-equality keys on canonical bytes (FlowDocument has no ==)', () {
      final a = _announcementPayload();
      final b = _announcementPayload();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('decode(canonicalBytes) round-trips to an equal payload', () {
      final original = _announcementPayload();
      final decoded = SurfacePayload.decode(original.canonicalBytes);
      expect(decoded, original);
      expect(decoded, isA<FlowSurfacePayload>());
    });
  });

  group('BlobSurfacePayload', () {
    test('constructs from a single blob + an explicit minClient', () {
      final payload = _paywallBlobPayload();
      expect(payload.payloadKind, 'blob');
      expect(payload.minClient, 3);
      expect(payload.blob, _loadBlob());
    });

    test('contentHash is sha256 over the canonical payload bytes', () {
      final payload = _paywallBlobPayload();
      final expected =
          'sha256:${crypto.sha256.convert(payload.canonicalBytes)}';
      expect(payload.contentHash, expected);
    });

    test('canonical bytes begin with the "blob" kind discriminator frame', () {
      final reader = _ByteReader(_paywallBlobPayload().canonicalBytes);
      expect(reader.readLengthPrefixedUtf8(), 'blob');
    });

    test('canonical bytes carry [kind][u32 minClient][lp blob] in order', () {
      // The minClient is embedded in the hashed bytes (anchored capability
      // floor) — it sits between the kind frame and the length-prefixed blob.
      final payload = _paywallBlobPayload();
      final reader = _ByteReader(payload.canonicalBytes);
      expect(reader.readLengthPrefixedUtf8(), 'blob');
      expect(reader.readUint32(), 3);
      expect(reader.readLengthPrefixedBytes(), _loadBlob());
    });

    test('blob is an unmodifiable view', () {
      final payload = _paywallBlobPayload();
      expect(() => payload.blob[0] = 0, throwsUnsupportedError);
    });

    test('mutating the returned canonical bytes does not corrupt the payload',
        () {
      final payload = _paywallBlobPayload();
      final first = payload.canonicalBytes;
      final originalHash = payload.contentHash;
      if (first.isNotEmpty) {
        first[0] = first[0] ^ 0xFF;
      }
      expect(payload.contentHash, originalHash);
      expect(
        'sha256:${crypto.sha256.convert(payload.canonicalBytes)}',
        originalHash,
      );
    });

    test('value-equality keys on canonical bytes', () {
      final a = _paywallBlobPayload();
      final b = _paywallBlobPayload();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs when the minClient differs (covered by the hash)', () {
      final a = _paywallBlobPayload();
      final b = BlobSurfacePayload(minClient: 4, blob: _loadBlob());
      expect(a, isNot(b));
      expect(a.contentHash, isNot(b.contentHash));
    });

    test('decode(canonicalBytes) round-trips to an equal blob payload', () {
      final original = _paywallBlobPayload();
      final decoded = SurfacePayload.decode(original.canonicalBytes);
      expect(decoded, original);
      expect(decoded, isA<BlobSurfacePayload>());
      expect((decoded as BlobSurfacePayload).minClient, 3);
    });
  });

  group('requiredLibraries on the payload (formatVersion 2)', () {
    test('a blob payload defaults requiredLibraries to the empty list', () {
      expect(_paywallBlobPayload().requiredLibraries, isEmpty);
    });

    test('a blob payload carries + canonically sorts requiredLibraries', () {
      final payload = BlobSurfacePayload(
        minClient: 3,
        blob: _loadBlob(),
        requiredLibraries: const [
          LibraryRequirement(namespace: 'zeta.widgets', minVersion: 5),
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
        ],
      );
      // Canonicalized: namespace-ascending, independent of input order.
      expect(
        payload.requiredLibraries.map((r) => r.namespace).toList(),
        ['acme.widgets', 'zeta.widgets'],
      );
    });

    test('a blob payload requiredLibraries round-trips through decode', () {
      final original = BlobSurfacePayload(
        minClient: 3,
        blob: _loadBlob(),
        requiredLibraries: const [
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
          LibraryRequirement(namespace: 'beta.kit', minVersion: 7),
        ],
      );
      final decoded =
          SurfacePayload.decode(original.canonicalBytes) as BlobSurfacePayload;
      expect(decoded.requiredLibraries, original.requiredLibraries);
      expect(decoded, original);
    });

    test('requiredLibraries is part of the content hash (tamper-evident)', () {
      final none = _paywallBlobPayload();
      final some = BlobSurfacePayload(
        minClient: 3,
        blob: _loadBlob(),
        requiredLibraries: const [
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
        ],
      );
      expect(none.contentHash, isNot(some.contentHash));
    });

    test('a flow payload carries + round-trips requiredLibraries', () {
      final original = FlowSurfacePayload(
        flowDocument: _loadFlowDocument(),
        screenBlobs: {'announcement': _loadBlob()},
        requiredLibraries: const [
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 4),
        ],
      );
      final decoded =
          SurfacePayload.decode(original.canonicalBytes) as FlowSurfacePayload;
      expect(decoded.requiredLibraries, original.requiredLibraries);
      expect(decoded, original);
    });

    test('an empty v2 payload writes a count=0 section (byte-distinct from v1)',
        () {
      // A v2-empty blob frame appends a u32 count of 0 (4 bytes) after the
      // blob, so it is strictly longer than the equivalent v1 frame would be.
      final v2Empty = _paywallBlobPayload().canonicalBytes;
      final v1Bytes = _readGoldenBytes('v1/paywall.surface_payload.golden.bin');
      expect(v2Empty.length, v1Bytes.length + 4);
    });
  });

  group('backward compatibility — a v2 build reads a v1 payload frame', () {
    // The committed v1/*.golden.bin are the AUTHENTIC pre-version-2 payload
    // frames (no required-libraries section). Decoding them proves a v1 frame
    // is exactly-consuming and degrades to the empty list — the soundness
    // condition for the self-describing `hasRemaining` discriminator.
    test('a v1 blob payload frame decodes with an empty requiredLibraries', () {
      final v1Bytes = _readGoldenBytes('v1/paywall.surface_payload.golden.bin');
      final decoded = SurfacePayload.decode(v1Bytes) as BlobSurfacePayload;
      expect(decoded.requiredLibraries, isEmpty);
      expect(decoded.minClient, 3);
      expect(decoded.blob, _loadBlob());
    });

    test('a v1 flow payload frame decodes with an empty requiredLibraries', () {
      final v1Bytes =
          _readGoldenBytes('v1/announcement.surface_payload.golden.bin');
      final decoded = SurfacePayload.decode(v1Bytes) as FlowSurfacePayload;
      expect(decoded.requiredLibraries, isEmpty);
      expect(decoded.flowDocument.flow, 'announcement');
    });

    test('a v1 envelope (formatVersion 1) decodes on a v2 build', () {
      final v1Bytes =
          _readGoldenBytes('v1/paywall.surface_envelope.golden.bin');
      final document = SurfaceDocumentCodec.decode(v1Bytes);
      expect(document.surfaceType, SurfaceType.paywall);
      expect(document.requiredLibraries, isEmpty);
      expect(document.payload, isA<BlobSurfacePayload>());
    });
  });

  group('SurfacePayload.decode negatives', () {
    test('truncated bytes are a FormatException', () {
      final full = _announcementPayload().canonicalBytes;
      expect(
        () => SurfacePayload.decode(full.sublist(0, full.length ~/ 2)),
        throwsFormatException,
      );
    });

    test('an unknown payload kind is a FormatException', () {
      // [u32be 5]["weird"] then arbitrary trailing bytes.
      final builder = BytesBuilder()
        ..add(_u32be(5))
        ..add(utf8.encode('weird'))
        ..add(const [0, 0, 0, 0]);
      expect(
        () => SurfacePayload.decode(builder.toBytes()),
        throwsFormatException,
      );
    });

    test('a tampered screen blob (hash mismatch) is a FormatException', () {
      final bytes = Uint8List.fromList(_announcementPayload().canonicalBytes);
      // Flip the final byte — that is inside the trailing screen blob.
      bytes[bytes.length - 1] = bytes[bytes.length - 1] ^ 0xFF;
      expect(() => SurfacePayload.decode(bytes), throwsFormatException);
    });

    test('truncated blob bytes are a FormatException', () {
      final full = _paywallBlobPayload().canonicalBytes;
      expect(
        () => SurfacePayload.decode(full.sublist(0, full.length ~/ 2)),
        throwsFormatException,
      );
    });

    test('trailing bytes after a blob frame are a FormatException', () {
      final full = _paywallBlobPayload().canonicalBytes;
      final padded = (BytesBuilder()
            ..add(full)
            ..add(const [0]))
          .toBytes();
      expect(() => SurfacePayload.decode(padded), throwsFormatException);
    });
  });

  group('SurfaceDocument', () {
    test('contentHash is derived from the payload (never a free parameter)',
        () {
      final payload = _announcementPayload();
      final document = _announcementDocument(payload: payload);
      expect(document.contentHash, payload.contentHash);
    });

    test('minClient must equal the flow document minClient for a flow payload',
        () {
      final payload = _announcementPayload();
      expect(
        () => SurfaceDocument(
          surfaceType: SurfaceType.onboarding,
          surfaceSlug: 'announcement',
          version: 1,
          minClient: payload.flowDocument.minClient + 1,
          payload: payload,
          publishedAt: _fixedPublishedAt,
        ),
        throwsArgumentError,
      );
    });

    test('minClient must equal the blob payload minClient for a blob payload',
        () {
      final payload = _paywallBlobPayload();
      expect(
        () => SurfaceDocument(
          surfaceType: SurfaceType.paywall,
          surfaceSlug: 'pro_upgrade',
          version: 1,
          minClient: payload.minClient + 1,
          payload: payload,
          publishedAt: _fixedPublishedAt,
        ),
        throwsArgumentError,
      );
    });

    test('value-equality over the envelope scalars + payload', () {
      final a = _announcementDocument();
      final b = _announcementDocument();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs when the version differs', () {
      final a = _announcementDocument();
      final b = _announcementDocument(version: 2);
      expect(a, isNot(b));
    });
  });

  group('SurfaceDocumentCodec (envelope)', () {
    test('encode/decode round-trips to an equal document', () {
      final original = _announcementDocument();
      final decoded = SurfaceDocumentCodec.decode(
        SurfaceDocumentCodec.encode(original),
      );
      expect(decoded, original);
    });

    test('encode/decode round-trips a paywall (blob) document', () {
      final original = _paywallDocument();
      final decoded = SurfaceDocumentCodec.decode(
        SurfaceDocumentCodec.encode(original),
      );
      expect(decoded, original);
      expect(decoded.surfaceType, SurfaceType.paywall);
      expect(decoded.payload, isA<BlobSurfacePayload>());
    });

    test('a header minClient inconsistent with a blob payload fails closed',
        () {
      final document = _paywallDocument();
      final bytes = SurfaceDocumentCodec.encode(document);
      final reader = _ByteReader(bytes);
      final header =
          jsonDecode(reader.readLengthPrefixedUtf8()) as Map<String, Object?>;
      final payloadBytes = reader.remaining();
      header['minClient'] = (header['minClient']! as int) + 1;
      final tampered = _envelopeFrom(header, payloadBytes);
      expect(
        () => SurfaceDocumentCodec.decode(tampered),
        throwsFormatException,
      );
    });

    test('envelope is [u32be headerLen][headerJson sorted][payloadBytes]', () {
      final document = _announcementDocument();
      final bytes = SurfaceDocumentCodec.encode(document);
      final reader = _ByteReader(bytes);
      final headerJson = reader.readLengthPrefixedUtf8();
      final header = jsonDecode(headerJson) as Map<String, Object?>;
      expect(header['surfaceType'], 'onboarding');
      expect(header['surfaceSlug'], 'announcement');
      expect(header['version'], 1);
      expect(header['formatVersion'], 2);
      expect(header['minClient'], document.minClient);
      expect(header['requiredLibraries'], isEmpty);
      expect(header['contentHash'], document.contentHash);
      expect(
        header['publishedAtMicros'],
        document.publishedAt.toUtc().microsecondsSinceEpoch,
      );
      // Header keys are emitted in ascending order.
      expect(
        header.keys.toList(),
        List<String>.from(header.keys)..sort(),
      );
      // The remainder is exactly the payload canonical bytes.
      final remainder = reader.remaining();
      expect(remainder, document.payload.canonicalBytes);
    });

    test('a tampered contentHash in the header is a FormatException', () {
      final document = _announcementDocument();
      final bytes = SurfaceDocumentCodec.encode(document);
      final reader = _ByteReader(bytes);
      final header =
          jsonDecode(reader.readLengthPrefixedUtf8()) as Map<String, Object?>;
      final payloadBytes = reader.remaining();
      header['contentHash'] = 'sha256:${'0' * 64}'; // valid shape, wrong value
      final tampered = _envelopeFrom(header, payloadBytes);
      expect(
        () => SurfaceDocumentCodec.decode(tampered),
        throwsFormatException,
      );
    });

    test(
        'a header minClient inconsistent with the payload is a FormatException',
        () {
      final document = _announcementDocument();
      final bytes = SurfaceDocumentCodec.encode(document);
      final reader = _ByteReader(bytes);
      final header =
          jsonDecode(reader.readLengthPrefixedUtf8()) as Map<String, Object?>;
      final payloadBytes = reader.remaining();
      header['minClient'] = (header['minClient']! as int) + 1;
      final tampered = _envelopeFrom(header, payloadBytes);
      expect(
        () => SurfaceDocumentCodec.decode(tampered),
        throwsFormatException,
      );
    });

    test('a truncated envelope (header longer than the buffer) fails closed',
        () {
      final bytes = SurfaceDocumentCodec.encode(_announcementDocument());
      expect(
        () => SurfaceDocumentCodec.decode(bytes.sublist(0, 6)),
        throwsFormatException,
      );
    });

    test('an envelope declaring an unsupported format version fails closed',
        () {
      final document = _announcementDocument();
      final bytes = SurfaceDocumentCodec.encode(document);
      final reader = _ByteReader(bytes);
      final header =
          jsonDecode(reader.readLengthPrefixedUtf8()) as Map<String, Object?>;
      final payloadBytes = reader.remaining();
      // A version beyond the supported ceiling is a shape this build cannot
      // read — reject rather than guess. Read first, before the hash check.
      header['formatVersion'] = (header['formatVersion']! as int) + 1;
      final tampered = _envelopeFrom(header, payloadBytes);
      expect(
        () => SurfaceDocumentCodec.decode(tampered),
        throwsFormatException,
      );
    });
  });

  group('SurfaceDocumentCodec — formatVersion 2 (requiredLibraries)', () {
    SurfaceDocument paywallWithLibraries() => SurfaceDocument(
          surfaceType: SurfaceType.paywall,
          surfaceSlug: 'pro_upgrade',
          version: 1,
          minClient: 3,
          requiredLibraries: const [
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
            LibraryRequirement(namespace: 'beta.kit', minVersion: 5),
          ],
          payload: BlobSurfacePayload(
            minClient: 3,
            blob: _loadBlob(),
            requiredLibraries: const [
              LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
              LibraryRequirement(namespace: 'beta.kit', minVersion: 5),
            ],
          ),
          publishedAt: _fixedPublishedAt,
        );

    test('encode writes formatVersion 2', () {
      final reader = _ByteReader(
        SurfaceDocumentCodec.encode(_paywallDocument()),
      );
      final header =
          jsonDecode(reader.readLengthPrefixedUtf8()) as Map<String, Object?>;
      expect(header['formatVersion'], 2);
    });

    test('a document with requiredLibraries round-trips', () {
      final original = paywallWithLibraries();
      final decoded =
          SurfaceDocumentCodec.decode(SurfaceDocumentCodec.encode(original));
      expect(decoded, original);
      expect(
        decoded.requiredLibraries.map((r) => r.namespace).toList(),
        ['acme.widgets', 'beta.kit'],
      );
    });

    test('the header requiredLibraries are emitted in canonical order', () {
      final reader = _ByteReader(
        SurfaceDocumentCodec.encode(paywallWithLibraries()),
      );
      final header =
          jsonDecode(reader.readLengthPrefixedUtf8()) as Map<String, Object?>;
      final libs = (header['requiredLibraries']! as List)
          .map((e) => (e as Map)['namespace'])
          .toList();
      expect(libs, ['acme.widgets', 'beta.kit']);
    });

    test(
        'a header requiredLibraries inconsistent with the payload fails closed',
        () {
      final document = paywallWithLibraries();
      final bytes = SurfaceDocumentCodec.encode(document);
      final reader = _ByteReader(bytes);
      final header =
          jsonDecode(reader.readLengthPrefixedUtf8()) as Map<String, Object?>;
      final payloadBytes = reader.remaining();
      // Bump a header minVersion without touching the hashed payload copy.
      (header['requiredLibraries']! as List)[0] = {
        'namespace': 'acme.widgets',
        'minVersion': 99,
      };
      final tampered = _envelopeFrom(header, payloadBytes);
      expect(
        () => SurfaceDocumentCodec.decode(tampered),
        throwsFormatException,
      );
    });

    test('a header requiredLibraries reorder is detected (tamper-evident)', () {
      final document = paywallWithLibraries();
      final bytes = SurfaceDocumentCodec.encode(document);
      final reader = _ByteReader(bytes);
      final header =
          jsonDecode(reader.readLengthPrefixedUtf8()) as Map<String, Object?>;
      final payloadBytes = reader.remaining();
      final libs = (header['requiredLibraries']! as List).reversed.toList();
      header['requiredLibraries'] = libs;
      final tampered = _envelopeFrom(header, payloadBytes);
      expect(
        () => SurfaceDocumentCodec.decode(tampered),
        throwsFormatException,
      );
    });

    test(
        'a v1 reader fails closed on a v2 envelope with a clean version '
        'diagnostic (not "unsupported field")', () {
      // Simulate a v1 reader: a v2-encoded envelope carries formatVersion 2 +
      // the requiredLibraries header key. The current (max=2) build accepts it;
      // the regression we lock is that the version gate is read BEFORE
      // unknown-key rejection, so an envelope declaring a version ABOVE the
      // ceiling reports the VERSION, never the field. Push formatVersion past
      // the ceiling while the requiredLibraries key is present.
      final bytes = SurfaceDocumentCodec.encode(paywallWithLibraries());
      final reader = _ByteReader(bytes);
      final header =
          jsonDecode(reader.readLengthPrefixedUtf8()) as Map<String, Object?>;
      final payloadBytes = reader.remaining();
      header['formatVersion'] = kMaxSupportedSurfaceEnvelopeVersion + 1;
      final tampered = _envelopeFrom(header, payloadBytes);
      expect(
        () => SurfaceDocumentCodec.decode(tampered),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('format version'),
          ),
        ),
      );
    });

    test('an unknown header key within a supported version still fails closed',
        () {
      final bytes = SurfaceDocumentCodec.encode(_paywallDocument());
      final reader = _ByteReader(bytes);
      final header =
          jsonDecode(reader.readLengthPrefixedUtf8()) as Map<String, Object?>;
      final payloadBytes = reader.remaining();
      header['surpriseField'] = 'nope';
      final tampered = _envelopeFrom(header, payloadBytes);
      expect(
        () => SurfaceDocumentCodec.decode(tampered),
        throwsFormatException,
      );
    });
  });

  group('version-strict decode + symmetric construction (Pass-1 hardening)',
      () {
    test('a v2 envelope whose payload has no manifest section fails closed',
        () {
      // A genuine v1 payload frame (section-less) wrapped in a v2 header: the
      // version-strict payload decode rejects the missing section rather than
      // defaulting to [] and re-encoding asymmetrically.
      final v1Payload =
          _readGoldenBytes('v1/paywall.surface_payload.golden.bin');
      final header = <String, Object?>{
        'contentHash': 'sha256:${crypto.sha256.convert(v1Payload)}',
        'formatVersion': 2,
        'minClient': 3,
        'publishedAtMicros': _fixedPublishedAt.microsecondsSinceEpoch,
        'requiredLibraries': <Object?>[],
        'surfaceSlug': 'pro_upgrade',
        'surfaceType': 'paywall',
        'version': 1,
      };
      expect(
        () => SurfaceDocumentCodec.decode(_envelopeFrom(header, v1Payload)),
        throwsFormatException,
      );
    });

    test('a v2 envelope missing the requiredLibraries header fails closed', () {
      final bytes = SurfaceDocumentCodec.encode(_paywallDocument());
      final reader = _ByteReader(bytes);
      final header =
          jsonDecode(reader.readLengthPrefixedUtf8()) as Map<String, Object?>;
      final payloadBytes = reader.remaining();
      header.remove('requiredLibraries');
      expect(
        () => SurfaceDocumentCodec.decode(_envelopeFrom(header, payloadBytes)),
        throwsFormatException,
      );
    });

    test('a v1 envelope carrying a requiredLibraries header fails closed', () {
      // The authentic v1 envelope golden (formatVersion 1) gains the v2-only
      // key — version-scoping rejects it.
      final v1Bytes =
          _readGoldenBytes('v1/paywall.surface_envelope.golden.bin');
      final reader = _ByteReader(v1Bytes);
      final header =
          jsonDecode(reader.readLengthPrefixedUtf8()) as Map<String, Object?>;
      final payloadBytes = reader.remaining();
      expect(header['formatVersion'], 1);
      header['requiredLibraries'] = <Object?>[];
      expect(
        () => SurfaceDocumentCodec.decode(_envelopeFrom(header, payloadBytes)),
        throwsFormatException,
      );
    });

    test('constructing a payload with a duplicate namespace throws', () {
      expect(
        () => BlobSurfacePayload(
          minClient: 3,
          blob: _loadBlob(),
          requiredLibraries: const [
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 1),
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('constructing a document with a duplicate namespace throws', () {
      final payload = BlobSurfacePayload(
        minClient: 3,
        blob: _loadBlob(),
        requiredLibraries: const [
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
        ],
      );
      expect(
        () => SurfaceDocument(
          surfaceType: SurfaceType.paywall,
          surfaceSlug: 'pro_upgrade',
          version: 1,
          minClient: 3,
          requiredLibraries: const [
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
            LibraryRequirement(namespace: 'acme.widgets', minVersion: 3),
          ],
          payload: payload,
          publishedAt: _fixedPublishedAt,
        ),
        throwsArgumentError,
      );
    });
  });

  group('byte-goldens (locked wire)', () {
    test('the flow payload frame matches the committed golden', () {
      final actual = _announcementPayload().canonicalBytes;
      _expectGoldenBytes('announcement.surface_payload.golden.bin', actual);
    });

    test('the flow envelope matches the committed golden', () {
      final actual = SurfaceDocumentCodec.encode(_announcementDocument());
      _expectGoldenBytes('announcement.surface_envelope.golden.bin', actual);
    });

    test('the blob payload frame matches the committed golden', () {
      final actual = _paywallBlobPayload().canonicalBytes;
      _expectGoldenBytes('paywall.surface_payload.golden.bin', actual);
    });

    test('the paywall envelope matches the committed golden', () {
      final actual = SurfaceDocumentCodec.encode(_paywallDocument());
      _expectGoldenBytes('paywall.surface_envelope.golden.bin', actual);
    });
  });
}

// ---------------------------------------------------------------------------
// Fixtures + helpers
// ---------------------------------------------------------------------------

/// A fixed, deterministic publish instant for the envelope golden.
final DateTime _fixedPublishedAt = DateTime.utc(2026);

FlowDocument _loadFlowDocument() =>
    FlowDocumentCodec.decodeJson(_readGoldenString('announcement.flow.json'));

Uint8List _loadBlob() => _readGoldenBytes('announcement.rfw');

FlowSurfacePayload _announcementPayload() => FlowSurfacePayload(
      flowDocument: _loadFlowDocument(),
      screenBlobs: {'announcement': _loadBlob()},
    );

SurfaceDocument _announcementDocument({
  FlowSurfacePayload? payload,
  int version = 1,
}) {
  final p = payload ?? _announcementPayload();
  return SurfaceDocument(
    surfaceType: SurfaceType.onboarding,
    surfaceSlug: 'announcement',
    version: version,
    minClient: p.flowDocument.minClient,
    payload: p,
    publishedAt: _fixedPublishedAt,
  );
}

/// A deterministic paywall blob payload: a single committed RFW blob carried
/// with an explicit (anchored) minClient floor of 3 — the paywall analogue of
/// [_announcementPayload].
BlobSurfacePayload _paywallBlobPayload() => BlobSurfacePayload(
      minClient: 3,
      blob: _loadBlob(),
    );

SurfaceDocument _paywallDocument({int version = 1}) {
  final p = _paywallBlobPayload();
  return SurfaceDocument(
    surfaceType: SurfaceType.paywall,
    surfaceSlug: 'pro_upgrade',
    version: version,
    minClient: p.minClient,
    payload: p,
    publishedAt: _fixedPublishedAt,
  );
}

Uint8List _blobFor(String marker) =>
    Uint8List.fromList(utf8.encode('rfw-blob:$marker'));

/// A synthetic two-screen flow whose screenArtifacts are made consistent with
/// the supplied [screenBlobs] (so the isomorphism holds) — used to assert the
/// screenId ordering of the payload frame.
FlowSurfacePayload _twoScreenPayload({
  required Map<String, Uint8List> screenBlobs,
}) {
  final artifacts = <String, Object?>{
    for (final entry in screenBlobs.entries)
      entry.key: {
        'contentHash': 'sha256:${crypto.sha256.convert(entry.value)}',
        'minClient': 3,
        'path': '${entry.key}.rfw',
        'schemaVersion': 1,
        'version': 1,
      },
  };
  final json = <String, Object?>{
    'flow': 'two_screen',
    'initial': 'a_screen',
    'minClient': 3,
    'schemaVersion': 1,
    'screenArtifacts': artifacts,
    'states': {
      'a_screen': {
        'kind': 'screen',
        'screen': 'a_screen',
        'on': {
          'act': {'target': 'b_screen', 'type': 'goto'},
        },
      },
      'b_screen': {
        'kind': 'screen',
        'screen': 'b_screen',
        'on': {
          'act': {'target': 'done', 'type': 'goto'},
        },
      },
      'done': {'kind': 'end', 'result': <String, Object?>{}},
    },
    'version': 1,
  };
  return FlowSurfacePayload(
    flowDocument: FlowDocumentCodec.decodeJson(jsonEncode(json)),
    screenBlobs: screenBlobs,
  );
}

Uint8List _envelopeFrom(Map<String, Object?> header, List<int> payloadBytes) {
  final sortedHeader = <String, Object?>{
    for (final key in header.keys.toList()..sort()) key: header[key],
  };
  final headerBytes = utf8.encode(jsonEncode(sortedHeader));
  return (BytesBuilder()
        ..add(_u32be(headerBytes.length))
        ..add(headerBytes)
        ..add(payloadBytes))
      .toBytes();
}

Uint8List _u32be(int value) {
  final bytes = Uint8List(4);
  ByteData.view(bytes.buffer).setUint32(0, value);
  return bytes;
}

// --- golden file IO (dual cwd: workspace root or package dir) ---------------

const _goldenDir = 'test/surface_document/goldens';
const _workspaceGoldenDir = 'packages/restage_shared/$_goldenDir';

File _goldenFile(String fileName) {
  final workspacePath = File('$_workspaceGoldenDir/$fileName');
  return workspacePath.existsSync()
      ? workspacePath
      : File('$_goldenDir/$fileName');
}

String _readGoldenString(String fileName) =>
    _goldenFile(fileName).readAsStringSync();

Uint8List _readGoldenBytes(String fileName) =>
    _goldenFile(fileName).readAsBytesSync();

/// Compares [actual] against the committed golden, or (re)writes the golden
/// when `UPDATE_SURFACE_GOLDENS=1` is set — the one-time bless after the
/// implementation is correct. The structural tests above pin the layout
/// independently; this is the regression lock on top.
void _expectGoldenBytes(String fileName, List<int> actual) {
  if (Platform.environment['UPDATE_SURFACE_GOLDENS'] == '1') {
    final useWorkspace = File('$_workspaceGoldenDir/$fileName').existsSync() ||
        Directory(_workspaceGoldenDir).existsSync();
    final path = useWorkspace
        ? '$_workspaceGoldenDir/$fileName'
        : '$_goldenDir/$fileName';
    File(path).writeAsBytesSync(actual);
    printOnFailure('wrote golden $fileName (${actual.length} bytes)');
    return;
  }
  expect(actual, _readGoldenBytes(fileName));
}

/// A minimal big-endian byte reader for the structural layout assertions.
class _ByteReader {
  _ByteReader(this._bytes);

  final List<int> _bytes;
  int _offset = 0;

  int readUint32() {
    final value = ByteData.view(
      Uint8List.fromList(_bytes).buffer,
    ).getUint32(_offset);
    _offset += 4;
    return value;
  }

  String readLengthPrefixedUtf8() => utf8.decode(readLengthPrefixedBytes());

  List<int> readLengthPrefixedBytes() {
    final length = readUint32();
    final slice = _bytes.sublist(_offset, _offset + length);
    _offset += length;
    return slice;
  }

  List<int> remaining() => _bytes.sublist(_offset);
}
