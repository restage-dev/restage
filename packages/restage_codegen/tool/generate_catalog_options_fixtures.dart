import 'dart:io';

import 'package:restage_codegen/src/surface_vocabulary.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart';

const releaseRegistrationFixturePath =
    'packages/restage_codegen/test/fixtures/catalog_options_registration.dart.txt';

/// Generates integration fixtures through the production registration emitter.
Map<String, String> emitCatalogOptionsFixtures() {
  final runtimeVocabulary = SurfaceVocabularyReferences(
    widgetNames: const ['restage.core:Text', 'restage.material:Icon'],
    icons: const [
      IconDataReference(codePoint: 0xe5f9, fontFamily: 'MaterialIcons'),
      IconDataReference(
        codePoint: 0xf81f,
        fontFamily: 'CupertinoIcons',
        fontPackage: 'cupertino_icons',
      ),
    ],
  );
  final releaseVocabulary = SurfaceVocabularyReferences(
    widgetNames: const ['restage.core:Text', 'restage.material:Icon'],
    icons: const [
      IconDataReference(codePoint: 0xe5f9, fontFamily: 'MaterialIcons'),
    ],
  );
  return {
    for (final full in [true, false])
      'packages/restage/test/runtime/fixtures/'
              'catalog_options_${full ? 'full' : 'derived'}.g.dart':
          emitEmptyUserFactoriesDart(
        appVocabulary: runtimeVocabulary,
        installWholeCatalog: full,
      ),
    releaseRegistrationFixturePath: emitEmptyUserFactoriesDart(
      appVocabulary: releaseVocabulary,
      installWholeCatalog: true,
    ),
  };
}

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Pass the absolute repository root.');
  }
  final root = Directory(arguments.single);
  for (final entry in emitCatalogOptionsFixtures().entries) {
    final file = File('${root.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
    stdout.writeln(entry.key);
  }
}
