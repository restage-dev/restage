import 'dart:convert';

import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/loader_engine_base.dart';
import 'package:test/test.dart';

void main() {
  final engineBase = Uri.parse(
    'https://bundles.example.dev/render-bundles/v1/engine/abc123/',
  );

  /// The shape a built loader has: the engine script, the build config, then
  /// the app's own call.
  String loader({
    String flutterJs = 'window._flutter.loader||(window._flutter.loader=1);',
    String config = '_flutter.buildConfig = {"engineRevision":"59d5"};\n',
    String call =
        "_flutter.loader.load({config: {fontFallbackBaseUrl: 'assets/'}});\n",
  }) => '$flutterJs\n$config$call';

  test('the base goes in between the build config and the call', () {
    final rewritten = withLoaderEngineBase(loader(), engineBase: engineBase);
    final configEnd = rewritten.indexOf('"engineRevision":"59d5"};\n');
    final wrapperAt = rewritten.indexOf('canvasKitBaseUrl:');
    final callAt = rewritten.indexOf('_flutter.loader.load({config:');
    expect(configEnd, greaterThan(-1));
    expect(wrapperAt, greaterThan(configEnd));
    expect(callAt, greaterThan(wrapperAt));
    expect(
      rewritten,
      contains(
        'canvasKitBaseUrl: '
        '"https://bundles.example.dev/render-bundles/v1/engine/abc123/"',
      ),
    );
  });

  test('nothing else in the loader moves', () {
    final source = loader();
    final rewritten = withLoaderEngineBase(source, engineBase: engineBase);
    final wrapperAt = rewritten.indexOf('(() => { const l = _flutter.loader');
    final wrapperEnd =
        rewritten.indexOf('})();\n', wrapperAt) + '})();\n'.length;
    expect(
      rewritten.substring(0, wrapperAt) + rewritten.substring(wrapperEnd),
      source,
    );
  });

  test('the same loader rewrites to the same bytes', () {
    final source = loader();
    expect(
      withLoaderEngineBase(source, engineBase: engineBase),
      withLoaderEngineBase(source, engineBase: engineBase),
    );
  });

  test('the base is embedded as an encoded string literal', () {
    // A quote in the path must not be able to close the literal it sits in.
    final base = Uri.parse("https://bundles.example.dev/engine/a'b/");
    final rewritten = withLoaderEngineBase(loader(), engineBase: base);
    const marker = 'canvasKitBaseUrl: ';
    final start = rewritten.indexOf(marker) + marker.length;
    final end = rewritten.indexOf('}});', start);
    expect(jsonDecode(rewritten.substring(start, end)), base.toString());
  });

  test('a loader without a build configuration is refused', () {
    expect(
      () => withLoaderEngineBase(loader(config: ''), engineBase: engineBase),
      throwsA(_loaderContract),
    );
  });

  test('an unterminated build configuration is refused', () {
    expect(
      () => withLoaderEngineBase(
        loader(config: '_flutter.buildConfig = {"engineRevision":"59d5"}'),
        engineBase: engineBase,
      ),
      throwsA(_loaderContract),
    );
  });

  test('a call that runs before the configuration is refused', () {
    expect(
      () => withLoaderEngineBase(
        '_flutter.loader.load({});\n'
        '_flutter.buildConfig = {"engineRevision":"59d5"};\n',
        engineBase: engineBase,
      ),
      throwsA(_loaderContract),
    );
  });

  test('a loader that never loads is refused', () {
    expect(
      () => withLoaderEngineBase(loader(call: ''), engineBase: engineBase),
      throwsA(_loaderContract),
    );
  });

  test('a configuration before the engine script is refused', () {
    expect(
      () => withLoaderEngineBase(
        loader(flutterJs: '// no engine script yet'),
        engineBase: engineBase,
      ),
      throwsA(_loaderContract),
    );
  });
}

final _loaderContract = isA<RenderBundleBuildException>().having(
  (error) => error.reason,
  'reason',
  'loader_contract',
);
