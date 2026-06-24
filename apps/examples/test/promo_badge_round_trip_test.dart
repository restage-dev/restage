import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_example/user_catalog.g.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/widgets/promo_badge.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

class _StaticResolver implements VariantResolver {
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
    Restage.debugReset();
    registerRestageCustomerWidgets();
  });

  testWidgets(
    'codegen → register → paywall renders the customer-defined PromoBadge',
    (tester) async {
      const blob = '''
        import restage_example.widgets;
        widget Paywall = PromoBadge(label: "2 weeks free");
      ''';
      final bytes =
          Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(blob)));
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: Scaffold(
          body: RestagePaywall(
            id: 'promo',
            resolver: _StaticResolver(bytes),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(PromoBadge), findsOneWidget);
      expect(find.text('2 weeks free'), findsOneWidget);
    },
  );

  testWidgets(
    'paywall blob can override the optional color property',
    (tester) async {
      const blob = '''
        import restage_example.widgets;
        widget Paywall = PromoBadge(label: "VIP", color: 0xFFFF0000);
      ''';
      final bytes =
          Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(blob)));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RestagePaywall(id: 'p', resolver: _StaticResolver(bytes)),
        ),
      ));
      await tester.pumpAndSettle();
      final badge = tester.widget<PromoBadge>(find.byType(PromoBadge));
      expect(badge.color, const Color(0xFFFF0000));
    },
  );

  testWidgets(
    'paywall blob without a required label fails the load + drops the widget',
    (tester) async {
      const blob = '''
        import restage_example.widgets;
        widget Paywall = PromoBadge();
      ''';
      final bytes =
          Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(blob)));
      final loadFailures = <PaywallLoadFailed>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RestagePaywall(
            id: 'p',
            resolver: _StaticResolver(bytes),
            onEvent: (event) {
              if (event is PaywallLoadFailed) loadFailures.add(event);
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // The factory's `ArgumentError` propagates as a render error: the
      // SDK's runtime error boundary intercepts it and fires
      // `PaywallLoadFailed` instead of mounting `PromoBadge`.
      expect(find.byType(PromoBadge), findsNothing);
      expect(loadFailures, hasLength(1));
      expect(loadFailures.single.errorCode, RestageErrorCodes.renderError);
    },
  );

  test('generated catalog registers the PromoBadge widget entry', () {
    final entry =
        kUserCatalog.widgets.firstWhere((w) => w.name == 'PromoBadge');
    expect(entry.library.namespace, 'restage_example.widgets');
    expect(entry.category, WidgetCategory.action);
    final label = entry.properties.firstWhere((p) => p.name == 'label');
    expect(label.required, isTrue);
    final color = entry.properties.firstWhere((p) => p.name == 'color');
    expect(color.defaultBrandToken, 'primary');
  });
}
