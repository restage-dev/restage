import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/onboarding/apex_drop_demo.dart';
import 'package:restage_example/onboarding/flows/apex_drop.dart';

/// Tall canvas so the full-bleed message renders without a false RenderFlex
/// overflow under the wide Ahem test font.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A flow resolver that always fails to resolve, so the flow reaches either its
/// compiled original or the unavailable path without touching the host screen.
class _FailingFlowResolver implements FlowResolver {
  const _FailingFlowResolver();
  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) async =>
      throw FlowUnavailableError(
        flowId: flow.id,
        flowVersion: flow.version,
        reason: 'missing_flow_json',
        message: 'No flow artifact for test',
      );
}

/// The authored reference with its compiled original removed. Derived from the
/// generated one so the two cannot drift apart in anything but the fallback.
final _withoutCompiledOriginal = SurfaceFlowRef<ApexDropResult>(
  id: apexDropFlowRef.id,
  version: apexDropFlowRef.version,
  minClient: apexDropFlowRef.minClient,
  surface: apexDropFlowRef.surface,
  deliveryMode: apexDropFlowRef.deliveryMode,
  decodeResult: apexDropFlowRef.decodeResult,
  vocabulary: apexDropFlowRef.vocabulary,
  subFlows: apexDropFlowRef.subFlows,
);

/// The message host's unavailable wiring: hide the surface, pop the route.
/// It mirrors [ApexDropDemo] so the routing under test is the shipped one.
class _MessageHost extends StatelessWidget {
  const _MessageHost(this.flow);

  final SurfaceFlowRef<ApexDropResult> flow;

  @override
  Widget build(BuildContext context) => RestageFlowGraph<ApexDropResult>(
        flow: flow,
        onFlowUnavailable: (error) => Navigator.of(context).maybePop(),
        loadingBuilder: (context) => const ColoredBox(color: Color(0xFF0A0A0A)),
        unavailable: const FlowUnavailablePolicy.hide(),
      );
}

/// Drives the single-state in-app message: it renders, its CTA acts (completes
/// the flow → host opens the shop), and its × dismisses (a host-handled custom
/// event → the message closes).
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const supportChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory support;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('apex-drop-test-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      supportChannel,
      (call) async {
        if (call.method != 'getApplicationSupportDirectory') {
          throw MissingPluginException('Unexpected method: ${call.method}');
        }
        return support.path;
      },
    );
    await Restage.debugResetAndWait();
    Restage.configure(
      apiKey: 'rs_pk_test',
      resolver: const AssetVariantResolver(),
    );
  });

  tearDown(() async {
    try {
      await Restage.debugResetAndWait();
    } finally {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        supportChannel,
        null,
      );
      await support.delete(recursive: true);
    }
  });

  // Pushes [message] over a trivial home so a dismiss has somewhere to pop to.
  Future<void> openHost(WidgetTester tester, Widget message) async {
    _useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => message),
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

  Future<void> openMessage(WidgetTester tester) =>
      openHost(tester, const ApexDropDemo());

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

  testWidgets('a delivery failure renders the compiled original',
      (tester) async {
    await tester.runAsync(() async {
      Restage.configure(
        apiKey: 'rs_pk_test',
        resolver: const AssetVariantResolver(),
        flowResolver: const _FailingFlowResolver(),
      );
    });

    await openMessage(tester);

    // The reference carries its authored screens, so a failed resolve renders
    // them rather than going blank: the message is on stage and nothing popped.
    expect(find.text('Velocity Run'), findsOneWidget);
    expect(find.text('Shop the drop'), findsOneWidget);
    expect(find.text('open'), findsNothing);
  });

  testWidgets('without a compiled original an unavailable flow pops the route',
      (tester) async {
    await tester.runAsync(() async {
      Restage.configure(
        apiKey: 'rs_pk_test',
        resolver: const AssetVariantResolver(),
        flowResolver: const _FailingFlowResolver(),
      );
    });

    await openHost(tester, _MessageHost(_withoutCompiledOriginal));

    // Nothing to fall back to, so the unavailable branch pops back to the home:
    // the message never renders and the prior screen's 'open' is on stage.
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
