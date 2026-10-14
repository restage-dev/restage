@Timeout(Duration(minutes: 5))
library;

import 'package:build/build.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A message screen whose buttons emit [emitted], each declared as an event.
String _screen(List<String> emitted) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/notice.restage.g.dart';

@Screen(surface: Surface.message)
final class NoticeScreen extends StatelessWidget {
  const NoticeScreen({super.key});

  static const done = SurfaceEvent<void>('done');
${[
      for (final event in emitted)
        "  static const ${_field(event)} = SurfaceEvent<void>('$event');",
    ].join('\n')}

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextButton(onPressed: surfaceEvent(done), child: const Text('Done')),
${[
      for (final event in emitted)
        '          TextButton(onPressed: surfaceEvent(${_field(event)}), '
            "child: const Text('$event')),",
    ].join('\n')}
        ],
      );
}
''';

String _field(String event) => '${event}Event';

/// The compact form: `done` completes; [extra] adds transitions and
/// [outbound] declares custom events.
String _compactFlow({String extra = '', String outbound = ''}) => '''
import 'package:restage/restage.dart';

import '../screens/notice.dart';

part 'restage.generated/notice_flow.restage.g.dart';

@FlowGraph(surface: Surface.message)
const noticeFlow = FlowDefinition(
  start: NoticeScreen,
  transitions: [
    Transition.complete(NoticeScreen.done),
$extra
  ],
  outbound: FlowOutboundPolicy($outbound),
);
''';

/// The builder form: `done` completes; [extra] adds `.on` transitions to the
/// screen state and [outbound] declares custom events.
String _builderFlow({String extra = '', String outbound = ''}) => '''
import 'package:restage/restage.dart';

import '../screens/notice.dart';

part 'restage.generated/notice_flow.restage.g.dart';

@FlowGraph(surface: Surface.message)
final class NoticeFlow extends RestageFlow {
  const NoticeFlow();

  @override
  FlowDef buildFlow() {
    final finish = endState('end');
    return flow(
      initial: noticeScreenRef,
      outbound: const FlowOutboundDeclarations($outbound),
      states: [
        screen(noticeScreenRef)
            .on(NoticeScreen.done)
            .goTo(finish)
$extra,
        end(finish, result: {}),
      ],
    );
  }
}
''';

void main() {
  group('compact flow', () {
    test('warns about an event the state does not handle and builds', () async {
      final result = await _compile(['privacy'], _compactFlow());
      _expectWarned(
        result,
        'The flow "notice_flow" does not handle every event its screens emit:\n'
        '- the screen "notice" in the state "notice" emits "privacy"\n'
        'Add a transition for each event in that state, or declare it as a '
        'custom event if the app handles it.',
      );
    });

    test('accepts a declared custom event', () async {
      final result = await _compile(
        ['privacy'],
        _compactFlow(
          outbound: '''
    customEvents: {'privacy': FlowOutboundPayloadDeclaration()},
''',
        ),
      );
      _expectBuilt(result);
    });

    // Commerce names never reach this check: authored surfaces cannot emit
    // them, and the shared rule's own tests cover their exemption.
    test('accepts back', () async {
      final result = await _compile(['back'], _compactFlow());
      _expectBuilt(result);
    });

    test('warns about skip unless a transition handles it', () async {
      _expectWarned(
        await _compile(['skip'], _compactFlow()),
        '- the screen "notice" in the state "notice" emits "skip"\n',
      );
      _expectBuilt(
        await _compile(
          ['skip'],
          _compactFlow(
              extra: '    Transition.complete(NoticeScreen.skipEvent),'),
        ),
      );
    });
  });

  group('builder flow', () {
    test('warns about an event the state does not handle and builds', () async {
      final result = await _compile(['privacy', 'terms'], _builderFlow());
      _expectWarned(
        result,
        '- the screen "notice" in the state "notice" emits "privacy" and '
        '"terms"\n',
      );
    });

    test('accepts a declared custom event', () async {
      final result = await _compile(
        ['privacy'],
        _builderFlow(
          outbound: '''
        customEvents: {'privacy': FlowOutboundPayloadDeclaration()},
''',
        ),
      );
      _expectBuilt(result);
    });

    test('accepts back', () async {
      final result = await _compile(['back'], _builderFlow());
      _expectBuilt(result);
    });

    test('warns about skip unless a transition handles it', () async {
      _expectWarned(
        await _compile(['skip'], _builderFlow()),
        '- the screen "notice" in the state "notice" emits "skip"\n',
      );
      _expectBuilt(
        await _compile(
          ['skip'],
          _builderFlow(
              extra: '            .on(NoticeScreen.skipEvent)\n'
                  '            .goTo(finish)'),
        ),
      );
    });
  });

  test('leaves a paywall navigation flow to its host', () async {
    final result = await _build({
      'apps_examples|lib/paywalls/entry.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'choose_plan.dart';

@PaywallSource(id: 'entry')
class EntryPaywall extends StatelessWidget {
  const EntryPaywall({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ElevatedButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const ChoosePlanPaywall()),
        ),
        child: const Text('Choose'),
      ),
      ElevatedButton(
        onPressed: paywallEvent('privacy'),
        child: const Text('Privacy'),
      ),
      ElevatedButton(
        onPressed: paywallEvent('skip'),
        child: const Text('Skip'),
      ),
    ],
  );
}
''',
      'apps_examples|lib/paywalls/choose_plan.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'choose_plan')
class ChoosePlanPaywall extends StatelessWidget {
  const ChoosePlanPaywall({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
    });
    _expectBuilt(result);
  });
}

final _logs = <TestBuilderResult, String>{};

Future<TestBuilderResult> _compile(List<String> emitted, String flow) =>
    _build({
      'apps_examples|lib/message/screens/notice.dart': _screen(emitted),
      'apps_examples|lib/message/flows/notice_flow.dart': flow,
    });

Future<TestBuilderResult> _build(Map<String, String> sources) async {
  final writer = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final logs = <LogRecord>[];
  final result = await testBuilders(
    [
      restageCodegenBuilder(BuilderOptions.empty),
      restageSourceRosterBuilder(BuilderOptions.forRoot),
      paywallFlowBuilder(BuilderOptions.empty),
      onboardingScreenBuilder(BuilderOptions.empty),
      onboardingFlowBuilder(BuilderOptions.empty),
      messageScreenBuilder(BuilderOptions.empty),
      messageFlowBuilder(BuilderOptions.empty),
      surveyScreenBuilder(BuilderOptions.empty),
      surveyFlowBuilder(BuilderOptions.empty),
      restagePackageSurfaceCompilerBuilder(BuilderOptions.forRoot),
      restageOutputsBuilder(BuilderOptions.empty),
      restageGeneratedDartBuilder(BuilderOptions.empty),
    ],
    sources,
    rootPackage: 'apps_examples',
    readerWriter: writer,
    flattenOutput: true,
    onLog: logs.add,
    verbose: true,
  );
  _logs[result] = logs.map((entry) => entry.message).join('\n');
  return result;
}

void _expectWarned(TestBuilderResult result, String message) {
  final log = _logs[result]!;
  expect(result.succeeded, isTrue, reason: log);
  expect(log, contains(message));
}

void _expectBuilt(TestBuilderResult result) {
  final log = _logs[result]!;
  expect(result.succeeded, isTrue, reason: log);
  expect(log, isNot(contains('does not handle every event')));
}
