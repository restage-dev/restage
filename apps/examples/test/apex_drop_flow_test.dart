import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/onboarding/apex_drop_demo.dart';

/// Tall canvas so the full-bleed message renders without a false RenderFlex
/// overflow under the wide Ahem test font.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A flow resolver that always fails to resolve, forcing the message flow into
/// the unavailable state without touching the host screen.
class _FailingFlowResolver implements FlowResolver {
  const _FailingFlowResolver();
  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async =>
      throw FlowUnavailableError(
        flowId: flow.id,
        flowVersion: flow.version,
        reason: 'missing_flow_json',
        message: 'No flow artifact for test',
      );
}

/// Drives the single-state in-app message: it renders, its CTA acts (completes
/// the flow → host opens the shop), and its × dismisses (a host-handled custom
/// event → the message closes).
void main() {
  setUp(() {
    Restage.debugReset();
    Restage.configure(
      apiKey: 'rs_pk_test',
      resolver: const AssetVariantResolver(),
    );
  });

  // Pushes the message over a trivial home so a dismiss has somewhere to pop to.
  Future<void> openMessage(WidgetTester tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ApexDropDemo(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the drop message card', (tester) async {
    await openMessage(tester);
    expect(find.text('Velocity Run'), findsOneWidget);
    expect(find.text('Shop the drop'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('the CTA acts — completes the flow and opens the shop',
      (tester) async {
    await openMessage(tester);
    await tester.tap(find.text('Shop the drop'));
    await tester.pumpAndSettle();
    expect(find.text('Velocity Run'), findsNothing);
    expect(find.text('Browsing the drop'), findsOneWidget);
  });

  testWidgets('the × dismisses — the message closes', (tester) async {
    await openMessage(tester);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Velocity Run'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('an unavailable flow pops the message route', (tester) async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      resolver: const AssetVariantResolver(),
      flowResolver: const _FailingFlowResolver(),
    );

    await openMessage(tester);

    // The unavailable branch pops back to the home: the message content never
    // renders and the prior screen's 'open' affordance is on stage again.
    expect(find.text('Velocity Run'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('ignores a custom event from a different flow', (tester) async {
    await openMessage(tester);
    expect(find.text('Velocity Run'), findsOneWidget);
    // A dismiss fired by some *other* flow must not close this message — the
    // host filters on both flowId and eventName.
    Restage.debugFire(
      FlowCustomEvent(
        flowId: 'a_different_flow',
        flowVersion: 1,
        eventName: 'dismiss',
        fields: const {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Velocity Run'), findsOneWidget);
  });
}
