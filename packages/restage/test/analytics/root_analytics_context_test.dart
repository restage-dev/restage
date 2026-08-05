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

  test('stage is invisible until activation and activation emits exactly once',
      () async {
    final presented = <RootAnalyticsEventContext>[];
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
      onSurfacePresented: presented.add,
    );
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: 'survey',
      surfaceId: 'survey-root',
    );

    presentation.stage(
      surfaceVersion: '7',
      experimentId: 'exp-survey',
      variantId: 'variant-a',
      experimentEpoch: 4,
    );

    expect(_bindingFrom(presentation).context, isNull);
    expect(presented, isEmpty);

    presentation
      ..activate()
      ..activate();

    final binding = _bindingFrom(presentation);
    expect(binding.surface, 'survey');
    expect(binding.surfaceId, 'survey-root');
    expect(binding.context, presented.single);
    expect(binding.context!.surfaceVersion, '7');
    expect(binding.context!.surfaceSessionId, isNotEmpty);
    expect(binding.context!.experimentId, 'exp-survey');
    expect(binding.context!.variantId, 'variant-a');
    expect(binding.context!.experimentEpoch, 4);
  });

  test('a partial experiment triple is normalized to all-null at staging',
      () async {
    final presented = <RootAnalyticsEventContext>[];
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
      onSurfacePresented: presented.add,
    );
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: 'survey',
      surfaceId: 'survey-root',
    );

    presentation.stage(
      surfaceVersion: '7',
      experimentId: 'exp-partial',
      variantId: 'variant-a',
    );
    presentation.activate();

    expect(presented, hasLength(1));
    expect(
      (
        presented.single.experimentId,
        presented.single.variantId,
        presented.single.experimentEpoch,
      ),
      (null, null, null),
    );
  });

  test('overlapping presentations retain owner-specific active context',
      () async {
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
      onSurfacePresented: (_) {},
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
      onSurfacePresented: (_) {},
    );
    final first = RootAnalyticsRuntime.createPresentation(
      surface: 'paywall',
      surfaceId: 'upgrade',
    )..stage(
        surfaceVersion: '1',
        experimentId: 'exp-a',
        variantId: 'variant-a',
        experimentEpoch: 1,
      );
    RootAnalyticsDeferredContext? firstSnapshot;
    first.captureDeferredContextOnActivation(
      (context) => firstSnapshot = context,
    );

    first.activate();
    final replacement = RootAnalyticsRuntime.createPresentation(
      surface: 'paywall',
      surfaceId: 'upgrade',
    )..stage(
        surfaceVersion: '2',
        experimentId: 'exp-b',
        variantId: 'variant-b',
        experimentEpoch: 2,
      );
    replacement.activate();
    first.dispose();

    final binding = _bindingFrom(firstSnapshot!);
    expect(binding.context!.surfaceVersion, '1');
    expect(binding.context!.experimentId, 'exp-a');
    expect(binding.context!.variantId, 'variant-a');
    expect(binding.context!.experimentEpoch, 1);
    expect(
      binding.context!.surfaceSessionId,
      isNot(_bindingFrom(replacement).context!.surfaceSessionId),
    );
  });

  test('overlapping paint winner activates once and loser activates zero',
      () async {
    final presented = <RootAnalyticsEventContext>[];
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
      onSurfacePresented: presented.add,
    );
    final retainedWinner = RootAnalyticsRuntime.createPresentation(
      surface: 'message',
      surfaceId: 'retained',
    )..stage(surfaceVersion: '1');
    final rejectedLoser = RootAnalyticsRuntime.createPresentation(
      surface: 'message',
      surfaceId: 'candidate',
    )..stage(surfaceVersion: '2');

    rejectedLoser
      ..abandon()
      ..activate();
    retainedWinner
      ..activate()
      ..activate();

    expect(presented, hasLength(1));
    expect(presented.single.surfaceId, 'retained');
    expect(presented.single.surfaceVersion, '1');
    expect(_bindingFrom(rejectedLoser).context, isNull);
    expect(_bindingFrom(retainedWinner).context, presented.single);
  });

  test('staged build/layout/paint failures activate zero canonical events',
      () async {
    final presented = <RootAnalyticsEventContext>[];
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
      onSurfacePresented: presented.add,
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

    expect(presented, isEmpty);
  });

  test('reset before activation retires staged canonical presentation',
      () async {
    final presented = <RootAnalyticsEventContext>[];
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
      onSurfacePresented: presented.add,
    );
    final stale = RootAnalyticsRuntime.createPresentation(
      surface: 'onboarding',
      surfaceId: 'first-run',
    )..stage(
        surfaceVersion: '8',
        experimentId: 'exp-old',
        variantId: 'variant-old',
        experimentEpoch: 3,
      );

    final reset = identity.reset();
    RootAnalyticsRuntime.retireAll();
    stale.activate();
    await reset;

    expect(presented, isEmpty);
    expect(_bindingFrom(stale).context, isNull);
  });

  test('reset retires active context while preserving actual surface identity',
      () async {
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
      onSurfacePresented: (_) {},
    );
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: 'onboarding',
      surfaceId: 'first-run',
    )..stage(
        surfaceVersion: '9',
        experimentId: 'exp-onboarding',
        variantId: 'variant-b',
        experimentEpoch: 6,
      );
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
      onSurfacePresented: (_) {},
    );
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: 'paywall',
      surfaceId: 'upgrade',
    )..stage(
        surfaceVersion: '12',
        experimentId: 'exp-paywall',
        variantId: 'variant-c',
        experimentEpoch: 2,
      );
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
      'same-authority install updates the emitter without retiring active or '
      'pending presentations', () async {
    final firstEmitter = <RootAnalyticsEventContext>[];
    final secondEmitter = <RootAnalyticsEventContext>[];
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
      onSurfacePresented: firstEmitter.add,
    );
    final active = RootAnalyticsRuntime.createPresentation(
      surface: 'message',
      surfaceId: 'active',
    )..stage(surfaceVersion: '1');
    active.activate();
    final pending = RootAnalyticsRuntime.createPresentation(
      surface: 'message',
      surfaceId: 'pending',
    )..stage(surfaceVersion: '2');

    RootAnalyticsRuntime.install(
      identity: identity,
      onSurfacePresented: secondEmitter.add,
    );
    pending.activate();

    expect(_bindingFrom(active).context, firstEmitter.single);
    expect(pending.isInvalidatedByIdentityReset, isFalse);
    expect(secondEmitter, hasLength(1));
    expect(secondEmitter.single.surfaceId, 'pending');
  });

  test(
      'authority retirement permanently invalidates pending and deferred '
      'contexts across reinstall', () async {
    final identity = _identity();
    await identity.anonymousId();
    RootAnalyticsRuntime.install(
      identity: identity,
      onSurfacePresented: (_) {},
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
      onSurfacePresented: (_) {},
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
