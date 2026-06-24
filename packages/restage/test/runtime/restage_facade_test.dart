import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// Direct path import — the registry is internal; the test reaches in to
// verify the public facade routes registrations into it.
// ignore: implementation_imports
import 'package:restage/src/runtime/library_runtime_registry.dart';
// Direct path import — the RPC client is internal, but the test-only facade
// seam exposes it for compatibility.
// ignore: implementation_imports
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
// `rfw` exposes a `WidgetLibrary` that collides with the catalog identifier
// re-exported from `restage`. Hide the rfw symbol.
import 'package:rfw/rfw.dart' hide WidgetLibrary;

void main() {
  setUp(() => Restage.debugReset());

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
}
