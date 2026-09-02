import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/analytics/analytics_event_mapper.dart';
import 'package:restage/src/analytics/root_analytics_context.dart';
import 'package:restage/src/events/restage_event.dart';
import 'package:restage_shared/legacy_analytics.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  const appContext = AnalyticsAppContext(
    platform: 'ios',
    locale: 'en_US',
    sdkVersion: '1.0.0',
  );
  final now = DateTime.utc(2026, 6, 13, 12);

  AnalyticsEvent map(
    RestageEvent event, {
    RootAnalyticsEventBinding? rootAttribution,
    String? surfaceSessionId,
    String? userId,
    bool omitAuthoredArguments = false,
  }) {
    return mapRestageEventToEnvelope(
      event,
      eventId: 'evt-1',
      anonymousId: 'anon-1',
      sessionId: 'sess-1',
      surfaceSessionId: surfaceSessionId,
      userId: userId,
      appContext: appContext,
      now: now,
      rootAttribution: rootAttribution,
      omitAuthoredArguments: omitAuthoredArguments,
    );
  }

  test('a paywall event maps to surface=paywall', () {
    final firedAt = DateTime.utc(2026, 6, 13, 11, 59);
    final envelope = map(
      PaywallViewed(
        paywallId: 'pw-1',
        firedAt: firedAt,
      ),
      surfaceSessionId: 'surf-9',
      userId: 'user-7',
    );
    expect(envelope.name, 'paywall_viewed');
    expect(envelope.surface, AnalyticsSurface.paywall);
    expect(envelope.surfaceId, 'pw-1');
    expect(envelope.surfaceSessionId, 'surf-9');
    expect(envelope.anonymousId, 'anon-1');
    expect(envelope.sessionId, 'sess-1');
    expect(envelope.userId, 'user-7');
    expect(envelope.appContext, appContext);
    expect(envelope.eventId, 'evt-1');
    expect(envelope.occurredAt, firedAt);
  });

  test('firedAt absent falls back to now', () {
    final envelope = map(const PaywallViewed(paywallId: 'pw-1'));
    expect(envelope.occurredAt, now);
  });

  test('a flow event maps to surface=onboarding with flow→surface mapping', () {
    final envelope = map(
      const FlowStarted(
        flowId: 'flow-7',
        flowVersion: 3,
        flowSessionId: 'flow-sess-1',
      ),
    );
    expect(envelope.surface, AnalyticsSurface.onboarding);
    expect(envelope.surfaceId, 'flow-7');
    expect(envelope.surfaceVersion, '3');
    expect(envelope.surfaceSessionId, 'flow-sess-1');
  });

  test('an authoritative general flow stays attributed to general', () {
    const root = RootAnalyticsEventContext(
      identityGeneration: 1,
      surface: AnalyticsSurface.general,
      surfaceId: 'account-recovery',
      surfaceVersion: '4',
      surfaceSessionId: 'general-session-1',
      sourceKind: SurfaceSourceKind.flowGraph,
      payloadKind: SurfacePayloadKind.flow,
    );

    final envelope = map(
      const FlowCompleted(
        flowId: 'account-recovery',
        flowVersion: 2,
        flowSessionId: 'flow-session-1',
      ),
      rootAttribution: RootAnalyticsEventBinding.active(root),
    );

    expect(envelope.surface, AnalyticsSurface.general);
    expect(envelope.surface, isNot(AnalyticsSurface.onboarding));
    expect(envelope.surfaceId, 'account-recovery');
    expect(envelope.surfaceVersion, '4');
  });

  test('a standalone general blob cannot emit flow completion', () {
    const root = RootAnalyticsEventContext(
      identityGeneration: 1,
      surface: AnalyticsSurface.general,
      surfaceId: 'maintenance-notice',
      surfaceVersion: '3',
      surfaceSessionId: 'general-session-1',
      sourceKind: SurfaceSourceKind.screen,
      payloadKind: SurfacePayloadKind.blob,
    );

    expect(
      () => map(
        const FlowCompleted(
          flowId: 'maintenance-notice',
          flowVersion: 1,
          flowSessionId: 'should-not-count',
        ),
        rootAttribution: RootAnalyticsEventBinding.active(root),
      ),
      throwsFormatException,
    );
  });

  test('PaywallViewed.publishedVersion promotes to envelope surfaceVersion',
      () {
    final envelope = map(
      const PaywallViewed(
        paywallId: 'pw-1',
        publishedVersion: 9,
      ),
    );
    expect(envelope.surfaceVersion, '9');
    // Promoted → typed field only, never duplicated into properties.
    expect(envelope.properties.containsKey('publishedVersion'), isFalse);
  });

  test('a custom event cannot smuggle render context into properties', () {
    final envelope = map(
      const PaywallCustomEvent(
        paywallId: 'pw-1',
        eventName: 'tapped_plan',
        args: {
          'plan': 'pro',
          'data': {'context': 'render-secret'},
          'context': 'leak',
        },
      ),
    );
    expect(envelope.properties.containsKey('data'), isFalse);
    expect(envelope.properties.containsKey('context'), isFalse);
    expect(envelope.properties['plan'], 'pro');
    expect(envelope.properties['eventName'], 'tapped_plan');
  });

  test('a custom event drops retired property tuples at any casing', () {
    const preserved = <String, Object?>{
      'plan': 'pro',
      'experimentIdentifier': 'keep',
      'variantIdentity': 'keep',
      'experimentEpochId': 'keep',
    };

    for (final args in <Map<String, Object?>>[
      <String, Object?>{
        ...preserved,
        'experimentId': 'exp-1',
        'variantId': 'variant-a',
        'experimentEpoch': 7,
      },
      <String, Object?>{
        ...preserved,
        'ExPeRiMeNtId': 'exp-2',
        'vArIaNtId': 'variant-b',
        'eXpErImEnTePoCh': 8,
      },
    ]) {
      final envelope = map(
        PaywallCustomEvent(
          paywallId: 'pw-1',
          eventName: 'tapped_plan',
          args: args,
        ),
      );

      expect(envelope.properties, <String, Object?>{
        'eventName': 'tapped_plan',
        ...preserved,
      });
    }
  });

  test('custom event payloads drop nested retired property keys', () {
    const paywallArgs = <String, Object?>{
      'payload': <String, Object?>{
        'ExPeRiMeNtId': 'exp-1',
        'label': 'visible',
        'data': <String, Object?>{'context': 'local'},
        'context': 'nested',
        'data.context.locale': 'en_US',
        'items': <Object?>[
          <String, Object?>{
            'vArIaNtId': 'variant-a',
            'label': 'first',
          },
          <String, Object?>{
            'nested': <String, Object?>{
              'eXpErImEnTePoCh': 7,
              'experimentEpochId': 'keep',
            },
          },
          'ordinary',
        ],
      },
    };
    const cleanedPayload = <String, Object?>{
      'label': 'visible',
      'data': <String, Object?>{'context': 'local'},
      'context': 'nested',
      'data.context.locale': 'en_US',
      'items': <Object?>[
        <String, Object?>{'label': 'first'},
        <String, Object?>{
          'nested': <String, Object?>{'experimentEpochId': 'keep'},
        },
        'ordinary',
      ],
    };
    const flowFields = <String, Object?>{
      'ExPeRiMeNtId': 'exp-2',
      'data': <String, Object?>{'context': 'local-flow'},
      'context': 'nested-flow',
      'context.locale': 'en_US',
      'items': <Object?>[
        <String, Object?>{
          'vArIaNtId': 'variant-b',
          'nested': <String, Object?>{
            'eXpErImEnTePoCh': 8,
            'experimentIdentifier': 'keep',
          },
        },
      ],
    };
    const cleanedFlowFields = <String, Object?>{
      'data': <String, Object?>{'context': 'local-flow'},
      'context': 'nested-flow',
      'context.locale': 'en_US',
      'items': <Object?>[
        <String, Object?>{
          'nested': <String, Object?>{
            'experimentIdentifier': 'keep',
          },
        },
      ],
    };

    final paywall = map(
      const PaywallCustomEvent(
        paywallId: 'pw-1',
        eventName: 'tapped_plan',
        args: paywallArgs,
      ),
    );
    final flow = map(
      const FlowCustomEvent(
        flowId: 'flow-1',
        flowVersion: 1,
        eventName: 'continue',
        fields: flowFields,
      ),
    );

    expect(paywall.properties, <String, Object?>{
      'eventName': 'tapped_plan',
      'payload': cleanedPayload,
    });
    expect(flow.properties, <String, Object?>{
      'eventName': 'continue',
      'fields': cleanedFlowFields,
    });
  });

  test('marked paywall custom events omit every authored argument', () {
    final envelope = map(
      const PaywallCustomEvent(
        paywallId: 'upgrade',
        eventName: 'selected_plan',
        args: <String, Object?>{
          'selection': 'private-plan',
          'eventName': 'forged-name',
          'paywallId': 'forged-root',
        },
      ),
      omitAuthoredArguments: true,
    );

    expect(envelope.name, 'paywall_custom_event');
    expect(envelope.surfaceId, 'upgrade');
    expect(envelope.properties, <String, Object?>{
      'eventName': 'selected_plan',
    });
  });

  test('marked flow custom events omit the complete authored fields map', () {
    final envelope = map(
      const FlowCustomEvent(
        flowId: 'first_run',
        flowVersion: 3,
        resolvedVersion: 8,
        eventName: 'selected_plan',
        fields: <String, Object?>{'selection': 'private-plan'},
      ),
      omitAuthoredArguments: true,
    );

    expect(envelope.name, 'flow_custom_event');
    expect(envelope.surfaceId, 'first_run');
    expect(envelope.surfaceVersion, '3');
    expect(envelope.properties, <String, Object?>{
      'resolvedVersion': 8,
      'eventName': 'selected_plan',
    });
  });

  test('the privacy marker does not alter non-custom events', () {
    final ordinary = map(
      const OnboardingStepViewed(
        flowId: 'first_run',
        flowVersion: 1,
        screenId: 'welcome',
        stepIndex: 0,
      ),
    );
    final marked = map(
      const OnboardingStepViewed(
        flowId: 'first_run',
        flowVersion: 1,
        screenId: 'welcome',
        stepIndex: 0,
      ),
      omitAuthoredArguments: true,
    );

    expect(marked, ordinary);
  });

  group('onboarding events conform to the onboarding envelope', () {
    test('onboarding_step_viewed → surface=onboarding + step properties', () {
      final envelope = map(
        const OnboardingStepViewed(
          flowId: 'first_run',
          flowVersion: 2,
          flowSessionId: 'flow-sess-1',
          screenId: 'value',
          stepIndex: 1,
          stepCount: 4,
        ),
      );
      expect(envelope.name, 'onboarding_step_viewed');
      expect(envelope.surface, AnalyticsSurface.onboarding);
      expect(envelope.surfaceId, 'first_run');
      expect(envelope.surfaceVersion, '2');
      expect(envelope.surfaceSessionId, 'flow-sess-1');
      // Per-event extras land in properties; flow identity rides the envelope.
      expect(envelope.properties, {
        'screenId': 'value',
        'stepIndex': 1,
        'stepCount': 4,
      });
      expect(envelope.properties.containsKey('flowId'), isFalse);
      expect(envelope.properties.containsKey('flowVersion'), isFalse);
      expect(envelope.properties.containsKey('flowSessionId'), isFalse);
    });

    test('onboarding_skipped → surface=onboarding + skip properties', () {
      final envelope = map(
        const OnboardingSkipped(
          flowId: 'first_run',
          flowVersion: 1,
          flowSessionId: 'flow-sess-2',
          atScreenId: 'notify',
          stepIndex: 2,
        ),
      );
      expect(envelope.name, 'onboarding_skipped');
      expect(envelope.surface, AnalyticsSurface.onboarding);
      expect(envelope.surfaceId, 'first_run');
      expect(envelope.surfaceSessionId, 'flow-sess-2');
      expect(envelope.properties, {'atScreenId': 'notify', 'stepIndex': 2});
    });

    test(
        'onboarding_permission_response → surface=onboarding + '
        'permission/granted', () {
      final envelope = map(
        const OnboardingPermissionResponse(
          flowId: 'first_run',
          flowVersion: 1,
          flowSessionId: 'flow-sess-3',
          permission: 'requestNotifications',
          granted: false,
        ),
      );
      expect(envelope.name, 'onboarding_permission_response');
      expect(envelope.surface, AnalyticsSurface.onboarding);
      expect(envelope.surfaceId, 'first_run');
      expect(envelope.surfaceSessionId, 'flow-sess-3');
      expect(envelope.properties, {
        'permission': 'requestNotifications',
        'granted': false,
      });
    });

    test(
        'splits contract version (envelope surfaceVersion) from resolved active '
        'version (properties.resolvedVersion)', () {
      final envelope = map(
        const FlowStarted(
          flowId: 'first_run',
          flowVersion: 1,
          resolvedVersion: 9,
          flowSessionId: 'flow-sess-4',
        ),
      );
      // flowVersion is the stable client-contract version → promoted to the
      // typed envelope surfaceVersion.
      expect(envelope.surfaceVersion, '1');
      // resolvedVersion has no typed envelope home → it rides in properties,
      // distinct from the contract version.
      expect(envelope.properties['resolvedVersion'], 9);
    });
  });

  test('preserves the drop-off property contract in mapped envelopes', () {
    final step = map(
      const OnboardingStepViewed(
        flowId: 'first_run',
        flowVersion: 1,
        screenId: 'welcome',
        stepIndex: 0,
      ),
    );
    final flowCustom = map(
      const FlowCustomEvent(
        flowId: 'first_run',
        flowVersion: 1,
        eventName: 'continue',
        fields: <String, Object?>{},
      ),
    );
    final paywallCustom = map(
      const PaywallCustomEvent(
        paywallId: 'upgrade',
        eventName: 'continue',
        args: <String, Object?>{},
      ),
    );
    final skipped = map(
      const OnboardingSkipped(
        flowId: 'first_run',
        flowVersion: 1,
        atScreenId: 'welcome',
        stepIndex: 0,
      ),
    );
    final page = map(PagerPageChanged(pageIndex: 1, pageCount: 3));
    final question = map(
      SurveyQuestionResponded(questionId: 'favoriteColor', questionIndex: 0),
    );

    expect(step.properties, containsPair('screenId', 'welcome'));
    expect(step.properties, containsPair('stepIndex', 0));
    expect(flowCustom.properties, containsPair('eventName', 'continue'));
    expect(paywallCustom.properties, containsPair('eventName', 'continue'));
    expect(skipped.properties, containsPair('atScreenId', 'welcome'));
    expect(page.properties, <String, Object?>{'pageIndex': 1, 'pageCount': 3});
    expect(question.properties, <String, Object?>{
      'questionId': 'favoriteColor',
      'questionIndex': 0,
    });
  });

  group('production suppression (no zeroed session summary by default)', () {
    test('paywall_session_summary is suppressed; real events are not', () {
      expect(isProdSuppressedAnalyticsEvent('paywall_session_summary'), isTrue);
      expect(isProdSuppressedAnalyticsEvent('paywall_viewed'), isFalse);
      expect(isProdSuppressedAnalyticsEvent('purchase_succeeded'), isFalse);
      expect(isProdSuppressedAnalyticsEvent('flow_started'), isFalse);
    });
  });

  group('authoritative internal root context', () {
    test('a child flow outcome inherits the exact rendered root envelope', () {
      const root = RootAnalyticsEventContext(
        identityGeneration: 3,
        surface: 'message',
        surfaceId: 'welcome-message',
        surfaceVersion: '14',
        surfaceSessionId: 'root-session-1',
      );

      final envelope = map(
        const FlowCustomEvent(
          flowId: 'child-flow',
          flowVersion: 2,
          resolvedVersion: 6,
          eventName: 'cta_tapped',
          fields: <String, Object?>{'cta': 'continue'},
        ),
        rootAttribution: RootAnalyticsEventBinding.active(root),
      );

      expect(envelope.surface, 'message');
      expect(envelope.surfaceId, 'welcome-message');
      expect(envelope.surfaceVersion, '14');
      expect(envelope.surfaceSessionId, 'root-session-1');
      expect(envelope.properties['eventName'], 'cta_tapped');
      expect(envelope.properties['fields'], <String, Object?>{
        'cta': 'continue',
      });
    });

    test('pre-paint and retired roots cannot trust event assignment fields',
        () {
      final envelope = map(
        const PaywallViewed(
          paywallId: 'upgrade',
          publishedVersion: 4,
        ),
        surfaceSessionId: 'global-slot',
        rootAttribution: const RootAnalyticsEventBinding.anonymous(
          surface: 'paywall',
          surfaceId: 'upgrade',
        ),
      );

      expect(envelope.surface, 'paywall');
      expect(envelope.surfaceId, 'upgrade');
      expect(envelope.surfaceVersion, isNull);
      expect(envelope.surfaceSessionId, isNull);
    });
  });
}
