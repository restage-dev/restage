import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/analytics/analytics_identity.dart';
import 'package:restage/src/analytics/root_analytics_context.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the metering identity is wired by `Restage.configure`.
///
/// Two design statements are load-bearing here and neither is self-evident from
/// reading the call site:
///
///  1. the metering identity is minted independently of the analytics opt-out —
///     turning analytics off must not turn delivery counting off; and
///  2. the metering identity is sent ONLY to the surface-delivery endpoint, and
///     never appears in the analytics event stream.
///
/// Both are privacy-relevant promises made in the metering store's own
/// documentation, so they are pinned rather than left to code reading.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const supportChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory supportDirectory;

  // A fast-failing host: the analytics POST is intercepted by the injected
  // client.
  const baseUrl = 'http://127.0.0.1:1';

  setUp(() async {
    supportDirectory =
        await Directory.systemTemp.createTemp('restage-configure-');
    messenger.setMockMethodCallHandler(
        supportChannel,
        (call) async => call.method == 'getApplicationSupportDirectory'
            ? supportDirectory.path
            : null);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Restage.debugResetAndWait();
  });
  tearDown(() async {
    try {
      await Restage.debugResetAndWait();
    } finally {
      RootAnalyticsRuntime.debugIdentityFactory = null;
      messenger.setMockMethodCallHandler(supportChannel, null);
      await supportDirectory.delete(recursive: true);
    }
  });

  test('configuring analytics off with a hosted URL never reads the identifier',
      () async {
    final identity = _IdentityCallSpy();
    RootAnalyticsRuntime.debugIdentityFactory = () => identity;
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: baseUrl,
      analyticsEnabled: false,
    );

    await pumpEventQueue();

    expect(identity.calls, 0);
  });

  test('configuring analytics off never warms a retained identifier', () async {
    final identity = _IdentityCallSpy();
    RootAnalyticsRuntime.debugIdentityFactory = () => identity;
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    await pumpEventQueue();
    expect(identity.calls, 1);
    identity.calls = 0;

    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: baseUrl,
      analyticsEnabled: false,
    );
    await pumpEventQueue();

    expect(identity.calls, 0);
  });

  test('turning analytics off before deferred work never reads the identifier',
      () async {
    final identity = _IdentityCallSpy();
    RootAnalyticsRuntime.debugIdentityFactory = () => identity;
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: baseUrl,
      analyticsEnabled: false,
    );

    await pumpEventQueue();

    expect(identity.calls, 0);
  });

  test('configure installs the metering identity even with analytics disabled',
      () async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: baseUrl,
      analyticsEnabled: false,
    );

    final key = await SurfaceMeteringKeyProvider.currentKey();
    expect(
      key,
      isNotNull,
      reason: 'delivery counting does not depend on the analytics opt-in',
    );
    expect(
      await SurfaceAssignmentKeyProvider.resolve(),
      isNull,
      reason: 'the experiment-assignment identity DOES follow the opt-out — '
          'the two are deliberately different',
    );
  });

  test('configure does not persist a metering identity before a surface fetch',
      () async {
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);

    await pumpEventQueue();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('restage.metering_token'), isFalse);
  });

  test('the first surface fetch persists the metering identity', () async {
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    final client = RestageRpcClient(
      baseUrl: baseUrl,
      apiKey: 'rs_pk_test',
      httpClient: MockClient((_) async => http.Response('', 500)),
    );

    await client.fetchSurface(
      surfaceType: 'paywall',
      surfaceSlug: 'pro_upgrade',
    );

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('restage.metering_token'), isNotNull);
  });

  test('configure without a base URL installs no metering identity', () {
    Restage.configure(apiKey: 'rs_pk_test');

    expect(SurfaceMeteringKeyProvider.currentKey(), completion(isNull));
  });

  test(
      're-configuring without a base URL clears a previously installed '
      'metering identity', () async {
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    expect(await SurfaceMeteringKeyProvider.currentKey(), isNotNull);

    Restage.configure(apiKey: 'rs_pk_test');

    expect(await SurfaceMeteringKeyProvider.currentKey(), isNull);
  });

  test('the metering identity is stable across re-configuration', () async {
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    final first = await SurfaceMeteringKeyProvider.currentKey();

    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);

    expect(
      await SurfaceMeteringKeyProvider.currentKey(),
      first,
      reason: 'a device must not be recounted just because configure re-ran',
    );
  });

  test('reset clears both the metering identity and its store', () async {
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: baseUrl);
    expect(await SurfaceMeteringKeyProvider.currentKey(), isNotNull);

    Restage.debugReset();

    expect(await SurfaceMeteringKeyProvider.currentKey(), isNull);
  });
}

class _IdentityCallSpy extends AnalyticsIdentity {
  int calls = 0;

  @override
  Future<String> anonymousId() async {
    calls += 1;
    return '12345678-1234-4234-8234-123456789abc';
  }
}
