import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

/// Gives configure/reset tests isolated storage for real journal retirement.
void installRestageRuntimeTestSupport() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory support;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('restage-runtime-test-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method != 'getApplicationSupportDirectory') {
          throw MissingPluginException('Unexpected method: ${call.method}');
        }
        return support.path;
      },
    );
    await Restage.debugResetAndWait();
  });

  tearDown(() async {
    try {
      await Restage.debugResetAndWait();
    } finally {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      await support.delete(recursive: true);
    }
  });
}
