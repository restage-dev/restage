import 'dart:convert';

import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';

const _buildConfigMarker = '_flutter.buildConfig = ';
const _loaderObject = '_flutter.loader';
const _loadCall = '_flutter.loader.load';

/// Sets both loader renderers to the immutable [engineBase] origin.
/// Throws [RenderBundleBuildException] with `loader_contract` for an
/// unrecognized loader layout.
String withLoaderEngineBase(String loaderSource, {required Uri engineBase}) {
  final configStart = loaderSource.lastIndexOf(_buildConfigMarker);
  if (configStart < 0) {
    throw const RenderBundleBuildException(
      RenderBundleBuildFailure.loaderContract,
    );
  }
  final configEnd = loaderSource.indexOf(
    ';\n',
    configStart + _buildConfigMarker.length,
  );
  if (configEnd < 0) {
    throw const RenderBundleBuildException(
      RenderBundleBuildFailure.loaderContract,
    );
  }
  final insertAt = configEnd + 2;

  final loaderAt = loaderSource.indexOf(_loaderObject);
  if (loaderAt < 0 || loaderAt >= insertAt) {
    throw const RenderBundleBuildException(
      RenderBundleBuildFailure.loaderContract,
    );
  }
  if (!loaderSource.contains(_loadCall, insertAt)) {
    throw const RenderBundleBuildException(
      RenderBundleBuildFailure.loaderContract,
    );
  }

  final base = jsonEncode(engineBase.toString());
  final wrapper =
      '(() => { const l = _flutter.loader, f = l.load.bind(l);\n'
      '  l.load = (o = {}) => f({...o, config: {...(o.config ?? {}), '
      'canvasKitBaseUrl: $base}});\n'
      '})();\n';
  return loaderSource.substring(0, insertAt) +
      wrapper +
      loaderSource.substring(insertAt);
}
