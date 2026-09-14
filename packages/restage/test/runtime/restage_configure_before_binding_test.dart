import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  var bindingAlreadyInitialized = false;
  try {
    ServicesBinding.instance;
    bindingAlreadyInitialized = true;
  } on Object {
    // This entry test starts before a host would initialize its binding.
  }
  final support =
      Directory.systemTemp.createTempSync('restage-before-binding-');

  // Match a synchronous host main: configure, then initialize via runApp.
  Restage.configure(apiKey: 'rs_pk_before_binding');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final methods = <String>[];
  binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
      (call) async {
    methods.add(call.method);
    return support.path;
  });

  test('synchronous startup initializes binding before deferred cold purge',
      () async {
    try {
      expect(bindingAlreadyInitialized, isFalse);
      await Restage.debugResetAndWait();
      expect(methods, ['getApplicationSupportDirectory']);
    } finally {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      await support.delete(recursive: true);
    }
  });

  test('ordinary reset hooks do not return an asynchronous retirement', () {
    expect(Function.apply(Restage.debugReset, const <Object?>[]), isNull);
  });
}
