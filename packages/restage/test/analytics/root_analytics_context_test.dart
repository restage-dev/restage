import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/analytics/analytics_identity.dart';
import 'package:restage/src/analytics/root_analytics_context.dart';
import 'package:restage/restage.dart';
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

  test('assignment lookup commits at activation and retains after unmount', () {
    const assignment = SurfaceAssignment(
      experimentId: 'experiment.welcome',
      experimentRevisionId: 'revision.welcome.1',
      experimentEpochId: 'epoch.welcome.1',
      variantId: 'arm.treatment',
    );
    final owner = Object();
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: 'onboarding',
      surfaceId: 'welcome',
      owner: owner,
    )..stage(surfaceVersion: '8', assignment: assignment);

    expect(
      Restage.assignmentFor('welcome', surfaceType: Surface.onboarding),
      isNull,
    );
    presentation.activate();
    expect(
      Restage.assignmentFor('welcome', surfaceType: Surface.onboarding),
      assignment,
    );
    presentation.dispose();
    expect(
      Restage.assignmentFor('welcome', surfaceType: Surface.onboarding),
      assignment,
    );
  });

  test('overlapping host owners make synchronous lookup ambiguous', () {
    const firstAssignment = SurfaceAssignment(
      experimentId: 'experiment.welcome',
      experimentRevisionId: 'revision.welcome.1',
      experimentEpochId: 'epoch.welcome.1',
      variantId: 'arm.first',
    );
    const secondAssignment = SurfaceAssignment(
      experimentId: 'experiment.welcome',
      experimentRevisionId: 'revision.welcome.1',
      experimentEpochId: 'epoch.welcome.1',
      variantId: 'arm.second',
    );
    final first = RootAnalyticsRuntime.createPresentation(
      surface: 'onboarding',
      surfaceId: 'welcome',
      owner: Object(),
    )..stage(surfaceVersion: '8', assignment: firstAssignment);
    final second = RootAnalyticsRuntime.createPresentation(
      surface: 'onboarding',
      surfaceId: 'welcome',
      owner: Object(),
    )..stage(surfaceVersion: '9', assignment: secondAssignment);
    first.activate();
    second.activate();

    expect(
      Restage.assignmentFor('welcome', surfaceType: Surface.onboarding),
      isNull,
    );
    second.dispose();
    expect(
      Restage.assignmentFor('welcome', surfaceType: Surface.onboarding),
      firstAssignment,
    );
  });

  test('one host owner replaces assignment atomically on refresh', () {
    const firstAssignment = SurfaceAssignment(
      experimentId: 'experiment.message',
      experimentRevisionId: 'revision.message.1',
      experimentEpochId: 'epoch.message.1',
      variantId: 'arm.first',
    );
    const secondAssignment = SurfaceAssignment(
      experimentId: 'experiment.message',
      experimentRevisionId: 'revision.message.1',
      experimentEpochId: 'epoch.message.1',
      variantId: 'arm.second',
    );
    final owner = Object();
    final first = RootAnalyticsRuntime.createPresentation(
      surface: 'message',
      surfaceId: 'offer',
      owner: owner,
    )..stage(surfaceVersion: '1', assignment: firstAssignment);
    first.activate();
    final second = RootAnalyticsRuntime.createPresentation(
      surface: 'message',
      surfaceId: 'offer',
      owner: owner,
    )..stage(surfaceVersion: '2', assignment: secondAssignment);
    second.activate();

    expect(
      Restage.assignmentFor('offer', surfaceType: Surface.message),
      secondAssignment,
    );
    first.dispose();
    expect(
      Restage.assignmentFor('offer', surfaceType: Surface.message),
      secondAssignment,
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
    )..stage(
        surfaceVersion: '9',
        assignment: const SurfaceAssignment(
          experimentId: 'experiment.welcome',
          experimentRevisionId: 'revision.welcome.1',
          experimentEpochId: 'epoch.welcome.1',
          variantId: 'arm.treatment',
        ),
      );
    presentation.activate();

    final reset = identity.reset();
    RootAnalyticsRuntime.retireAll();
    final binding = _bindingFrom(presentation);
    await reset;

    expect(binding.surface, 'onboarding');
    expect(binding.surfaceId, 'first-run');
    expect(binding.context, isNull);
    expect(binding.attribution.surfaceVersion, isNull);
    expect(binding.attribution.assignment, isNull);
    expect(
      Restage.assignmentFor('first-run', surfaceType: Surface.onboarding),
      isNull,
    );
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
