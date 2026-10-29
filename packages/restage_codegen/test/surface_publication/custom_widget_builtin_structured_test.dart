import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_cli/src/publication/publication_outputs.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _package = 'apps_examples';

const _caption = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.ui'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

@RestageWidget(
  name: 'Caption',
  library: WidgetLibrary.custom('acme.ui'),
  category: WidgetCategory.decoration,
  description: 'A styled caption.',
)
class Caption extends StatelessWidget {
  const Caption({super.key, required this.text, this.style});

  @RestageProperty(description: 'The text.', required: true)
  final String text;

  @RestageProperty(description: 'The text style.')
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(text, style: style);
}
''';

const _screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/caption.dart';

part 'restage.generated/styled_notice.restage.g.dart';

@Screen(id: 'styled_notice', surface: Surface.message)
final class StyledNotice extends StatelessWidget {
  const StyledNotice({super.key});

  @override
  Widget build(BuildContext context) => const Column(
        children: [
          Caption(text: 'Hello', style: TextStyle(fontSize: 18)),
          Caption(text: 'Plain'),
        ],
      );
}
''';

void main() {
  test('a custom widget with only String and TextStyle builds and publishes',
      () async {
    final readerWriter =
        await readerWriterWithFilesystemSources(rootPackage: _package);
    final result = await testBuilders(
      [
        restageSourceRosterBuilder(BuilderOptions.forRoot),
        userCatalogJsonBuilder(BuilderOptions.empty),
        restagePackageSurfaceCompilerBuilder(BuilderOptions.forRoot),
        restageGeneratedDartBuilder(BuilderOptions.empty),
        restageOutputsBuilder(BuilderOptions.empty),
        userCatalogBuilder(BuilderOptions.forRoot),
        userFactoryBuilder(BuilderOptions.forRoot),
      ],
      {
        '$_package|lib/widgets/caption.dart': _caption,
        '$_package|lib/features/styled_notice.dart': _screen,
      },
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
    final root = await Directory.systemTemp.createTemp('builtin_structured_');
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
    final entry = loaded.manifest.publications.singleWhere(
      (entry) => entry.publication.slug == 'styled_notice',
    );
    final assembled = await SurfacePublicationAssembler().assemble(
      loaded: loaded,
      entry: entry,
    );
    expect(assembled.payload.requiredLibraries, isNotEmpty);
  });
}
