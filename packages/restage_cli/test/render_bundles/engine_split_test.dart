import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));
  String hashOf(Uint8List value) => 'sha256:${crypto.sha256.convert(value)}';

  final skwasm = bytes('skwasm runtime');
  final canvaskit = bytes('chromium canvaskit');
  final engineSet = RenderBundleEngineSet(
    flutterVersion: '3.47.0',
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
    expect(artifact.engineFiles.keys, <String>[
      'skwasm.wasm',
      'chromium/canvaskit.wasm',
    ]);
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
    expect(artifact.engineFiles.keys, <String>[
      'skwasm.wasm',
      'chromium/canvaskit.wasm',
    ]);
  });

  test('a pinned file the build never produced refuses it', () {
    expect(
      () => splitRenderBundleEngineFiles(<String, Uint8List>{
        'index.html': bytes('<!doctype html>'),
        '${renderBundleEnginePathPrefix}skwasm.wasm': skwasm,
      }, engineSet),
      throwsA(
        isA<RenderBundleBuildException>()
            .having((error) => error.reason, 'reason', 'engine_incomplete')
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
          (error) => error.reason,
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
          (error) => error.reason,
          'reason',
          'engine_toolchain',
        ),
      ),
    );
  });

  test('the pinned set the builder uses is the one for its Flutter pin', () {
    final pinned = renderBundleEngineSetForFlutterVersion(
      requiredRenderBundleFlutterVersion,
    );
    expect(pinned, isNotNull);
    expect(pinned!.flutterVersion, requiredRenderBundleFlutterVersion);
  });
}
