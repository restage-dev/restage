import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/widgets/pulse_badge.dart';
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
      'the codegen-generated pulse_paywall blob references the '
      'AnimationController-driven PulseBadge and the runtime resolves + renders '
      'it — a categorical (never-inlinable) 4b, end to end via public codegen',
      (tester) async {
    // The committed rfwtxt is the canonical public-codegen output; encode it
    // exactly as the runtime decodes a delivered blob.
    final bytes = Uint8List.fromList(
      encodeLibraryBlob(
        parseLibraryFile(
          File('assets/paywalls/pulse_paywall.rfwtxt').readAsStringSync(),
        ),
      ),
    );
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final failures = <PaywallLoadFailed>[];
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: Scaffold(
        body: RestagePaywall(
          id: 'pulse_paywall',
          resolver: _StaticResolver(bytes),
          onEvent: (e) {
            if (e is PaywallLoadFailed) failures.add(e);
          },
        ),
      ),
    ));
    // Pump bounded frames (not pumpAndSettle) — enough to resolve the blob and
    // run the one-shot 400ms entrance to completion.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // No error surfaced while resolving + building the imperative widget.
    expect(tester.takeException(), isNull);
    expect(
        failures.map((f) => '${f.errorCode}: ${f.message}').toList(), isEmpty);
    // The real PulseBadge mounts (resolved via the registered factory), and it
    // built a ScaleTransition driven by its AnimationController — proving the
    // widget was REFERENCED, not inlined, and the reference resolves at runtime
    // to the real imperative Flutter widget.
    expect(find.byType(PulseBadge), findsOneWidget);
    expect(find.text('Streak: 12'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PulseBadge),
        matching: find.byType(ScaleTransition),
      ),
      findsOneWidget,
    );
  });
}
