import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';

Uint8List _blob(String text) {
  final source = '''
    import restage.core;
    widget Paywall = Text(text: "$text");
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

class _MutableResolver implements VariantResolver {
  _MutableResolver(this.bytes, this.version);
  Uint8List bytes;
  int version;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(
          bytes: bytes, paywallId: id, paywallPublishedVersion: version);
}

void main() {
  setUp(Restage.debugReset);

  testWidgets('reloadSurfaces(surfaceId:) only reloads the named surface',
      (tester) async {
    final ra = _MutableResolver(_blob('A1'), 1);
    final rb = _MutableResolver(_blob('B1'), 1);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          RestagePaywall(id: 'a', resolver: ra),
          RestagePaywall(id: 'b', resolver: rb),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('B1'), findsOneWidget);

    ra
      ..bytes = _blob('A2')
      ..version = 2;
    rb
      ..bytes = _blob('B2')
      ..version = 2;
    await Restage.reloadSurfaces(surfaceId: 'a');
    await tester.pumpAndSettle();

    expect(find.text('A2'), findsOneWidget); // reloaded
    expect(find.text('B1'), findsOneWidget); // untouched
    expect(find.text('B2'), findsNothing);
  });
}
