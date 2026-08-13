import 'package:restage_example/user_factories.g.dart';
import 'package:restage_preview_harness/restage_preview_harness.dart';
import 'package:restage_preview_host/restage_preview_host.dart';

import 'src/render_bundle_manifest_loader.dart';

const String _parentOrigin = String.fromEnvironment(
  'RESTAGE_RENDER_BUNDLE_PARENT_ORIGIN',
);

/// Starts the isolated customer render bundle.
Future<void> main() async {
  final manifest = await loadRenderBundleManifest();
  final transport = createBrowserRenderMessageTransport(
    parentOrigin: _parentOrigin,
  );
  runRestageRenderBundleHarness(
    transport: transport,
    manifest: manifest,
    engine: RenderEngine(flutterVersion: '3.47.0', renderer: 'skwasm'),
    registerCustomerWidgets: registerRestageCustomerWidgets,
    initialize: (_) {},
  );
}
