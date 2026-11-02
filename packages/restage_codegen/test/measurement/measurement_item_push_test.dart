import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_cli/src/publication/publication_outputs.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show
        kMeasurementPublicationItemArgumentKeyV1,
        kMeasurementPublicationRouteArgumentKeyV1;
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

import '../helpers.dart';

const _package = 'apps_examples';

const _hostPlans = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/host_plans.restage.g.dart';

final class Plan {
  const Plan({required this.id, required this.title});

  final String id;
  final String title;
}

@Screen(id: 'host_plans', surface: Surface.general)
final class HostPlans extends StatelessWidget {
  const HostPlans({required this.plans, super.key});

  final List<Plan> plans;

  static const selectPlan = SurfaceEvent<String>('selectPlan');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final plan in plans)
            InkWell(
              onTap: surfaceEvent(selectPlan, plan.id),
              child: Text(plan.title),
            ),
        ],
      );
}
''';

const _staticPlans = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/static_plans.restage.g.dart';

@Screen(id: 'static_plans', surface: Surface.general)
final class StaticPlans extends StatelessWidget {
  const StaticPlans({super.key});

  static const pick = SurfaceEvent<String>('pick');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final plan in const ['yearly', 'monthly'])
            TextButton(
              key: ValueKey(plan),
              onPressed: surfaceEvent(pick, plan),
              child: Text(plan),
            ),
        ],
      );
}
''';

void main() {
  test('per-item taps build and assemble a measured push', () async {
    final sources = {
      '$_package|lib/surfaces/host_plans.dart': _hostPlans,
      '$_package|lib/surfaces/static_plans.dart': _staticPlans,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: _package,
    );
    final result = await testBuilders(
      [
        restageSourceRosterBuilder(BuilderOptions.forRoot),
        userCatalogJsonBuilder(BuilderOptions.empty),
        restagePackageSurfaceCompilerBuilder(
          BuilderOptions.forRoot,
        ),
        restageGeneratedDartBuilder(BuilderOptions.empty),
        restageOutputsBuilder(BuilderOptions.empty),
      ],
      sources,
      rootPackage: _package,
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

    List<int> read(String path) =>
        readerWriter.testing.readBytes(AssetId(_package, path));
    const indexPath = '.restage/build/metadata/restage.outputs.json';
    final outputIndex = RestageOutputIndex.decodeJson(
      String.fromCharCodes(read(indexPath)),
    );
    final root = await Directory.systemTemp.createTemp('item_push_');
    addTearDown(() => root.delete(recursive: true));
    File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: $_package\n');
    for (final path in {
      kRestageSurfacePublicationCompilerBundlePath,
      kRestageMeasurementCompilerOutputPath,
      indexPath,
      '.restage/build/metadata/restage.publication.json',
      '.restage/build/metadata/restage.measurement.index.json',
      ...outputIndex.entries.map((entry) => entry.bundle),
    }) {
      final file = File(p.join(root.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(read(path));
    }

    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: root,
    );
    for (final slug in ['host_plans', 'static_plans']) {
      final entry = loaded.manifest.publications.singleWhere(
        (entry) => entry.publication.slug == slug,
      );
      final assembled = await SurfacePublicationAssembler().assemble(
        loaded: loaded,
        entry: entry,
      );
      expect(assembled.measurementUpload, isNotNull, reason: slug);
      final items = <String, List<Object?>>{};
      for (final MapEntry(:key, :value) in assembled.artifactBytes.entries) {
        if (!key.endsWith('.rfw')) continue;
        void walk(Object? node) {
          switch (node) {
            case fmt.EventHandler(:final eventArguments):
              final route =
                  eventArguments[kMeasurementPublicationRouteArgumentKeyV1];
              if (route is String) {
                (items[route] ??= []).add(
                  eventArguments[kMeasurementPublicationItemArgumentKeyV1],
                );
              }
            case fmt.ConstructorCall(:final arguments):
              arguments.values.forEach(walk);
            case fmt.Loop(:final output):
              walk(output);
            case final List<Object?> list:
              list.forEach(walk);
            case final Map<Object?, Object?> map:
              map.values.forEach(walk);
          }
        }

        for (final widget in fmt.decodeLibraryBlob(value).widgets) {
          walk(widget.root);
        }
      }
      // A host-data loop taps on one element; a static list's elements share
      // one route, each with its own item.
      expect(
        items.values.single.map((item) => item.toString()),
        slug == 'static_plans' ? ['yearly', 'monthly'] : [isNotEmpty],
        reason: slug,
      );
    }
  });
}
