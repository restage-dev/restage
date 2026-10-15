/// Renders an app's widgets for a preview: the render protocol, the raw RFW
/// render surface, and the entrypoint of the web bundle a build generates.
library;

import 'package:flutter/widgets.dart' show VoidCallback, runApp;

import 'src/browser_render_message_transport.dart';
import 'src/render_bundle_manifest_loader.dart';
import 'src/render_bundle_view_binding.dart';
import 'src/render_core.dart';
import 'src/render_host_app.dart';

export 'src/render_core.dart';
export 'src/render_host_app.dart' show RenderHostApp;
export 'src/wire_json.dart' show rejectCredentialFields, snapshotWireMap;

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
