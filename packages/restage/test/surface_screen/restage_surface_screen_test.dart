import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/analytics/analytics_identity.dart';
import 'package:restage/src/analytics/root_analytics_context.dart';
import 'package:restage_shared/restage_shared.dart';

import 'surface_screen_test_support.dart';

void main() {
  setUp(resetSurfaceScreenTestState);

  testWidgets(
      'renders a screen-category publication on the paywall category and dispatches only its typed event',
      (tester) async {
    final fixture = stringScreenFixture(
      surface: Surface.paywall,
      text: 'Paywall-category screen',
    );
    final events = <String>[];

    await tester.pumpWidget(
      _host(
        fixture: fixture,
        resolver: FixedScreenResolver(fixture.bundled()),
        onEvent: events.add,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Paywall-category screen'), findsOneWidget);
    await tester.tap(find.text('Paywall-category screen'));
    await tester.pumpAndSettle();

    expect(events, <String>['tap']);
    expect(find.textContaining('fallback:'), findsNothing);
  });

  test('refuses a reference whose event decoder disagrees with its schema', () {
    final fixture = stringScreenFixture();
    final differentSchema = SurfaceScreenEventSchema(
      events: const <SurfaceScreenEvent>[],
    );

    // Provenance and the typed decoder are generated separately, so their
    // agreement is the one cross-check a reference can still get wrong. Every
    // other way for a reference to disagree with its contract is now
    // unconstructible: identity and capabilities come from the provenance.
    expect(
      () => SurfaceScreenRef<String>.generated(
        provenance: fixture.provenance,
        eventContract: SurfaceScreenEventContract<String>.generated(
          hash: SurfaceScreenEventContractHash.hash(differentSchema),
          decodeValidated: (_, __) => 'unexpected',
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  testWidgets('rejects a custom resolver result with a different identity',
      (tester) async {
    final fixture = stringScreenFixture();
    final mismatched = ResolvedSurfaceScreen.bundled(
      surface: fixture.ref.surface,
      slug: fixture.ref.slug,
      contractVersion: fixture.ref.contractVersion + 1,
      sourceKind: fixture.ref.sourceKind,
      payloadKind: fixture.ref.payloadKind,
      capabilities: fixture.capabilities,
      contractFingerprint: fixture.ref.contractFingerprint,
      eventContractHash: fixture.ref.eventContract.hash,
      blob: fixture.blob,
      contentHash: fixture.contentHash,
    );
    final resolver = FixedScreenResolver(mismatched);

    await tester.pumpWidget(_host(fixture: fixture, resolver: resolver));
    await tester.pumpAndSettle();

    expect(resolver.calls, 1);
    expect(find.text('fallback:identityMismatch'), findsOneWidget);
  });

  testWidgets('rejects an unknown RFW event without calling the typed callback',
      (tester) async {
    final schema = SurfaceScreenEventSchema(
      events: <SurfaceScreenEvent>[
        SurfaceScreenEvent(
          id: 'tap',
          arguments: const SurfaceScreenEventNoArguments(),
        ),
      ],
    );
    final fixture = stringScreenFixture(
      emittedEvent: 'other',
      schema: schema,
      text: 'Unknown event',
    );
    final events = <String>[];

    await tester.pumpWidget(
      _host(
        fixture: fixture,
        resolver: FixedScreenResolver(fixture.bundled()),
        onEvent: events.add,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unknown event'));
    await tester.pumpAndSettle();

    expect(events, isEmpty);
    expect(find.text('fallback:eventRejected'), findsOneWidget);
  });

  testWidgets('rejects malformed RFW arguments before conversion',
      (tester) async {
    final schema = SurfaceScreenEventSchema(
      events: <SurfaceScreenEvent>[
        SurfaceScreenEvent(
          id: 'tap',
          arguments: const SurfaceScreenEventValueArguments(
            SurfaceScreenEventScalarShapeV1(
              SurfaceScreenEventScalarKind.string,
            ),
          ),
        ),
      ],
    );
    final fixture = stringScreenFixture(
      schema: schema,
      text: 'Malformed event',
      decoder: (name, arguments) => '${arguments['value']}',
    );
    final events = <String>[];

    await tester.pumpWidget(
      _host(
        fixture: fixture,
        resolver: FixedScreenResolver(fixture.bundled()),
        onEvent: events.add,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Malformed event'));
    await tester.pumpAndSettle();

    expect(events, isEmpty);
    expect(find.text('fallback:eventRejected'), findsOneWidget);
  });

  testWidgets('rejects absent and throwing typed event consumers',
      (tester) async {
    final noCallback = stringScreenFixture(text: 'No callback');
    await tester.pumpWidget(
      _host(
        fixture: noCallback,
        resolver: FixedScreenResolver(noCallback.bundled()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('No callback'));
    await tester.pumpAndSettle();
    expect(find.text('fallback:eventRejected'), findsOneWidget);

    final decoderThrows = stringScreenFixture(
      slug: 'throwing_decoder',
      text: 'Throwing decoder',
      decoder: (_, __) => throw StateError('decoder rejected'),
    );
    await tester.pumpWidget(
      _host(
        key: const ValueKey<String>('throwing-decoder'),
        fixture: decoderThrows,
        resolver: FixedScreenResolver(decoderThrows.bundled()),
        onEvent: (_) {},
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Throwing decoder'));
    await tester.pumpAndSettle();

    expect(find.text('fallback:eventRejected'), findsOneWidget);
  });

  testWidgets('rejects every event for an event-free Never reference',
      (tester) async {
    final fixture = neverScreenFixture(text: 'Never event');

    await tester.pumpWidget(
      _host(
        fixture: fixture,
        resolver: FixedScreenResolver(fixture.bundled()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never event'));
    await tester.pumpAndSettle();

    expect(find.text('fallback:eventRejected'), findsOneWidget);
  });

  testWidgets('uses explicit hide behavior when resolution is unavailable',
      (tester) async {
    final fixture = stringScreenFixture(text: 'Unavailable content');
    final errors = <SurfaceScreenUnavailableError>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: <Widget>[
            const Text('Host remains visible'),
            RestageScreen<String>(
              screen: fixture.ref,
              resolver: FailingScreenResolver(
                const SurfaceScreenUnavailableError(
                  reason: SurfaceScreenUnavailableReason.missing,
                  message: 'Unavailable for test.',
                ),
              ),
              unavailable: const SurfaceScreenUnavailablePolicy.hide(),
              onUnavailable: errors.add,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Host remains visible'), findsOneWidget);
    expect(find.text('Unavailable content'), findsNothing);
    expect(errors.single.reason, SurfaceScreenUnavailableReason.missing);
  });

  testWidgets('routes a render failure through the unavailable policy',
      (tester) async {
    const library = WidgetLibrary.custom('example.throwing');
    Restage.registerWidgetLibrary(
      library,
      widgets: <RestageWidgetFactory>[
        RestageWidgetFactory(
          name: 'Throwing',
          builder: (_, __) => const _ThrowingWidget(),
        ),
      ],
    );
    final fixture = stringScreenFixture(
      text: 'unused',
      blob: rfwSourceBlob('''
import example.throwing;

widget OnboardingScreen = Throwing();
'''),
    );

    await tester.pumpWidget(
      _host(
        fixture: fixture,
        resolver: FixedScreenResolver(fixture.bundled()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('fallback:renderFailure'), findsOneWidget);
  });

  testWidgets('stages root attribution on first paint using delivery revision',
      (tester) async {
    final fixture = stringScreenFixture(text: 'Hosted attribution');
    final contexts = <RootAnalyticsEventContext>[];
    var nextId = 0;
    RootAnalyticsRuntime.install(
      identity: AnalyticsIdentity(newId: () => 'id-${nextId++}'),
      onSurfacePresented: contexts.add,
    );

    await tester.pumpWidget(
      _host(
        fixture: fixture,
        resolver: FixedScreenResolver(
          fixture.hosted(
            publishedRevision: 9,
            assignment: SurfaceExperimentAssignment(
              experimentId: 'experiment',
              variantId: 'variant',
              experimentEpoch: 2,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(contexts, hasLength(1));
    final context = contexts.single;
    expect(context.surface, fixture.ref.surface.wireName);
    expect(context.surfaceId, fixture.ref.slug);
    expect(context.surfaceVersion, '9');
    expect(context.sourceKind, SurfaceSourceKind.screen);
    expect(context.payloadKind, SurfacePayloadKind.blob);
    expect(context.experimentId, 'experiment');
    expect(context.variantId, 'variant');
    expect(context.experimentEpoch, 2);
  });

  testWidgets('stages the generated contract version for bundled attribution',
      (tester) async {
    final fixture = stringScreenFixture(contractVersion: 3);
    final contexts = <RootAnalyticsEventContext>[];
    RootAnalyticsRuntime.install(
      identity: AnalyticsIdentity(newId: () => 'id'),
      onSurfacePresented: contexts.add,
    );

    await tester.pumpWidget(
      _host(
        fixture: fixture,
        resolver: FixedScreenResolver(fixture.bundled()),
      ),
    );
    await tester.pumpAndSettle();

    expect(contexts, hasLength(1));
    expect(contexts.single.surfaceVersion, '3');
  });
}

Widget _host<E>({
  Key? key,
  required ScreenFixture<E> fixture,
  required SurfaceScreenResolver resolver,
  ValueChanged<E>? onEvent,
}) =>
    MaterialApp(
      home: Scaffold(
        body: RestageScreen<E>(
          key: key,
          screen: fixture.ref,
          resolver: resolver,
          onEvent: onEvent,
          unavailable: SurfaceScreenUnavailablePolicy.fallback(
            builder: (_, error) => Text('fallback:${error.reason.name}'),
          ),
        ),
      ),
    );

final class _ThrowingWidget extends StatelessWidget {
  const _ThrowingWidget();

  @override
  Widget build(BuildContext context) => throw StateError('render failed');
}
