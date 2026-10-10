import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _carrier =
    'mrv1.ZWRnZS5jaGVja291dC1yb290.AAECAwQFBgcICQoLDA0ODxAREhMUFRYX';

class _StaticResolver implements VariantResolver {
  _StaticResolver(this.bytes);

  final Uint8List bytes;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(bytes: bytes, surfaceVersion: 'test', paywallId: id);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
  });

  testWidgets('a paywall never delivers the measure-only tap to the host',
      (tester) async {
    final received = <RestageEvent>[];
    final bytes = Uint8List.fromList(
      encodeLibraryBlob(
        parseLibraryFile('''
          import restage.core;
          widget Paywall { picked: false } = GestureDetector(
            onTap: [
              set state.picked = true,
              event "$kMeasurementPublicationTapEventNameV1" {
                $kMeasurementPublicationRouteArgumentKeyV1: "$_carrier"
              },
            ],
            child: Text(text: switch state.picked {
              true: "Picked",
              false: "Pick",
            }),
          );
        '''),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'plans',
          resolver: _StaticResolver(bytes),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    received.clear();

    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();

    expect(find.text('Picked'), findsOneWidget);
    expect(received.whereType<PaywallCustomEvent>(), isEmpty);
  });
}
