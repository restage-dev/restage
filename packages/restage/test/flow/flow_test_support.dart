import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

/// Shared fixtures for the flow controller/view tests.
///
/// Public (no leading underscore) so multiple test files can reuse them; the
/// existing `flow_controller_test.dart` / `restage_onboarding_test.dart` keep
/// their own local copies and are intentionally left untouched.

/// Typed terminal result for the first-run fixture flow.
final class FirstRunResult {
  const FirstRunResult({required this.completed});

  final bool completed;

  static FirstRunResult decode(Map<String, Object?> result) {
    if (result.keys.toSet().difference({'completed'}).isNotEmpty) {
      throw const FormatException('Unexpected result keys.');
    }
    final completed = result['completed'];
    if (completed is! bool) {
      throw const FormatException('Expected completed bool.');
    }
    return FirstRunResult(completed: completed);
  }
}

/// The first-run fixture flow descriptor.
const firstRunFlowRef = OnboardingFlowRef<FirstRunResult>(
  id: 'first_run',
  version: 1,
  minClient: 3,
  decodeResult: FirstRunResult.decode,
);

/// Resolver that always returns a fixed [ResolvedFlow].
final class StaticFlowResolver implements FlowResolver {
  const StaticFlowResolver(this.flow);

  final ResolvedFlow flow;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async => this.flow;
}

/// Encodes a one-screen RFW library whose root taps fire [event] and render
/// [text]. The blob imports `restage.core` (GestureDetector + Text).
Uint8List screenBlob(String text, String event) {
  final source = '''
    import restage.core;
    widget OnboardingScreen = GestureDetector(
      onTap: event "$event" { },
      child: Text(text: "$text")
    );
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// Encodes a screen that reads paywall-style price data from `data.products`.
Uint8List priceScreenBlob() {
  const source = '''
    import restage.core;
    widget OnboardingScreen = Text(
      text: data.products.annual.localizedPrice
    );
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// Builds the default linear first-run flow document (welcome -> profile ->
/// done), or [states] when supplied.
FlowDocument flowDocument({
  String flow = 'first_run',
  Map<String, FlowActionContract>? actions,
  FlowOutboundDeclarations outbound = const FlowOutboundDeclarations(),
  bool legacyTerminalResultPassthrough = false,
  Map<String, FlowState>? states,
  Map<String, FlowContentHash>? screenHashes,
}) {
  final hashes = screenHashes ??
      {
        'welcome': FlowContentHash.compute(screenBlob('Welcome', 'next')),
        'profile': FlowContentHash.compute(screenBlob('Profile', 'finish')),
      };
  return FlowDocument(
    flow: flow,
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'welcome',
    actions: actions ?? const {},
    outbound: outbound,
    legacyTerminalResultPassthrough: legacyTerminalResultPassthrough,
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'welcome.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: hashes['welcome']!,
      ),
      'profile': ScreenArtifact(
        path: 'profile.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: hashes['profile']!,
      ),
    },
    states: states ??
        const {
          'welcome': ScreenFlowState(
            screen: 'welcome',
            on: {'next': FlowTransition.goto('profile')},
          ),
          'profile': ScreenFlowState(
            screen: 'profile',
            on: {'finish': FlowTransition.goto('done')},
          ),
          'done': EndFlowState(result: {'completed': true}),
        },
  );
}

const _throwingLibrary = WidgetLibrary.custom('acme.throwing');

class _ThrowingScreenWidget extends StatelessWidget {
  const _ThrowingScreenWidget();

  @override
  Widget build(BuildContext context) =>
      throw StateError('flow screen render failed');
}

/// Registers a custom widget whose build always throws, for render-failure
/// (fail-closed) tests.
void registerThrowingWidget() {
  Restage.registerWidgetLibrary(
    _throwingLibrary,
    widgets: <RestageWidgetFactory>[
      RestageWidgetFactory(
        name: 'ThrowingWidget',
        builder: (_, __) => const _ThrowingScreenWidget(),
      ),
    ],
  );
}

/// A registered stateful widget for verifying that a kept-mounted screen's
/// Element/State is preserved across forward navigation — its [initState] runs
/// exactly once, not again when the screen is re-rendered or held offstage.
class StatefulProbe extends StatefulWidget {
  const StatefulProbe({super.key});

