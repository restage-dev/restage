import 'dart:convert';
import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/onboarding/general_discipline_validators.dart'
    show OutboundSinkClass, kOutboundSlotSinks;
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Build-time general discipline: analytics-reaching outbound surfaces
/// (`customEvents` / `surveyAnswers` / `lifecycle`) must be event-args only,
/// and a host-seeded flow-state key must never egress via `terminalResult`.
/// General-only; typed flows get NO new failure modes.
void main() {
  group('analytics-sink invariant (general-only, all analytics-reaching slots)',
      () {
    for (final slot in const ['customEvents', 'surveyAnswers', 'lifecycle']) {
      test('a flow-state ref in $slot fails the build (general)', () async {
        final result = await _build(
          _sources(
            delivery: 'general',
            flowStateBlock: _internalState('secret', 'FlowDataType.string'),
            outboundBlock: _analyticsSlotWithStateRef(slot, 'secret'),
          ),
        );
        expect(result.succeeded, isFalse);
        expect(result.logs, contains('[generalAnalyticsSinkStateRef]'));
        // The message names the canonical trap so the author sees the rule.
        expect(result.logs, contains('surveyAnswers'));
      });
    }

    test('the corrected form (event-args ref in customEvents) builds (general)',
        () async {
      final result = await _build(
        _sources(
          delivery: 'general',
          flowStateBlock: '',
          outboundBlock: '''
        customEvents: {
          'evt': FlowOutboundPayloadDeclaration(
            fields: {
              'ctaId': FlowOutboundField(
                type: FlowDataType.string,
                ref: EventFlowOutboundRef(key: 'ctaId'),
              ),
            },
          ),
        },
''',
        ),
      );
      expect(result.succeeded, isTrue);
      expect(result.logs, isNot(contains('[generalAnalyticsSinkStateRef]')));
    });

    test(
        'an IDENTICAL violating customEvents state-ref builds clean when TYPED',
        () async {
      final result = await _build(
        _sources(
          delivery: 'typed',
          flowStateBlock: _internalState('secret', 'FlowDataType.string'),
          outboundBlock: _analyticsSlotWithStateRef('customEvents', 'secret'),
        ),
      );
      expect(result.succeeded, isTrue);
      expect(result.logs, isNot(contains('[generalAnalyticsSinkStateRef]')));
    });
  });

  group('branch-only provenance (host-seeded state must not egress via result)',
      () {
    test('a host-seeded state ref in terminalResult fails the build (general)',
        () async {
      final result = await _build(
        _sources(
          delivery: 'general',
          flowStateBlock: '''
        'userId': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
          hostSeedable: true,
        ),
''',
          outboundBlock: '''
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'uid': FlowOutboundField(
              type: FlowDataType.string,
              ref: StateFlowOutboundRef(key: 'userId'),
            ),
          },
        ),
''',
        ),
      );
      expect(result.succeeded, isFalse);
      expect(result.logs, contains('[generalHostSeededResultRef]'));
      // The message names the offending outbound field.
      expect(result.logs, contains('uid'));
    });

    test('a non-seedable (in-flow-captured) result state ref builds (general)',
        () async {
      final result = await _build(
        _sources(
          delivery: 'general',
          flowStateBlock: '''
        'completed': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.exportable,
        ),
''',
          outboundBlock: '''
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'completed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: StateFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
''',
        ),
      );
      expect(result.succeeded, isTrue);
      expect(result.logs, isNot(contains('[generalHostSeededResultRef]')));
    });

    test(
        'a host-seeded result ref remains accepted in TYPED mode with a '
        'declared fallback', () async {
      final result = await _build(
        _sources(
          delivery: 'typed',
          flowStateBlock: '''
        'userId': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
          hostSeedable: true,
          // Typed decoding must have a value even when the host supplies no
          // seed; this keeps the test focused on the general-only provenance
          // rule rather than an unavailable typed result field.
          defaultValue: '',
        ),
''',
          outboundBlock: '''
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'uid': FlowOutboundField(
              type: FlowDataType.string,
              ref: StateFlowOutboundRef(key: 'userId'),
            ),
          },
        ),
''',
        ),
      );
      expect(result.succeeded, isTrue);
      expect(result.logs, isNot(contains('[generalHostSeededResultRef]')));
    });
  });

  group('close-the-class guard', () {
    test('every serialized outbound slot is classified', () {
      // The wire format is the authoritative slot registry: encode a
      // FlowOutboundDeclarations with every slot populated and assert each
      // emitted key is classified in kOutboundSlotSinks. Coverage caveat (Dart
      // has no field reflection): this catches a new slot once it is SERIALIZED
      // here; a future slot added with an empty default that this fixture does
      // not populate escapes until first use. The honest guard, not a full
      // by-construction net.
      final document = FlowDocument(
        flow: 'x',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        initial: 'a',
        flowState: const {
          's': FlowStateDeclaration(
            type: FlowDataType.string,
            classification: FlowStateClassification.internal,
          ),
        },
        outbound: const FlowOutboundDeclarations(
          actionArgs: {'act': _payload},
          terminalResult: _payload,
          lifecycle: _payload,
          surveyAnswers: _payload,
          subFlowResult: _payload,
          customEvents: {'evt': _payload},
        ),
        screenArtifacts: {
          'a': ScreenArtifact(
            path: 'a.rfw',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: FlowContentHash.compute(_bytes),
          ),
        },
        states: const {
          'a': ScreenFlowState(screen: 'a', on: {}),
        },
      );
      final json = jsonDecode(
        utf8.decode(FlowDocumentCodec.encodeCanonicalJson(document)),
      ) as Map<String, Object?>;
      final outbound = json['outbound']! as Map<String, Object?>;
      for (final key in outbound.keys) {
        expect(
          kOutboundSlotSinks.containsKey(key),
          isTrue,
          reason:
              'outbound slot "$key" is not classified in kOutboundSlotSinks',
        );
      }
      // And the three analytics-reaching slots are exactly those.
      final analytics = kOutboundSlotSinks.entries
          .where((e) => e.value == OutboundSinkClass.analyticsReaching)
          .map((e) => e.key)
          .toSet();
      expect(analytics, {'customEvents', 'surveyAnswers', 'lifecycle'});
    });
  });
}

