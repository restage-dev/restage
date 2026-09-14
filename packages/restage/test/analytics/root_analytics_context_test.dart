import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/analytics/analytics_identity.dart';
import 'package:restage/src/analytics/root_analytics_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RootAnalyticsRuntime.clear();
  });
  tearDown(RootAnalyticsRuntime.clear);

  test('stage rejects an empty surface version', () {
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: 'survey',
      surfaceId: 'survey-root',
    );

    expect(
      () => presentation.stage(surfaceVersion: ''),
      throwsArgumentError,
    );
  });

  test('overlapping presentations retain owner-specific active context',
      () async {
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
    );
    final retained = RootAnalyticsRuntime.createPresentation(
      surface: 'message',
      surfaceId: 'retained',
    )..stage(surfaceVersion: '1');
    retained.activate();
    final candidate = RootAnalyticsRuntime.createPresentation(
      surface: 'message',
      surfaceId: 'candidate',
    )..stage(surfaceVersion: '2');
    candidate.activate();

    final retainedBinding = _bindingFrom(retained);
    final candidateBinding = _bindingFrom(candidate);

    expect(retainedBinding.context!.surfaceId, 'retained');
    expect(retainedBinding.context!.surfaceVersion, '1');
    expect(candidateBinding.context!.surfaceId, 'candidate');
    expect(candidateBinding.context!.surfaceVersion, '2');
    expect(
      retainedBinding.context!.surfaceSessionId,
      isNot(candidateBinding.context!.surfaceSessionId),
    );
  });

  test(
      'an activation callback snapshots its exact owner before a replacement '
      'disposes it', () async {
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
    );
    final first = RootAnalyticsRuntime.createPresentation(
      surface: 'paywall',
      surfaceId: 'upgrade',
    )..stage(surfaceVersion: '1');
    RootAnalyticsDeferredContext? firstSnapshot;
    first.captureDeferredContextOnActivation(
      (context) => firstSnapshot = context,
    );

    first.activate();
    final replacement = RootAnalyticsRuntime.createPresentation(
      surface: 'paywall',
      surfaceId: 'upgrade',
    )..stage(surfaceVersion: '2');
    replacement.activate();
    first.dispose();

    final binding = _bindingFrom(firstSnapshot!);
    expect(binding.context!.surfaceVersion, '1');
    expect(
      binding.context!.surfaceSessionId,
      isNot(_bindingFrom(replacement).context!.surfaceSessionId),
    );
  });

  test('staged build/layout/paint failures activate zero canonical events',
      () async {
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
    );

    for (final failure in const <String>['build', 'layout', 'paint']) {
      final presentation = RootAnalyticsRuntime.createPresentation(
        surface: 'survey',
        surfaceId: failure,
      )..stage(surfaceVersion: '1');
      presentation
        ..abandon()
        ..activate();
      expect(_bindingFrom(presentation).context, isNull);
    }
  });

  test('reset before activation retires staged canonical presentation',
      () async {
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
    );
    final stale = RootAnalyticsRuntime.createPresentation(
      surface: 'onboarding',
      surfaceId: 'first-run',
    )..stage(surfaceVersion: '8');

    final reset = identity.reset();
    RootAnalyticsRuntime.retireAll();
    stale.activate();
    await reset;

    expect(_bindingFrom(stale).context, isNull);
  });

  test('reset retires active context while preserving actual surface identity',
      () async {
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
    );
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: 'onboarding',
      surfaceId: 'first-run',
    )..stage(surfaceVersion: '9');
    presentation.activate();

    final reset = identity.reset();
    RootAnalyticsRuntime.retireAll();
    final binding = _bindingFrom(presentation);
    await reset;

    expect(binding.surface, 'onboarding');
    expect(binding.surfaceId, 'first-run');
    expect(binding.context, isNull);
  });

  test(
      'deferred outcome survives unmount but reset before outcome strips context',
      () async {
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
    );
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: 'paywall',
      surfaceId: 'upgrade',
    )..stage(surfaceVersion: '12');
    presentation.activate();
    final deferred = presentation.captureDeferredContext();
    presentation.dispose();

    expect(_bindingFrom(deferred).context!.surfaceVersion, '12');

    final reset = identity.reset();
    RootAnalyticsRuntime.retireAll();
    final afterReset = _bindingFrom(deferred);
    await reset;

    expect(afterReset.surface, 'paywall');
    expect(afterReset.surfaceId, 'upgrade');
    expect(afterReset.context, isNull);
  });

  test(
      'authority retirement permanently invalidates pending and deferred '
      'contexts across reinstall', () async {
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
    );
    final active = RootAnalyticsRuntime.createPresentation(
      surface: 'paywall',
      surfaceId: 'active',
    )..stage(surfaceVersion: '4');
    active.activate();
    final deferred = active.captureDeferredContext();
    final pending = RootAnalyticsRuntime.createPresentation(
      surface: 'paywall',
      surfaceId: 'pending',
    )..stage(surfaceVersion: '5');

    RootAnalyticsRuntime.retireAuthority();
    RootAnalyticsRuntime.install(
      identity: identity,
    );

    expect(pending.isInvalidatedByIdentityReset, isTrue);
    expect(_bindingFrom(active).context, isNull);
    expect(_bindingFrom(deferred).context, isNull);
  });
}

AnalyticsIdentity _identity() {
  var next = 0;
  return AnalyticsIdentity(
    prefsProvider: SharedPreferences.getInstance,
    newId: () => 'id-${next++}',
  );
}

RootAnalyticsEventBinding _bindingFrom(
  RootAnalyticsContextSource source,
) {
  RootAnalyticsEventBinding? binding;
  source.runWithEventContext(() {
    binding = RootAnalyticsRuntime.currentEventBinding;
  });
  return binding!;
}
