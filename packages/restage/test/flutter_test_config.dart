import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';

/// Installs the whole built-in widget catalog for every test in this package,
/// so a test that mounts a surface renders the widgets that surface names.
/// Each test starts with an empty surface store.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
  setUp(() => sharedSurfaceArtifactStore = MemorySurfaceArtifactStore());
  await testMain();
}
