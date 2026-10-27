import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_shared/restage_shared.dart' show CapabilitySidecar;
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final catalog = decodeCatalog(
    File('../restage_core/lib/src/widget_catalog/catalog.json')
        .readAsStringSync(),
  );
  Future<TranslationResult> translate(
    String body, {
    String declarations = '',
  }) async {
    final expression = await parseExpressionFromSourceForTest(
      '''
      import 'package:flutter/material.dart';
      $declarations
      Widget x() => $body;
    ''',
      rootPackage: 'apps_examples',
    );
    return ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
        .translate(expression);
  }

  const child = 'child: const SizedBox(width: 60, height: 40)';
  const shape = 'RoundedRectangleBorder(borderRadius: '
      'BorderRadius.only(topLeft: Radius.circular(12)))';
  const directionalShape = 'RoundedRectangleBorder(borderRadius: '
      'BorderRadiusDirectional.only(topStart: Radius.circular(12)))';
  const cases = {
    'plain': 'ClipPath($child)',
    'none': 'ClipPath(clipper: null, clipBehavior: Clip.none, $child)',
    'constNull': 'ClipPath(clipper: noClipper, $child)',
    'directNull':
        'ClipPath(clipper: ShapeBorderClipper(shape: $shape), $child)',
    'directLtr': 'ClipPath(clipper: ShapeBorderClipper(shape: $shape, '
        'textDirection: TextDirection.ltr), $child)',
    'directRtl': 'ClipPath(clipper: ShapeBorderClipper(shape: $shape, '
        'textDirection: TextDirection.rtl), $child)',
    'shape': 'ClipPath.shape(shape: $shape, $child)',
    'directionalShape': 'ClipPath.shape(shape: $directionalShape, $child)',
    'directionalLtr':
        'ClipPath(clipper: ShapeBorderClipper(shape: $directionalShape, '
            'textDirection: TextDirection.ltr), $child)',
    'directionalRtl':
        'ClipPath(clipper: ShapeBorderClipper(shape: $directionalShape, '
            'textDirection: TextDirection.rtl), $child)',
  };
  test('native forms compile into the runtime differential fixture', () async {
    final compiled = <String, String>{};
    for (final example in cases.entries) {
      final result = await translate(
        example.value,
        declarations: example.key == 'constNull'
            ? 'const CustomClipper<Path>? noClipper = null;'
            : '',
      );
      expect(
        result.issues.where((i) => !i.code.isInformational),
        isEmpty,
        reason: example.key,
      );
      expect(
        result.dsl,
        startsWith(example.key == 'shape' || example.key == 'directionalShape'
            ? 'ClipPathShape('
            : 'ClipPath('),
      );
      compiled[example.key] = result.dsl;
    }
    final fixture =
        File('../restage_core/test/fixtures/clip_path_compiled.json');
    if (Platform.environment['REGEN_CLIP_PATH_FIXTURE'] == '1') {
      fixture.parent.createSync(recursive: true);
      fixture.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(compiled)}\n',
      );
    }
    expect(jsonDecode(fixture.readAsStringSync()), compiled);
  });

  test('const-null clipper aliases preserve nullable-slot boundaries',
      () async {
    for (final source in {
      'noClipper': 'const CustomClipper<Path>? noClipper = null;',
      'Clippers.noClipper': '''
        class Clippers {
          static const CustomClipper<Path>? noClipper = null;
        }
      ''',
    }.entries) {
      final result = await translate(
        'ClipPath(clipper: ${source.key}, $child)',
        declarations: source.value,
      );
      expect(result.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(
        result.dsl,
        'ClipPath(child: SizedBox(width: 60.0, height: 40.0))',
      );
    }
    final runtimeNull = await translate(
      'ClipPath(clipper: noClipper, $child)',
      declarations: 'CustomClipper<Path>? get noClipper => null;',
    );
    expect(
      runtimeNull.issues.where((i) => !i.code.isInformational),
      isNotEmpty,
    );
    final nonnullableSlot = await translate(
      'DefaultTextStyle(style: noStyle, child: const SizedBox())',
      declarations: 'const TextStyle? noStyle = null;',
    );
    expect(
      nonnullableSlot.issues.where((i) => !i.code.isInformational),
      isNotEmpty,
    );
  });

  test('custom imperative clipper is diagnosed', () async {
    final result = await translate(
      'ClipPath(clipper: AppClipper())',
      declarations: '''
      class AppClipper extends CustomClipper<Path> {
        @override
        Path getClip(Size size) => Path()..addOval(Offset.zero & size);
        @override
        bool shouldReclip(AppClipper oldClipper) => false;
      }
    ''',
    );
    expect(result.issues.where((i) => !i.code.isInformational), isNotEmpty);
    expect(result.issues.map((i) => i.message).join(' '), contains('clipper'));
  });

  test('lookalike clipper identity is refused', () async {
    final result = await translate(
      'ClipPath(clipper: ShapeBorderClipper(shape: const CircleBorder()))',
      declarations: '''
        class ShapeBorderClipper extends CustomClipper<Path> {
          ShapeBorderClipper({required ShapeBorder shape});
          @override
          Path getClip(Size size) => Path();
          @override
          bool shouldReclip(ShapeBorderClipper oldClipper) => false;
        }
      ''',
    );
    expect(result.issues.where((i) => !i.code.isInformational), isNotEmpty);
  });

  test('lookalike static callable never binds the native entry', () async {
    final result = await translate(
      'ClipPath.shape(shape: const CircleBorder())',
      declarations: '''
        class ClipPath {
          static Widget shape({required ShapeBorder shape}) => const SizedBox();
        }
      ''',
    );
    expect(result.dsl, isNot(startsWith('ClipPathShape(')));
  });

  test('surface compiler admits native static calls in composed widgets',
      () async {
    const source = '''
      import 'package:flutter/material.dart';
      import 'package:restage/restage.dart';
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
      part 'restage.generated/clipped.restage.g.dart';
      @Screen(id: 'clipped', surface: Surface.general)
      class Clipped extends StatelessWidget {
        const Clipped({super.key});
        @override
        Widget build(BuildContext context) => ClipPath.shape(
          shape: const CircleBorder(), child: const ClippedPanel());
      }
      @RestageWidget(name: 'ClippedPanel', library: WidgetLibrary.custom('sample.widgets'), category: WidgetCategory.decoration, description: 'A clipped panel.')
      class ClippedPanel extends StatelessWidget {
        const ClippedPanel();
        @override
        Widget build(BuildContext context) => ClipPath.shape(
          shape: const CircleBorder(), child: const SizedBox(width: 60, height: 40));
      }
    ''';
    final readerWriter =
        await readerWriterWithFilesystemSources(rootPackage: 'apps_examples');
    final messages = <String>[];
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      {'apps_examples|lib/clipped.dart': source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
      onLog: (record) => messages.add(record.message),
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    expect(messages.join('\n'), isNot(contains('Measurement is unavailable')));
    final bundle = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
            'apps_examples',
            kRestageSurfacePublicationCompilerBundlePath,
          ),
        ),
      ),
    );
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    final sidecars = bundle.artifacts.entries
        .where((entry) => entry.key.endsWith('.capability.json'))
        .map(
          (entry) => CapabilitySidecar.fromJson(
            jsonDecode(utf8.decode(entry.value)) as Map<String, dynamic>,
          ),
        )
        .toList();
    expect(sidecars, isNotEmpty);
    expect(
      sidecars.map((sidecar) => sidecar.manifest.builtInFloor),
      everyElement(21),
    );

    final dsl = utf8
        .decode(bundle.ownedOutputs['assets/general/screens/clipped.rfwtxt']!);
    final library = fmt.parseLibraryFile(dsl);
    expect(
      (library.widgets.singleWhere((w) => w.name == 'OnboardingScreen').root
              as fmt.ConstructorCall)
          .name,
      'ClipPathShape',
    );
    expect(
      (library.widgets.singleWhere((w) => w.name == 'ClippedPanel').root
              as fmt.ConstructorCall)
          .name,
      'ClipPathShape',
    );
  });

  test('shape entries require capability 21', () {
    for (final name in ['ClipPath', 'ClipPathShape']) {
      expect(
        catalog.widgets.singleWhere((e) => e.name == name).sinceVersion,
        21,
      );
    }
  });
}
