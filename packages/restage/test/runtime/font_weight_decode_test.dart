// Proves the decoder side of the build-time `FontWeight.<member>` lowering: a
// blob carrying the bare enum-name string a transpiled custom widget emits
// (`fontWeight: "w600"`) renders to the real `FontWeight.w600` through rfw's
// `enumValue<FontWeight>(FontWeight.values, …)` decoder. The build-time side
// (the classifier recognising `FontWeight.w600` and the translator emitting
// `"w600"`) is covered in restage_codegen; this is the end-to-end render half.
//
// Test shape note: values are read while the paywall is mounted, then the tree
// is unmounted before assertions (the same convention as the theme test).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

Uint8List _blob(String source) =>
    Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));

void main() {
  setUp(Restage.debugReset);

  testWidgets(
      'a blob fontWeight enum-name string decodes to the real FontWeight '
      '(the render half of the FontWeight.<member> lowering)', (tester) async {
    final resolver = _StaticResolver(_blob('''
      import restage.core;
      widget Paywall = Text(text: "Bold", fontWeight: "w600");
    '''));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RestagePaywall(id: 'p', resolver: resolver)),
      ),
    );
    await tester.pumpAndSettle();

    final weight = tester.widget<Text>(find.text('Bold')).style?.fontWeight;

    await tester.pumpWidget(const SizedBox());
    expect(weight, FontWeight.w600);
  });
}
