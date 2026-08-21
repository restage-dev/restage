import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

import 'package:restage_example/surfaces/categorized_screens.dart';
import 'package:restage_example/surfaces/general_flow.dart';
import 'package:restage_example/surfaces/message_offer_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(Restage.debugReset);

  test('generated screen references preserve authored identities', () {
    final onboarding = <SurfaceScreenRef<OnboardingWelcomeEvent>>[
      onboardingWelcomeRef,
    ];
    final message = <SurfaceScreenRef<MessageNoticeEvent>>[messageNoticeRef];
    final general = <SurfaceScreenRef<GeneralStatusEvent>>[generalStatusRef];

    expect(onboarding.single.surface, Surface.onboarding);
    expect(onboarding.single.slug, 'onboarding_welcome');
    expect(message.single.surface, Surface.message);
    expect(message.single.slug, 'message_notice');
    expect(general.single.surface, Surface.general);
    expect(general.single.slug, 'general_status');

    expect(generalStatusRef.eventContract.hash, startsWith('sha256:'));
    expect(const GeneralStatusFinishEvent(), isA<GeneralStatusEvent>());
  });

  test('general and paywall-composing flows resolve complete closures',
      () async {
    const resolver = AssetFlowResolver();

    final general = await resolver.resolve(generalJourneyRef);
    expect(generalJourneyRef.surface, Surface.general);
    expect(generalJourneyRef.sourceKind, SurfaceSourceKind.flowGraph);
    expect(generalJourneyRef.payloadKind, SurfacePayloadKind.flow);
    expect(general.document.flow, generalJourneyRef.id);
    expect(
      general.document.screenArtifacts.keys,
      contains(generalStatusRef.slug),
    );
    expect(general.screenBlobs.keys, contains(generalStatusRef.slug));

    final message = await resolver.resolve(messageOfferRef);
    expect(messageOfferRef.surface, Surface.message);
    expect(messageOfferRef.sourceKind, SurfaceSourceKind.flowGraph);
    expect(messageOfferRef.payloadKind, SurfacePayloadKind.flow);
    expect(message.document.flow, messageOfferRef.id);
    expect(
      message.document.screenArtifacts.keys,
      contains(messageNoticeRef.slug),
    );
    final embeddedPaywall = message.document.screenArtifacts.keys.singleWhere(
      (id) => id != messageNoticeRef.slug,
    );
    expect(message.screenBlobs.keys, contains(embeddedPaywall));
  });

  testWidgets('general flow mounts and completes through its generated ref',
      (tester) async {
    final completed = <GeneralJourneyResult>[];
    final unavailable = <FlowUnavailableError>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RestageFlowGraph<GeneralJourneyResult>(
            flow: generalJourneyRef,
            unavailable: FlowUnavailablePolicy.fallback(
              builder: (_, error) => Text('flow fallback:${error.reason}'),
            ),
            resolver: const AssetFlowResolver(),
            onFlowUnavailable: unavailable.add,
            onComplete: completed.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(unavailable, isEmpty);
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(completed, hasLength(1));
    expect(completed.single, isA<GeneralJourneyResult>());
  });

  testWidgets('message flow enters its embedded paywall publication',
      (tester) async {
    final unavailable = <FlowUnavailableError>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RestageFlowGraph<MessageOfferResult>(
            flow: messageOfferRef,
            unavailable: FlowUnavailablePolicy.fallback(
              builder: (_, error) => Text('flow fallback:${error.reason}'),
            ),
            resolver: const AssetFlowResolver(),
            onFlowUnavailable: unavailable.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(unavailable, isEmpty);
    expect(find.text('Open offer'), findsOneWidget);
    await tester.tap(find.text('Open offer'));
    await tester.pumpAndSettle();
    expect(find.text('Upgrade'), findsOneWidget);
  });

  testWidgets('one generic host mounts categorized generated screens',
      (tester) async {
    final onboardingEvents = <OnboardingWelcomeEvent>[];
    final unavailable = <SurfaceScreenUnavailableError>[];
    await tester.pumpWidget(
      _surfaceHost(
        screen: onboardingWelcomeRef,
        onEvent: onboardingEvents.add,
        onUnavailable: unavailable.add,
      ),
    );
    await tester.pumpAndSettle();
    expect(unavailable, isEmpty);
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(onboardingEvents, hasLength(1));
    expect(onboardingEvents.single, isA<OnboardingWelcomeContinueFlowEvent>());

    final messageEvents = <MessageNoticeEvent>[];
    await tester.pumpWidget(
      _surfaceHost(
        screen: messageNoticeRef,
        onEvent: messageEvents.add,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open offer'), findsOneWidget);
    await tester.tap(find.text('Open offer'));
    await tester.pumpAndSettle();
    expect(messageEvents, hasLength(1));
    expect(messageEvents.single, isA<MessageNoticeOpenOfferEvent>());

    final generalEvents = <GeneralStatusEvent>[];
    await tester.pumpWidget(
      _surfaceHost(
        screen: generalStatusRef,
        onEvent: generalEvents.add,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(generalEvents, hasLength(1));
    expect(generalEvents.single, isA<GeneralStatusFinishEvent>());
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

Widget _surfaceHost<E>({
  required SurfaceScreenRef<E> screen,
  required ValueChanged<E> onEvent,
  ValueChanged<SurfaceScreenUnavailableError>? onUnavailable,
}) =>
    MaterialApp(
      home: Scaffold(
        body: RestageScreen<E>(
          screen: screen,
          onEvent: onEvent,
          onUnavailable: onUnavailable,
          unavailable: SurfaceScreenUnavailablePolicy.fallback(
            builder: (_, error) => Text('fallback:${error.reason.name}'),
          ),
        ),
      ),
    );
