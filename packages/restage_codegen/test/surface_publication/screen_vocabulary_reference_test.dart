import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/onboarding/screen_builder.dart';
import 'package:restage_codegen/src/surface_publication/screen_contract_reference_emitter.dart';
import 'package:restage_codegen/src/surface_vocabulary.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../shared_resolvers.dart';

const IconDataReference _check = IconDataReference(
  codePoint: 0xe156,
  fontFamily: 'MaterialIcons',
);

void main() {
  group('generated screen reference vocabulary', () {
    test('names the builders and icons that screen needs', () async {
      final inspection = await _inspect(
        _screenSource("import 'package:flutter/material.dart';"),
        vocabulary: SurfaceVocabularyReferences(
          widgetNames: const ['restage.core:Text', 'restage.material:Chip'],
          icons: const [_check],
        ),
      );

      expect(inspection.issues, isEmpty);
      final emitted = inspection.contract!.emitReferenceDart();

      expect(emitted, contains('vocabulary: const SurfaceVocabulary('));
      expect(emitted, contains("'Text': buildText"));
      expect(emitted, contains("'Chip': buildChip"));
      expect(
        _packed(emitted),
        contains("0xe156:IconData(0xe156,fontFamily:'MaterialIcons'"),
      );
      // The whole catalog stays out of the app: a widget the screen does not
      // render is never named.
      expect(emitted, isNot(contains('buildRow')));
      expect(emitted, isNot(contains('buildCupertinoButton')));
    });

    test('omits the argument when the screen names nothing installable',
        () async {
      final inspection = await _inspect(
        _screenSource("import 'package:flutter/material.dart';"),
      );

      expect(inspection.issues, isEmpty);
      expect(
        inspection.contract!.emitReferenceDart(),
        isNot(contains('vocabulary:')),
      );
    });

    test('rebuilds an icon a source importing only widgets.dart names',
        () async {
      // The generated part is a part of a file that imports the SDK, which is
      // the only identity the rebuilt icon names.
      final inspection = await _inspect(
        _screenSource("import 'package:flutter/widgets.dart';"),
        vocabulary: SurfaceVocabularyReferences(icons: const [_check]),
      );

      expect(inspection.issues, isEmpty);
      expect(
        _packed(inspection.contract!.emitReferenceDart()),
        contains("0xe156:IconData(0xe156,fontFamily:'MaterialIcons'"),
      );
    });
  });
}

/// [source] with its whitespace removed, so an assertion about an emitted
/// expression survives the formatter's line breaks.
String _packed(String source) => source.replaceAll(RegExp(r'\s+'), '');

String _screenSource(String flutterImport) => '''
$flutterImport
import 'package:restage/restage.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class MaintenanceNotice extends StatelessWidget {
  const MaintenanceNotice({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

Future<StandaloneScreenContractInspection> _inspect(
  String source, {
  SurfaceVocabularyReferences vocabulary = SurfaceVocabularyReferences.empty,
}) async {
  final assetId = AssetId('apps_examples', 'lib/maintenance_notice.dart');
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  readerWriter.testing.writeString(assetId, source);

  StandaloneScreenContractInspection? inspection;
  await testBuilder(
    _ProbeBuilder((library, resolvedAssetId) async {
      final screen = library.classes.singleWhere(
        (candidate) => candidate.name == 'MaintenanceNotice',
      );
      final screenInput = (await inspectCanonicalScreenDeclarations(
        library,
        resolvedAssetId,
      ))
          .screens
          .singleWhere((candidate) => candidate.declaration == screen);
      inspection = inspectStandaloneScreenContract(
        ResolvedStandaloneScreenContractInput(
          assetId: resolvedAssetId,
          screen: screen,
          surface: Surface.general,
          slug: 'maintenance_notice',
          contractVersion: 1,
          capabilities: CapabilityManifest(
            builtInFloor: 1,
            requiredLibraries: const [],
          ),
          rootParams: screenInput.build.rootParams,
          constructorParams: screenInput.build.constructorParams,
          mountConstructorProblem: screenInput.build.mountConstructorProblem,
          vocabulary: vocabulary,
        ),
      );
    }),
    {'apps_examples|lib/maintenance_notice.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    resolvers: sharedResolvers,
  );
  return inspection!;
}

final class _ProbeBuilder implements Builder {
  _ProbeBuilder(this.onLibrary);

  final Future<void> Function(LibraryElement library, AssetId assetId)
      onLibrary;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.screen_vocabulary_probe'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    await onLibrary(await buildStep.inputLibrary, buildStep.inputId);
  }
}