  static int initCount = 0;

  @override
  State<StatefulProbe> createState() => _StatefulProbeState();
}

class _StatefulProbeState extends State<StatefulProbe> {
  @override
  void initState() {
    super.initState();
    StatefulProbe.initCount += 1;
  }

  @override
  Widget build(BuildContext context) =>
      const Text('probe', textDirection: TextDirection.ltr);
}

const _probeLibrary = WidgetLibrary.custom('acme.probe');

/// Registers [StatefulProbe] and resets its [StatefulProbe.initCount].
void registerStatefulProbe() {
  StatefulProbe.initCount = 0;
  Restage.registerWidgetLibrary(
    _probeLibrary,
    widgets: <RestageWidgetFactory>[
      RestageWidgetFactory(
        name: 'StatefulProbe',
        builder: (_, __) => const StatefulProbe(),
      ),
    ],
  );
}

/// A flow whose welcome screen embeds a tappable [StatefulProbe] (fires `next`)
/// and a plain profile screen — for keep-mounted / state-preservation tests.
ResolvedFlow probeResolvedFlow() {
  final welcome = _probeWelcomeBlob();
  final profile = screenBlob('Profile', 'finish');
  return ResolvedFlow(
    document: flowDocument(
      legacyTerminalResultPassthrough: true,
      screenHashes: {
        'welcome': FlowContentHash.compute(welcome),
        'profile': FlowContentHash.compute(profile),
      },
    ),
    screenBlobs: {'welcome': welcome, 'profile': profile},
    cacheHit: false,
  );
}

