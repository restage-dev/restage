import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/analytics/analytics_identity.dart';
import 'package:restage/src/analytics/root_analytics_context.dart';
import 'package:restage/src/surface_screen/surface_screen_manifest.dart';
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
    installManifestBundle(fixture.bundle);

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

  testWidgets('resolves the generated manifest before a custom resolver',
      (tester) async {
    final requested = stringScreenFixture(slug: 'requested');
    final different = stringScreenFixture(slug: 'different');
    final resolver = FixedScreenResolver(requested.bundled());
    installManifestBundle(different.bundle);

    await tester.pumpWidget(
      _host(fixture: requested, resolver: resolver),
    );
    await tester.pumpAndSettle();

    expect(resolver.calls, 0);
    expect(find.text('fallback:missing'), findsOneWidget);
  });

  test('revalidates each generated contract on an exact-identity cache hit',
      () async {
    final fixture = stringScreenFixture();
    installManifestBundle(fixture.bundle);
    await SurfaceScreenManifestRegistry.resolve(fixture.ref);
    final differentSchema = SurfaceScreenEventSchemaV1(
      events: const <SurfaceScreenEventV1>[],
    );
    final mismatched = SurfaceScreenRef<String>.generated(
      slug: fixture.ref.slug,
      contractVersion: fixture.ref.contractVersion,
      capabilities: fixture.capabilities,
      surface: fixture.ref.surface,
      contractFingerprint: fixture.ref.contractFingerprint,
      eventContract: SurfaceScreenEventContract<String>.generated(
        hash: SurfaceScreenEventContractHashV1.hash(differentSchema),
        decodeValidated: (_, __) => 'unexpected',
      ),
    );

    await expectLater(
      SurfaceScreenManifestRegistry.resolve(mismatched),
      throwsA(
        isA<SurfaceScreenUnavailableError>().having(
          (error) => error.reason,
          'reason',
          SurfaceScreenUnavailableReason.contractMismatch,
        ),
      ),
    );
  });

  testWidgets('rejects a paywall-source manifest before resolver content',
      (tester) async {
    final fixture = stringScreenFixture(surface: Surface.paywall);
    final resolver = FixedScreenResolver(fixture.bundled());
    installManifestBundle(
      paywallSourceManifestBundle(reference: fixture.ref, blob: fixture.blob),
    );

    await tester.pumpWidget(
      _host(fixture: fixture, resolver: resolver),
    );
    await tester.pumpAndSettle();

    expect(resolver.calls, 0);
    expect(find.text('fallback:contractMismatch'), findsOneWidget);
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
    installManifestBundle(fixture.bundle);

    await tester.pumpWidget(_host(fixture: fixture, resolver: resolver));
    await tester.pumpAndSettle();

    expect(resolver.calls, 1);
    expect(find.text('fallback:identityMismatch'), findsOneWidget);
  });

  testWidgets('rejects an unknown RFW event without calling the typed callback',
      (tester) async {
    final schema = SurfaceScreenEventSchemaV1(
      events: <SurfaceScreenEventV1>[
        SurfaceScreenEventV1(
          id: 'tap',
          arguments: const SurfaceScreenEventNoArgumentsV1(),
        ),
      ],
    );
    final fixture = stringScreenFixture(
      emittedEvent: 'other',
      schema: schema,
      text: 'Unknown event',
    );
    final events = <String>[];
    installManifestBundle(fixture.bundle);

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
    final schema = SurfaceScreenEventSchemaV1(
      events: <SurfaceScreenEventV1>[
        SurfaceScreenEventV1(
          id: 'tap',
          arguments: const SurfaceScreenEventValueArgumentsV1(
            SurfaceScreenEventScalarShapeV1(
              SurfaceScreenEventScalarKindV1.string,
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
    installManifestBundle(fixture.bundle);

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
    installManifestBundle(noCallback.bundle);
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
      text: 'Throwing decoder',
      decoder: (_, __) => throw StateError('decoder rejected'),
    );
    installManifestBundle(decoderThrows.bundle);
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
    installManifestBundle(fixture.bundle);

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
    installManifestBundle(fixture.bundle);
    final errors = <SurfaceScreenUnavailableError>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: <Widget>[
            const Text('Host remains visible'),
            RestageSurfaceScreen<String>(
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
    installManifestBundle(fixture.bundle);

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
    installManifestBundle(fixture.bundle);

    await tester.pumpWidget(
      _host(
        fixture: fixture,
        resolver: FixedScreenResolver(
          fixture.hosted(
            publishedRevision: 9,
            assignment: SurfaceExperimentAssignmentV1(
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
    installManifestBundle(fixture.bundle);

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
        body: RestageSurfaceScreen<E>(
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
