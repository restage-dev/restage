import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_seam_assembly.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// PROOF (a) — the production-entrypoint seam-assembly byte-parity (the
/// condition-#3 core).
///
/// The regen proofs (`a2ui_interactive_proof_regen_test` /
/// `a2ui_rich_shape_proof_regen_test`) resolve the committed fixtures via an
/// `AnalysisContextCollection` and assemble the seams inline, then emit the
/// committed goldens. This proof resolves the SAME fixtures off a real
/// `buildStep.resolver` (the production resolution path), drives the SAME
/// `assembleA2uiSeams`, feeds the SAME customer-only catalog + the SAME
/// test-boundary URI normalization into the UNCHANGED `emitA2uiCatalogDart`,
/// and asserts byte-IDENTICAL to the committed goldens.
///
/// That ties the new resolver-fed read legs to the proven goldens: the build
/// resolver produces exactly what the hand-resolved harness produced.
/// A divergence in the customer-widget lowering (NOT the import URI / scope) is
/// a real fidelity gap — escalate, do not edit the golden.

const _interactiveFixturePath =
    '../restage_a2ui/test/generated/interactive_fixture.dart';
const _interactiveGoldenPath =
    '../restage_a2ui/test/generated/interactive_catalog.g.dart';
const _interactiveFixtureImport = 'interactive_fixture.dart';

const _richShapeFixturePath =
    '../restage_a2ui/test/generated/rich_shape_fixture.dart';
const _richShapeGoldenPath =
    '../restage_a2ui/test/generated/rich_shape_catalog.g.dart';
const _richShapeFixtureImport = 'rich_shape_fixture.dart';

/// The interactive proof widgets (mirrors the regen proof's table): the catalog
/// name, the fixture class the emitter constructs, the value properties, and
/// the callback (event) properties.
const _interactiveWidgets = <({
  String catalogName,
  String widgetClass,
  List<(String, PropertyType)> valueProps,
  List<String> callbacks,
})>[
  (
    catalogName: 'QuickCheck',
    widgetClass: 'QuickCheckFixture',
    valueProps: [('selected', PropertyType.integer)],
    callbacks: ['onSelected'],
  ),
  (
    catalogName: 'MultiSelect',
    widgetClass: 'MultiSelectFixture',
    valueProps: [('chosen', PropertyType.stringList)],
    callbacks: ['onChosen'],
  ),
  (
    catalogName: 'ActionButton',
    widgetClass: 'ActionButtonFixture',
    valueProps: [('label', PropertyType.string)],
    callbacks: ['onPressed'],
  ),
  (
    catalogName: 'Range',
    widgetClass: 'RangeFixture',
    valueProps: [('low', PropertyType.integer), ('high', PropertyType.integer)],
    callbacks: ['onLow', 'onHigh'],
  ),
];

/// The rich-shape proof widgets (mirrors the regen proof's table): the catalog
/// name, the fixture class, and the single structured data property.
const _richShapeWidgets =
    <({String catalogName, String widgetClass, String param})>[
  (catalogName: 'PlanCard', widgetClass: 'PlanCardFixture', param: 'plan'),
  (
    catalogName: 'FeatureGrid',
    widgetClass: 'FeatureGridFixture',
    param: 'features',
  ),
  (catalogName: 'Glossary', widgetClass: 'GlossaryFixture', param: 'terms'),
  (catalogName: 'MetaBar', widgetClass: 'MetaBarFixture', param: 'meta'),
  (catalogName: 'LinkCard', widgetClass: 'LinkCardFixture', param: 'link'),
  (
    catalogName: 'CommentThread',
    widgetClass: 'CommentThreadFixture',
    param: 'root',
  ),
];

