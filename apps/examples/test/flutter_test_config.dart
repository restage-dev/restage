import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
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
