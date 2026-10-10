import 'package:build/build.dart';
import 'package:restage_codegen/src/generated_dart_builder.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/surface_publication/surface_list_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('lists every generated screen and flow reference of the package',
      () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/announcement.restage.g.dart';

@Screen(surface: Surface.general)
final class FeatureAnnouncement extends StatelessWidget {
  const FeatureAnnouncement({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('Announcement');
}
''';
    const flow = '''
import 'package:restage/restage.dart';

import '../features/announcement.dart';

part 'restage.generated/launch.restage.g.dart';

@FlowGraph(surface: Surface.general)
const launch = FlowDefinition(
  start: FeatureAnnouncement,
  transitions: [
    Transition.complete(FeatureAnnouncement.dismiss),
  ],
);
''';
    final sources = <String, String>{
      'apps_examples|lib/features/announcement.dart': screen,
      'apps_examples|lib/journeys/launch.dart': flow,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    for (final builder in <Builder>[
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      RestageGeneratedDartBuilder(BuilderOptions.empty),
      const RestageSurfaceListBuilder(),
    ]) {
      final result = await testBuilder(
        builder,
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    }

    final list = readerWriter.testing.readString(
      AssetId('apps_examples', kRestageSurfaceListPath),
    );
    expect(
      list,
      contains(
        "import 'package:apps_examples/features/announcement.dart' as s0;",
      ),
    );
    expect(
      list,
      contains("import 'package:apps_examples/journeys/launch.dart' as s1;"),
    );
    expect(list, contains('    s0.featureAnnouncementRef,\n'));
    expect(list, contains('    s1.launchRef,\n'));
    expect(list, isNot(contains('PaywallRef')));
  });

  test('emits paywalls by id and references in a stable order', () {
    final source = emitRestageSurfaceList(
      package: 'app',
      paywallIds: const ['pro'],
      refs: const [
        SurfaceListReference(libraryPath: 'lib/b.dart', name: 'zRef'),
        SurfaceListReference(libraryPath: 'lib/a.dart', name: 'yRef'),
        SurfaceListReference(libraryPath: 'lib/b.dart', name: 'aRef'),
      ],
    );
    expect(
      source,
      endsWith('''
import 'package:restage/restage.dart' as restage;
import 'package:app/a.dart' as s0;
import 'package:app/b.dart' as s1;

/// Every surface this package compiles, for
/// `Restage.configure(surfaces: restageSurfaces)`.
final List<restage.RestageSurfaceRef> restageSurfaces =
    List<restage.RestageSurfaceRef>.unmodifiable(
  <restage.RestageSurfaceRef>[
    const restage.PaywallRef('pro'),
    s0.yRef,
    s1.aRef,
    s1.zRef,
  ],
);
'''),
    );
  });
}
