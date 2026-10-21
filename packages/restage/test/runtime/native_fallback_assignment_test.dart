import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';

import '../flow/flow_test_support.dart';
import '../support/canonical_assignment_fixture.dart';
import '../surface_screen/surface_screen_test_support.dart';

const _assignment = SurfaceAssignment(
  experimentId: 'experiment.original',
  experimentRevisionId: 'revision.original',
  experimentEpochId: 'epoch.original',
  variantId: 'arm.original',
);

void main() {
  setUp(Restage.debugReset);
  tearDown(Restage.debugReset);

  for (final surface in [Surface.onboarding, Surface.message, Surface.survey]) {
    testWidgets(
        'offstage $surface fallback retires certainty until hosted paint',
        (tester) async {
      final base = resolvedFlow();
      final assigned = ResolvedFlow(
        document: base.document,
        screenBlobs: base.screenBlobs,
        cacheHit: false,
        assignment: _assignment,
      );
      final ref = SurfaceFlowRef<FirstRunResult>(
        id: 'first_run',
        version: 1,
        minClient: 3,
        surface: surface,
        decodeResult: FirstRunResult.decode,
      );
      Widget hosted() => RestageFlowGraph(
            flow: ref,
            resolver: StaticFlowResolver(assigned),
            unavailable: const FlowUnavailablePolicy.hide(),
          );
      final events = <RestageEvent>[];
      final subscription = Restage.events.listen(events.add);
      addTearDown(subscription.cancel);
      await tester.pumpWidget(MaterialApp(home: hosted()));
      await tester.pumpAndSettle();
      expect(Restage.assignmentFor(ref.id, surfaceType: surface), _assignment);
      await tester.pumpWidget(const SizedBox());
      final started = events.whereType<FlowStarted>().length;

      await tester.pumpWidget(MaterialApp(
        home: Offstage(
          offstage: true,
          child: Column(children: [
            RestageFlowGraph(
              flow: ref,
              resolver: const _UnavailableFlow(),
              unavailable: FlowUnavailablePolicy.fallback(
                  builder: (_, __) => const Expanded(child: Text('Fallback'))),
            ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Fallback', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(events.whereType<FlowStarted>().length, started);
      expect(Restage.assignmentFor(ref.id, surfaceType: surface), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(Restage.assignmentFor(ref.id, surfaceType: surface), isNull);
      await tester.pumpWidget(MaterialApp(home: hosted()));
      await tester.pumpAndSettle();
      expect(Restage.assignmentFor(ref.id, surfaceType: surface), _assignment);
    });
  }

  testWidgets('same screen State recovers assignment only after hosted paint',
      (tester) async {
    final fixture = stringScreenFixture();
    final assignment = canonicalAssignmentFixture();
    final assigned = attachMeasurementPublicationBindingReference(
      fixture.hosted(),
      null,
      canonicalExperimentAssignment: assignment,
    );
    SurfaceScreenResolver resolver = FailingScreenResolver(
        const SurfaceScreenUnavailableError(
            reason: SurfaceScreenUnavailableReason.missing,
            message: 'Unavailable'));
    var offstage = true;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return Offstage(
          offstage: offstage,
          child: Column(children: [
            RestageScreen(
              screen: fixture.ref,
              resolver: resolver,
              unavailable: SurfaceScreenUnavailablePolicy.fallback(
                  builder: (_, __) => const Expanded(child: Text('Fallback'))),
            ),
          ]),
        );
      }),
    ));
    await tester.pumpAndSettle();
    final screen = find.byType(RestageScreen<String>, skipOffstage: false);
    final state = tester.state(screen);
    expect(find.text('Fallback', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
        Restage.assignmentFor(fixture.ref.slug, surfaceType: Surface.general),
        isNull);
    update(() => resolver = FixedScreenResolver(assigned));
    await tester.pumpAndSettle();
    expect(tester.state(screen), same(state));
    expect(
        Restage.assignmentFor(fixture.ref.slug, surfaceType: Surface.general),
        isNull);
    update(() => offstage = false);
    await tester.pumpAndSettle();
    expect(tester.state(screen), same(state));
    expect(tester.takeException(), isNull);
    expect(
        Restage.assignmentFor(fixture.ref.slug, surfaceType: Surface.general),
        projectSurfaceAssignment(assignment));
  });

  testWidgets('offstage screen fallback retires certainty until hosted paint',
      (tester) async {
    final fixture = stringScreenFixture();
    final assignment = canonicalAssignmentFixture();
    final assigned = attachMeasurementPublicationBindingReference(
      fixture.hosted(),
      null,
      canonicalExperimentAssignment: assignment,
    );
    Widget hosted() => RestageScreen(
          screen: fixture.ref,
          resolver: FixedScreenResolver(assigned),
          unavailable: const SurfaceScreenUnavailablePolicy.hide(),
        );
    await tester.pumpWidget(MaterialApp(home: hosted()));
    await tester.pumpAndSettle();
    final expected = projectSurfaceAssignment(assignment);
    expect(
        Restage.assignmentFor(fixture.ref.slug, surfaceType: Surface.general),
        expected);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
      home: Offstage(
        offstage: true,
        child: Column(children: [
          RestageScreen(
            screen: fixture.ref,
            resolver: FailingScreenResolver(const SurfaceScreenUnavailableError(
                reason: SurfaceScreenUnavailableReason.missing,
                message: 'Unavailable')),
            unavailable: SurfaceScreenUnavailablePolicy.fallback(
                builder: (_, __) => const Expanded(child: Text('Fallback'))),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Fallback', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
        Restage.assignmentFor(fixture.ref.slug, surfaceType: Surface.general),
        isNull);
    await tester.pumpWidget(const SizedBox());
    expect(
        Restage.assignmentFor(fixture.ref.slug, surfaceType: Surface.general),
        isNull);
    await tester.pumpWidget(MaterialApp(home: hosted()));
    await tester.pumpAndSettle();
    expect(
        Restage.assignmentFor(fixture.ref.slug, surfaceType: Surface.general),
        expected);
  });
}

final class _UnavailableFlow implements FlowResolver {
  const _UnavailableFlow();

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async =>
      throw StateError('Unavailable');
}
