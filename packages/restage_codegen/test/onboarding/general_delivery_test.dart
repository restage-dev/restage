import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Codegen coverage for `delivery: FlowDeliveryMode.general` authoring: the
/// document stamp, the untyped identity-decode descriptor leg, and typed-mode
/// invisibility (typed output omits the marker entirely).
void main() {
  group('general delivery mode', () {
    test('stamps deliveryMode:general on the emitted document', () async {
      final json = await _buildFlowJson(_generalSources());
      expect(json, contains('"deliveryMode":"general"'));
    });

    test('typed delivery omits the deliveryMode key entirely', () async {
      final json = await _buildFlowJson(_typedSources());
      expect(json, isNot(contains('deliveryMode')));
    });

    test(
        'emits an untyped Map descriptor leg — SurfaceFlowRef<Map>, identity '
        'decode, and no generated result class', () async {
      final generated = await _buildFlowDart(_generalSources());
      expect(
        generated,
        allOf(
          contains('SurfaceFlowRef<Map<String, Object?>>'),
          contains('surface: Surface.onboarding'),
          contains(
            'decodeResult: GeneralFirstRunFlowDescriptor._decodeResult',
          ),
          contains(
            'static Map<String, Object?> _decodeResult(Map<String, Object?> '
            'result) =>',
          ),
        ),
      );
      // No typed result class is generated for a general flow (the host reads
      // the untyped Map directly).
      expect(generated, isNot(contains('class GeneralFirstRunResult')));
    });

    test('the generated identity decoder returns its input map unchanged',
        () async {
      final generated = await _buildFlowDart(_generalSources());
      await _assertIdentityDecoderRuns(generated);
    });

    test(
        'the general registry installs both channels — FlowActionRegistry AND '
        'FlowSignalRegistry with the enumerated signal names', () async {
      final generated = await _buildFlowDart(_generalSources());
      expect(
        generated,
        allOf(
          contains(
            'class GeneralFirstRunActions implements FlowActionRegistry, '
            'FlowSignalRegistry',
          ),
          contains('installedSignalNames'),
          contains("'skip'"),
          // Even with no host actions, the registry is a passable
          // FlowActionRegistry (empty bindings) so both channels ride it.
          contains('flowActionBindings'),
        ),
      );
    });

    test('a typed flow registry gains no FlowSignalRegistry (unchanged)',
        () async {
      final generated = await _buildFlowDart(_typedSources());
      expect(generated, isNot(contains('FlowSignalRegistry')));
      expect(generated, isNot(contains('installedSignalNames')));
    });

    test(
        'the full proof — a general flow with an action + custom event + '
        'outbound codegens the stamped doc, untyped leg, and both-channel '
        'registry', () async {
      final json = await _buildFlowJson(_generalWithActionSources());
      expect(json, contains('"deliveryMode":"general"'));

      final generated = await _buildFlowDart(_generalWithActionSources());
      expect(
        generated,
        allOf(
          // Untyped identity-decode leg.
          contains('SurfaceFlowRef<Map<String, Object?>>'),
          isNot(contains('class GeneralProofResult')),
          // Both installed vocabulary channels ride the one registry: the
          // action verb binding AND the enumerated signal name.
          contains(
            'class GeneralProofActions implements FlowActionRegistry, '
            'FlowSignalRegistry',
          ),
          contains("'requestNotifications'"),
          contains('installedSignalNames'),
          contains("'skip'"),
        ),
      );
    });
  });
}

