import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A resolver that always returns the same fixed bytes for any paywall id —
/// mirrors `_StaticResolver` in the happy-path suite.
final class _StaticResolver implements VariantResolver {
  _StaticResolver(this.bytes);
  final Uint8List bytes;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(bytes: bytes, paywallId: id);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
  });

  // The 2x2 discovery control: the SAME price-bound blob rendered under the
  // two host states. Context absent renders the shared placeholder and
  // behaves as a successful load; context present keeps
  // today's fail-closed behavior unchanged.
  const source = '''
    import restage.core;
    widget Paywall = Text(text: data.products.annual.localizedPrice);
  ''';

  testWidgets(
      'no commerce context: a price-bound blob renders the placeholder, '
      'PaywallViewed fires, no PaywallLoadFailed', (tester) async {
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
    final received = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'no_context',
          resolver: _StaticResolver(bytes),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(r'$X.XX'), findsOneWidget);
    final names = received.map((e) => e.name).toSet();
    expect(names, contains('paywall_viewed'));
    expect(names, isNot(contains('paywall_load_failed')));
  });

  testWidgets(
      'commerce context present (products registered, slot unresolved): '
      'the same blob still fails closed', (tester) async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      products: const [
        RestageProduct(id: 'annual_id', slot: 'annual', entitlement: 'pro'),
      ],
    );
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
    final received = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'context_present',
          resolver: _StaticResolver(bytes),
          onEvent: received.add,
          // priceQueries deliberately omits 'annual_id' — the product is
          // registered but its price never resolved, so populateProductData
          // (context present) skips it exactly as it does today.
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(r'$X.XX'), findsNothing);
    final names = received.map((e) => e.name).toList();
    expect(names, contains('paywall_load_failed'));
    final failed = received.whereType<PaywallLoadFailed>().single;
    expect(failed.errorCode, RestageErrorCodes.renderError);
  });

  testWidgets(
      'no commerce context becomes commerce-context-present on a '
      'priceQueries rebuild: the placeholder heals to the live price',
      (tester) async {
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
    final resolver = _StaticResolver(bytes);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'heals_on_price_queries_rebuild',
          resolver: resolver,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(r'$X.XX'), findsOneWidget);

    // Commerce context arrives: a product is registered and the widget is
    // rebuilt with a fresh (non-identical) priceQueries map — the documented
    // way a host supplies newly resolved prices after mount
    // (state_variables.dart's `populateProductData` doc example).
    Restage.configure(
      apiKey: 'rs_pk_test',
      products: const [
        RestageProduct(id: 'annual_id', slot: 'annual', entitlement: 'pro'),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'heals_on_price_queries_rebuild',
          resolver: resolver,
          priceQueries: const {
            'annual_id': PriceInfo(
              localizedPrice: r'$49.99',
              priceMicros: 49990000,
              currency: 'USD',
              title: 'Annual',
              description: '',
            ),
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(r'$49.99'), findsOneWidget);
    expect(find.text(r'$X.XX'), findsNothing);
  });

  testWidgets(
      'commerce context arriving via configure() + a mutated priceQueries '
      'map heals on the next dependency change (not a priceQueries rebuild)',
      (tester) async {
    // Isolates the didChangeDependencies healing seam from the didUpdateWidget
    // one exercised above: priceQueries keeps the SAME map identity across
    // the rebuild (mutated in place, not replaced), so didUpdateWidget's
    // `!identical` dirty-check never fires. Only an unrelated ambient
    // dependency change (the Theme swap below) can heal this surface.
    final priceQueries = <String, PriceInfo>{};
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
    final resolver = _StaticResolver(bytes);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Scaffold(
        body: RestagePaywall(
          id: 'heals_on_dependency_change',
          resolver: resolver,
          priceQueries: priceQueries,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(r'$X.XX'), findsOneWidget);

    Restage.configure(
      apiKey: 'rs_pk_test',
      products: const [
        RestageProduct(id: 'annual_id', slot: 'annual', entitlement: 'pro'),
      ],
    );
    priceQueries['annual_id'] = const PriceInfo(
      localizedPrice: r'$59.99',
      priceMicros: 59990000,
      currency: 'USD',
      title: 'Annual',
      description: 'One year',
    );

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: RestagePaywall(
          id: 'heals_on_dependency_change',
          resolver: resolver,
          priceQueries: priceQueries,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(r'$59.99'), findsOneWidget);
    expect(find.text(r'$X.XX'), findsNothing);
  });
}
