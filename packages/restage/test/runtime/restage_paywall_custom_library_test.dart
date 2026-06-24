import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// `rfw` exposes a `WidgetLibrary` that collides with the catalog
// identifier re-exported from `restage`. Hide rfw's symbol.
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
  setUp(Restage.debugReset);

  testWidgets(
    'RestagePaywall renders widgets from a customer-registered library',
    (tester) async {
      Restage.registerWidgetLibrary(
        const WidgetLibrary.custom('acme.design_system'),
        widgets: <RestageWidgetFactory>[
          RestageWidgetFactory(
            name: 'AcmeMarker',
            builder: (context, source) => Text(
              source.v<String>(<Object>['label']) ?? '<missing>',
              textDirection: TextDirection.ltr,
            ),
          ),
        ],
      );

      const source = '''
        import acme.design_system;
        widget Paywall = AcmeMarker(label: "from-customer-widget");
      ''';
      final bytes =
          Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RestagePaywall(id: 'acme', resolver: _StaticResolver(bytes)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('from-customer-widget'), findsOneWidget);
    },
  );
}
