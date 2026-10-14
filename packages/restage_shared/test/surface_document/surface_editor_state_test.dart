import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

Uint8List _json(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  final catalog = <String, Object?>{
    'schemaVersion': 5,
    'libraries': <String, Object?>{
      'app.widgets': <String, Object?>{'version': '1.0.0'},
    },
    'widgets': <Object?>[
      <String, Object?>{'name': 'StreakBadge', 'library': 'app.widgets'},
    ],
  };

  test('round-trips meta and catalog, keeping int and double apart', () {
    final state = SurfaceEditorState(
      meta: const <String, Object?>{
        'canvas': <String, Object?>{
          'main': <String, Object?>{'x': 10, 'y': 2.5, 'w': 390.0},
        },
        'slots': <String, Object?>{
          'card': <String, Object?>{'title': 'Hi', 'on': true, 'none': null},
        },
        'list': <Object?>[1, 1.0, 'a'],
      },
      catalog: catalog,
    );
    final decoded = SurfaceEditorState.decode(state.encode());
    expect(decoded, state);
    expect(decoded.encode(), state.encode());
    final main = (decoded.meta['canvas']! as Map)['main'] as Map;
    expect(main['x'], isA<int>());
    expect(main['w'], isA<double>());
    expect((decoded.meta['list']! as List)[1], isA<double>());
    expect(decoded.catalog, catalog);
  });

  test('encoding is canonical whatever the insertion order', () {
    final a = SurfaceEditorState(
      meta: const <String, Object?>{
        'b': 1,
        'a': <String, Object?>{'y': 1, 'x': 2},
      },
    );
    final b = SurfaceEditorState(
      meta: const <String, Object?>{
        'a': <String, Object?>{'x': 2, 'y': 1},
        'b': 1,
      },
    );
    expect(a.encode(), b.encode());
    expect(utf8.decode(a.encode()), '{"meta":{"a":{"x":2,"y":1},"b":1}}');
  });

  test('a state without a catalog omits it', () {
    final state = SurfaceEditorState();
    expect(utf8.decode(state.encode()), '{"meta":{}}');
    expect(SurfaceEditorState.decode(state.encode()).catalog, isNull);
  });

  test('travels in a draft payload', () {
    final state = SurfaceEditorState(meta: const <String, Object?>{'k': 'v'});
    final payload = BlobSurfacePayload(
      minClient: kBaselineCatalogVersion,
      blob: Uint8List.fromList(<int>[1, 2, 3]),
      editorState: state.encode(),
    );
    final decoded =
        SurfacePayload.decode(payload.canonicalBytes) as BlobSurfacePayload;
    expect(SurfaceEditorState.decode(decoded.editorState!), state);
  });

  test('round-trips per-screen meta, canonically', () {
    final state = SurfaceEditorState(
      catalog: catalog,
      screens: <String, Map<String, Object?>>{
        'welcome': <String, Object?>{'presentationStyle': 'sheet'},
        'goal': <String, Object?>{
          'canvas': <String, Object?>{'w': 1.5, 'n': 2},
        },
      },
    );
    final bytes = state.encode();
    final decoded = SurfaceEditorState.decode(bytes);
    expect(decoded, state);
    expect(decoded.screens!['goal'], state.screens!['goal']);
    expect(decoded.meta, isEmpty);
    expect(
      utf8.decode(bytes),
      startsWith('{"catalog":'),
    );
    expect(utf8.decode(bytes), contains('"screens":{"goal":'));
    expect(SurfaceEditorState().screens, isNull);
  });

  test('refuses bytes that are not editor state', () {
    for (final text in <String>[
      'not json',
      '[]',
      '{}',
      '{"meta":[]}',
      '{"meta":{},"catalog":1}',
      '{"meta":{},"extra":1}',
      '{"meta":{},"screens":[]}',
      '{"meta":{},"screens":{"a":1}}',
    ]) {
      expect(
        () => SurfaceEditorState.decode(_json(text)),
        throwsFormatException,
        reason: text,
      );
    }
  });

  test('refuses values JSON cannot carry', () {
    expect(
      () => SurfaceEditorState(meta: const <String, Object?>{'n': double.nan}),
      throwsArgumentError,
    );
    expect(
      () => SurfaceEditorState(
        meta: <String, Object?>{'d': DateTime(2026)},
      ),
      throwsArgumentError,
    );
    expect(
      () => SurfaceEditorState(
        meta: const <String, Object?>{
          'm': <Object, Object?>{1: 'x'},
        },
      ),
      throwsArgumentError,
    );
  });
}
