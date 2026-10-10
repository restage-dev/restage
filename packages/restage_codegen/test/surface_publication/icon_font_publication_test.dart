import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/favorites.restage.g.dart';

@Screen(surface: Surface.general)
final class FavoritesNotice extends StatelessWidget {
  const FavoritesNotice({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => Row(
        children: const [
          Icon(Icons.favorite),
          Icon(Icons.chevron_left_rounded),
        ],
      );
}
''';

void main() {
  test('a surface with literal icons publishes their subset font', () async {
    final sources = {'apps_examples|lib/features/favorites.dart': _screen};
    final readerWriter =
        await readerWriterWithFilesystemSources(rootPackage: 'apps_examples');
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

    final handoff = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
              'apps_examples', kRestageSurfacePublicationCompilerBundlePath),
        ),
      ),
    );
    expect(handoff.valid, isTrue, reason: handoff.errors.join('\n'));
    final manifest = handoff.manifest!;
    final entry = manifest.publications.single;
    final font = entry.artifacts.singleWhere(
      (artifact) => artifact.role == SurfacePublicationArtifactRole.iconFont,
    );
    expect(font.id, 'MaterialIcons');
    expect(font.path, endsWith('.icon-fonts/MaterialIcons.otf'));

    final files = {...handoff.artifacts, ...handoff.borrowedArtifacts};
    final closure = manifest.validateArtifactClosure(files).single;
    final fontBytes = closure.iconFonts.single.bytes;
    // Icons.favorite and Icons.chevron_left_rounded.
    expect(readSfntCoveredCodePoints(fontBytes), {0xe25b, 0xf63a});
    expect(
      entry.publication.capabilities!.builtInFloor,
      10,
      reason: 'The Row catalog entry requires version 10.',
    );
  });
}
