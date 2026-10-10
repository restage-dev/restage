import 'dart:convert';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

const _revision = 'af7e796e161ae0bb1ff0758c71a7105418bd9ded';

RenderBundleEngineSet _set({String flutterVersion = '3.49.0-1.2.pre'}) =>
    RenderBundleEngineSet.fromFiles(
      flutterVersion: flutterVersion,
      engineRevision: _revision,
      files: {
        'skwasm.wasm': utf8.encode('wasm bytes'),
        'chromium/canvaskit.wasm': utf8.encode('canvaskit bytes'),
        'skwasm.js': utf8.encode('loader'),
      },
    );

void main() {
  test('a set derived from files is sorted, hashed and measured', () {
    final set = _set();
    expect(set.files.map((file) => file.path), [
      'chromium/canvaskit.wasm',
      'skwasm.js',
      'skwasm.wasm',
    ]);
    expect(set.fileForPath('skwasm.js')!.byteLength, 6);
    expect(set.byteLength, 31);
    expect(set.canonicalForm, startsWith('restage.render-bundle-engine-set.'));
    expect(
      set.canonicalForm,
      contains('\nflutter 3.49.0-1.2.pre\nengine $_revision\n'),
    );
    expect(set.id, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('the identifier follows the SDK version and every byte', () {
    expect(_set().id, _set().id);
    expect(_set(flutterVersion: '3.50.1').id, isNot(_set().id));
    expect(
      RenderBundleEngineSet.fromFiles(
        flutterVersion: '3.49.0-1.2.pre',
        engineRevision: 'b' * 40,
        files: {'skwasm.wasm': utf8.encode('wasm bytes')},
      ).id,
      isNot(
        RenderBundleEngineSet.fromFiles(
          flutterVersion: '3.49.0-1.2.pre',
          engineRevision: _revision,
          files: {'skwasm.wasm': utf8.encode('wasm bytes')},
        ).id,
      ),
    );
    final other = RenderBundleEngineSet.fromFiles(
      flutterVersion: '3.49.0-1.2.pre',
      engineRevision: _revision,
      files: {'skwasm.wasm': utf8.encode('wasm bytez')},
    );
    expect(other.id, isNot(_set().id));
  });

  test('a canonical form parses back to the same set', () {
    final set = _set();
    final parsed = RenderBundleEngineSet.parse(set.canonicalForm);
    expect(parsed.id, set.id);
    expect(parsed.files, set.files);
    expect(parsed.flutterVersion, set.flutterVersion);
    expect(parsed.engineRevision, _revision);
  });

  test('text that is not exactly a canonical form is refused', () {
    final text = _set().canonicalForm;
    for (final bad in [
      '',
      text.trimRight(),
      '$text\n',
      text.replaceFirst('restage.', 'other.'),
      text.replaceFirst(' 10\n', ' 010\n'),
      text.replaceFirst('\n', '\r\n'),
      text.replaceFirst('flutter ', 'flutter  '),
      text.replaceFirst('engine $_revision', 'engine ${'A' * 40}'),
      text.replaceAll('\n', ' \n'),
    ]) {
      expect(() => RenderBundleEngineSet.parse(bad), throwsFormatException);
    }
  });

  test('a bundle path maps to the set entry the loader asks for', () {
    final set = _set();
    final file = set.fileForPath('chromium/canvaskit.wasm');
    expect(file, isNotNull);
    expect(
      set.holds(
        path: 'chromium/canvaskit.wasm',
        contentHash: file!.contentHash,
      ),
      isTrue,
    );
    expect(
      set.holds(
        path: 'chromium/canvaskit.wasm',
        contentHash: 'sha256:${'0' * 64}',
      ),
      isFalse,
    );
    expect(set.fileForPath('canvaskit/skwasm.wasm'), isNull);
  });

  test('a set refuses a shape the loader could not resolve', () {
    RenderBundleEngineFile file(String path) => RenderBundleEngineFile(
          path: path,
          contentHash: 'sha256:${'a' * 64}',
          byteLength: 1,
        );

    expect(() => file('../escape.wasm'), throwsFormatException);
    expect(() => file('/absolute.wasm'), throwsFormatException);
    expect(() => file('has space.wasm'), throwsFormatException);
    expect(
      () => RenderBundleEngineFile(
        path: 'a.wasm',
        contentHash: 'sha256:${'A' * 64}',
        byteLength: 1,
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineFile(
        path: 'a.wasm',
        contentHash: 'sha256:${'a' * 64}',
        byteLength: 0,
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineSet(
        flutterVersion: '3.47.0',
        engineRevision: _revision,
        files: <RenderBundleEngineFile>[file('b.wasm'), file('a.wasm')],
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineSet(
        flutterVersion: '3.47.0',
        engineRevision: _revision,
        files: <RenderBundleEngineFile>[file('a.wasm'), file('a.wasm')],
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineSet(
        flutterVersion: 'latest',
        engineRevision: _revision,
        files: <RenderBundleEngineFile>[file('a.wasm')],
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineSet(
        flutterVersion: '3.47.0',
        engineRevision: _revision,
        files: const <RenderBundleEngineFile>[],
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineFile(
        path: 'a.wasm',
        contentHash: 'sha256:${'a' * 64}',
        byteLength: renderBundleEngineFileMaxBytes + 1,
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineSet(
        flutterVersion: '3.47.0',
        engineRevision: _revision,
        files: <RenderBundleEngineFile>[
          for (var index = 0; index < 5; index++)
            RenderBundleEngineFile(
              path: 'f$index.wasm',
              contentHash: 'sha256:${'a' * 64}',
              byteLength: renderBundleEngineFileMaxBytes,
            ),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineSet(
        flutterVersion: '3.47.0',
        engineRevision: 'local',
        files: <RenderBundleEngineFile>[file('a.wasm')],
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineSet(
        flutterVersion: '3.47.0 ',
        engineRevision: _revision,
        files: <RenderBundleEngineFile>[file('a.wasm')],
      ),
      throwsFormatException,
    );
    expect(
      () => RenderBundleEngineSet(
        flutterVersion: '3.47.0',
        engineRevision: _revision,
        files: <RenderBundleEngineFile>[
          for (var index = 0; index <= renderBundleEngineSetMaxFiles; index++)
            file('f${index.toString().padLeft(3, '0')}.wasm'),
        ],
      ),
      throwsFormatException,
    );
  });
}
