/// Entrypoint for the web bundle used to preview an app's widgets.
/// Imported only by the generated render bundle entrypoint.
library;

import 'package:flutter/widgets.dart' show VoidCallback, runApp;

import 'src/render_host/render_bundle_manifest_loader.dart';
import 'src/render_host/render_bundle_view_binding.dart';
import 'src/render_host/render_core.dart';
import 'src/render_host/render_host_app.dart';
import 'src/render_host/browser_render_message_transport.dart';

/// Loads the bundle's manifest, connects to the dashboard at [parentOrigin],
/// and renders what it sends with the widgets [registerWidgets] installs.
///
/// Called by the generated render bundle entrypoint; apps do not call it.
///
/// [flutterVersion] is the toolchain the bundle was built with.
Future<void> runRestageRenderBundle({
  required VoidCallback registerWidgets,
  required String parentOrigin,
  required String flutterVersion,
}) async {
  final manifest = await loadRenderBundleManifest();
  final transport = createBrowserRenderMessageTransport(
    parentOrigin: parentOrigin,
  );
  final rasterController = RenderBundleViewBinding();
  runApp(RenderHostApp(
    transport: transport,
    manifest: manifest,
    engine: RenderEngine(flutterVersion: flutterVersion, renderer: 'skwasm'),
    registerAppWidgets: registerWidgets,
    rasterController: rasterController,
  ));
}
