import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Proves the generic flow-authoring container: a flow authored with the
/// generic `@FlowSource` / `@ScreenSource` annotations emits the same flow
/// artifacts as the (now deprecated) onboarding-named annotations. The runtime
/// + IR are already generic; this guards the authoring-annotation surface.
void main() {
  group('generic flow container', () {
    test('@FlowSource flow emits a descriptor and canonical flow JSON',
        () async {
      final sources = _twoScreenFlowSources(useGenericNames: true);
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      final generated = result.readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'lib/onboarding/flows/first_run.rsflow.g.dart',
        ),
      );
      expect(
        generated,
        allOf(
          contains("part of 'first_run.dart';"),
          contains('abstract final class FirstRunFlowDescriptor'),
        ),
      );

      final jsonBytes = result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/onboarding/flows/first_run.flow.json'),
      );
      expect(jsonBytes, isNotEmpty);
    });

    test(
        'deprecated @OnboardingFlow/@OnboardingSource aliases emit '
        'byte-identical flow JSON', () async {
      final genericBytes = await _flowJsonFor(useGenericNames: true);
      final aliasBytes = await _flowJsonFor(useGenericNames: false);

      expect(genericBytes, isNotEmpty);
      expect(aliasBytes, genericBytes);
    });
  });
}

Future<Uint8List> _flowJsonFor({required bool useGenericNames}) async {
  final sources = _twoScreenFlowSources(useGenericNames: useGenericNames);
  final readerWriter = await _readerWriterWith(sources);

  final result = await testBuilders(
    [
      onboardingScreenBuilder(BuilderOptions.empty),
      onboardingFlowBuilder(BuilderOptions.empty),
    ],
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );

  return result.readerWriter.testing.readBytes(
    AssetId('apps_examples', 'assets/onboarding/flows/first_run.flow.json'),
  );
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

/// A tiny two-screen flow. Only the annotation NAMES vary by
/// [useGenericNames]; the ids, class names, and build bodies are identical, so
/// the emitted artifacts must be byte-identical regardless of which name family
/// authored them (the annotation name never reaches the generated output).
Map<String, String> _twoScreenFlowSources({required bool useGenericNames}) {
  final screenAnnotation =
      useGenericNames ? 'ScreenSource' : 'OnboardingSource';
  final flowAnnotation = useGenericNames ? 'FlowSource' : 'OnboardingFlow';
  return {
    'apps_examples|lib/onboarding/screens/welcome.dart':
        _screenSource('welcome', 'WelcomeScreen', 'next', screenAnnotation),
    'apps_examples|lib/onboarding/screens/ready.dart':
        _screenSource('ready', 'ReadyScreen', 'start', screenAnnotation),
    'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/ready.dart';
import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@$flowAnnotation(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  const FirstRunFlow();

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
}

String _screenSource(
  String id,
  String className,
  String eventName,
  String annotation,
) =>
    '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part '$id.rsscreen.g.dart';

@$annotation(id: '$id')
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
