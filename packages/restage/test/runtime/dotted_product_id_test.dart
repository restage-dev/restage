// A real store id — reverse-DNS, so full of dots — must survive the whole
// chain: authored blob text -> parse -> encode -> decode -> product data
// population -> rendered price.
//
// The id reaches the widget-text format as a QUOTED reference part, which is
// what keeps it a single part instead of one part per dotted segment. The
// literal reference text asserted here is the seam with the build-time
// lowering: the codegen side asserts it emits exactly this string
// (`paywall_price_id_quoting_test.dart` in the codegen package), and this side
// asserts the runtime resolves it. Neither package can import the other, so
// the shared string is the contract.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// Direct path import — the walk is an internal implementation detail of the
// placeholder-price population sites, not public SDK surface.
import 'package:restage/src/runtime/product_reference_walk.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The store id under test: dotted, and therefore only expressible as a
/// single reference part when quoted.
const String kDottedId = 'com.example.pro.annual';

/// A resolver that always returns the same fixed bytes for any paywall id —
/// mirrors `_StaticResolver` in the placeholder and happy-path suites.
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

  // Exactly the text the build-time lowering emits for
  // `paywallPriceFor(productId: 'com.example.pro.annual')`.
  const source = '''
    import restage.core;
    widget Paywall = Text(text: data.products."$kDottedId".localizedPrice);
  ''';

  Uint8List blob() =>
      Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));

  test('the quoted dotted id decodes as ONE reference part', () {
    final decoded = decodeLibraryBlob(blob());
    final root = decoded.widgets.single.root as ConstructorCall;
    final reference = root.arguments['text']! as DataReference;

    expect(reference.parts, <Object>['products', kDottedId, 'localizedPrice']);
  });

  test('referencedProductSlots reports the WHOLE id, not its first segment',
      () {
    // The mis-keying the placeholder walk showed before the reference form was
    // fixed: it collected `parts[1]`, which for a bare dotted id was `com` —
    // the first segment, which is what the placeholder was injected under and
    // what the debug log reported as a success.
    expect(referencedProductSlots(decodeLibraryBlob(blob())), {kDottedId});
  });

  testWidgets('a product registered under a dotted id renders its live price',
      (tester) async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      products: const [
        RestageProduct(id: kDottedId, slot: 'annual', entitlement: 'pro'),
      ],
    );
    final received = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'dotted_live_price',
          resolver: _StaticResolver(blob()),
          onEvent: received.add,
          priceQueries: const {
            kDottedId: PriceInfo(
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

    // The live lane: a real price, not the unbound placeholder, and no
    // fail-closed render error.
    expect(find.text(r'$49.99'), findsOneWidget);
    expect(find.text(r'$X.XX'), findsNothing);
    final names = received.map((e) => e.name).toSet();
    expect(names, contains('paywall_viewed'));
    expect(names, isNot(contains('paywall_load_failed')));
  });

  testWidgets(
      'with no commerce context the dotted id gets one placeholder entry',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'dotted_placeholder',
          resolver: _StaticResolver(blob()),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The lane where the mis-keying above produced the false-success log.
    expect(find.text(r'$X.XX'), findsOneWidget);
  });
}
