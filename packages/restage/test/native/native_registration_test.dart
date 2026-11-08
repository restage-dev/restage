import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/runtime/native_facts.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';

// Exercise the production channel path; its test bypass checks the binding name.
class _ChannelBinding extends AutomatedTestWidgetsFlutterBinding {}

void main() {
  final binding = _ChannelBinding();
  const channel = MethodChannel('restage/early_request');

  setUp(() {
    NativeFacts.reset();
    NativeFacts.debugFacts = null;
    NativeFacts.debugResetRegistration = null;
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    NativeFacts.reset();
  });

  final oldNativeTuple = <String, Object?>{
    'registrationNonce':
        base64UrlEncode(List<int>.filled(32, 1)).replaceAll('=', ''),
    'registrationCreatedAtMicros': 100,
  };
  final newNativeTuple = <String, Object?>{
    'registrationNonce':
        base64UrlEncode(List<int>.filled(32, 2)).replaceAll('=', ''),
    'registrationCreatedAtMicros': 200,
  };

  for (final failure in ['platform', 'missingChannel', 'null', 'malformed']) {
    for (final stage in ['read', 'reset']) {
      test('native channel $stage $failure refuses durable rotation', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final calls = <String>[];
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
            (call) async {
          calls.add(call.method);
          if (stage == 'reset' && call.method == 'registration') {
            return oldNativeTuple;
          }
          switch (failure) {
            case 'platform':
              throw PlatformException(code: 'registration_unavailable');
            case 'missingChannel':
              throw MissingPluginException();
            case 'null':
              return null;
            default:
              return {'registrationNonce': 42};
          }
        });
        await expectLater(
          SurfaceAssignmentCredentialStore.resetPlatformRegistration(
            isCurrent: () => true,
          ),
          throwsA(isA<Object>()),
        );
        expect(
            calls,
            stage == 'read'
                ? ['registration']
                : ['registration', 'resetRegistration']);
      });
    }
  }

  test('native channel success rotates and unsupported platform is absent',
      () async {
    final calls = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return call.method == 'registration' ? oldNativeTuple : newNativeTuple;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await SurfaceAssignmentCredentialStore.resetPlatformRegistration(
      isCurrent: () => true,
    );
    expect(calls, ['registration', 'resetRegistration']);
    expect((await NativeFacts.registration())!.nonce,
        newNativeTuple['registrationNonce']);
    calls.clear();
    NativeFacts.reset();
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await SurfaceAssignmentCredentialStore.resetPlatformRegistration(
      isCurrent: () => true,
    );
    expect(calls, isEmpty);
  });

  test('native channel ordinary reads remain best effort', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final calls = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      throw PlatformException(code: 'registration_unavailable');
    });
    expect(await NativeFacts.registration(), isNull);
    expect(await NativeFacts.resetRegistration(), isNull);
    expect(calls, ['facts', 'registration', 'resetRegistration']);
    // Cached best-effort absence must not acknowledge the later durable reset.
    await expectLater(
      SurfaceAssignmentCredentialStore.resetPlatformRegistration(
        isCurrent: () => true,
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(calls.last, 'registration');
  });
}
