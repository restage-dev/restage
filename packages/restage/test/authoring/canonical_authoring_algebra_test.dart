import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

@Screen()
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(surface: Surface.message, id: 'profile')
final class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen()
final class QuestionScreen extends StatelessWidget {
  const QuestionScreen({super.key});

  static const answer = SurfaceEvent<String>('answer');
  static const skip = SurfaceEvent<void>('skip');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen()
final class GuidedScreen extends StatelessWidget {
  const GuidedScreen({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen()
final class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Paywall()
final class UpgradePaywall extends StatelessWidget {
  const UpgradePaywall({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@FlowGraph(surface: Surface.onboarding)
const welcomeFlow = FlowDefinition(
  start: WelcomeScreen,
  transitions: [
    Transition(WelcomeScreen.next, to: ProfileScreen),
    Transition.complete(ProfileScreen.finish),
  ],
);

@FlowGraph(surface: Surface.onboarding)
const embeddedPaywallFlow = FlowDefinition(
  start: WelcomeScreen,
  transitions: [
    Transition(WelcomeScreen.next, to: UpgradePaywall),
    Transition.complete(PaywallEvents.purchase, from: UpgradePaywall),
  ],
);

const answer = FlowStateRef<String>(
  'answer',
  classification: FlowStateClassification.exportable,
);
const returningUser = SeedableFlowStateRef<bool>(
  'returningUser',
  defaultValue: false,
);
const retryCount = FlowStateRef<int>('retryCount', defaultValue: 0);
final route = Decision(
  'route',
  branches: [
    Branch(when: answer.equals('guided'), to: GuidedScreen),
  ],
  otherwise: ExploreScreen,
);

@FlowGraph(surface: Surface.survey)
final setupSurvey = FlowDefinition(
  start: QuestionScreen,
  state: [answer, returningUser],
  transitions: [
    Transition(QuestionScreen.answer, capture: answer, to: route),
    Transition(
      QuestionScreen.skip,
      writes: [answer.set('skipped')],
      to: ExploreScreen,
    ),
    Transition.complete(GuidedScreen.finish),
    Transition.complete(ExploreScreen.finish),
  ],
  outbound: FlowOutboundPolicy(
    terminalResult: {'answer': answer},
    surveyAnswers: {'answer': answer},
  ),
);

const _advancedScreen = NeutralFlowScreenRef(
  id: 'advanced',
  artifactPath: 'advanced.rfw',
  version: 1,
  minClient: 1,
);

@FlowGraph(surface: Surface.onboarding)
final class AdvancedFlow extends RestageFlow {
  const AdvancedFlow();

  @override
  FlowDef buildFlow() => flow(initial: _advancedScreen, states: const []);
}

void main() {
  test('canonical authoring algebra exposes the approved public forms', () {
    const screen = Screen();
    const categorizedScreen = Screen(surface: Surface.general, id: 'notice');
    const paywall = Paywall();
    const graph = FlowGraph(surface: Surface.general);

    expect(screen.id, isNull);
    expect(screen.surface, isNull);
    expect(categorizedScreen.surface, Surface.general);
    expect(paywall.id, isNull);
    expect(graph.surface, Surface.general);
    expect(welcomeFlow.transitions.last.completionId, 'done');
    expect(welcomeFlow.transitions.last.completionResult, isEmpty);

    expect(setupSurvey.state, [answer, returningUser]);
    expect(route.branches.single.when, isA<FlowCondition>());
    expect(answer.set('saved').state, same(answer));
    expect(returningUser.fromValue(true).child, same(returningUser));
    expect(retryCount.atLeast(2), isA<FlowCondition>());
    expect(
      embeddedPaywallFlow.transitions.last.from,
      UpgradePaywall,
    );

    const action = FlowActionRef<void, bool>('requestNotifications');
    final gated = Transition(
      WelcomeScreen.next,
      action: action.continueWhen((granted) => granted),
      to: ProfileScreen,
    );
    expect(gated.action!.action, same(action));

    final completion = const Completion('completed', result: {'ok': true});
    final child = Subflow(
      'child',
      flow: welcomeFlow,
      onComplete: completion,
      input: [returningUser.fromValue(true)],
    );
    expect(child.onComplete, same(completion));
    expect(const NodeRef('later').id, 'later');

    final screenRef = SurfaceScreenRef<Never>.generated(
      slug: 'service_status',
      contractVersion: 1,
      surface: Surface.general,
      contractFingerprint:
          'sha256:0000000000000000000000000000000000000000000000000000000000000000',
      capabilities: CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const [],
      ),
      eventContract: const SurfaceScreenEventContract<Never>.none(
        hash:
            'sha256:0000000000000000000000000000000000000000000000000000000000000000',
      ),
    );
    expect(screenRef.surface, Surface.general);
    expect(screenRef.payloadKind, SurfacePayloadKind.blob);

    final flowRef = SurfaceFlowRef<void>(
      id: 'account_recovery',
      version: 1,
      minClient: 1,
      surface: Surface.general,
      decodeResult: _decodeVoid,
    );
    expect(flowRef.surface, Surface.general);
    expect(flowRef.payloadKind, SurfacePayloadKind.flow);

    // ignore: deprecated_member_use
    const legacyScreen = ScreenSource(id: 'legacy_screen');
    // ignore: deprecated_member_use
    const legacyPaywall = PaywallSource(id: 'legacy_paywall');
    // ignore: deprecated_member_use
    const legacyFlow = FlowSource(id: 'legacy_flow');
    // ignore: deprecated_member_use
    const legacyEvent = OnboardingEvent<void>('legacy_event');
    expect(legacyScreen.id, 'legacy_screen');
    expect(legacyPaywall.id, 'legacy_paywall');
    expect(legacyFlow.id, 'legacy_flow');
    expect(legacyEvent.id, 'legacy_event');
    expect(const AdvancedFlow(), isA<RestageFlow>());
  });
}

void _decodeVoid(Map<String, Object?> _) {}
