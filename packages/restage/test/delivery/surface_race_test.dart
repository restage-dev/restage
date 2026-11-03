import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/delivery/raced_surface_resolver.dart';
import 'package:restage/src/delivery/render_deadline.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;
import 'package:restage/src/delivery/surface_race.dart';

void main() {
  const deadline = Duration(milliseconds: 300);
  final started = <RenderDeadline>[];
  RenderDeadline start(Duration duration) {
    final mountDeadline = RenderDeadline.start(duration);
    started.add(mountDeadline);
    return mountDeadline;
  }

  // Mounts cancel their deadline on dispose; these races do the same.
  void raceTest(String description, WidgetTesterCallback body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        for (final d in started) {
          d.cancel();
        }
        started.clear();
      }
    });
  }

  raceTest(
      'an answer that arrives inside the window and is accepted after it '
      'wins over the saved content', (tester) async {
    final fresh = Completer<_Content?>();
    final saved = _Content('saved');
    markHeldDecision(saved);
    var arrived = false;
    RaceOutcome<_Content>? outcome;
    final mount = RenderDeadline.start(const Duration(milliseconds: 1000),
        window: const Duration(milliseconds: 150));
    started.add(mount);
    unawaited(raceSurface<_Content>(
      deadline: mount,
      fresh: () => fresh.future,
      bestLocal: () async => saved,
      answerArrived: () => arrived,
    ).then((o) => outcome = o));

    await tester.pump(const Duration(milliseconds: 100));
    arrived = true;
    await tester.pump(const Duration(milliseconds: 100));
    // Past the window, but the answer is on the device: still waiting.
    expect(outcome, isNull);
    fresh.complete(_Content('fresh'));
    await tester.pump();
    expect(outcome, isA<RaceFresh<_Content>>());
    expect(outcome!.value!.name, 'fresh');
  });

  raceTest('without an arrived answer the window ends on the saved content',
      (tester) async {
    final fresh = Completer<_Content?>();
    final saved = _Content('saved');
    markHeldDecision(saved);
    RaceOutcome<_Content>? outcome;
    final mount = RenderDeadline.start(const Duration(milliseconds: 1000),
        window: const Duration(milliseconds: 150));
    started.add(mount);
    unawaited(raceSurface<_Content>(
      deadline: mount,
      fresh: () => fresh.future,
      bestLocal: () async => saved,
      answerArrived: () => false,
    ).then((o) => outcome = o));

    await tester.pump(const Duration(milliseconds: 150));
    expect(outcome, isA<RaceLocal<_Content>>());
    expect(outcome!.value!.name, 'saved');
  });

  raceTest('fresh accepted before the deadline wins', (tester) async {
    final fresh = Completer<String?>();
    final local = Completer<String?>();
    RaceOutcome<String>? outcome;
    unawaited(raceSurface<String>(
      deadline: start(deadline),
      fresh: () => fresh.future,
      bestLocal: () => local.future,
    ).then((o) => outcome = o));

    local.complete('disk');
    await tester.pump(const Duration(milliseconds: 100));
    expect(outcome, isNull);
    fresh.complete('fresh');
    await tester.pump();
    expect(outcome, isA<RaceFresh<String>>());
    expect(outcome!.value, 'fresh');
  });

  raceTest('at the deadline the ready local candidate renders', (tester) async {
    final fresh = Completer<String?>();
    RaceOutcome<String>? outcome;
    String? late;
    unawaited(raceSurface<String>(
      deadline: start(deadline),
      fresh: () => fresh.future,
      bestLocal: () async => 'disk',
      onLateFresh: (value) => late = value,
    ).then((o) => outcome = o));

    await tester.pump(const Duration(milliseconds: 299));
    expect(outcome, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(outcome, isA<RaceLocal<String>>());
    expect(outcome!.value, 'disk');

    fresh.complete('fresh');
    await tester.pump();
    expect(late, 'fresh');
  });

  raceTest('a local candidate still loading at the deadline is nothing',
      (tester) async {
    final local = Completer<String?>();
    RaceOutcome<String>? outcome;
    unawaited(raceSurface<String>(
      deadline: start(deadline),
      fresh: () => Completer<String?>().future,
      bestLocal: () => local.future,
    ).then((o) => outcome = o));

    await tester.pump(deadline);
    expect(outcome, isA<RaceNone<String>>());
    expect(outcome!.value, isNull);
    expect((outcome! as RaceNone<String>).freshPending, isTrue);
    local.complete('bundled');
    await tester.pump();
    expect(outcome, isA<RaceNone<String>>());
  });

  raceTest('a failed fresh settles on local without waiting', (tester) async {
    RaceOutcome<String>? outcome;
    unawaited(raceSurface<String>(
      deadline: start(deadline),
      fresh: () async => throw StateError('offline'),
      bestLocal: () async => 'bundled',
    ).then((o) => outcome = o));

    await tester.pump(const Duration(milliseconds: 1));
    expect(outcome, isA<RaceLocal<String>>());
    expect(outcome!.value, 'bundled');
    expect(outcome!.freshError, isA<StateError>());
  });

  raceTest('a null fresh with nothing local settles as nothing',
      (tester) async {
    RaceOutcome<String>? outcome;
    unawaited(raceSurface<String>(
      deadline: start(deadline),
      fresh: () async => null,
      bestLocal: () async => null,
    ).then((o) => outcome = o));

    await tester.pump(const Duration(milliseconds: 1));
    expect(outcome, isA<RaceNone<String>>());
    expect((outcome! as RaceNone<String>).freshPending, isFalse);
  });

  raceTest('the deadline is absolute across races on one mount',
      (tester) async {
    final mountDeadline = start(deadline);
    await tester.pump(const Duration(milliseconds: 250));
    RaceOutcome<String>? outcome;
    unawaited(raceSurface<String>(
      deadline: mountDeadline,
      fresh: () => Completer<String?>().future,
      bestLocal: () async => 'disk',
    ).then((o) => outcome = o));

    await tester.pump(const Duration(milliseconds: 50));
    expect(outcome, isA<RaceLocal<String>>());
  });

  raceTest('a race started after the deadline still takes a ready local copy',
      (tester) async {
    final mountDeadline = start(deadline);
    await tester.pump(deadline);
    expect(mountDeadline.hasPassed, isTrue);
    RaceOutcome<String>? outcome;
    unawaited(raceSurface<String>(
      deadline: mountDeadline,
      fresh: () => Completer<String?>().future,
      bestLocal: () async => 'disk',
    ).then((o) => outcome = o));
    await tester.pump(const Duration(milliseconds: 1));
    expect(outcome, isA<RaceLocal<String>>());
  });

  raceTest('a zero deadline takes the compiled floor when nothing is ready',
      (tester) async {
    RaceOutcome<String>? outcome;
    unawaited(raceSurface<String>(
      deadline: start(Duration.zero),
      fresh: () => Completer<String?>().future,
      bestLocal: () => Completer<String?>().future,
    ).then((o) => outcome = o));
    await tester.pump(const Duration(milliseconds: 1));
    expect(outcome, isA<RaceNone<String>>());
    expect((outcome! as RaceNone<String>).freshPending, isTrue);
  });

  raceTest('a late fresh failure is not reported as late content',
      (tester) async {
    final fresh = Completer<String?>();
    var lateCalls = 0;
    unawaited(raceSurface<String>(
      deadline: start(deadline),
      fresh: () => fresh.future,
      bestLocal: () async => 'disk',
      onLateFresh: (_) => lateCalls++,
    ));
    await tester.pump(deadline);
    fresh.completeError(StateError('late'));
    await tester.pump();
    expect(lateCalls, 0);
  });

  test('a reporting failure asserts in debug builds', () {
    const key = SurfaceStoreKey(
      scope: 'scope',
      surfaceType: 'paywall',
      slug: 'pro',
      contractVersion: 0,
    );
    expect(
      () => reportRaceWinner<String>(_BrokenReporter(), key, null),
      throwsA(isA<AssertionError>()),
    );
  });
}

final class _BrokenReporter
    with RacedSurfaceReporting<String>
    implements RacedSurfaceResolver<String> {
  @override
  final SurfaceArtifactStore store = MemorySurfaceArtifactStore();

  @override
  Surface reportSurfaceFor(SurfaceStoreKey key) =>
      throw StateError('no surface');

  @override
  Future<String?> bestLocal(SurfaceStoreKey key) async => null;

  @override
  Future<String?> fresh(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    Future<void>? keyDeadline,
  }) async =>
      null;
}

final class _Content {
  _Content(this.name);
  final String name;
}
