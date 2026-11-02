import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _package = 'apps_examples';

const _steps = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/steps.restage.g.dart';

@Screen(id: 'steps', surface: Surface.general)
final class Steps extends StatelessWidget {
  const Steps({required this.step, super.key});

  final String step;

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => step == 'a'
      ? TextButton(onPressed: surfaceEvent(next), child: const Text('A'))
      : const Text('B');
}
''';

void main() {
  test('a conditional at the root compiles measured', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: _package,
    );
    final result = await testBuilders(
      [
        restageSourceRosterBuilder(BuilderOptions.forRoot),
        userCatalogJsonBuilder(BuilderOptions.empty),
        restagePackageSurfaceCompilerBuilder(BuilderOptions.forRoot),
      ],
      {'$_package|lib/surfaces/steps.dart': _steps},
      rootPackage: _package,
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

    final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
      readerWriter.testing.readBytes(
        AssetId(_package, kRestageMeasurementCompilerOutputPath),
      ),
    );
    expect(output.valid, isTrue, reason: output.errors.join('\n'));
    final routes = output.publications.single.routePlan.routes.where(
      (route) => route.orderedCaptureV1?.lifecycleChannel == null,
    );
    expect(routes, hasLength(1));
  });
}
