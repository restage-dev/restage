import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A generated part may not declare anything it does not use.
///
/// A private declaration nothing references is dead weight in the consumer's
/// source tree and an analyzer warning in their build. The assertion here is
/// the property, not the absence of one known name, so a future emitter that
/// leaves a different unreferenced declaration behind fails the same way.
void main() {
  test('a general-mode flow part declares nothing it does not use', () async {
    expect(
      _declaredAndNeverUsed(await _generatedPart(_generalFlowSources())),
      isEmpty,
    );
  });

  test('a typed flow part declares nothing it does not use', () async {
    expect(
      _declaredAndNeverUsed(await _generatedPart(_typedFlowSources())),
      isEmpty,
    );
  });
}

/// Private names [part] mentions exactly once.
///
/// Generated code declares its own private names, so a single occurrence is a
/// declaration nothing ever reads — dead weight in the consumer's tree and an
/// `unused_element` warning in their build. Asserting the property rather than
/// one known name means a future emitter leaving a different unreferenced
/// declaration behind fails the same way.
Set<String> _declaredAndNeverUsed(String part) {
  final counts = <String, int>{};
  for (final match in RegExp(r'\b_[A-Za-z0-9_]+\b').allMatches(part)) {
    counts.update(match.group(0)!, (count) => count + 1, ifAbsent: () => 1);
  }
  return {
    for (final entry in counts.entries)
      if (entry.value == 1) entry.key,
  };
}

Future<String> _generatedPart(Map<String, String> sources) async {
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
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue);
  return result.readerWriter.testing.readString(
    AssetId(
      'apps_examples',
      'lib/onboarding/flows/restage.generated/first_run.restage.g.dart',
    ),
  );
}

String _screenSource(String id, String className, String event) => '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/$id.restage.g.dart';

@Screen(id: '$id', surface: Surface.general)
final class $className extends StatelessWidget {
  const $className({super.key});

  static const $event = SurfaceEvent<void>('$event');

  @override
  Widget build(BuildContext context) => const SizedBox(width: 1, height: 1);
}
''';

Map<String, String> _flowSources({required String delivery}) => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _screenSource('welcome', 'WelcomeScreen', 'next'),
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'restage.generated/first_run.restage.g.dart';

@FlowGraph(id: 'first_run', surface: Surface.general$delivery)
const firstRun = FlowDefinition(
  start: WelcomeScreen,
  transitions: [
    Transition.complete(WelcomeScreen.next),
  ],
);
''',
    };

Map<String, String> _generalFlowSources() =>
    _flowSources(delivery: ', delivery: FlowDeliveryMode.general');

Map<String, String> _typedFlowSources() => _flowSources(delivery: '');
