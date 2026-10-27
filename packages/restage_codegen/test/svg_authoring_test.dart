import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/surface_publication/app_widget_mount_install.dart';
import 'package:restage_shared/rfw_formats.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart' show testBuilders;

void main() {
  late Catalog catalog;
  late ResolvedUnitResult unit;
  setUpAll(() async {
    final path = File('../restage_svg/test/fixtures/authoring.dart')
        .resolveSymbolicLinksSync();
    final contexts = AnalysisContextCollection(includedPaths: [path]);
    addTearDown(contexts.dispose);
    unit = await contexts.contextFor(path).currentSession.getResolvedUnit(path)
        as ResolvedUnitResult;
    final svg = decodeCatalog(
      File('../restage_svg/lib/src/widget_catalog/catalog.json')
          .readAsStringSync(),
    );
    final core = decodeCatalog(
      File('../restage_core/lib/src/widget_catalog/catalog.json')
          .readAsStringSync(),
    );
    catalog = Catalog(
      schemaVersion: svg.schemaVersion,
      generatedAt: svg.generatedAt,
      libraries: {...core.libraries, ...svg.libraries},
      widgets: [...core.widgets, ...svg.widgets],
      structuredTypes: [...core.structuredTypes, ...svg.structuredTypes],
      unions: [...core.unions, ...svg.unions],
    );
  });
  TranslationResult compile(String name) {
    final declaration = unit.unit.declarations
        .whereType<FunctionDeclaration>()
        .firstWhere((entry) => entry.name.lexeme == name);
    final expression =
        (declaration.functionExpression.body as ExpressionFunctionBody)
            .expression;
    return ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
        .translate(expression, hoistInMount: false);
  }

  test(
      'combined SVG exact color placeholder and directional Clip preserve native contracts',
      () {
    final result = compile('combinedPicture');
    expect(result.issues.where((issue) => !issue.code.isInformational), isEmpty,
        reason: result.issues.map((i) => i.message).join('\n'));
    final library = parseLibraryFile(
        'import restage.svg; import restage.core; widget Screen = ${result.dsl};');
    expect(validateModelAgainstCatalog(library, catalog), isEmpty);
    final capability = deriveCapabilityManifest(library, catalog).manifest!;
    // The typed Color alias is stored in an SDK24 lexical value frame.
    expect(capability.builtInFloor, 24);
    final svg = capability.requiredLibraries.single;
    expect(svg.namespace, 'restage.svg');
    expect(svg.minVersion, 2);
    expect(svg.minGenerated, 3);
    expect(result.dsl,
        contains('context:ancestor:1:theme:defaultTextStyle.fontSize'));
    expect(result.dsl, contains('context:theme:defaultTextStyle.fontSize'));
    final fixture =
        File('../restage_svg/test/fixtures/combined_picture.rfwtxt');
    if (Platform.environment['WRITE_SVG_RUNTIME_FIXTURE'] == '1')
      fixture.writeAsStringSync('${result.dsl}\n');
    expect(fixture.readAsStringSync().trim(), result.dsl);
  });
  test('optional nested Color destinations retain subtype and nonnull proof',
      () {
    for (final name in [
      'subtypeThemePicture',
      'subtypeFilterPicture',
      'directSubtypeThemePicture',
      'directSubtypeFilterPicture',
      'crossSubtypeThemePicture',
      'dynamicCrossSubtypePicture'
    ]) {
      final result = compile(name);
      expect(result.dsl, contains('SvgPicture'), reason: name);
      expect(result.issues, isEmpty, reason: name);
      expect(result.dsl, contains('material:'), reason: name);
    }
    for (final name in ['nullThemePicture', 'nullFilterPicture']) {
      final result = compile(name);
      expect(result.dsl, isNot(contains('SvgPicture')), reason: name);
      expect(result.issues, isNotEmpty, reason: name);
    }
  });
  test('ordinary framework paint retains native subtype alias admission', () {
    final result = compile('ordinarySubtypePaint');
    expect(result.issues, isEmpty);
    expect(result.dsl, contains('ColoredBox('));
    expect(result.dsl, contains('material: "red"'));
  });
  test('optional constant colors preserve exact components and color space',
      () {
    for (final (name, space) in [
      ('crossExactColorPicture', 'displayP3'),
      ('crossExactSrgbPicture', 'sRGB')
    ]) {
      final result = compile(name);
      expect(result.issues, isEmpty,
          reason: result.issues.map((i) => i.message).join('\n'));
      expect(result.dsl, contains('colorSpace: "$space"'));
      expect(result.dsl, contains('a: 0.75'));
      expect(result.dsl, contains('r: 0.2'));
    }
    final dynamic = compile('dynamicCrossExactPicture');
    expect(dynamic.issues, isEmpty,
        reason: dynamic.issues.map((i) => i.message).join('\n'));
    expect(dynamic.dsl, contains('displayP3'));
  });
  test('native source lowers typed values and exact loader identities', () {
    for (final name in [
      'stringPicture',
      'bytesPicture',
      'assetPicture',
      'networkPicture',
      'loaderPicture',
      'loaderBytesPicture',
      'loaderAssetPicture',
      'loaderNetworkPicture',
      'gammaPicture',
      'placeholderPicture',
      'nullPlaceholderPicture',
      'aliasedStringPicture',
    ]) {
      final result = compile(name);
      expect(result.issues, isEmpty, reason: '$name: ${result.issues}');
      expect(result.dsl, contains('SvgPicture'));
      expect(
          validateModelAgainstCatalog(
              parseLibraryFile(
                  'import restage.svg; import restage.core; widget Screen = ${result.dsl};'),
              catalog),
          isEmpty);
    }
    expect(compile('stringPicture').dsl, contains('fontSize: 20'));
    expect(compile('stringPicture').dsl, contains('kind: "mode"'));
    expect(compile('networkPicture').dsl, contains('key: "X-Svg"'));
    expect(compile('loaderPicture').dsl, contains('SvgStringLoader'));
    for (final (source, name) in [
      ('stringPicture', 'string_picture'),
      ('placeholderPicture', 'placeholder_picture'),
      ('aliasedStringPicture', 'aliased_picture'),
    ]) {
      final fixture = File('../restage_svg/test/fixtures/$name.rfwtxt');
      final compiled = compile(source).dsl;
      if (Platform.environment['WRITE_SVG_RUNTIME_FIXTURE'] == '1') {
        fixture.writeAsStringSync('$compiled\n');
      }
      expect(fixture.readAsStringSync().trim(), compiled);
    }
  });
  test('native values preserve direct and resolved constant alias semantics',
      () {
    for (final (direct, aliases) in [
      ('directThemePicture', ['aliasThemePicture', 'crossThemePicture']),
      ('directFilterPicture', ['aliasFilterPicture', 'crossFilterPicture']),
      ('directHeadersPicture', ['aliasHeadersPicture', 'crossHeadersPicture']),
      (
        'directStringLoaderPicture',
        ['aliasStringLoaderPicture', 'crossStringLoaderPicture']
      ),
      ('directAssetLoaderPicture', ['crossAssetLoaderPicture']),
      ('directNetworkLoaderPicture', ['crossNetworkLoaderPicture']),
      ('directBytesAliasPicture', ['crossBytesAliasPicture']),
      ('directMatrixPicture', ['crossMatrixPicture']),
      ('directLinearPicture', ['crossLinearPicture']),
      ('directSrgbPicture', ['crossSrgbPicture']),
    ]) {
      final control = compile(direct);
      expect(control.issues, isEmpty, reason: '$direct: ${control.issues}');
      for (final name in aliases) {
        final result = compile(name);
        expect(result.issues, isEmpty, reason: '$name: ${result.issues}');
        ConstructorCall root(String source) => parseLibraryFile(
              'import restage.svg; widget Screen = $source;',
            ).widgets.single.root as ConstructorCall;
        final expected = root(control.dsl);
        final actual = root(result.dsl);
        expect(actual.name, expected.name, reason: name);
        expect(actual.arguments, expected.arguments, reason: name);
      }
    }
    for (final name in ['badConstLoaderPicture', 'badRuntimeHeadersPicture']) {
      expect(compile(name).issues, isNotEmpty, reason: name);
    }
  });
  test('unsupported supplied values and callbacks refuse explicitly', () {
    for (final name in [
      'badBytes',
      'badLoader',
      'badCallback',
      'badLookalike',
      'badBundle',
      'badMapper'
    ]) {
      expect(compile(name).issues, isNotEmpty, reason: name);
    }
  });
  test('sidecars preserve installed namespace capability and native factories',
      () {
    final sidecar = AppWidgetMountFactories.fromCatalog(
      decodeCatalog(
        File('../restage_svg/lib/src/widget_catalog/catalog.json')
            .readAsStringSync(),
      ),
    ).toJson();
    expect(
        sidecar,
        jsonDecode(File(
                '../restage_svg/lib/src/widget_catalog/app_widget_factories.json')
            .readAsStringSync()));
    expect(
        AppWidgetMountFactories.fromJson(sidecar).curatedLibrarySource(),
        File('../restage_svg/lib/src/curated_factories.g.dart')
            .readAsStringSync());
    expect(sidecar['capabilityVersions'], {'restage.svg': 2});
    expect(sidecar['compatibleSince'], {'restage.svg': 1});
    final factories = sidecar['factories']! as Map;
    expect(factories, hasLength(6));
    expect(
      factories['restage.svg:SvgPictureMemory'].toString(),
      contains('SvgNativeValues.bytes'),
    );
    final result = deriveCapabilityManifest(
      parseLibraryFile(
        'import restage.svg; widget Screen = ${compile('stringPicture').dsl};',
      ),
      catalog,
    );
    expect(result.issues, isEmpty);
    expect(
      result.manifest!.requiredLibraries.map((entry) => entry.namespace),
      contains('restage.svg'),
    );
    final absent = deriveCapabilityManifest(
      parseLibraryFile(
          'import restage.core; widget Screen = SizedBox(width: 1.0);'),
      catalog,
    );
    expect(absent.manifest?.requiredLibraries ?? [], isEmpty);
  });
  test('declared optional dependencies install their generated factories',
      () async {
    for (final includeSvg in [true, false]) {
      final result = await testBuilders(
        [
          _OptionalCatalogProbe(),
        ],
        {
          'app|lib/probe.dart': '',
          'app|pubspec.yaml':
              'name: app\ndependencies:\n  ${includeSvg ? 'restage_svg: any' : 'other: any'}\n',
          'other|pubspec.yaml': 'name: other\n',
          'restage_svg|pubspec.yaml': 'name: restage_svg\n',
          'restage_svg|lib/src/widget_catalog/catalog.json':
              File('../restage_svg/lib/src/widget_catalog/catalog.json')
                  .readAsStringSync(),
          'restage_svg|$kAppWidgetFactoriesPath':
              File('../restage_svg/$kAppWidgetFactoriesPath')
                  .readAsStringSync(),
        },
        rootPackage: 'app',
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue);
      final probe = jsonDecode(
        result.readerWriter.testing
            .readString(AssetId('app', 'lib/probe.probe.json')),
      ) as Map<String, Object?>;
      if (includeSvg) {
        expect(probe['namespaces'], contains('restage.svg'));
        expect(
          probe['registration'],
          contains("WidgetLibrary.custom('restage.svg')"),
        );
        expect(probe['registration'], contains('capabilityVersion: 2'));
        expect(
          probe['imports'].toString(),
          contains('package:restage_svg/src/native_values.dart'),
        );
      } else {
        expect(probe['namespaces'], isEmpty);
        expect(probe['registration'], isEmpty);
        expect(probe['imports'], isEmpty);
      }
    }
  });
}

final class _OptionalCatalogProbe implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.probe.json'],
      };
  @override
  Future<void> build(BuildStep step) async {
    final catalog = await loadMergedCatalog(step);
    final factories = await loadAppWidgetFactories(step);
    final registration = factories.registrationSource();
    await step.writeAsString(
      step.inputId.changeExtension('.probe.json'),
      jsonEncode({
        'namespaces':
            catalog.libraries.keys.map((library) => library.namespace).toList(),
        'registration': registration.registrations,
        'imports': registration.imports,
      }),
    );
  }
}
