import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/main_hosted_paywall_demo.dart'
    show FakeSurfaceServer;
import 'package:restage_example/main_rollback_paywall_flow_demo.dart';

/// De-risks the dev-only FLOW-PAYWALL rollback smoke entrypoint. A hosted flow
/// paywall (a paywall lowered to a navigation flow) served through the SDK
/// paywall flow active arm, gated against the app's own bundled contract:
///  - a re-pointed version with an unchanged contract renders the ACTIVE version
///    (the re-point reached the client — distinguishable by its "· rolled back"
///    entry copy);
///  - a re-pointed version with a raised capability floor fails closed to the
///    BUNDLED version (the render gate still applies to a rolled-back target).
void main() {
  setUp(() {
    Restage.debugReset();
    Restage.configure(apiKey: 'pk_test');
  });

  RestageVariantResolver resolverFor({required bool compatible}) {
    return RestageVariantResolver(
      apiKey: 'rs_pk_demo',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://fake-surfaces.local',
      httpClient: FakeSurfaceServer(
        buildRolledBackFlowPaywallEnvelope(compatible: compatible),
      ),
      assetFallback: AssetVariantResolver(bundle: buildBundledFlowPaywall()),
    );
  }

  Future<void> pumpPaywall(
      WidgetTester tester, RestageVariantResolver r) async {
    await tester.pumpWidget(
      MaterialApp(
          home: Scaffold(body: RestagePaywall(id: 'pro_upgrade', resolver: r))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a compatible re-pointed flow paywall renders the ACTIVE rolled-back version',
    (tester) async {
      await pumpPaywall(tester, resolverFor(compatible: true));
      // The active arm served the re-pointed version, gate-accepted against the
      // bundled contract — its distinct entry copy proves it, not the fallback.
      expect(find.text('See plans · rolled back'), findsOneWidget);
    },
  );

  testWidgets(
    'a contract-changed re-pointed flow paywall (raised floor) fails closed to '
    'the BUNDLED version',
    (tester) async {
      await pumpPaywall(tester, resolverFor(compatible: false));
      // The incompatible re-pointed version was rejected by the render gate /
      // retained floor backstop; the app's own bundled paywall renders.
      expect(find.text('See plans'), findsOneWidget);
      expect(find.text('See plans · rolled back'), findsNothing);
    },
  );
}
