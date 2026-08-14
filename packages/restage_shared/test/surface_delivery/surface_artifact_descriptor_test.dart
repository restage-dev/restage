import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('SurfaceArtifactDescriptorV1Codec version gating', () {
    // The ORDER is the contract. Each of these descriptors is unreadable for
    // two independent reasons at once: an unsupported version AND something
    // else the decoder would otherwise complain about first. The assertion is
    // on WHICH complaint comes back, because that is the only observable
    // difference between "gated before decoding" and "gated somewhere during
    // decoding" — and only the former is safe.

    test('an unknown descriptor version is refused before any other field', () {
      expect(
        () => SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
          'descriptorVersion':
              kMaxSupportedSurfaceArtifactDescriptorVersion + 1,
          // Everything below is ALSO wrong: an unsupported payload format, an
          // unknown key, a missing slug, a malformed hash. None of it may be
          // what comes back.
          'payloadFormatVersion':
              kMaxSupportedSurfaceArtifactPayloadFormatVersion + 1,
          'aFieldFromTheFuture': true,
          'version': 0,
          'publishedAtMicros': 0,
          'contentHash': 'not-a-hash',
          'surfaceType': 'paywall',
          'artifactUrl': 'not a url',
          'artifactPass': '',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported artifact descriptor version'),
          ),
        ),
      );
    });

    test('an unknown payload format version is refused before any other field',
        () {
      expect(
        () => SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
          'descriptorVersion': kSurfaceArtifactDescriptorVersion,
          'payloadFormatVersion':
              kMaxSupportedSurfaceArtifactPayloadFormatVersion + 1,
          'aFieldFromTheFuture': true,
          'version': 0,
          'publishedAtMicros': 0,
          'contentHash': 'not-a-hash',
          'surfaceType': 'paywall',
          'surfaceSlug': '',
          'artifactUrl': 'not a url',
          'artifactPass': '',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported payload format version'),
          ),
        ),
      );
    });

    test('the descriptor version is gated before the payload format version',
        () {
      // Both are unsupported. The descriptor's own shape has to be understood
      // before any field inside it means anything, INCLUDING the other version
      // number — so this ordering is not a preference.
      expect(
        () => SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
          'descriptorVersion': 99,
          'payloadFormatVersion': 99,
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported artifact descriptor version'),
          ),
        ),
      );
    });

    test('an unknown field is refused only once the versions are understood',
        () {
      expect(
        () => SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
          ..._valid,
          'aFieldFromTheFuture': true,
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported descriptor field "aFieldFromTheFuture"'),
          ),
        ),
      );
    });

    test('a zero or negative version in either domain is refused', () {
      for (final domain in <String>[
        'descriptorVersion',
        'payloadFormatVersion',
      ]) {
        for (final bad in <int>[0, -1]) {
          expect(
            () => SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
              ..._valid,
              domain: bad,
            }),
            throwsA(isA<FormatException>()),
            reason: '$domain = $bad must be refused',
          );
        }
      }
    });
  });

  group('SurfaceArtifactDescriptorV1Codec field validation', () {
    test('round-trips a well-formed descriptor', () {
      final decoded = SurfaceArtifactDescriptorV1Codec.decode(_valid);
      expect(decoded.surfaceType, Surface.paywall);
      expect(decoded.surfaceSlug, 'pro_upgrade');
      expect(decoded.version, 12);
      expect(decoded.payloadFormatVersion, 1);
      expect(decoded.contentHash, _hash);
      expect(decoded.publishedAt.isUtc, isTrue);
      expect(
        decoded.publishedAt.microsecondsSinceEpoch,
        decoded.publishedAtMicros,
      );
      expect(
        SurfaceArtifactDescriptorV1Codec.encode(decoded),
        _valid,
        reason: 'encode must be the exact inverse of decode',
      );
    });

    test('refuses a content hash that is not the canonical spelling', () {
      // Uppercase hex, a bare digest, the wrong length, and the wrong algorithm
      // are each a hash that would never match a computed one — so accepting
      // them would turn an integrity check into an always-fails check, which is
      // indistinguishable from an outage.
      for (final bad in <String>[
        'sha256:${'A' * 64}',
        'a' * 64,
        'sha256:${'a' * 63}',
        'sha1:${'a' * 64}',
        '',
      ]) {
        expect(
          () => SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
            ..._valid,
            'contentHash': bad,
          }),
          throwsA(isA<FormatException>()),
          reason: 'content hash "$bad" must be refused',
        );
      }
    });

    test('refuses an artifact URL that is relative or carries credentials', () {
      for (final bad in <String>[
        '/artifacts/x',
        'artifacts/x',
        'https://user:secret@artifacts.example/x',
        '',
      ]) {
        expect(
          () => SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
            ..._valid,
            'artifactUrl': bad,
          }),
          throwsA(isA<FormatException>()),
          reason: 'artifact URL "$bad" must be refused',
        );
      }
    });

    test('refuses an empty pass', () {
      expect(
        () => SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
          ..._valid,
          'artifactPass': '',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('refuses an untrimmed or empty slug', () {
      for (final bad in <String>['', ' pro_upgrade', 'pro_upgrade ']) {
        expect(
          () => SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
            ..._valid,
            'surfaceSlug': bad,
          }),
          throwsA(isA<FormatException>()),
          reason: 'slug "$bad" must be refused',
        );
      }
    });

    test('refuses a missing, null, or wrongly-typed required field', () {
      for (final key in _valid.keys) {
        expect(
          () => SurfaceArtifactDescriptorV1Codec.decode(
            <String, Object?>{..._valid}..remove(key),
          ),
          throwsA(isA<FormatException>()),
          reason: 'a missing "$key" must be refused',
        );
        expect(
          () => SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
            ..._valid,
            key: null,
          }),
          throwsA(isA<FormatException>()),
          reason: 'a null "$key" must be refused',
        );
      }
    });

    test('refuses a float where an integer is required', () {
      // JSON has one number type, so a version arriving as 1.0 is a real wire
      // shape rather than a hypothetical, and silently flooring it would accept
      // a version nobody wrote.
      expect(
        () => SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
          ..._valid,
          'version': 12.0,
        }),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', contains('integer')),
        ),
      );
    });

    test('refuses a body that is not a JSON object', () {
      for (final bad in <Object?>[null, 3, 'a string', <Object?>[]]) {
        expect(
          () => SurfaceArtifactDescriptorV1Codec.decode(bad),
          throwsA(isA<FormatException>()),
          reason: '$bad must be refused',
        );
      }
    });

    test('decodeJson refuses a malformed document without leaking it', () {
      expect(
        () => SurfaceArtifactDescriptorV1Codec.decodeJson('{not json'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('the routing shape claim', () {
    // The publication record can say which payload shape it routed a delivery
    // on. That claim used to be checked against the decoded bytes where the
    // bytes were decoded; the bytes now arrive elsewhere, so the claim has to
    // travel to meet them. These pin the three states it can be in.

    test('an absent claim decodes as absent, not as some default kind', () {
      // The shape-agnostic route makes no claim. Reading that as a kind would
      // invent a claim nobody made and start failing deliveries that are fine.
      final decoded = SurfaceArtifactDescriptorV1Codec.decode(_valid);
      expect(decoded.payloadKind, isNull);
    });

    test('a claim round-trips verbatim', () {
      final decoded = SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
        ..._valid,
        'payloadKind': 'flow',
      });
      expect(decoded.payloadKind, 'flow');
      expect(
        SurfaceArtifactDescriptorV1Codec.encode(decoded),
        <String, Object?>{..._valid, 'payloadKind': 'flow'},
      );
    });

    test('an unrecognised claim is carried, not rejected here', () {
      // The claim is checked against the frame, not against a list this build
      // keeps. Rejecting an unknown spelling in the codec would turn what must
      // be a frame-level refusal into a descriptor-level one, and would make
      // this build unable to even read a delivery it should be refusing for a
      // reason it can explain.
      expect(
        SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
          ..._valid,
          'payloadKind': 'sculpture',
        }).payloadKind,
        'sculpture',
      );
    });

    test('a present-but-meaningless claim is refused', () {
      // Absent already means "no claim". An empty or padded string would be a
      // second spelling of it, and two spellings of one state is how a check
      // gets skipped by accident.
      for (final bad in <String>['', ' ', 'blob ', ' blob']) {
        expect(
          () => SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
            ..._valid,
            'payloadKind': bad,
          }),
          throwsA(isA<FormatException>()),
          reason: 'payload kind "$bad" must be refused',
        );
      }
      expect(
        () => SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
          ..._valid,
          'payloadKind': null,
        }),
        throwsA(isA<FormatException>()),
        reason: 'an explicit null is not the spelling of "no claim"',
      );
      expect(
        () => SurfaceArtifactDescriptorV1Codec.decode(<String, Object?>{
          ..._valid,
          'payloadKind': 1,
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('payload frame strictness translation', () {
    test('every readable payload format requires a requirement section', () {
      // The self-contained document numbers its format 2 while a stored frame
      // numbers its format 1. They are different domains, and the whole reason
      // this function exists is that reading one as the other would drop a
      // frame into the tolerant decode — where a stripped requirement section
      // reads as "requires nothing" instead of failing.
      for (var v = 1;
          v <= kMaxSupportedSurfaceArtifactPayloadFormatVersion;
          v += 1) {
        expect(
          surfaceArtifactFrameRequiresManifest(v),
          isTrue,
          reason: 'payload format $v must decode strictly',
        );
      }
    });

    test('the three version domains are not silently the same number', () {
      // A guard against the easiest possible mistake: someone "tidying up" by
      // collapsing these onto one constant. They are allowed to coincide, but
      // never by accident — if this fails, check that the collapse was intended
      // rather than changing the expectation.
      expect(kSurfaceArtifactDescriptorVersion, 1);
      expect(kSurfaceArtifactPayloadFormatVersion, 1);
      expect(kSurfaceEnvelopeFormatVersion, 2);
    });
  });
}

const String _hash =
    'sha256:0000000000000000000000000000000000000000000000000000000000000000';

/// A descriptor every field of which is acceptable. Cases derive from it so a
/// test is only ever exercising the one thing it changed.
final Map<String, Object?> _valid = <String, Object?>{
  'artifactPass': 'v1.k1.1786579200.${'a' * 64}',
  'artifactUrl':
      'https://artifacts.example/artifacts/orgs/1/artifacts/1/$_hash',
  'contentHash': _hash,
  'descriptorVersion': kSurfaceArtifactDescriptorVersion,
  'payloadFormatVersion': kSurfaceArtifactPayloadFormatVersion,
  'publishedAtMicros': 1786579200000000,
  'surfaceSlug': 'pro_upgrade',
  'surfaceType': 'paywall',
  'version': 12,
};