Map<String, String> _generalWithActionSources() => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/screens/ready.dart':
          _screenSource('ready', 'ReadyScreen', 'start'),
      'apps_examples|lib/onboarding/flows/general_proof.dart': '''
import 'package:restage/restage.dart';

import '../screens/ready.dart';
import '../screens/welcome.dart';

part 'general_proof.rsflow.g.dart';

@FlowSource(
  id: 'general_proof',
  version: 1,
  minClient: 3,
  delivery: FlowDeliveryMode.general,
)
final class GeneralProofFlow extends RestageFlow {
  static const requestNotifications =
      FlowActionRef<void, bool>('requestNotifications');

  const GeneralProofFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      flowState: const {
        'completed': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.exportable,
        ),
      },
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'completed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: StateFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
        customEvents: {
          'skip': FlowOutboundPayloadDeclaration(),
        },
      ),
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .run(requestNotifications)
            .result((granted) => granted)
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

// --- fixtures -------------------------------------------------------------

Map<String, String> _generalSources() => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/screens/ready.dart':
          _screenSource('ready', 'ReadyScreen', 'start'),
      'apps_examples|lib/onboarding/flows/general_first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/ready.dart';
import '../screens/welcome.dart';

part 'general_first_run.rsflow.g.dart';

@FlowSource(
  id: 'general_first_run',
  version: 1,
  minClient: 3,
  delivery: FlowDeliveryMode.general,
)
final class GeneralFirstRunFlow extends RestageFlow {
  const GeneralFirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      flowState: const {
        'completed': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.exportable,
        ),
      },
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'completed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: StateFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
        customEvents: {
          'skip': FlowOutboundPayloadDeclaration(),
        },
      ),
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

Map<String, String> _typedSources() => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/screens/ready.dart':
          _screenSource('ready', 'ReadyScreen', 'start'),
      'apps_examples|lib/onboarding/flows/typed_first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/ready.dart';
import '../screens/welcome.dart';

part 'typed_first_run.rsflow.g.dart';

@FlowSource(id: 'typed_first_run', version: 1, minClient: 3)
final class TypedFirstRunFlow extends RestageFlow {
  const TypedFirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
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

// --- harness --------------------------------------------------------------

Future<String> _buildFlowJson(Map<String, String> sources) async {
  final stem = _flowStem(sources);
  final result = await _run(sources);
  final bytes = result.readerWriter.testing.readBytes(
    AssetId('apps_examples', 'assets/onboarding/flows/$stem.flow.json'),
  );
  return utf8.decode(bytes);
}

Future<String> _buildFlowDart(Map<String, String> sources) async {
  final stem = _flowStem(sources);
  final result = await _run(sources);
  return result.readerWriter.testing.readString(
    AssetId('apps_examples', 'lib/onboarding/flows/$stem.rsflow.g.dart'),
  );
}

Future<TestBuilderResult> _run(Map<String, String> sources) async {
  final readerWriter = await _readerWriterWith(sources);
  return testBuilders(
    [
      onboardingScreenBuilder(BuilderOptions.empty),
      onboardingFlowBuilder(BuilderOptions.empty),
    ],
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

String _flowStem(Map<String, String> sources) {
  final key = sources.keys.firstWhere((k) => k.contains('/flows/'));
  return key.split('/').last.replaceAll('.dart', '');
}

Future<TestReaderWriter> _readerWriterWith(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return readerWriter;
}

String _screenSource(String id, String className, String eventName) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part '$id.rsscreen.g.dart';

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

/// Compiles the generated general descriptor standalone and proves its
/// `decodeResult` is the identity — an arbitrary map (including keys a typed
/// decoder would reject) round-trips unchanged.
Future<void> _assertIdentityDecoderRuns(String generated) async {
  final dir = Directory('.dart_tool/general_delivery_test')
    ..createSync(recursive: true);
  final script = File('${dir.path}/general_identity_check.dart');
  final source = generated.replaceFirst(
    "part of 'general_first_run.dart';",
    "import 'package:restage/src/flow/flow_descriptors.dart';\n"
        "import 'package:restage_shared/restage_shared.dart' "
        'show FlowDeliveryMode, Surface;',
  );
  script.writeAsStringSync('''
$source

void main() {
  const input = <String, Object?>{'completed': true, 'anything': 42};
  final decoded = GeneralFirstRunFlowDescriptor.ref.decodeResult(input);
  if (!identical(decoded, input) && decoded.length != input.length) {
    throw StateError('identity decode altered the map: \$decoded');
  }
  if (decoded['completed'] != true || decoded['anything'] != 42) {
    throw StateError('identity decode dropped keys: \$decoded');
  }
}
''');

  final result = await Process.run(
    'dart',
    [script.path],
    workingDirectory: Directory.current.path,
  );
  expect(
    result.exitCode,
    0,
    reason: '${result.stdout}\n${result.stderr}',
  );
}
