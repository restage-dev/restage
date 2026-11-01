import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Installs the whole built-in widget catalog for every test in this package,
/// so a test that mounts a surface renders the widgets that surface names.
/// Each test starts with an empty surface store.
/// Platform metadata is unavailable unless a test supplies it. Preferences
/// are in memory, so the first-launch read never reaches a missing plugin.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
  setUp(() {
    sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (BindingBase.debugBindingType() == null) return;
    final binding = ServicesBinding.instance;
    if (binding is! TestDefaultBinaryMessengerBinding) return;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (_) async => throw MissingPluginException(),
    );
  });
  await testMain();
}
