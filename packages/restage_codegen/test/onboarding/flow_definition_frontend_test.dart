import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/onboarding/flow_definition_frontend.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('flow definition frontend', () {
    test('a source extending the host widget is told which class it wanted',
        () async {
      // `RestageFlowGraph` mounts a flow; `RestageFlow` is what a flow source
      // extends, and the two sit next to each other in a completion list.
      //
      // The analyzer already rejects this (the widget is a `final class`), so
      // this test is really asking whether the build ALSO reaches the case and
      // says which of the pair was wanted. If build_runner stopped at the
      // semantic error the branch would be unreachable and the diagnostic
      // would be dead code.
      final result = await _inspect({
        'lib/onboarding/flows/mixed_up.dart': """
import 'package:restage/restage.dart';

@FlowGraph(id: 'mixed_up', surface: Surface.onboarding)
final class MixedUpFlow extends RestageFlowGraph {
  const MixedUpFlow();

  @override
  FlowDef buildFlow() => flow(initial: null, states: const []);
}
""",
      });

      expect(result.flows, isEmpty);
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.unsupportedBaseClass),
      );
      expect(
        result.issues.map((i) => i.message).join('\n'),
        allOf(
          contains('RestageFlowGraph is the host widget'),
          contains('extends RestageFlow'),
        ),
        reason: 'the message must name the class the author wanted, not just '
            'restate that the base class is unsupported',
      );
    });

    test('normalizes a legacy class flow into the shared source model',
        () async {
      final result = await _inspect({
        'lib/onboarding/flows/welcome.dart': '''
import 'package:restage/restage.dart';

@FlowSource(id: 'welcome')
final class WelcomeFlow extends RestageFlow {
  const WelcomeFlow();

  @override
  FlowDef buildFlow() => flow(
        initial: const OnboardingScreenRef(
          id: 'welcome',
          artifactPath: 'welcome.rfw',
          version: 1,
          minClient: 3,
        ),
        states: const [],
      );
}
''',
      });

      expect(result.issues, isEmpty);
      expect(result.flows, hasLength(1));
      final flow = result.flows.single;
      expect(flow.id, 'welcome');
      expect(flow.isCanonical, isFalse);
      expect(flow.surface, Surface.onboarding);
      expect(flow.declaration, isA<ClassElement>());
    });

    test('recognizes the canonical annotation on an advanced flow class',
        () async {
      final result = await _inspect({
        'lib/onboarding/flows/advanced_flow.dart': '''
import 'package:restage/restage.dart';

@FlowGraph(surface: Surface.onboarding)
final class AdvancedFlow extends RestageFlow {
  const AdvancedFlow();

  @override
  FlowDef buildFlow() => flow(
        initial: const OnboardingScreenRef(
          id: 'advanced',
          artifactPath: 'advanced.rfw',
          version: 1,
          minClient: 3,
        ),
        states: const [],
      );
}
''',
      });

      expect(result.issues, isEmpty, reason: result.issues.toString());
      expect(result.flows.single.id, 'advanced_flow');
      expect(result.flows.single.hasExplicitId, isFalse);
      expect(result.flows.single.isCanonical, isTrue);
      expect(result.flows.single.graph, isNull);
    });

    test('does not admit a local FlowSource lookalike', () async {
      final result = await _inspect({
        'lib/onboarding/flows/lookalike.dart': '''
class FlowSource {
  const FlowSource({required this.id});
  final String id;
}

@FlowSource(id: 'lookalike')
final class Lookalike {}
''',
      });

      expect(result.flows, isEmpty);
      expect(result.issues, isEmpty);
    });

    test('lowers a resolved flattened linear graph', () async {
      final result = await _inspect({
        'lib/onboarding/screens/welcome.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Screen()
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  static const next = SurfaceEvent<void>('next');
  @override
  Widget build(BuildContext context) => const Text('Welcome');
}
''',
        'lib/onboarding/screens/profile.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Screen()
final class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  static const finish = SurfaceEvent<void>('finish');
  @override
  Widget build(BuildContext context) => const Text('Profile');
}
''',
        'lib/onboarding/flows/welcome_flow.dart': '''
import 'package:restage/restage.dart';
import '../screens/profile.dart';
import '../screens/welcome.dart';

@FlowGraph(surface: Surface.onboarding)
const welcomeFlow = FlowDefinition(
  start: WelcomeScreen,
  transitions: [
    Transition(WelcomeScreen.next, to: ProfileScreen),
    Transition.complete(ProfileScreen.finish),
  ],
);
''',
      });

      expect(result.issues, isEmpty);
      expect(result.issues, isEmpty, reason: result.issues.toString());
      expect(result.flows, hasLength(1));
      final graph = result.flows.single.graph!;
      expect(result.flows.single.id, 'welcome_flow');
      expect(graph.states['welcome'], isA<ScreenFlowState>());
      expect(graph.states['profile'], isA<ScreenFlowState>());
      expect(graph.states['done'], isA<EndFlowState>());
      expect(
        graph.states['welcome']! as ScreenFlowState,
        isA<ScreenFlowState>(),
      );
    });

    test('rejects repeated state keys with different defaults', () async {
      final result = await _inspect({
        'lib/onboarding/screens/start.dart': _screenSource('StartScreen', ''),
        'lib/onboarding/flows/duplicate_state.dart': '''
import 'package:restage/restage.dart';
import '../screens/start.dart';

const firstAnswer = FlowStateRef<String>(
  'answer',
  defaultValue: 'first',
);
const secondAnswer = FlowStateRef<String>(
  'answer',
  defaultValue: 'second',
);

@FlowGraph(surface: Surface.onboarding)
const duplicateState = FlowDefinition(
  start: StartScreen,
  state: [firstAnswer, secondAnswer],
  transitions: [],
);
''',
      });

      expect(result.flows, isEmpty);
      expect(
        result.issues.map((issue) => issue.message).join('\n'),
        contains('Flow-state key "answer" is declared more than once.'),
      );
    });

    test('rejects repeated state keys across regular and seedable refs',
        () async {
      final result = await _inspect({
        'lib/onboarding/screens/start.dart': _screenSource('StartScreen', ''),
        'lib/onboarding/flows/duplicate_seedable_state.dart': '''
import 'package:restage/restage.dart';
import '../screens/start.dart';

const regularAnswer = FlowStateRef<String>('answer');
const seedableAnswer = SeedableFlowStateRef<String>('answer');

@FlowGraph(surface: Surface.onboarding)
const duplicateSeedableState = FlowDefinition(
  start: StartScreen,
  state: [regularAnswer, seedableAnswer],
  transitions: [],
);
''',
      });

      expect(result.flows, isEmpty);
      expect(
        result.issues.map((issue) => issue.message).join('\n'),
        contains('Flow-state key "answer" is declared more than once.'),
      );
    });

    test('requires state declarations to have reusable analyzer elements',
        () async {
      final result = await _inspect({
        'lib/onboarding/screens/start.dart': _screenSource('StartScreen', ''),
        'lib/onboarding/flows/inline_state.dart': '''
import 'package:restage/restage.dart';
import '../screens/start.dart';

@FlowGraph(surface: Surface.onboarding)
final inlineState = FlowDefinition(
  start: StartScreen,
  state: [const FlowStateRef<String>('answer')],
  transitions: [],
);
''',
      });

      expect(result.flows, isEmpty);
      expect(
        result.issues.map((issue) => issue.message).join('\n'),
        contains(
          'FlowDefinition.state entries must reference analyzer-resolved '
          'FlowStateRef declarations.',
        ),
      );
    });

    test('rejects same-key aliases in every parent state-ref use', () async {
      final result = await _inspect({
        'lib/onboarding/screens/start.dart': _screenSource(
          'StartScreen',
          "static const next = SurfaceEvent<void>('next'); "
              "static const answer = SurfaceEvent<String>('answer'); "
              "static const finish = SurfaceEvent<void>('finish');",
        ),
        'lib/onboarding/screens/destination.dart': _screenSource(
          'DestinationScreen',
          "static const finish = SurfaceEvent<void>('finish');",
        ),
        'lib/onboarding/flows/state_aliases.dart': '''
import 'package:restage/restage.dart';
import '../screens/destination.dart';
import '../screens/start.dart';

const declaredAnswer = FlowStateRef<String>('answer');
const answerAlias = FlowStateRef<String>('answer');
const declaredOther = FlowStateRef<String>('other');
const otherAlias = FlowStateRef<String>('other');
const declaredSeed = SeedableFlowStateRef<bool>('seed');
const regularSeedAlias = FlowStateRef<bool>('seed');

final predicateRoute = Decision(
  'predicate_route',
  branches: [
    Branch(when: answerAlias.equals('yes'), to: DestinationScreen),
  ],
  otherwise: DestinationScreen,
);

final equalsStateRoute = Decision(
  'equals_state_route',
  branches: [
    Branch(
      when: declaredAnswer.equalsState(otherAlias),
      to: DestinationScreen,
    ),
  ],
  otherwise: DestinationScreen,
);

void decodeChild(Map<String, Object?> result) {}

const childFlow = SurfaceFlowRef<void>(
  id: 'child',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  decodeResult: decodeChild,
);
const childAnswer = FlowStateRef<String>('childAnswer');
final subflowTerminal = Completion('subflow_terminal');
final aliasSubflow = Subflow(
  'alias_subflow',
  flow: childFlow,
  input: [childAnswer.fromState(answerAlias)],
  onComplete: subflowTerminal,
);

@FlowGraph(id: 'alias_write', surface: Surface.onboarding)
final aliasWrite = FlowDefinition(
  start: StartScreen,
  state: [declaredAnswer],
  transitions: [
    Transition(
      StartScreen.next,
      writes: [answerAlias.set('written')],
      to: DestinationScreen,
    ),
    Transition.complete(DestinationScreen.finish),
  ],
);

@FlowGraph(id: 'alias_capture', surface: Surface.onboarding)
final aliasCapture = FlowDefinition(
  start: StartScreen,
  state: [declaredAnswer],
  transitions: [
    Transition(
      StartScreen.answer,
      capture: answerAlias,
      to: DestinationScreen,
    ),
    Transition.complete(DestinationScreen.finish),
  ],
);

@FlowGraph(id: 'alias_predicate', surface: Surface.onboarding)
final aliasPredicate = FlowDefinition(
  start: StartScreen,
  state: [declaredAnswer],
  nodes: [predicateRoute],
  transitions: [
    Transition(StartScreen.next, to: predicateRoute),
    Transition.complete(DestinationScreen.finish),
  ],
);

@FlowGraph(id: 'alias_equals_state', surface: Surface.onboarding)
final aliasEqualsState = FlowDefinition(
  start: StartScreen,
  state: [declaredAnswer, declaredOther],
  nodes: [equalsStateRoute],
  transitions: [
    Transition(StartScreen.next, to: equalsStateRoute),
    Transition.complete(DestinationScreen.finish),
  ],
);

@FlowGraph(id: 'alias_outbound', surface: Surface.onboarding)
final aliasOutbound = FlowDefinition(
  start: StartScreen,
  state: [declaredAnswer],
  transitions: [Transition.complete(StartScreen.finish)],
  outbound: FlowOutboundPolicy(
    terminalResult: {'answer': answerAlias},
  ),
);

@FlowGraph(id: 'alias_seed', surface: Surface.onboarding)
final aliasSeed = FlowDefinition(
  start: StartScreen,
  state: [declaredSeed],
  transitions: [Transition.complete(StartScreen.finish)],
  outbound: FlowOutboundPolicy(
    terminalResult: {'seed': regularSeedAlias},
  ),
);

@FlowGraph(id: 'alias_subflow_input', surface: Surface.onboarding)
final aliasSubflowInput = FlowDefinition(
  start: StartScreen,
  state: [declaredAnswer],
  nodes: [subflowTerminal, aliasSubflow],
  transitions: [Transition(StartScreen.next, to: aliasSubflow)],
);
''',
      });

      expect(result.flows, isEmpty);
      final messages = result.issues.map((issue) => issue.message).join('\n');
      expect(messages, contains('FlowStateRef.set(...) for flow-state key'));
      expect(messages, contains('Transition.capture for flow-state key'));
      expect(messages, contains('Decision predicate for flow-state key'));
      expect(
        messages,
        contains(
          'FlowStateRef.equalsState(...) argument for flow-state key',
        ),
      );
      expect(messages, contains('Outbound field "answer" for flow-state key'));
      expect(messages, contains('Outbound field "seed" for flow-state key'));
      expect(
        messages,
        contains('Subflow parent-state input for flow-state key'),
      );
      expect(
        RegExp(
          'must reuse the exact analyzer-resolved FlowStateRef declaration',
        ).allMatches(messages),
        hasLength(7),
      );
    });

    test('accepts the deprecated OnboardingEvent typedef by resolved element',
        () async {
      final result = await _inspect({
        'lib/onboarding/screens/welcome.dart': _screenSource(
          'WelcomeScreen',
          "static const finish = OnboardingEvent<void>('finish');",
        ),
        'lib/onboarding/flows/welcome_flow.dart': '''
import 'package:restage/restage.dart';
import '../screens/welcome.dart';

@FlowGraph(surface: Surface.onboarding)
const welcomeFlow = FlowDefinition(
  start: WelcomeScreen,
  transitions: [Transition.complete(WelcomeScreen.finish)],
);
''',
      });

      expect(result.issues, isEmpty, reason: result.issues.toString());
      expect(result.flows.single.graph!.states['done'], isA<EndFlowState>());
    });

    test('lowers typed state, decision branches, writes, and outbound policy',
        () async {
      final result = await _inspect({
        'lib/survey/screens/question.dart': _screenSource(
          'QuestionScreen',
          "static const answer = SurfaceEvent<String>('answer');",
        ),
        'lib/survey/screens/guided.dart': _screenSource(
          'GuidedScreen',
          "static const finish = SurfaceEvent<void>('finish');",
        ),
        'lib/survey/screens/explore.dart': _screenSource(
          'ExploreScreen',
          "static const finish = SurfaceEvent<void>('finish');",
        ),
        'lib/survey/flows/setup_survey.dart': '''
import 'package:restage/restage.dart';
import '../screens/explore.dart';
import '../screens/guided.dart';
import '../screens/question.dart';

const answer = FlowStateRef<String>(
  'answer',
  classification: FlowStateClassification.exportable,
);
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
  state: [answer],
  transitions: [
    Transition(QuestionScreen.answer, capture: answer, to: route),
    Transition.complete(GuidedScreen.finish),
    Transition.complete(ExploreScreen.finish),
  ],
  outbound: FlowOutboundPolicy(
    terminalResult: {'answer': answer},
    surveyAnswers: {'answer': answer},
  ),
);
''',
      });

      expect(result.issues, isEmpty, reason: result.issues.toString());
      final graph = result.flows.single.graph!;
      expect(
        graph.flowState['answer']!.classification,
        FlowStateClassification.exportable,
      );
      expect(graph.states['route'], isA<DecisionFlowState>());
      final question = graph.states['question']! as ScreenFlowState;
      final transition = question.on['answer']! as GotoFlowTransition;
      expect(transition.target, 'route');
      expect(
        transition.stateWrites['answer']!.value,
        isA<EventFlowValueSource>(),
      );
      expect(
        graph.outbound.surveyAnswers.fields['answer']!.ref,
        isA<StateFlowOutboundRef>(),
      );
    });

    test('lowers a subflow and preserves typed child input identity', () async {
      final result = await _inspect(
        {
          'lib/onboarding/screens/account.dart': _screenSource(
            'AccountScreen',
            "static const profile = SurfaceEvent<void>('profile');",
          ),
          'lib/onboarding/screens/error.dart': _screenSource(
            'ErrorScreen',
            '',
          ),
          'lib/onboarding/screens/profile.dart': _screenSource(
            'ProfileScreen',
            "static const finish = SurfaceEvent<void>('finish');",
          ),
          'lib/onboarding/flows/profile_flow.dart': '''
import 'package:restage/restage.dart';
import '../screens/profile.dart';

const profileName = FlowStateRef<String>('profileName');

@FlowGraph(surface: Surface.onboarding)
const profileFlow = FlowDefinition(
  start: ProfileScreen,
  state: [profileName],
  transitions: [Transition.complete(ProfileScreen.finish)],
);
''',
          'lib/onboarding/flows/account_setup.dart': '''
import 'package:restage/restage.dart';
import '../screens/account.dart';
import '../screens/error.dart';
import 'profile_flow.dart';

const accountName = FlowStateRef<String>('accountName');
final done = Completion('done');
final profileStep = Subflow(
  'profile',
  flow: profileFlow,
  input: [profileName.fromState(accountName)],
  onComplete: done,
  onUnavailable: ErrorScreen,
);

@FlowGraph(surface: Surface.onboarding)
final accountSetup = FlowDefinition(
  start: AccountScreen,
  state: [accountName],
  transitions: [Transition(AccountScreen.profile, to: profileStep)],
);
''',
        },
        preferredFlowPath: 'account_setup.dart',
      );

      expect(result.issues, isEmpty, reason: result.issues.toString());
      final graph = result.flows.single.graph!;
      final subflow = graph.states['profile']! as SubFlowState;
      expect(subflow.flow, 'profile_flow');
      expect(subflow.input['profileName'], isA<StateFlowValueSource>());
      expect(graph.states['done'], isA<EndFlowState>());
      expect(graph.states['error'], isA<ScreenFlowState>());
    });

    test('rejects duplicate subflow child input mappings', () async {
      final result = await _inspect(
        {
          'lib/onboarding/screens/account.dart': _screenSource(
            'AccountScreen',
            "static const open = SurfaceEvent<void>('open');",
          ),
          'lib/onboarding/screens/profile.dart': _screenSource(
            'ProfileScreen',
            "static const finish = SurfaceEvent<void>('finish');",
          ),
          'lib/onboarding/flows/profile_flow.dart': '''
import 'package:restage/restage.dart';
import '../screens/profile.dart';

const profileName = FlowStateRef<String>('profileName');

@FlowGraph(surface: Surface.onboarding)
const profileFlow = FlowDefinition(
  start: ProfileScreen,
  state: [profileName],
  transitions: [Transition.complete(ProfileScreen.finish)],
);
''',
          'lib/onboarding/flows/account_setup.dart': '''
import 'package:restage/restage.dart';
import '../screens/account.dart';
import 'profile_flow.dart';

const accountName = FlowStateRef<String>('accountName');
final done = Completion('done');
final profileStep = Subflow(
  'profile',
  flow: profileFlow,
  input: [
    profileName.fromState(accountName),
    profileName.fromValue('fallback'),
  ],
  onComplete: done,
);

@FlowGraph(surface: Surface.onboarding)
final accountSetup = FlowDefinition(
  start: AccountScreen,
  state: [accountName],
  transitions: [Transition(AccountScreen.open, to: profileStep)],
);
''',
        },
        preferredFlowPath: 'account_setup.dart',
      );

      expect(result.flows, isEmpty);
      expect(
        result.issues.map((issue) => issue.message).join('\n'),
        contains(
          'Subflow input child key "profileName" is mapped more than once.',
        ),
      );
    });

    test('rejects a child flow whose resolved surface differs from its parent',
        () async {
      final result = await _inspect(
        {
          'lib/onboarding/screens/account.dart': _screenSource(
            'AccountScreen',
            "static const open = SurfaceEvent<void>('open');",
          ),
          'lib/onboarding/screens/error.dart': _screenSource(
            'ErrorScreen',
            '',
          ),
          'lib/onboarding/flows/account_setup.dart': '''
import 'package:restage/restage.dart';
import '../screens/account.dart';
import '../screens/error.dart';

void _decode(Map<String, Object?> result) {}

const messageChild = SurfaceFlowRef<void>(
  id: 'shared_child',
  version: 1,
  minClient: 1,
  surface: Surface.message,
  decodeResult: _decode,
);
final done = Completion('done');
final childStep = Subflow(
  'child',
  flow: messageChild,
  onComplete: done,
  onUnavailable: ErrorScreen,
);

@FlowGraph(id: 'account_setup', surface: Surface.onboarding)
final accountSetup = FlowDefinition(
  start: AccountScreen,
  transitions: [Transition(AccountScreen.open, to: childStep)],
);
''',
        },
        preferredFlowPath: 'account_setup.dart',
      );

      expect(result.issues, isNotEmpty);
      expect(
        result.issues.map((issue) => issue.message).join('\n'),
        contains('cannot be included in a onboarding flow'),
      );
    });

    test('keeps equal child slugs distinct across surface identities',
        () async {
      final sources = {
        'lib/onboarding/screens/start.dart': _screenSource(
          'OnboardingStartScreen',
          "static const open = SurfaceEvent<void>('open');",
        ),
        'lib/message/screens/start.dart': _screenSource(
          'MessageStartScreen',
          "static const open = SurfaceEvent<void>('open');",
        ),
        'lib/onboarding/flows/parent.dart': '''
import 'package:restage/restage.dart';
import '../screens/start.dart';

void _decodeOnboarding(Map<String, Object?> result) {}

const onboardingChild = SurfaceFlowRef<void>(
  id: 'shared_child',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  decodeResult: _decodeOnboarding,
);
final done = Completion('done');
final childStep = Subflow(
  'child',
  flow: onboardingChild,
  onComplete: done,
);

@FlowGraph(id: 'onboarding_parent', surface: Surface.onboarding)
final onboardingParent = FlowDefinition(
  start: OnboardingStartScreen,
  transitions: [Transition(OnboardingStartScreen.open, to: childStep)],
);
''',
        'lib/message/flows/parent.dart': '''
import 'package:restage/restage.dart';
import '../screens/start.dart';

void _decodeMessage(Map<String, Object?> result) {}

const messageChild = SurfaceFlowRef<void>(
  id: 'shared_child',
  version: 1,
  minClient: 1,
  surface: Surface.message,
  decodeResult: _decodeMessage,
);
final done = Completion('done');
final childStep = Subflow(
  'child',
  flow: messageChild,
  onComplete: done,
);

@FlowGraph(id: 'message_parent', surface: Surface.message)
final messageParent = FlowDefinition(
  start: MessageStartScreen,
  transitions: [Transition(MessageStartScreen.open, to: childStep)],
);
''',
      };

      final onboarding = await _inspect(
        sources,
        preferredFlowPath: 'lib/onboarding/flows/parent.dart',
      );
      final message = await _inspect(
        sources,
        preferredFlowPath: 'lib/message/flows/parent.dart',
      );

      expect(onboarding.issues, isEmpty, reason: onboarding.issues.toString());
      expect(message.issues, isEmpty, reason: message.issues.toString());
      expect(
        onboarding.flows.single.graph!.childFlows.keys.single,
        const NormalizedFlowIdentity(
          surface: Surface.onboarding,
          id: 'shared_child',
        ),
      );
      expect(
        message.flows.single.graph!.childFlows.keys.single,
        const NormalizedFlowIdentity(
          surface: Surface.message,
          id: 'shared_child',
        ),
      );
    });

    test('accepts a resolved advanced FlowGraph class as a subflow target',
        () async {
      final result = await _inspect(
        {
          'lib/onboarding/screens/account.dart': _screenSource(
            'AccountScreen',
            "static const open = SurfaceEvent<void>('open');",
          ),
          'lib/onboarding/flows/account_setup.dart': '''
import 'package:restage/restage.dart';
import '../screens/account.dart';

@FlowGraph(id: 'advanced_child', surface: Surface.onboarding)
final class AdvancedChild extends RestageFlow {
  const AdvancedChild();

  @override
  FlowDef buildFlow() => flow(
        initial: const OnboardingScreenRef(
          id: 'advanced_screen',
          artifactPath: 'advanced_screen.rfw',
          version: 1,
          minClient: 1,
        ),
        states: const [],
      );
}

final done = Completion('done');
final childStep = Subflow(
  'child',
  flow: AdvancedChild,
  onComplete: done,
);

@FlowGraph(id: 'account_setup', surface: Surface.onboarding)
final accountSetup = FlowDefinition(
  start: AccountScreen,
  transitions: [Transition(AccountScreen.open, to: childStep)],
);
''',
        },
        preferredFlowPath: 'account_setup.dart',
      );

      expect(result.issues, isEmpty, reason: result.issues.toString());
      final parent = result.flows.singleWhere((flow) => flow.graph != null);
      final reference = parent.graph!.childFlows.values.single;
      expect(reference.identity.id, 'advanced_child');
      expect(reference.identity.surface, Surface.onboarding);
      expect(reference.declarationIdentity, contains('#AdvancedChild'));
    });

    test('rejects an unannotated advanced-flow lookalike target', () async {
      final result = await _inspect(
        {
          'lib/onboarding/screens/account.dart': _screenSource(
            'AccountScreen',
            "static const open = SurfaceEvent<void>('open');",
          ),
          'lib/onboarding/flows/account_setup.dart': '''
import 'package:restage/restage.dart';
import '../screens/account.dart';

final class AdvancedChild extends RestageFlow {
  const AdvancedChild();

  @override
  FlowDef buildFlow() => flow(
        initial: const OnboardingScreenRef(
          id: 'advanced_screen',
          artifactPath: 'advanced_screen.rfw',
          version: 1,
          minClient: 1,
        ),
        states: const [],
      );
}

final done = Completion('done');
final childStep = Subflow(
  'child',
  flow: AdvancedChild,
  onComplete: done,
);

@FlowGraph(id: 'account_setup', surface: Surface.onboarding)
final accountSetup = FlowDefinition(
  start: AccountScreen,
  transitions: [Transition(AccountScreen.open, to: childStep)],
);
''',
        },
        preferredFlowPath: 'account_setup.dart',
      );

      expect(result.flows, isEmpty);
      expect(
        result.issues.map((issue) => issue.message).join('\n'),
        contains('canonical @FlowGraph class'),
      );
    });

    test('rejects distinct decisions and subflows with the same node id',
        () async {
      final result = await _inspect({
        'lib/onboarding/screens/start.dart': _screenSource('StartScreen', ''),
        'lib/onboarding/flows/duplicate_nodes.dart': '''
import 'package:restage/restage.dart';
import '../screens/start.dart';

const choice = FlowStateRef<String>('choice');
void decodeChild(Map<String, Object?> result) {}
const childFlow = SurfaceFlowRef<void>(
  id: 'child',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  decodeResult: decodeChild,
);
final done = Completion('done');
final route = Decision(
  'shared',
  branches: [
    Branch(when: choice.equals('yes'), to: StartScreen),
  ],
  otherwise: StartScreen,
);
final child = Subflow(
  'shared',
  flow: childFlow,
  onComplete: done,
);

@FlowGraph(surface: Surface.onboarding)
final duplicateNodes = FlowDefinition(
  start: StartScreen,
  state: [choice],
  nodes: [route, child],
  transitions: [],
);
''',
      });

      expect(result.flows, isEmpty);
      expect(
        result.issues.map((issue) => issue.message).join('\n'),
        contains(
          'Flow node id "shared" resolves to distinct analyzer declarations',
        ),
      );
    });

    test('rejects a direct node target that collides with a screen id',
        () async {
      final result = await _inspect({
        'lib/onboarding/screens/start.dart': _screenSource(
          'StartScreen',
          "static const open = SurfaceEvent<void>('open');",
        ),
        'lib/onboarding/flows/colliding_node.dart': '''
import 'package:restage/restage.dart';
import '../screens/start.dart';

const choice = FlowStateRef<String>('choice');
final route = Decision(
  'start',
  branches: [
    Branch(when: choice.equals('yes'), to: StartScreen),
  ],
  otherwise: StartScreen,
);

@FlowGraph(surface: Surface.onboarding)
final collidingNode = FlowDefinition(
  start: StartScreen,
  state: [choice],
  transitions: [Transition(StartScreen.open, to: route)],
);
''',
      });

      expect(result.flows, isEmpty);
      expect(
        result.issues.map((issue) => issue.message).join('\n'),
        contains('Flow node id "start" collides with screen identity "start"'),
      );
    });

    test('allows equivalent Transition.complete terminal references', () async {
      final result = await _inspect({
        'lib/onboarding/screens/start.dart': _screenSource(
          'StartScreen',
          "static const finish = SurfaceEvent<void>('finish'); "
              "static const next = SurfaceEvent<void>('next');",
        ),
        'lib/onboarding/screens/alternate.dart': _screenSource(
          'AlternateScreen',
          "static const finish = SurfaceEvent<void>('finish');",
        ),
        'lib/onboarding/flows/equivalent_completion.dart': '''
import 'package:restage/restage.dart';
import '../screens/alternate.dart';
import '../screens/start.dart';

@FlowGraph(surface: Surface.onboarding)
final equivalentCompletion = FlowDefinition(
  start: StartScreen,
  transitions: [
    Transition.complete(
      StartScreen.finish,
      id: 'complete',
      result: {'status': 'ok'},
    ),
    Transition(StartScreen.next, to: AlternateScreen),
    Transition.complete(
      AlternateScreen.finish,
      id: 'complete',
      result: {'status': 'ok'},
    ),
  ],
);
''',
      });

      expect(result.issues, isEmpty, reason: result.issues.toString());
      final terminal =
          result.flows.single.graph!.states['complete']! as EndFlowState;
      expect(terminal.result, {'status': 'ok'});
    });

    test('rejects Transition.complete IDs colliding with every node kind',
        () async {
      final screenCollision = await _inspect({
        'lib/onboarding/screens/done.dart': _screenSource(
          'DoneScreen',
          "static const finish = SurfaceEvent<void>('finish');",
        ),
        'lib/onboarding/flows/screen_terminal_collision.dart': '''
import 'package:restage/restage.dart';
import '../screens/done.dart';

@FlowGraph(surface: Surface.onboarding)
final screenTerminalCollision = FlowDefinition(
  start: DoneScreen,
  transitions: [Transition.complete(DoneScreen.finish)],
);
''',
      });
      expect(screenCollision.flows, isEmpty);
      expect(
        screenCollision.issues.map((issue) => issue.message).join('\n'),
        contains('Flow node id "done" collides with screen identity "done"'),
      );

      final decisionCollision = await _inspect({
        'lib/onboarding/screens/start.dart': _screenSource(
          'StartScreen',
          "static const finish = SurfaceEvent<void>('finish');",
        ),
        'lib/onboarding/flows/decision_terminal_collision.dart': '''
import 'package:restage/restage.dart';
import '../screens/start.dart';

const choice = FlowStateRef<String>('choice');
final route = Decision(
  'done',
  branches: [
    Branch(when: choice.equals('yes'), to: StartScreen),
  ],
  otherwise: StartScreen,
);

@FlowGraph(surface: Surface.onboarding)
final decisionTerminalCollision = FlowDefinition(
  start: StartScreen,
  state: [choice],
  nodes: [route],
  transitions: [Transition.complete(StartScreen.finish)],
);
''',
      });
      expect(decisionCollision.flows, isEmpty);
      expect(
        decisionCollision.issues.map((issue) => issue.message).join('\n'),
        contains('Flow node id "done" resolves to distinct analyzer'),
      );

      final subflowCollision = await _inspect({
        'lib/onboarding/screens/start.dart': _screenSource(
          'StartScreen',
          "static const finish = SurfaceEvent<void>('finish');",
        ),
        'lib/onboarding/flows/subflow_terminal_collision.dart': '''
import 'package:restage/restage.dart';
import '../screens/start.dart';

void decodeChild(Map<String, Object?> result) {}

const childFlow = SurfaceFlowRef<void>(
  id: 'child',
  version: 1,
  minClient: 1,
  surface: Surface.onboarding,
  decodeResult: decodeChild,
);
final finished = Completion('finished');
final child = Subflow(
  'done',
  flow: childFlow,
  onComplete: finished,
);

@FlowGraph(surface: Surface.onboarding)
final subflowTerminalCollision = FlowDefinition(
  start: StartScreen,
  nodes: [finished, child],
  transitions: [Transition.complete(StartScreen.finish)],
);
''',
      });
      expect(subflowCollision.flows, isEmpty);
      expect(
        subflowCollision.issues.map((issue) => issue.message).join('\n'),
        contains('Flow node id "done" resolves to distinct analyzer'),
      );

      final explicitCompletionCollision = await _inspect({
        'lib/onboarding/screens/start.dart': _screenSource(
          'StartScreen',
          "static const finish = SurfaceEvent<void>('finish');",
        ),
        'lib/onboarding/flows/explicit_terminal_collision.dart': '''
import 'package:restage/restage.dart';
import '../screens/start.dart';

final explicitDone = Completion(
  'done',
  result: {'status': 'ok'},
);

@FlowGraph(surface: Surface.onboarding)
final explicitTerminalCollision = FlowDefinition(
  start: StartScreen,
  nodes: [explicitDone],
  transitions: [
    Transition.complete(
      StartScreen.finish,
      result: {'status': 'ok'},
    ),
  ],
);
''',
      });
      expect(explicitCompletionCollision.flows, isEmpty);
      expect(
        explicitCompletionCollision.issues
            .map((issue) => issue.message)
            .join('\n'),
        contains('Flow node id "done" resolves to distinct analyzer'),
      );
    });

    test('lowers a resolved host-action transition gate', () async {
      final result = await _inspect({
        'lib/onboarding/screens/permission.dart': _screenSource(
          'PermissionScreen',
          "static const enable = SurfaceEvent<void>('enable');",
        ),
        'lib/onboarding/screens/ready.dart': _screenSource(
          'ReadyScreen',
          "static const finish = SurfaceEvent<void>('finish');",
        ),
        'lib/onboarding/flows/permission_flow.dart': '''
import 'package:restage/restage.dart';
import '../screens/permission.dart';
import '../screens/ready.dart';

const requestNotifications = FlowActionRef<void, bool>(
  'requestNotifications',
);

@FlowGraph(surface: Surface.onboarding)
final permissionFlow = FlowDefinition(
  start: PermissionScreen,
  transitions: [
    Transition(
      PermissionScreen.enable,
      action: requestNotifications.continueWhen((granted) => granted),
      to: ReadyScreen,
    ),
    Transition.complete(ReadyScreen.finish),
  ],
);
''',
      });

      expect(result.issues, isEmpty, reason: result.issues.toString());
      final graph = result.flows.single.graph!;
      expect(graph.actions['requestNotifications'], isA<FlowActionContract>());
      final permission = graph.states['permission']! as ScreenFlowState;
      final transition = permission.on['enable']! as ActionFlowTransition;
      expect(transition.action, 'requestNotifications');
      expect(
        transition.resultPredicate,
        const BoolEqualsActionResultPredicate(value: true),
      );
    });

    test('rejects conflicting duplicate host-action ids before overwrite',
        () async {
      final result = await _inspect({
        'lib/onboarding/screens/start.dart': _screenSource(
          'StartScreen',
          "static const first = SurfaceEvent<void>('first'); "
              "static const second = SurfaceEvent<void>('second');",
        ),
        'lib/onboarding/screens/ready.dart': _screenSource(
          'ReadyScreen',
          "static const finish = SurfaceEvent<void>('finish');",
        ),
        'lib/onboarding/flows/action_flow.dart': '''
import 'package:restage/restage.dart';
import '../screens/ready.dart';
import '../screens/start.dart';

const firstAction = FlowActionRef<void, bool>('same_action');
const secondAction = FlowActionRef<String, bool>('same_action');

@FlowGraph(surface: Surface.onboarding)
final actionFlow = FlowDefinition(
  start: StartScreen,
  transitions: [
    Transition(
      StartScreen.first,
      action: firstAction.continueWhen((result) => result),
      to: ReadyScreen,
    ),
    Transition(
      StartScreen.second,
      action: secondAction.continueWhen((result) => result),
      to: ReadyScreen,
    ),
    Transition.complete(ReadyScreen.finish),
  ],
);
''',
      });

      expect(result.flows, isEmpty);
      expect(
        result.issues.map((issue) => issue.message).join('\n'),
        contains('Host action id "same_action" is declared by both'),
      );
    });
  });
}

