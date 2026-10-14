import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

void main() {
  const welcome = '''
widget OnboardingScreen = Column(children: [
  Button(onPressed: event "next" {}),
  Button(onPressed: event "later" {}),
]);
''';
  const goal = '''
widget OnboardingScreen = Button(onPressed: event "done" {});
''';

  List<String> gaps(
    Map<String, String> screens, {
    Map<String, String>? base,
    Map<String, FlowState> states = _states,
  }) =>
      flowScreenEventGaps(
        _flow(screens, states: states),
        base: base == null ? null : _flow(base),
      ).map((gap) => '$gap').toList();

  test('events the state showing the screen handles are no gaps', () {
    expect(gaps({'welcome': welcome, 'goal': goal}), isEmpty);
  });

  test(
      'an event one state handles is a gap in another state showing the '
      'same screen', () {
    expect(
      gaps(
        {'welcome': welcome, 'goal': goal},
        states: {
          ..._states,
          'goal': const ScreenFlowState(
            screen: 'goal',
            on: {'done': FlowTransition.goto('welcome_again')},
          ),
          'welcome_again': const ScreenFlowState(
            screen: 'welcome',
            on: {'later': FlowTransition.goto('done')},
          ),
        },
      ),
      ['event "next" on screen "welcome" in state "welcome_again"'],
    );
  });

  test('a screen no state shows has no gaps', () {
    expect(
      gaps({
        'welcome': welcome,
        'goal': goal,
        'unused': 'widget OnboardingScreen = Button(onPressed: event "x" {});',
      }),
      isEmpty,
    );
  });

  test('skip is a gap unless the state or a custom event handles it', () {
    const skipping = 'widget OnboardingScreen = Column(children: [\n'
        '  Button(onPressed: event "done" {}),\n'
        '  Button(onPressed: event "skip" {}),\n'
        ']);';
    expect(gaps({'welcome': welcome, 'goal': skipping}), [
      'event "skip" on screen "goal" in state "goal"',
    ]);
    expect(
      gaps(
        {'welcome': welcome, 'goal': skipping},
        states: {
          ..._states,
          'goal': const ScreenFlowState(
            screen: 'goal',
            on: {
              'done': FlowTransition.goto('welcome'),
              'skip': FlowTransition.goto('done'),
            },
          ),
        },
      ),
      isEmpty,
    );
  });

  test(
      'back, declared custom events and events outside the contract are '
      'handled on any screen', () {
    expect(
      gaps({
        'welcome': welcome,
        'goal': '''
widget OnboardingScreen = Column(children: [
  Button(onPressed: event "back" {}),
  Button(onPressed: event "dismiss" {}),
  Button(onPressed: event "restage.local.set" { key: "k", value: 1 }),
]);
''',
      }),
      isEmpty,
    );
  });

  test('a reserved commerce event is a gap', () {
    expect(
      gaps({
        'welcome': welcome,
        'goal': '''
widget OnboardingScreen = Button(onPressed: event "purchase" {});
''',
      }),
      ['event "purchase" on screen "goal" in state "goal"'],
    );
  });

  test(
      'an event the state showing the screen does not handle is a gap, '
      'wherever it is emitted', () {
    expect(
      gaps({
        'welcome': welcome.replaceFirst('"next"', '"continue"'),
        'goal': '''
widget OnboardingScreen = Column(children: [
  Button(onPressed: event "next" {}),
  Button(onPressed: event "skip" {}),
]);
widget component_1 = Button(onPressed: event "onPressed" {});
''',
      }),
      [
        'event "next" on screen "goal" in state "goal"',
        'event "onPressed" on screen "goal" in state "goal"',
        'event "skip" on screen "goal" in state "goal"',
        'event "continue" on screen "welcome" in state "welcome"',
      ],
    );
  });

  test('the message groups events by screen and state', () {
    expect(
      flowScreenEventGapsMessage('welcome_flow', const [
        FlowScreenEventGap(state: 'plan', screen: 'plan', event: 'next'),
        FlowScreenEventGap(state: 'goal', screen: 'goal', event: 'skip'),
        FlowScreenEventGap(state: 'plan', screen: 'plan', event: 'later'),
      ]),
      'The flow "welcome_flow" does not handle every event its screens emit:\n'
      '- the screen "goal" in the state "goal" emits "skip"\n'
      '- the screen "plan" in the state "plan" emits "later" and "next"\n'
      'Add a transition for each event in that state, or declare it as a '
      'custom event if the app handles it.',
    );
  });

  test('an event the same screen of the base already emits is no gap', () {
    final unhandled = welcome.replaceFirst('"later"', '"legacy"');
    expect(gaps({'welcome': unhandled, 'goal': goal}), [
      'event "legacy" on screen "welcome" in state "welcome"',
    ]);
    expect(
      gaps(
        {'welcome': unhandled, 'goal': goal},
        base: {'welcome': unhandled, 'goal': goal},
      ),
      isEmpty,
    );
    // The base emitted it on another screen.
    expect(
      gaps(
        {'welcome': welcome, 'goal': goal.replaceFirst('"done"', '"legacy"')},
        base: {'welcome': unhandled, 'goal': goal},
      ),
      ['event "legacy" on screen "goal" in state "goal"'],
    );
  });
}

const Map<String, FlowState> _states = {
  'welcome': ScreenFlowState(
    screen: 'welcome',
    on: {
      'next': FlowTransition.goto('goal'),
      'later': FlowTransition.goto('done'),
    },
  ),
  'goal': ScreenFlowState(
    screen: 'goal',
    on: {'done': FlowTransition.goto('welcome')},
  ),
  'done': EndFlowState(result: {}),
};

FlowSurfacePayload _flow(
  Map<String, String> screens, {
  Map<String, FlowState> states = _states,
}) {
  final blobs = {
    for (final MapEntry(key: id, value: library) in screens.entries)
      id: encodeLibraryBlob(parseLibraryFile('import core;\n$library')),
  };
  return FlowSurfacePayload(
    flowDocument: FlowDocument(
      flow: 'welcome_flow',
      version: 1,
      schemaVersion: 1,
      minClient: 3,
      initial: 'welcome',
      screenArtifacts: {
        for (final MapEntry(key: id, value: blob) in blobs.entries)
          id: ScreenArtifact(
            path: '$id.rfw',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: FlowContentHash.compute(blob),
          ),
      },
      states: states,
      outbound: const FlowOutboundDeclarations(
        customEvents: {'dismiss': FlowOutboundPayloadDeclaration()},
      ),
    ),
    screenBlobs: <String, Uint8List>{...blobs},
  );
}
