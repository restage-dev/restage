import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _package = 'apps_examples';

// A build with an early return and a returned switch renders one of three
// paths; each path's tap is its own measured occurrence.
const _paths = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/paths.restage.g.dart';

@Screen(id: 'paths', surface: Surface.general)
final class Paths extends StatelessWidget {
  const Paths({required this.step, required this.flag, super.key});

  final String? step;
  final bool flag;

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) {
    if (step == null) {
      return TextButton(onPressed: context.surfaceEvent(next), child: const Text('none'));
    }
    return switch (flag) {
      true => TextButton(onPressed: context.surfaceEvent(next), child: const Text('on')),
      false => TextButton(onPressed: context.surfaceEvent(next), child: const Text('off')),
    };
  }
}
''';

// A list a helper builds from one the build computes renders from the app;
// the taps around it are measured.
const _spread = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/spread.restage.g.dart';

List<Widget> rows(List<String> names) => [for (final name in names) Text(name)];

@Screen(id: 'spread', surface: Surface.general)
final class Spread extends StatelessWidget {
  const Spread({required this.names, super.key});

  final List<String> names;

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => Column(children: [
        TextButton(onPressed: context.surfaceEvent(next), child: const Text('go')),
        Column(children: [
          const Text('h'),
          ...rows([
            for (final n in names)
              if (n != 'a') n,
          ]),
        ]),
      ]);
}
''';

Future<RestageMeasurementCompilerOutputV1> _measured(
  String path,
  String source,
) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
  );
  final result = await testBuilders(
    [
      restageSourceRosterBuilder(BuilderOptions.forRoot),
      userCatalogJsonBuilder(BuilderOptions.empty),
      restagePackageSurfaceCompilerBuilder(BuilderOptions.forRoot),
    ],
    {'$_package|$path': source},
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
  expect(output.publications, hasLength(1));
  return output;
}

Iterable<Object?> _tapRoutes(RestageMeasurementCompilerOutputV1 output) =>
    output.publications.single.routePlan.routes.where(
      (route) => route.orderedCaptureV1?.lifecycleChannel == null,
    );

void main() {
  test('a spread the app builds leaves its surface measured', () async {
    final output = await _measured('lib/surfaces/spread.dart', _spread);
    expect(_tapRoutes(output), hasLength(1));
  });

  test('each path a build returns compiles measured', () async {
    final output = await _measured('lib/surfaces/paths.dart', _paths);
    expect(_tapRoutes(output), hasLength(3));
  });
}
