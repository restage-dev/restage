import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/paywalls/pulse_paywall.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

import '_support/bundled_artifacts.dart';

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
    Restage.debugReset();
    registerRestageWidgets();
  });

  testWidgets(
      'the delivered pulse_paywall renders the split PulseBadge as the app '
      'does, its controller-driven scale from the app', (tester) async {
    // The committed rfwtxt is the canonical public-codegen output; encode it
    // exactly as the runtime decodes a delivered blob.
    final bytes = Uint8List.fromList(
      encodeLibraryBlob(
        parseLibraryFile(
          readDeliveryText('assets/paywalls/pulse_paywall.rfwtxt'),
        ),
      ),
    );
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The app's own paywall, then the delivered design: the same texts and
    // the same controller-driven scale, the badge now split around it.
    Future<(List<String?>, int)> run(Widget body) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: Scaffold(body: body),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      return (
        [
          for (final element in find.byType(Text).evaluate())
            (element.widget as Text).data ??
                (element.widget as Text).textSpan?.toPlainText(),
        ],
        find.byType(ScaleTransition).evaluate().length,
      );
    }

    final app = await run(const PulsePaywall());
    final failures = <PaywallLoadFailed>[];
    final delivered = await run(RestagePaywall(
      id: 'pulse_paywall',
      resolver: _StaticResolver(bytes),
      onEvent: (e) {
        if (e is PaywallLoadFailed) failures.add(e);
      },
    ));
    expect(
        failures.map((f) => '${f.errorCode}: ${f.message}').toList(), isEmpty);
    expect(find.text('Streak: 12'), findsOneWidget);
    expect(delivered.$1, app.$1);
    expect(delivered.$2, app.$2);
  });
}
