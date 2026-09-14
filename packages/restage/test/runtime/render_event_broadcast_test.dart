import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/restage_runtime_test_support.dart';

/// The host-facing event stream carries the authored arguments a rendered
/// event declares, including values read from host render data.
void main() {
  installRestageRuntimeTestSupport();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.configure(apiKey: 'rs_pk_test');
  });

  testWidgets('a rendered custom event reaches the host intact',
      (tester) async {
    final local = <PaywallCustomEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywall(
          id: 'pricing',
          resolver: _BlobResolver(_paywallBlob()),
          context: const <String, Object?>{'secret': 'local'},
          onEvent: (event) {
            if (event is PaywallCustomEvent) local.add(event);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select paywall plan'));
    await tester.pump();
    await tester.tap(find.text('Select without host data'));
    await tester.pump();

    const expected = <Map<String, Object?>>[
      {'selection': 'local', 'control': 'retained'},
      {'control': 'retained'},
    ];
    expect(local.map((event) => event.args), expected);
  });
}

final class _BlobResolver implements VariantResolver {
  _BlobResolver(this.bytes);

  final Uint8List bytes;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(bytes: bytes, surfaceVersion: 'test', paywallId: id);
}

Uint8List _paywallBlob() {
  const source = '''
import restage.core;

widget Paywall = Column(children: [
  GestureDetector(
    onTap: event "selected_plan" {
      selection: data.context.secret,
      control: "retained"
    },
    child: Text(text: "Select paywall plan")
  ),
  GestureDetector(
    onTap: event "control_only" { control: "retained" },
    child: Text(text: "Select without host data")
  )
]);
''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}
