import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

const _revision = 'af7e796e161ae0bb1ff0758c71a7105418bd9ded';

void main() {
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));
  String hashOf(Uint8List value) => 'sha256:${crypto.sha256.convert(value)}';

  final skwasm = bytes('skwasm runtime');
  final canvaskit = bytes('chromium canvaskit');
  final engineSet = RenderBundleEngineSet(
    flutterVersion: '3.47.0',
    engineRevision: _revision,
    files: <RenderBundleEngineFile>[
      RenderBundleEngineFile(
        path: 'chromium/canvaskit.wasm',
        contentHash: hashOf(canvaskit),
        byteLength: canvaskit.length,
      ),
      RenderBundleEngineFile(
        path: 'skwasm.wasm',
        contentHash: hashOf(skwasm),
        byteLength: skwasm.length,
      ),
    ],
  );

  test('the engine leaves the app files under its own paths', () {
    final artifact = splitRenderBundleEngineFiles(<String, Uint8List>{
      'index.html': bytes('<!doctype html>'),
      'main.dart.wasm': bytes('app'),
      'flutter.js': bytes('loader'),
      '${renderBundleEnginePathPrefix}skwasm.wasm': skwasm,
      '${renderBundleEnginePathPrefix}chromium/canvaskit.wasm': canvaskit,
    }, engineSet);

    expect(artifact.appFiles.keys, <String>[
      'index.html',
      'main.dart.wasm',
      'flutter.js',
    ]);
    // `flutter.js` sits at the output root, so it stays with the app.
    expect(artifact.engineSetId, engineSet.id);
  });

  test('the symbol maps beside the engine are dropped', () {
    final artifact = splitRenderBundleEngineFiles(<String, Uint8List>{
      'index.html': bytes('<!doctype html>'),
      '${renderBundleEnginePathPrefix}skwasm.wasm': skwasm,
      '${renderBundleEnginePathPrefix}skwasm.wasm.symbols': bytes('unfetched'),
      '${renderBundleEnginePathPrefix}chromium/canvaskit.wasm': canvaskit,
      '${renderBundleEnginePathPrefix}chromium/canvaskit.wasm.symbols': bytes(
        'unfetched',
      ),
    }, engineSet);

    expect(artifact.appFiles.keys, <String>['index.html']);
    expect(artifact.engineSetId, engineSet.id);
  });

  test('a pinned file the build never produced refuses it', () {
    expect(
      () => splitRenderBundleEngineFiles(<String, Uint8List>{
        'index.html': bytes('<!doctype html>'),
        '${renderBundleEnginePathPrefix}skwasm.wasm': skwasm,
      }, engineSet),
      throwsA(
        isA<RenderBundleBuildException>()
            .having((error) => error.reason.code, 'reason', 'engine_incomplete')
            .having(
              (error) => error.detail,
              'detail',
              'chromium/canvaskit.wasm',
            ),
      ),
    );
  });

  test('an engine file the set does not hold refuses the build', () {
    expect(
      () => splitRenderBundleEngineFiles(<String, Uint8List>{
        'index.html': bytes('<!doctype html>'),
        '${renderBundleEnginePathPrefix}skwasm.wasm': bytes('another build'),
      }, engineSet),
      throwsA(
        isA<RenderBundleBuildException>().having(
          (error) => error.reason.code,
          'reason',
          'engine_toolchain',
        ),
      ),
    );
  });

  test('a file the set never names refuses the build', () {
    expect(
      () => splitRenderBundleEngineFiles(<String, Uint8List>{
        'index.html': bytes('<!doctype html>'),
        '${renderBundleEnginePathPrefix}surprise.wasm': bytes('surprise'),
      }, engineSet),
      throwsA(
        isA<RenderBundleBuildException>().having(
          (error) => error.reason.code,
          'reason',
          'engine_toolchain',
        ),
      ),
    );
  });

  test('the set is derived from the files the build wrote', () {
    final files = <String, Uint8List>{
      'index.html': bytes('<!doctype html>'),
      '${renderBundleEnginePathPrefix}skwasm.wasm': skwasm,
      '${renderBundleEnginePathPrefix}skwasm.wasm.symbols': bytes('unfetched'),
      '${renderBundleEnginePathPrefix}chromium/canvaskit.wasm': canvaskit,
    };
    final derived = deriveRenderBundleEngineSet(
      files,
      flutterVersion: '3.99.0-0.1.pre',
      engineRevision: _revision,
    );
    expect(derived.flutterVersion, '3.99.0-0.1.pre');
    expect(derived.files.map((file) => file.path), <String>[
      'chromium/canvaskit.wasm',
      'skwasm.wasm',
    ]);
    expect(derived.fileForPath('skwasm.wasm')!.contentHash, hashOf(skwasm));
    // Same bytes, same version, same identifier as a set declared by hand.
    expect(
      deriveRenderBundleEngineSet(
        files,
        flutterVersion: '3.47.0',
        engineRevision: _revision,
      ).id,
      engineSet.id,
    );

    final artifact = splitRenderBundleEngineFiles(files, derived);
    expect(artifact.engineSetId, derived.id);
    expect(artifact.flutterVersion, '3.99.0-0.1.pre');
  });

  test('a build that wrote no engine files is refused', () {
    expect(
      () => deriveRenderBundleEngineSet(
        <String, Uint8List>{'index.html': bytes('<!doctype html>')},
        flutterVersion: '3.47.0',
        engineRevision: _revision,
      ),
      throwsA(
        isA<RenderBundleBuildException>().having(
          (error) => error.reason.code,
          'reason',
          'engine_missing',
        ),
      ),
    );
  });
}
