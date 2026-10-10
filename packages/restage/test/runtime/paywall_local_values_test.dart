import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_sections_carrier.dart';
import 'package:restage/src/runtime/local_values.dart';
import 'package:rfw/formats.dart';

class _StaticResolver implements VariantResolver {
  _StaticResolver(this.bytes, {this.sections = SurfaceSections.none});
  final Uint8List bytes;
  final SurfaceSections sections;
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      attachSurfaceSections(
        ResolvedVariant(bytes: bytes, surfaceVersion: 'test', paywallId: id),
        sections,
      );
}

Uint8List _paywallBytes() {
  const source = '''
    import restage.core;
    import restage.material;
    widget Paywall = Column(children: [
      TextField(onChanged: event "restage.local.set" { key: "code" }),
      switch data.local.code {
        "SAVE10": Text(text: "SAVE10"),
        "WELCOME": Text(text: "WELCOME"),
        default: Text(text: "no code"),
      },
    ]);
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

void main() {
  setUp(() => Restage.debugReset());

  testWidgets(
      'a value callback writes a local value the paywall reads, and the '
      'write never reaches the host', (tester) async {
    final received = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _StaticResolver(_paywallBytes()),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('no code'), findsOneWidget);
    final before = received.length;

    tester.widget<TextField>(find.byType(TextField)).onChanged!('SAVE10');
    await tester.pump();

    expect(find.text('SAVE10'), findsOneWidget);
    expect(received.skip(before), isEmpty);
    expect(received.whereType<PaywallCustomEvent>(), isEmpty);
  });

  testWidgets('a delivered seed shows before the first input', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _StaticResolver(
            _paywallBytes(),
            sections: const SurfaceSections(
              localSeeds: <String, Map<String, Object>>{
                'Paywall': <String, Object>{'code': 'WELCOME'},
              },
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('WELCOME'), findsOneWidget);
  });
}
