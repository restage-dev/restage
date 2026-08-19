import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/widgets/streak_badge.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

import 'restage_render_expectations.dart';

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
      ResolvedVariant(bytes: bytes, paywallId: id);
}

Future<List<PaywallLoadFailed>> _mountCustomBadgePaywall(
  WidgetTester tester,
) async {
  // The committed rfwtxt is the canonical codegen output; encode it exactly
  // as the runtime decodes a delivered blob.
  final bytes = Uint8List.fromList(
    encodeLibraryBlob(
      parseLibraryFile(
        readDeliveryText('assets/paywalls/custom_badge.rfwtxt'),
      ),
    ),
  );
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final failures = <PaywallLoadFailed>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: Scaffold(
        body: RestagePaywall(
          id: 'custom_badge',
          resolver: _StaticResolver(bytes),
          onEvent: (event) {
            if (event is PaywallLoadFailed) {
              failures.add(event);
            }
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return failures;
}

void main() {
  setUp(() {
    Restage.debugReset();
    registerRestageCustomerWidgets();
  });

  testWidgets(
    'check() reinstates the flutter_test handler and leaves it installed when '
    'an expectation fails',
    (tester) async {
      final expectations = RestageRenderExpectations()..capture();
      final testHandler = FlutterError.onError;
      await _mountCustomBadgePaywall(tester);

      expect(FlutterError.onError, isNot(same(testHandler)));

      late final FlutterExceptionHandler? handlerDuringCheck;
      expectations.check(() {
        handlerDuringCheck = FlutterError.onError;
      });
      expect(handlerDuringCheck, same(testHandler));
      expect(FlutterError.onError, isNot(same(testHandler)));

      Object? caught;
      try {
        expectations.check(() {
          expect(1, 2);
        });
      } catch (error) {
        caught = error;
      }

      expect(caught, isA<TestFailure>());
      expect(FlutterError.onError, same(testHandler));
    },
  );

  testWidgets(
    'a correct expectation still passes while a paywall is mounted',
    (tester) async {
      final expectations = RestageRenderExpectations()..capture();
      final failures = await _mountCustomBadgePaywall(tester);
      expectations.check(() {
        expect(failures, isEmpty);
        expect(find.byType(StreakBadge), findsNWidgets(2));
      });
    },
  );

  testWidgets(
    'a failed finder expectation produces a readable diff',
    (tester) async {
      final expectations = RestageRenderExpectations()..capture();
      await _mountCustomBadgePaywall(tester);

      Object? caught;
      try {
        expectations.check(() {
          expect(find.byType(StreakBadge), findsNWidgets(99));
        });
      } catch (error) {
        caught = error;
      }

      expect(caught, isA<TestFailure>());
      final message = caught.toString();
      // This test pins the message content; Test 1 pins the mechanism.
      expect(message, contains('Expected:'));
      expect(message, isNot(contains('_pendingExceptionDetails')));
    },
  );
}