/// Resolves [fixturePath]'s source off a real `buildStep.resolver` (the
/// production resolution path) by feeding it as an in-memory asset under
/// `restage_codegen` and capturing the resolved library element.
Future<LibraryElement> _resolveOffBuildResolver(String fixturePath) async {
  final source =
      File('${Directory.current.path}/$fixturePath').resolveSymbolicLinksSync();
  final content = File(source).readAsStringSync();
  // Mount under `apps_examples` so the resolved library URI
  // (`package:apps_examples/...`) sorts before `package:flutter/...` — matching
  // the import order the regen proofs get from their `file://`-resolved fixture
  // (the emitter sorts imports by URI). The URI itself is normalized away below
  // (replaceAll → the relative import the golden uses), so only the resulting
  // import ORDER reaches the golden, and it must match.
  const assetKey = 'apps_examples|lib/_a2ui_seam_parity_fixture.dart';
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
    includeFlutter: true,
  );
  readerWriter.testing.writeString(AssetId.parse(assetKey), content);

  LibraryElement? captured;
  await testBuilder(
    _LibraryCapture(
      AssetId.parse(assetKey),
      (library) => captured = library,
    ),
    {assetKey: content},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
  );
  if (captured == null) {
    throw StateError('failed to resolve $fixturePath off the build resolver');
  }
  return captured!;
}

ClassElement _classFor(LibraryElement library, String name) =>
    library.classes.firstWhere(
      (c) => c.name == name,
      orElse: () => throw StateError("no class '$name' in the fixture"),
    );

void main() {
  group('proof (a) — seam-assembly byte-parity off the build resolver', () {
    test('the interactive golden regenerates from the build-resolver seams',
        () async {
      final library = await _resolveOffBuildResolver(_interactiveFixturePath);
      final fixtureUri = _classFor(
        library,
        _interactiveWidgets.first.widgetClass,
      ).library.identifier;

      final widgets = <({WidgetEntry entry, ClassElement element})>[
        for (final w in _interactiveWidgets)
          (
            entry: entry(
              name: w.catalogName,
              flutterType: '$fixtureUri#${w.widgetClass}',
              properties: [
                for (final v in w.valueProps) prop(v.$1, v.$2, required: true),
                for (final c in w.callbacks)
                  prop(c, PropertyType.event, required: true),
              ],
            ),
            element: _classFor(library, w.widgetClass),
          ),
      ];
      final catalog = catalogWith([for (final w in widgets) w.entry]);
      final seams = assembleA2uiSeams(widgets);

      final emitted = emitA2uiCatalogDart(
        catalog,
        eventSeam: seams.eventSeam,
        pairingSeam: seams.pairingSeam,
        richShapes: seams.richShapes,
      );
      final normalized = formatGeneratedDart(
        emitted.replaceAll(fixtureUri, _interactiveFixtureImport),
      ).trimRight();

      expect(
        normalized,
        File(_interactiveGoldenPath).readAsStringSync().trimRight(),
        reason: 'the build-resolver seam assembly must reproduce the committed '
            'interactive golden byte-for-byte (condition #3, production path)',
      );
    });

    test('the rich-shape golden regenerates from the build-resolver seams',
        () async {
      final library = await _resolveOffBuildResolver(_richShapeFixturePath);
      final fixtureUri = _classFor(
        library,
        _richShapeWidgets.first.widgetClass,
      ).library.identifier;

      final widgets = <({WidgetEntry entry, ClassElement element})>[
        for (final w in _richShapeWidgets)
          (
            entry: entry(
              name: w.catalogName,
              flutterType: '$fixtureUri#${w.widgetClass}',
              properties: [
                prop(w.param, PropertyType.structured, required: true),
              ],
            ),
            element: _classFor(library, w.widgetClass),
          ),
      ];
      final catalog = catalogWith([for (final w in widgets) w.entry]);
      final seams = assembleA2uiSeams(widgets);

      final emitted =
          emitA2uiCatalogDart(catalog, richShapes: seams.richShapes);
      final normalized = formatGeneratedDart(
        emitted.replaceAll(fixtureUri, _richShapeFixtureImport),
      ).trimRight();

      expect(
        normalized,
        File(_richShapeGoldenPath).readAsStringSync().trimRight(),
        reason: 'the build-resolver seam assembly must reproduce the committed '
            'rich-shape golden byte-for-byte (condition #3, production path)',
      );
    });
  });
}

/// Resolves a single input asset to its [LibraryElement] off the build
/// resolver and hands it to [onLibrary] — the production resolution path.
class _LibraryCapture implements Builder {
  _LibraryCapture(this.target, this.onLibrary);

  final AssetId target;
  final void Function(LibraryElement library) onLibrary;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.a2uiseamproof'],
      };

  @override
  Future<void> build(BuildStep step) async {
    if (step.inputId != target) return;
    onLibrary(await step.inputLibrary);
  }
}
