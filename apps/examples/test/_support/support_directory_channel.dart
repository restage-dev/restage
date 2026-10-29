import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

/// Answers the application support directory channel for this test file.
/// Call once at the top of `main` so the SDK's background privacy purge does
/// and install-date read do not fail on a missing platform channel after the
/// test finishes.
void useSupportDirectoryChannel() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  const preferences = MethodChannel('plugins.flutter.io/shared_preferences');
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('restage-example-test-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method != 'getApplicationSupportDirectory') {
          throw MissingPluginException('Unexpected method: ${call.method}');
        }
        return directory.path;
      },
    );
    // The SDK reads its install date from stored preferences at configure.
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      preferences,
      (call) async => switch (call.method) {
        'getAll' => <String, Object>{},
        _ => true,
      },
    );
  });

  tearDownAll(() async {
    await Restage.debugResetAndWait();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(preferences, null);
    await directory.delete(recursive: true);
  });
}
