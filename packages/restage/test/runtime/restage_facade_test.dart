import 'dart:convert';

import 'package:flutter/widgets.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
  });

  test('configure sets apiKey, environment, products', () {
    Restage.configure(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
    );
    expect(Restage.debugApiKey, 'rs_pk_test');
    expect(Restage.debugEnvironment, RestageEnvironment.sandbox);
    expect(Restage.debugProducts.length, 1);
  });

  test('configure with apiKey installs RestageVariantResolver as default', () {
    Restage.configure(apiKey: 'rs_pk_test');
    expect(Restage.debugDefaultResolver, isA<RestageVariantResolver>());
  });

  test('configure threads apiKey + environment into the default resolver', () {
    // No baseUrl on configure: a configured baseUrl would kick off the
    // unrelated cold-start entitlement-sync network path. apiKey + environment
    // are the observable threading; baseUrl rides the same ctor call (it is
    // wrapped privately into the hosted-fetch client).
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
    _installNoopRpcClient();

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
    _installNoopRpcClient();

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

  test('debugEntitlementClient aliases debugRestageRpcClient', () {
    final client = RestageRpcClient(
      baseUrl: 'https://api.example.com',
      apiKey: 'rs_pk_test',
    );

    // ignore: deprecated_member_use_from_same_package
    Restage.debugEntitlementClient = client;

    expect(Restage.debugRestageRpcClient, same(client));
    // ignore: deprecated_member_use_from_same_package
    expect(Restage.debugEntitlementClient, same(client));
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

  test('identify / track / reset are no-ops with debug warning', () {
    Restage.configure(apiKey: 'rs_pk_test');
    Restage.identify('user_42', attributes: {'tier': 'gold'});
    Restage.track('app_open');
    Restage.reset();
    // No assertion — just verifies they don't throw.
  });

  test(
      'configure with baseUrl and analytics enabled installs the internal '
      'assignment-key provider', () async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://api.example.com',
    );
    _installNoopRpcClient();

    expect(await SurfaceAssignmentKeyProvider.resolve(), isNotNull);
  });

  test(
      'analyticsEnabled false disables assignment keys even with hosted '
      'delivery configured', () async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://api.example.com',
      analyticsEnabled: false,
    );
    _installNoopRpcClient();

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
    _installNoopRpcClient();
    expect(await SurfaceAssignmentKeyProvider.resolve(), isNotNull);

    Restage.debugReset();

    expect(await SurfaceAssignmentKeyProvider.resolve(), isNull);
  });

  test('reconfiguring from hosted to bundled-only clears assignment keys',
      () async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://api.example.com',
    );
    _installNoopRpcClient();
    expect(await SurfaceAssignmentKeyProvider.resolve(), isNotNull);

    Restage.configure(apiKey: 'rs_pk_test');

    expect(await SurfaceAssignmentKeyProvider.resolve(), isNull);
  });
}

final class _FacadeUpdateChannel implements SurfaceUpdateChannel {
  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) => const Stream.empty();
}

void _installNoopRpcClient() {
  Restage.debugRestageRpcClient = RestageRpcClient(
    baseUrl: 'https://api.example.com',
    apiKey: 'rs_pk_test',
    httpClient: MockClient(
      (_) async => http.Response(
        jsonEncode(<String, Object?>{'entitlements': <Object?>[]}),
        200,
      ),
    ),
  );
}
