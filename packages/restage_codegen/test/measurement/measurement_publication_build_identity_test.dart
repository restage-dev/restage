import 'package:build/build.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _policyOptions = BuilderOptions({
  kMeasurementMinimumClientOption: 1,
  kMeasurementPrivacyPolicyRevisionOption: 'privacy.automatic-v1',
  kMeasurementCollectionBudgetRevisionOption: 'budget.automatic-v1',
});

void main() {
  test('route identities do not depend on unpublished local build count',
      () async {
    const button = 'FilledButton(onPressed: surfaceEvent(activate), '
        "child: Text('Go'))";
    const oneEvent = 'Column(children: [$button])';
    const twoEvents = 'Column(children: [$button, '
        "TextButton(onPressed: surfaceEvent(activate), child: Text('Skip'))])";
    Future<RestageMeasurementCompilerOutputV1> build(
      String body, [
      RestageMeasurementCompilerOutputV1? prior,
    ]) async {
      final result = await _compile(
        {
          'apps_examples|lib/features/first.dart': _screen(body: body),
        },
        priorOutput: prior,
      );
      expect(
        result.result.succeeded,
        isTrue,
        reason: result.result.errors.join('\n'),
      );
      expect(result.output.valid, isTrue);
      return result.output;
    }

    final initial = await build(oneEvent);
    expect(
      _operations(initial),
      everyElement(LineageOperation.continueLineage),
    );
    final stable = await build(oneEvent, initial);
    _expectSameRoutes(initial, stable);
    final added = await build(twoEvents, stable);
    final addedAgain = await build(twoEvents, added);
    final addedThird = await build(twoEvents, addedAgain);
    expect(_operations(added), everyElement(LineageOperation.continueLineage));
    expect(
      _operations(addedAgain),
      everyElement(LineageOperation.continueLineage),
    );
    _expectSameRoutes(added, addedAgain);
    _expectSameRoutes(addedAgain, addedThird);
    final removed = await build(oneEvent, addedThird);
    final removedAgain = await build(oneEvent, removed);
    final removedThird = await build(oneEvent, removedAgain);
    expect(
      _operations(removed),
      everyElement(LineageOperation.continueLineage),
    );
    expect(
      _operations(removedAgain),
      everyElement(LineageOperation.continueLineage),
    );
    _expectSameRoutes(removed, removedAgain);
    _expectSameRoutes(removedAgain, removedThird);
  });
}

Iterable<LineageOperation> _operations(
  RestageMeasurementCompilerOutputV1 output,
) =>
    output.publications.single.draft.lineageIntents
        .map((intent) => intent.operation);

void _expectSameRoutes(
  RestageMeasurementCompilerOutputV1 first,
  RestageMeasurementCompilerOutputV1 repeated,
) {
  final left = first.publications.single.draft;
  final right = repeated.publications.single.draft;
  expect(right.canonicalBytes, orderedEquals(left.canonicalBytes));
  expect(right.routeDraftClosureDigest, left.routeDraftClosureDigest);
  expect(right.routes, orderedEquals(left.routes));
  expect(right.presentationRoutes, orderedEquals(left.presentationRoutes));
  expect(right.artifacts, orderedEquals(left.artifacts));
  expect(
    MeasurementPublicationDraftV1.fromCanonicalBytes(right.canonicalBytes),
    right,
  );
  expect(right.routeDraftClosureDigest, right.routePlan.canonicalDigest);
}

String _screen({required String body}) {
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/first.restage.g.dart';

@Screen(id: 'first', surface: Surface.general)
final class FirstScreen extends StatelessWidget {
  const FirstScreen({super.key});

  static const activate = SurfaceEvent<void>('activate');

  @override
  Widget build(BuildContext context) => $body;
}
''';
}

Future<
    ({
      TestBuilderResult result,
      RestageMeasurementCompilerOutputV1 output,
    })> _compile(
  Map<String, String> sources, {
  RestageMeasurementCompilerOutputV1? priorOutput,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final result = await testBuilder(
    const PackageSurfaceCompilerBuilder(_policyOptions),
    {
      ...sources,
      if (priorOutput != null)
        'apps_examples|$kRestageMeasurementCompilerLedgerSourcePath':
            priorOutput.encodeCanonicalJson(),
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
    readerWriter.testing.readBytes(
      AssetId('apps_examples', kRestageMeasurementCompilerOutputPath),
    ),
  );
  return (result: result, output: output);
}
