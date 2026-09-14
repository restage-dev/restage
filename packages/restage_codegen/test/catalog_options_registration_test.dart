import 'dart:io';

import 'package:restage_codegen/src/app_size_disclosure.dart';
import 'package:restage_codegen/src/surface_vocabulary.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../tool/generate_catalog_options_fixtures.dart';

void main() {
  test('runtime and release registration fixtures match their owning emitter',
      () {
    for (final entry in emitCatalogOptionsFixtures().entries) {
      expect(
        File('../../${entry.key}').readAsStringSync(),
        entry.value,
        reason: 'Regenerate with tool/generate_catalog_options_fixtures.dart.',
      );
      expect(entry.value, contains("'Text': buildText"));
      expect(entry.value, contains("'Icon': buildIcon"));
      expect(entry.value, contains('0xe5f9: IconData(0xe5f9,'));
      expect(
        entry.value.contains('0xf81f: IconData(0xf81f,'),
        entry.key != releaseRegistrationFixturePath,
      );
    }
  });

  for (final full in [false, true]) {
    for (final custom in [false, true]) {
      test('registration options preserve full=$full custom=$custom', () {
        final source = custom
            ? emitUserFactoriesDart(
                const [
                  WidgetEntry(
                    wireId: WireId.unallocatedWidget,
                    name: 'Badge',
                    library: WidgetLibrary.custom('acme.widgets'),
                    category: WidgetCategory.layout,
                    description: 'A badge.',
                    flutterType: 'package:acme/widgets.dart#Badge',
                    childrenSlot: ChildrenSlot.none,
                    properties: [],
                  ),
                ],
                installWholeCatalog: full,
              )!
            : emitEmptyUserFactoriesDart(installWholeCatalog: full);
        final compact = source.replaceAll(RegExp(r'\s+'), '');
        expect(
          compact,
          contains('voidregisterRestageWidgets({'
              'boolincludeMaterial=true,boolincludeCupertino=true,}){'
              'kRestageWidgetRegistration('
              'includeMaterial:includeMaterial,'
              'includeCupertino:includeCupertino,);}'),
        );
        expect(
          compact,
          contains('constRestageWidgetRegistrationkRestageWidgetRegistration='
              '_RestageWidgetRegistration();'),
        );
        expect(
          compact,
          contains('finalclass_RestageWidgetRegistration'
              'implementsRestageWidgetRegistration{'
              'const_RestageWidgetRegistration();'
              '@overridevoidcall({'
              'boolincludeMaterial=true,boolincludeCupertino=true,}){'),
        );
        for (final helper in [
          'RestageWidgetLibraries.builtIn',
          'builtInIconTable',
        ]) {
          expect(
            compact.contains('$helper(includeMaterial:includeMaterial,'
                'includeCupertino:includeCupertino,)'),
            full,
          );
          expect(
            RegExp(RegExp.escape('$helper(')).allMatches(compact).length,
            full ? 1 : 0,
          );
          if (!full) expect(source, isNot(contains('$helper(')));
        }
        expect(
          compact,
          contains('kRestageAppVocabulary.addToInstalled('
              'explicitSelection:true);'),
        );
        expect(
          'kRestageAppVocabulary.addToInstalled'.allMatches(source).length,
          1,
        );
        if (full) {
          expect(
            source.indexOf('InstalledIconTable.add('),
            lessThan(source.indexOf('  kRestageAppVocabulary.addToInstalled')),
          );
        }
        if (custom) {
          expect(
            source.indexOf('  kRestageAppVocabulary.addToInstalled'),
            lessThan(source.indexOf('  Restage.registerWidgetLibrary(')),
          );
        }
        expect(
          compact,
          contains('voidregisterRestageCustomerWidgets()=>'
              'registerRestageWidgets();'),
        );
      });
    }
  }

  test('full and explicit-helper disclosures qualify family selection', () {
    for (final position in [
      CatalogPosition.wholeCatalog,
      CatalogPosition.appInstalled,
    ]) {
      final summary = summariseAppVocabulary(
        SurfaceVocabularyReferences.empty,
        position: position,
        builtInWidgetCount: 119,
      );
      expect(summary, contains('includeMaterial/includeCupertino'));
      expect(summary, isNot(contains('every one of them stays in the build')));
      if (position == CatalogPosition.wholeCatalog) {
        expect(summary, contains('by default'));
        expect(summary, contains('keeping app requirements'));
      }
    }
  });
}
