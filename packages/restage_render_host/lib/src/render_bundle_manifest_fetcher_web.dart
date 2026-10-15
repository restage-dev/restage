import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'render_bundle_manifest_fetch.dart';

Future<RenderBundleManifestFetchResponse> fetchRenderBundleManifest(
  RenderBundleManifestFetchRequest request,
) async {
  final response = await web.window
      .fetch(
        request.uri.toString().toJS,
        web.RequestInit(
          method: request.method,
          credentials: request.credentials,
          cache: request.cache,
          mode: request.mode,
          redirect: request.redirect,
        ),
      )
      .toDart;
  final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
  return (status: response.status, bytes: bytes);
}