const _payload = FlowOutboundPayloadDeclaration(
  fields: {
    'f': FlowOutboundField(
      type: FlowDataType.string,
      ref: StateFlowOutboundRef(key: 's'),
    ),
  },
);

final Uint8List _bytes = Uint8List.fromList(const [1, 2, 3]);

String _internalState(String key, String type) => '''
        '$key': FlowStateDeclaration(
          type: $type,
          classification: FlowStateClassification.internal,
        ),
''';

String _analyticsSlotWithStateRef(String slot, String stateKey) {
  const field = '''
FlowOutboundField(
                type: FlowDataType.string,
                ref: StateFlowOutboundRef(key: '__KEY__'),
              )''';
  final f = field.replaceAll('__KEY__', stateKey);
  if (slot == 'customEvents') {
    return '''
        customEvents: {
          'evt': FlowOutboundPayloadDeclaration(
            fields: {'leaked': $f},
          ),
        },
''';
  }
  return '''
        $slot: FlowOutboundPayloadDeclaration(
          fields: {'leaked': $f},
        ),
''';
}

Map<String, String> _sources({
  required String delivery,
  required String flowStateBlock,
  required String outboundBlock,
}) {
  final deliveryArg =
      delivery == 'general' ? ', delivery: FlowDeliveryMode.general' : '';
  final flowStateArg = flowStateBlock.isEmpty
      ? ''
      : 'flowState: const {\n$flowStateBlock      },';
  return {
    'apps_examples|lib/onboarding/screens/welcome.dart':
        _screenSource('welcome', 'WelcomeScreen', 'next'),
    'apps_examples|lib/onboarding/screens/ready.dart':
        _screenSource('ready', 'ReadyScreen', 'start'),
    'apps_examples|lib/onboarding/flows/disc_flow.dart': '''
import 'package:restage/restage.dart';

import '../screens/ready.dart';
import '../screens/welcome.dart';

part 'restage.generated/disc_flow.restage.g.dart';

@FlowSource(id: 'disc_flow', version: 1, minClient: 3$deliveryArg)
final class DiscFlow extends RestageFlow {
  const DiscFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      $flowStateArg
      outbound: const FlowOutboundDeclarations(
$outboundBlock      ),
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .goTo(ReadyScreenDescriptor.ref),
        screen(ReadyScreenDescriptor.ref)
            .on(ReadyScreen.start)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''',
  };
}

// --- harness --------------------------------------------------------------

typedef _BuildResult = ({bool succeeded, String logs});

Future<_BuildResult> _build(Map<String, String> sources) async {
  final logs = <LogRecord>[];
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  final result = await testBuilders(
    [
      onboardingScreenBuilder(BuilderOptions.empty),
      onboardingFlowBuilder(BuilderOptions.empty),
      restagePackageSurfaceCompilerBuilder(BuilderOptions.empty),
      restageGeneratedDartBuilder(BuilderOptions.empty),
    ],
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    onLog: logs.add,
  );
  return (
    succeeded: result.succeeded,
    logs: logs.map((log) => log.message).join('\n'),
  );
}

String _screenSource(String id, String className, String eventName) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/$id.restage.g.dart';

@ScreenSource(id: '$id')
final class $className extends StatelessWidget {
  static const $eventName = OnboardingEvent<void>('$eventName');

  const $className({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: onboardingEvent($eventName),
          child: const Text('$className'),
        ),
      );
}
''';
