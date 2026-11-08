import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('SurfaceLoadCompleted carries its source and waits', () {
    const event = SurfaceLoadCompleted(
      surfaceId: 'welcome',
      surface: Surface.onboarding,
      source: SurfaceLoadSource.original,
      elapsed: Duration(milliseconds: 1000),
      firstLaunchWaitPassed: true,
      freshWindowPassed: true,
    );
    expect(event.name, 'surface_load_completed');
    expect(event.surfaceId, 'welcome');
    expect(event.toMap(), {
      'name': 'surface_load_completed',
      'surfaceId': 'welcome',
      'surface': 'onboarding',
      'source': 'original',
      'elapsedMs': 1000,
      'firstLaunchWaitPassed': true,
      'freshWindowPassed': true,
    });
    expect(event.analyticsProperties, {
      'restage_surface_id': 'welcome',
      'restage_surface_type': 'onboarding',
      'restage_load_source': 'original',
      'restage_load_duration_ms': 1000,
      'restage_first_launch_wait_passed': 1,
      'restage_fresh_window_passed': 1,
    });
  });

  test('SurfaceLoadStarted and SurfaceLoadFailed carry no message text', () {
    const started =
        SurfaceLoadStarted(surfaceId: 'nps', surface: Surface.survey);
    expect(started.toMap(), {
      'name': 'surface_load_started',
      'surfaceId': 'nps',
      'surface': 'survey',
    });
    const failed = SurfaceLoadFailed(
      surfaceId: 'nps',
      surface: Surface.survey,
      reason: SurfaceLoadFailureReason.invalid,
      detail: 'decode_failed',
      elapsed: Duration(milliseconds: 40),
    );
    expect(failed.toMap(), {
      'name': 'surface_load_failed',
      'surfaceId': 'nps',
      'surface': 'survey',
      'reason': 'invalid',
      'detail': 'decode_failed',
      'elapsedMs': 40,
    });
    expect(failed.analyticsProperties['restage_reason'], 'invalid');
  });

  group('a placement reports the surface it declares', () {
    setUp(Restage.debugReset);
    tearDown(Restage.debugReset);

    Future<List<RestageEvent>> mount(WidgetTester tester, Widget host) async {
      final events = <RestageEvent>[];
      final subscription = Restage.events.listen(events.add);
      addTearDown(subscription.cancel);
      await tester.pumpWidget(MaterialApp(home: host));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pumpWidget(const SizedBox());
      return events;
    }

    testWidgets('a named placement is general', (tester) async {
      final events = await mount(
          tester,
          RestagePlacement(
              id: 'home_banner',
              fallbackBuilder: (_) => const Text('Original')));
      final started = events.whereType<SurfaceLoadStarted>().single;
      expect((started.surfaceId, started.surface),
          ('home_banner', Surface.general));
    });

    testWidgets('a surface placement is that surface', (tester) async {
      final events = await mount(
          tester,
          RestagePlacement.forSurface(
              surfaceType: Surface.message,
              surfaceId: 'welcome_back',
              fallbackBuilder: (_) => const Text('Original')));
      final started = events.whereType<SurfaceLoadStarted>().single;
      expect((started.surfaceId, started.surface),
          ('welcome_back', Surface.message));
      // No asset exists, so the fallback paints: the original.
      final completed = events.whereType<SurfaceLoadCompleted>().single;
      expect(completed.source, SurfaceLoadSource.original);
      expect(events.whereType<SurfaceLoadFailed>(), isEmpty);
      expect(completed.surfaceType, Surface.message);
      expect(completed.analyticsProperties['restage_surface_type'], 'message');
    });
  });
}