Uint8List _probeWelcomeBlob() {
  const source = '''
    import acme.probe;
    import restage.core;
    widget OnboardingScreen = GestureDetector(
      onTap: event "next" { },
      child: StatefulProbe(),
    );
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// A three-screen flow whose FIRST screen embeds a tappable [StatefulProbe]
/// (fires `next`), then two plain screens (`Two` fires `next`, `Three` fires
/// `finish`). For asserting that a multi-step back to the probe restores its
/// preserved Element/State (its [initState] does not run again) rather than
/// remounting it.
ResolvedFlow probeThreeScreenResolvedFlow() =>
    _threeScreenFlow(firstId: 'welcome', firstBlob: _probeWelcomeBlob());

/// A registered widget that throws on build only while [shouldThrow] is set —
/// for the poisoned-screen-on-restore test (a prior screen that renders fine,
/// then throws when brought back onstage).
class ConditionalThrowProbe extends StatelessWidget {
  const ConditionalThrowProbe({super.key});

  static bool shouldThrow = false;

  @override
  Widget build(BuildContext context) {
    if (shouldThrow) {
      throw StateError('flow screen poisoned on restore');
    }
    return const Text('cond', textDirection: TextDirection.ltr);
  }
}

const _condLibrary = WidgetLibrary.custom('acme.cond');

/// Registers [ConditionalThrowProbe] and resets its [shouldThrow] flag.
void registerConditionalThrowProbe() {
  ConditionalThrowProbe.shouldThrow = false;
  Restage.registerWidgetLibrary(
    _condLibrary,
    widgets: <RestageWidgetFactory>[
      RestageWidgetFactory(
        name: 'ConditionalThrowProbe',
        builder: (_, __) => const ConditionalThrowProbe(),
      ),
    ],
  );
}

/// A flow whose welcome screen embeds a tappable [ConditionalThrowProbe]
/// (fires `next`) and a plain profile screen — for poisoned-on-restore tests.
ResolvedFlow conditionalThrowResolvedFlow() {
  final welcome = _condWelcomeBlob();
  final profile = screenBlob('Profile', 'finish');
  return ResolvedFlow(
    document: flowDocument(
      legacyTerminalResultPassthrough: true,
      screenHashes: {
        'welcome': FlowContentHash.compute(welcome),
        'profile': FlowContentHash.compute(profile),
      },
    ),
    screenBlobs: {'welcome': welcome, 'profile': profile},
    cacheHit: false,
  );
}

Uint8List _condWelcomeBlob() {
  const source = '''
    import acme.cond;
    import restage.core;
    widget OnboardingScreen = GestureDetector(
      onTap: event "next" { },
      child: ConditionalThrowProbe(),
    );
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// A one-screen blob whose root widget throws during build.
Uint8List throwingScreenBlob() {
  const source = '''
    import acme.throwing;
    widget OnboardingScreen = ThrowingWidget();
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// A [ResolvedFlow] whose initial (welcome) screen throws during render.
ResolvedFlow throwingResolvedFlow() {
  final throwing = throwingScreenBlob();
  final profile = screenBlob('Profile', 'finish');
  return ResolvedFlow(
    document: flowDocument(
      legacyTerminalResultPassthrough: true,
      screenHashes: {
        'welcome': FlowContentHash.compute(throwing),
        'profile': FlowContentHash.compute(profile),
      },
    ),
    screenBlobs: {'welcome': throwing, 'profile': profile},
    cacheHit: false,
  );
}

/// A three-screen linear flow (One -> Two -> Three -> done) with three distinct
/// screen texts — for multi-screen back (e.g. multi-step pop) tests.
ResolvedFlow threeScreenResolvedFlow() =>
    _threeScreenFlow(firstId: 'one', firstBlob: screenBlob('One', 'next'));

/// Builds a three-screen linear flow whose first screen is [firstId] backed by
/// [firstBlob], followed by the standard `Two` (fires `next`) and `Three`
/// (fires `finish`) screens, terminating at `done`. Parameterizing the first
/// screen lets the plain three-screen flow and the [StatefulProbe]-first flow
/// share one builder.
ResolvedFlow _threeScreenFlow({
  required String firstId,
  required Uint8List firstBlob,
}) {
  final two = screenBlob('Two', 'next');
  final three = screenBlob('Three', 'finish');
  return ResolvedFlow(
    document: FlowDocument(
      flow: 'first_run',
      version: 1,
      schemaVersion: 1,
      minClient: 3,
      initial: firstId,
      legacyTerminalResultPassthrough: true,
      screenArtifacts: {
        firstId: ScreenArtifact(
          path: '$firstId.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 3,
          contentHash: FlowContentHash.compute(firstBlob),
        ),
        'two': ScreenArtifact(
          path: 'two.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 3,
          contentHash: FlowContentHash.compute(two),
        ),
        'three': ScreenArtifact(
          path: 'three.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 3,
          contentHash: FlowContentHash.compute(three),
        ),
      },
      states: {
        firstId: ScreenFlowState(
          screen: firstId,
          on: {'next': FlowTransition.goto('two')},
        ),
        'two': const ScreenFlowState(
          screen: 'two',
          on: {'next': FlowTransition.goto('three')},
        ),
        'three': const ScreenFlowState(
          screen: 'three',
          on: {'finish': FlowTransition.goto('done')},
        ),
        'done': const EndFlowState(result: {'completed': true}),
      },
    ),
    screenBlobs: {firstId: firstBlob, 'two': two, 'three': three},
    cacheHit: false,
  );
}

/// A first-run flow whose welcome screen authors a `skip` transition (so
/// `canSkip` is true), for default skip-affordance tests.
ResolvedFlow skipResolvedFlow() {
  return resolvedFlow(
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {
          'next': FlowTransition.goto('profile'),
          'skip': FlowTransition.goto('done'),
        },
      ),
      'profile': ScreenFlowState(
        screen: 'profile',
        on: {'finish': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
}

/// A first-run flow whose *profile* (second) screen authors an `on['back']`
/// transition (to `done`) — so an authored back handler exists on a screen
/// reached with in-flow history. For asserting that the SDK's auto-shown back
/// chrome is a pure history pop and does NOT take an authored `on['back']`
/// transition (that hook is reserved for an author-placed in-screen control).
ResolvedFlow authoredBackResolvedFlow() {
  return resolvedFlow(
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('profile')},
      ),
      'profile': ScreenFlowState(
        screen: 'profile',
        on: {
          'back': FlowTransition.goto('done'),
          'finish': FlowTransition.goto('done'),
        },
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
}

const _emptyArgsSchema = FlowActionSchema.object({});
const _boolResultSchema = FlowActionSchema.bool();

/// A `requestNotifications` action contract matching [HoldActionRegistry].
FlowActionContract actionContract() {
  return const FlowActionContract(
    actionName: 'requestNotifications',
    contractVersion: 1,
    argsSchema: _emptyArgsSchema,
    resultSchema: _boolResultSchema,
    minClient: 3,
    idempotent: false,
  );
}

/// A [FlowActionRegistry] that binds `requestNotifications` to a handler held
/// open by a [Completer], so a test can keep a host action *in flight*
/// (`controller.isBusy` stays true) until it calls [release].
final class HoldActionRegistry implements FlowActionRegistry {
  HoldActionRegistry();

  final Completer<bool> _gate = Completer<bool>();

  /// Completes the in-flight action so the controller settles.
  void release({bool result = false}) {
    if (!_gate.isCompleted) _gate.complete(result);
  }

  @override
  late final Map<String, FlowActionBinding<dynamic, dynamic>>
      flowActionBindings = {
    'requestNotifications': FlowActionBinding<void, bool>(
      descriptor: const FlowActionDescriptor<void, bool>(
        actionName: 'requestNotifications',
        contractVersion: 1,
        argsSchema: _emptyArgsSchema,
        resultSchema: _boolResultSchema,
        minClient: 3,
        idempotent: false,
      ),
      actionName: 'requestNotifications',
      contractVersion: 1,
      argsSchema: _emptyArgsSchema,
      resultSchema: _boolResultSchema,
      minClient: 3,
      idempotent: false,
      handler: (_, __) => _gate.future,
      decodeArgs: (_) {},
      encodeResult: (value) => value,
    ),
  };
}

/// A first-run flow whose *profile* (second) screen fires a `request` event
/// that runs the `requestNotifications` host action. Reaching profile gives the
/// flow back history (`canBack` is true), so a test can hold the action in
/// flight to exercise chrome behavior while `controller.isBusy` is true.
ResolvedFlow actionFromProfileResolvedFlow() {
  final welcome = screenBlob('Welcome', 'next');
  final profile = screenBlob('Profile', 'request');
  return ResolvedFlow(
    document: flowDocument(
      legacyTerminalResultPassthrough: true,
      actions: {'requestNotifications': actionContract()},
      states: const {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {'next': FlowTransition.goto('profile')},
        ),
        'profile': ScreenFlowState(
          screen: 'profile',
          on: {
            'request': ActionFlowTransition(
              action: 'requestNotifications',
              resultPredicate: BoolEqualsActionResultPredicate(value: true),
              target: 'done',
            ),
          },
        ),
        'done': EndFlowState(result: {'completed': true}),
      },
      screenHashes: {
        'welcome': FlowContentHash.compute(welcome),
        'profile': FlowContentHash.compute(profile),
      },
    ),
    screenBlobs: {'welcome': welcome, 'profile': profile},
    cacheHit: false,
  );
}

/// Builds a [ResolvedFlow] for the default linear first-run flow.
ResolvedFlow resolvedFlow({
  FlowDocument? document,
  Map<String, Uint8List>? screenBlobs,
  Map<String, FlowState>? states,
  String welcomeText = 'Welcome',
  String profileText = 'Profile',
}) {
  final welcome = screenBlobs?['welcome'] ?? screenBlob(welcomeText, 'next');
  final profile = screenBlobs?['profile'] ?? screenBlob(profileText, 'finish');
  return ResolvedFlow(
    document: document ??
        flowDocument(
          legacyTerminalResultPassthrough: true,
          states: states,
          screenHashes: {
            'welcome': FlowContentHash.compute(welcome),
            'profile': FlowContentHash.compute(profile),
          },
        ),
    screenBlobs: {
      'welcome': welcome,
      'profile': profile,
    },
    cacheHit: false,
  );
}

/// Settles the controller's microtask queue (two ticks) so an async transition
/// or host action drains before assertions.
Future<void> drainFlowTasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

/// A [FlowActionRegistry] backed by an explicit bindings map.
final class TestActionRegistry implements FlowActionRegistry {
  const TestActionRegistry(this.flowActionBindings);

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;
}