String _screenSource(String className, String event) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Screen()
final class $className extends StatelessWidget {
  const $className({super.key});
  $event
  @override
  Widget build(BuildContext context) => const Text('screen');
}
''';

Future<FlowFrontendResult> _inspect(
  Map<String, String> sources, {
  String? preferredFlowPath,
}) async {
  final writer = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final assetMap = <String, String>{
    for (final entry in sources.entries)
      'apps_examples|${entry.key}': entry.value,
  };
  for (final entry in assetMap.entries) {
    writer.testing.writeString(AssetId.parse(entry.key), entry.value);
  }

  FlowFrontendResult? inspected;
  await testBuilder(
    _ProbeBuilder((library, assetId) async {
      final candidate = await inspectFlowDefinitions(
        library,
        assetId,
        legacySurface: Surface.onboarding,
      );
      if ((preferredFlowPath == null ||
              assetId.path.endsWith(preferredFlowPath)) &&
          (assetId.path.contains('/flows/') ||
              candidate.flows.isNotEmpty ||
              candidate.issues.isNotEmpty)) {
        inspected = candidate;
      }
    }),
    assetMap,
    rootPackage: 'apps_examples',
    readerWriter: writer,
  );
  return inspected!;
}

final class _ProbeBuilder implements Builder {
  _ProbeBuilder(this.onLibrary);

  final Future<void> Function(LibraryElement library, AssetId assetId)
      onLibrary;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.flow_frontend_probe'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    await onLibrary(await buildStep.inputLibrary, buildStep.inputId);
  }
}
