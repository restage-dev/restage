import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/neutral_part_directive.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Deprecated `*Source` libraries reach the one generated-Dart owner through
/// the package compiler, the same channel canonical sources use.
///
/// The compiler owns the generated part and borrows every delivery artifact:
/// it must never start demanding bytes another builder produces. A legacy
/// screen that no flow references is the discriminating case — it exercises
/// the demand path with nothing to satisfy it.
const String _screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@ScreenSource(id: 'welcome', version: 1, minClient: 1)
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  static const finish = OnboardingEvent<String>('finish');

  @override
  Widget build(BuildContext context) => const Text('Welcome');
}
''';

const String _flow = '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'restage.generated/welcome_flow.restage.g.dart';

@FlowSource(id: 'welcome_flow', version: 1, minClient: 1)
final class WelcomeFlow extends RestageFlow {
  const WelcomeFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: welcomeRef,
      states: [
        screen(welcomeRef).on(Welcome.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';

const String _screenPath = 'lib/onboarding/screens/welcome.dart';
const String _flowPath = 'lib/onboarding/flows/welcome_flow.dart';

void main() {
  final plan = RestageOutputPlacementPlan.fromBuilderOptions(
    BuilderOptions.empty,
  );

  test('a legacy screen no flow references still gets its generated part',
      () async {
    final sources = <String, String>{'apps_examples|$_screenPath': _screen};
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilders(
      [
        onboardingScreenBuilder(BuilderOptions.empty),
        restagePackageSurfaceCompilerBuilder(BuilderOptions.empty),
      ],
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue);

    final bundle = _handoff(result);
    expect(
      bundle.valid,
      isTrue,
      reason: 'the compiler must not demand artifacts it does not own: '
          '${bundle.errors.join('; ')}',
    );
    expect(
      bundle.ownedOutputs,
      contains(neutralPartPath(plan, _screenPath)),
      reason: 'the generated part reaches the one owner through the compiler',
    );
  });

  test(
      'a legacy flow gets its generated part, and its flow document is still '
      'the borrowed bytes', () async {
    final sources = <String, String>{
      'apps_examples|$_screenPath': _screen,
      'apps_examples|$_flowPath': _flow,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
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
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue);

    for (final library in const [_flowPath]) {
      final partPath = neutralPartPath(plan, library);
      expect(
        result.readerWriter.testing.exists(
          AssetId('apps_examples', partPath),
        ),
        isTrue,
        reason: 'the generated-Dart builder writes $partPath',
      );
      expect(
        result.readerWriter.testing.readString(
          AssetId('apps_examples', partPath),
        ),
        startsWith("part of '../${library.split('/').last}';"),
      );
    }

    // The flow document keeps its existing producer; only the generated
    // reference travels through the compiler.
    final emitted = result.readerWriter.testing.readBytes(
      AssetId(
        'apps_examples',
        'assets/onboarding/flows/welcome_flow.flow.json',
      ),
    );
    final bundle = _handoff(result);
    expect(
      bundle
          .borrowedArtifacts['assets/onboarding/flows/welcome_flow.flow.json'],
      emitted,
      reason: 'the compiler borrows the exact emitted bytes; it does not '
          'recompile the document',
    );

    // Inspection text is not a delivery artifact, so it never joins a
    // manifest closure and travels as an owned output — the same route the
    // canonical frontend uses to get it into a bundle.
    const screenText = 'assets/onboarding/screens/welcome.rfwtxt';
    expect(
      bundle.ownedOutputs,
      contains(screenText),
      reason: "a deprecated library's bundle carries its rfw text like every "
          'other library',
    );
    expect(
      bundle.ownedOutputs[screenText],
      result.readerWriter.testing.readBytes(
        AssetId('apps_examples', screenText),
      ),
      reason: 'the carried text is the exact bytes its own builder emitted',
    );
  });
}

RestageSurfacePublicationBundle _handoff(TestBuilderResult result) =>
    RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        result.readerWriter.testing.readString(
          AssetId(
            'apps_examples',
            kRestageSurfacePublicationCompilerBundlePath,
          ),
        ),
      ),
    );
