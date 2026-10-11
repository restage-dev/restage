import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

/// Answers the application support directory channel for this test file.
/// Call once at the top of `main` so the SDK's background privacy purge does
/// not fail on a missing platform channel after the test finishes.
void useSupportDirectoryChannel() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
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
  });

  tearDownAll(() async {
    await Restage.debugResetAndWait();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });
}
