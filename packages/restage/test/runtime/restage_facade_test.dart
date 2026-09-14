import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
// Direct path import — the registry is internal; the test reaches in to
// verify the public facade routes registrations into it.
// ignore: implementation_imports
import 'package:restage/src/refresh/restage_hosted_update_channel.dart';
import 'package:restage/src/runtime/library_runtime_registry.dart';
// Direct path import — the assignment-key provider is internal; these tests pin
// configure/debugReset lifecycle rather than exposing a host-facing API.
// ignore: implementation_imports
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
// Direct path import — the RPC client is internal, but the test-only facade
// seam exposes it for compatibility.
// ignore: implementation_imports
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
// `rfw` exposes a `WidgetLibrary` that collides with the catalog identifier
// re-exported from `restage`. Hide the rfw symbol.
import 'package:rfw/rfw.dart' hide WidgetLibrary;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const supportChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory supportDirectory;

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
      messenger.setMockMethodCallHandler(supportChannel, null);
      await supportDirectory.delete(recursive: true);
    }
  });

  test('configure sets apiKey and environment', () {
    Restage.configure(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
    );
    expect(Restage.debugApiKey, 'rs_pk_test');
    expect(Restage.debugEnvironment, RestageEnvironment.sandbox);
  });

  test('commerce is stable across runtime resets', () {
    final commerce = Restage.commerce;

    expect(commerce, isA<RestageCommerce>());

    Restage.debugReset();

    expect(Restage.commerce, same(commerce));
  });

  test('configure with apiKey installs RestageVariantResolver as default', () {
    Restage.configure(apiKey: 'rs_pk_test');
    expect(Restage.debugDefaultResolver, isA<RestageVariantResolver>());
  });

  test('configure threads apiKey + environment into the default resolver', () {
    // apiKey + environment are the observable threading; baseUrl rides the
    // same constructor call and is wrapped into the hosted-fetch client.
    Restage.configure(
      apiKey: 'rs_pk_live_xyz',
      environment: RestageEnvironment.production,
    );
    final resolver = Restage.debugDefaultResolver;
    expect(resolver, isA<RestageVariantResolver>());
    expect((resolver as RestageVariantResolver).apiKey, 'rs_pk_live_xyz');
    expect(resolver.environment, RestageEnvironment.production);
  });

  test('an explicit resolver overrides the hosted default', () {
    Restage.configure(
      apiKey: 'rs_pk_test',
      resolver: const AssetVariantResolver(),
    );
    expect(Restage.debugDefaultResolver, isA<AssetVariantResolver>());
  });

  test('configure installs the hosted update channel when fully configured',
      () {
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://api.example.com',
      liveRefreshEdgeUrl: Uri.parse('https://edge.example.com'),
    );
    _installRpcClient();

    expect(
      Restage.configuredUpdateChannel,
      isA<RestageHostedUpdateChannel>(),
    );
  });

  test('a custom update channel wins over the hosted channel', () {
    final channel = _FacadeUpdateChannel();
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://api.example.com',
      liveRefreshEdgeUrl: Uri.parse('https://edge.example.com'),
      updateChannel: channel,
    );
    _installRpcClient();

    expect(Restage.configuredUpdateChannel, same(channel));
  });

  test('events is a broadcast stream', () async {
    Restage.configure(apiKey: 'rs_pk_test');
    final received = <String>[];
    final sub1 = Restage.events.listen((e) => received.add('A:${e.name}'));
    final sub2 = Restage.events.listen((e) => received.add('B:${e.name}'));
    Restage.debugFire(const PaywallLoadStarted(paywallId: 'x'));
    await Future<void>.delayed(Duration.zero);
    expect(received, ['A:paywall_load_started', 'B:paywall_load_started']);
    await sub1.cancel();
    await sub2.cancel();
  });

  test('registerWidgetLibrary records the library in the runtime registry', () {
    Restage.configure(apiKey: 'rs_pk_test');
    Restage.registerWidgetLibrary(
      const WidgetLibrary.custom('acme.design_system'),
      widgets: <RestageWidgetFactory>[
        RestageWidgetFactory(
          name: 'AcmeButton',
          builder: (context, source) => const SizedBox(),
        ),
      ],
    );

    final runtime = Runtime();
    LibraryRuntimeRegistry.applyTo(runtime);
    expect(
      runtime.libraries.keys,
      contains(const LibraryName(['acme', 'design_system'])),
    );
  });

  test('debugReset clears registered widget libraries', () {
    Restage.configure(apiKey: 'rs_pk_test');
    Restage.registerWidgetLibrary(
      const WidgetLibrary.custom('acme.design_system'),
      widgets: <RestageWidgetFactory>[
        RestageWidgetFactory(
          name: 'AcmeButton',
          builder: (context, source) => const SizedBox(),
        ),
      ],
    );

    Restage.debugReset();

    final runtime = Runtime();
    LibraryRuntimeRegistry.applyTo(runtime);
    expect(runtime.libraries, isEmpty);
  });

  test('reset is a no-op when configure was given no baseUrl', () {
    Restage.configure(apiKey: 'rs_pk_test');
    Restage.reset();
    // No assertion — just verifies it does not throw with no actor to rotate.
  });

  test(
      'configure with baseUrl and analytics enabled installs the '
      'assignment-key provider', () async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://api.example.com',
    );
    _installRpcClient();

    expect(await SurfaceAssignmentKeyProvider.resolve(), 'credential.facade');
  });

  test(
      'analyticsEnabled false disables assignment keys even with hosted '
      'delivery configured', () async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://api.example.com',
      analyticsEnabled: false,
    );
    _installRpcClient();

    expect(await SurfaceAssignmentKeyProvider.resolve(), isNull);
  });

  test('configure without baseUrl leaves assignment keys disabled', () async {
    Restage.configure(apiKey: 'rs_pk_test');

    expect(await SurfaceAssignmentKeyProvider.resolve(), isNull);
  });

  test('debugReset clears the internal assignment-key provider', () async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://api.example.com',
    );
    _installRpcClient();
    expect(await SurfaceAssignmentKeyProvider.resolve(), 'credential.facade');

    Restage.debugReset();

    expect(await SurfaceAssignmentKeyProvider.resolve(), isNull);
  });

  test('reconfiguring from hosted to bundled-only clears assignment keys',
      () async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://api.example.com',
    );
    _installRpcClient();
    expect(await SurfaceAssignmentKeyProvider.resolve(), 'credential.facade');

    Restage.configure(apiKey: 'rs_pk_test');

    expect(await SurfaceAssignmentKeyProvider.resolve(), isNull);
  });
}

final class _FacadeUpdateChannel implements SurfaceUpdateChannel {
  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) => const Stream.empty();
}

void _installRpcClient() {
  Restage.debugRestageRpcClient = RestageRpcClient(
    baseUrl: 'https://api.example.com',
    apiKey: 'rs_pk_test',
    httpClient: MockClient(
      (request) async => request.url.path ==
              '/sdk/v1/measurement-assignment-credential'
          ? http.Response(
              '{"credentialHandle":"credential.facade","expiresAtMicros":4102444800000000}',
              200)
          : http.Response('', 404),
    ),
  );
}
