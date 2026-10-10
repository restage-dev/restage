import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_cli/src/publication/publication_outputs.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _package = 'apps_examples';

const _iconScreen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/star_notice.restage.g.dart';

@Screen(id: 'star_notice', surface: Surface.message)
final class StarNotice extends StatelessWidget {
  const StarNotice({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: surfaceEvent(dismiss),
        child: const Icon(Icons.star),
      );
}
''';

const _localWriteScreen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/reminder_toggle.restage.g.dart';

@Screen(id: 'reminder_toggle', surface: Surface.message)
final class ReminderToggle extends StatefulWidget {
  const ReminderToggle({super.key});

  @override
  State<ReminderToggle> createState() => _ReminderToggleState();
}

final class _ReminderToggleState extends State<ReminderToggle> {
  bool reminders = true;

  @override
  Widget build(BuildContext context) => Switch(
        value: reminders,
        onChanged: (on) => setState(() => reminders = on),
      );
}
''';

void main() {
  test(
    'surfaces with an icon font or local seeds assemble a measured push',
    () async {
      final sources = {
        '$_package|lib/features/star_notice.dart': _iconScreen,
        '$_package|lib/features/reminder_toggle.dart': _localWriteScreen,
      };
      final readerWriter =
          await readerWriterWithFilesystemSources(rootPackage: _package);
      final result = await testBuilders(
        [
          restageSourceRosterBuilder(const BuilderOptions({}, isRoot: true)),
          userCatalogJsonBuilder(BuilderOptions.empty),
          restagePackageSurfaceCompilerBuilder(
            const BuilderOptions({}, isRoot: true),
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
      final root = await Directory.systemTemp.createTemp('sections_push_');
      addTearDown(() => root.delete(recursive: true));
      File(p.join(root.path, 'pubspec.yaml'))
          .writeAsStringSync('name: $_package\n');
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
      for (final (slug, role) in [
        ('star_notice', SurfacePublicationArtifactRole.iconFont),
        ('reminder_toggle', SurfacePublicationArtifactRole.localSeeds),
      ]) {
        final entry = loaded.manifest.publications.singleWhere(
          (entry) => entry.publication.slug == slug,
        );
        expect(
          entry.artifacts.map((artifact) => artifact.role),
          contains(role),
          reason: slug,
        );

        final assembled = await SurfacePublicationAssembler().assemble(
          loaded: loaded,
          entry: entry,
        );

        expect(assembled.measurementUpload, isNotNull, reason: slug);
        expect(assembled.payload.carriesSections, isTrue, reason: slug);
      }
    },
  );
}
