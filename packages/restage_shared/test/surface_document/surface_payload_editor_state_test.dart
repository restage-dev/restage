import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

Uint8List _bytes(String text) => Uint8List.fromList(text.codeUnits);

BlobSurfacePayload _blob({
  Uint8List? editorState,
  Map<String, Map<String, Object>> localSeeds = const {},
  List<DeliveredIconFont> iconFonts = const [],
  int minClient = kSurfaceFeatureClientFloor,
}) =>
    BlobSurfacePayload(
      minClient: minClient,
      blob: _bytes('blob'),
      localSeeds: localSeeds,
      iconFonts: iconFonts,
      editorState: editorState,
    );

FlowSurfacePayload _flow({Uint8List? editorState}) {
  final blob = _bytes('screen');
  final json = <String, Object?>{
    'flow': 'one_screen',
    'initial': 'a_screen',
    'minClient': 3,
    'schemaVersion': 1,
    'screenArtifacts': {
      'a_screen': {
        'contentHash': 'sha256:${crypto.sha256.convert(blob)}',
        'minClient': 3,
        'path': 'a_screen.rfw',
        'schemaVersion': 1,
        'version': 1,
      },
    },
    'states': {
      'a_screen': {
        'kind': 'screen',
        'screen': 'a_screen',
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
    screenBlobs: {'a_screen': blob},
    editorState: editorState,
  );
}

void main() {
  group('editor state section', () {
    test('round-trips opaque bytes', () {
      final payload = _blob(editorState: _bytes('canvas'));
      final decoded =
          SurfacePayload.decode(payload.canonicalBytes) as BlobSurfacePayload;
      expect(decoded, payload);
      expect(decoded.editorState, _bytes('canvas'));
    });

    test('a payload without it decodes unchanged', () {
      final plain = _blob();
      final decoded =
          SurfacePayload.decode(plain.canonicalBytes) as BlobSurfacePayload;
      expect(decoded.editorState, isNull);
      expect(decoded.canonicalBytes, plain.canonicalBytes);
    });

    test('the bytes are covered by the content hash', () {
      expect(
        _blob(editorState: _bytes('a')).contentHash,
        isNot(_blob(editorState: _bytes('b')).contentHash),
      );
      expect(
        _blob(editorState: _bytes('a')).contentHash,
        isNot(_blob().contentHash),
      );
    });

    test('it does not count as a device section', () {
      final payload = _blob(editorState: _bytes('a'), minClient: 3);
      expect(payload.carriesSections, isFalse);
    });

    test('an empty section is refused', () {
      expect(
        () => _blob(editorState: Uint8List(0)),
        throwsArgumentError,
      );
    });

    test('it follows the icon-font and local-seed sections', () {
      final payload = _blob(
        editorState: _bytes('state'),
        localSeeds: {
          'R': {'k': true},
        },
        iconFonts: [DeliveredIconFont(family: 'A', bytes: _bytes('a'))],
      );
      final decoded =
          SurfacePayload.decode(payload.canonicalBytes) as BlobSurfacePayload;
      expect(decoded.editorState, _bytes('state'));
      expect(decoded.localSeeds['R'], {'k': true});
      expect(decoded.iconFonts, hasLength(1));
    });

    test('a payload format without sections refuses it', () {
      final bytes = _blob(editorState: _bytes('a')).canonicalBytes;
      expect(
        () => SurfacePayload.decode(bytes, allowSections: false),
        throwsFormatException,
      );
    });

    test('a zero-length section on the wire is refused', () {
      final plain = _blob().canonicalBytes;
      final tail = ByteData(8)..setUint32(0, 3);
      final bytes =
          Uint8List.fromList([...plain, ...tail.buffer.asUint8List()]);
      expect(() => SurfacePayload.decode(bytes), throwsFormatException);
    });

    test('a section after the editor state is refused', () {
      final bytes = _blob(editorState: _bytes('a')).canonicalBytes;
      final extra = ByteData(4)..setUint32(0, 4);
      expect(
        () => SurfacePayload.decode(
          Uint8List.fromList([...bytes, ...extra.buffer.asUint8List()]),
        ),
        throwsFormatException,
      );
    });
  });

  group('a flow payload', () {
    test('round-trips editor state', () {
      final payload = _flow(editorState: _bytes('screens'));
      final decoded =
          SurfacePayload.decode(payload.canonicalBytes) as FlowSurfacePayload;
      expect(decoded, payload);
      expect(decoded.editorState, _bytes('screens'));
      expect(payload.contentHash, isNot(_flow().contentHash));
    });

    test('without editor state equals the payload built without it', () {
      final stripped = _flow(editorState: _bytes('x')).withoutEditorState();
      expect(stripped.editorState, isNull);
      expect(stripped.canonicalBytes, _flow().canonicalBytes);
      final plain = _flow();
      expect(identical(plain.withoutEditorState(), plain), isTrue);
    });

    test('publish validation and the envelope refuse its editor state', () {
      final payload = _flow(editorState: _bytes('a'));
      expect(
        () => validatePayloadSectionsForPublish(payload),
        throwsFormatException,
      );
      expect(
        () => SurfaceDocument(
          surfaceType: Surface.onboarding,
          surfaceSlug: 'tour',
          version: 1,
          minClient: 3,
          payload: payload,
          publishedAt: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });
  });

  group('withoutEditorState', () {
    test('returns the payload itself when it has none', () {
      final plain = _blob();
      expect(identical(plain.withoutEditorState(), plain), isTrue);
    });

    test('equals the payload built without it', () {
      final seeds = {
        'R': {'k': 1.0},
      };
      final withState = _blob(editorState: _bytes('x'), localSeeds: seeds);
      final stripped = withState.withoutEditorState();
      expect(stripped.editorState, isNull);
      expect(stripped, _blob(localSeeds: seeds));
      expect(stripped.contentHash, _blob(localSeeds: seeds).contentHash);
    });
  });

  group('publish', () {
    test('validation refuses a payload that carries editor state', () {
      expect(
        () => validatePayloadSectionsForPublish(
          _blob(editorState: _bytes('a')),
        ),
        throwsFormatException,
      );
    });

    test('an envelope refuses a payload that carries editor state', () {
      expect(
        () => SurfaceDocument(
          surfaceType: Surface.paywall,
          surfaceSlug: 'main',
          version: 1,
          minClient: kSurfaceFeatureClientFloor,
          payload: _blob(editorState: _bytes('a')),
          publishedAt: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });
  });
}
