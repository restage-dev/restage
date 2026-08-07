import 'dart:convert';

import 'package:restage_preview_host/restage_preview_host.dart';

import 'render_bundle_manifest_fetch.dart';
import 'render_bundle_manifest_fetcher_stub.dart'
    if (dart.library.js_interop) 'render_bundle_manifest_fetcher_web.dart'
    as browser;

export 'render_bundle_manifest_fetch.dart';

const _manifestPath = 'restage_bundle_manifest.json';
const _invalidManifest = 'Invalid render bundle manifest.';

/// Loads and validates the bundle's immutable same-origin manifest sidecar.
///
/// The caller must await this before creating transport or starting the
/// harness, so every failure remains a handshake timeout at the parent.
Future<RenderBundleManifest> loadRenderBundleManifest({
  Uri? documentUri,
  RenderBundleManifestFetcher? fetch,
}) async {
  try {
    final base = documentUri ?? Uri.base;
    if (!base.isAbsolute ||
        (base.scheme != 'http' && base.scheme != 'https') ||
        base.userInfo.isNotEmpty) {
      throw const FormatException(_invalidManifest);
    }
    final sidecar = base.resolve(_manifestPath);
    if (sidecar.origin != base.origin) {
      throw const FormatException(_invalidManifest);
    }
    final request = RenderBundleManifestFetchRequest(uri: sidecar);
    final response = await (fetch ?? browser.fetchRenderBundleManifest)(
      request,
    );
    if (response.status != 200) {
      throw const FormatException(_invalidManifest);
    }
    final source = utf8.decode(response.bytes, allowMalformed: false);
    final decoded = jsonDecode(source);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException(_invalidManifest);
    }
    final document = <String, Object?>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException(_invalidManifest);
      }
      document[entry.key! as String] = entry.value;
    }
    return RenderBundleManifest.fromJson(document);
  } on Object {
    throw const FormatException(_invalidManifest);
  }
}
