import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final catalog = decodeCatalog(File(
    '../restage_core/lib/src/widget_catalog/catalog.json',
  ).readAsStringSync());

  Future<TranslationResult> translate(String body,
      {String declarations = ''}) async {
    final expression = await parseExpressionFromSourceForTest('''
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
const gradient = LinearGradient(colors: [Colors.red, Colors.blue]);
class Palette {
  static const gradient = SweepGradient(colors: [Colors.red, Colors.blue], transform: GradientRotation(0.5));
}
$declarations
Widget x() => $body;
''', rootPackage: 'apps_examples');
    return ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
        .translate(expression);
  }

  const colors = 'colors: [Colors.red, Colors.blue]';
  const supported = <String, String>{
    'linear':
        'ShaderMask(shaderCallback: (b) => LinearGradient($colors).createShader(b), blendMode: BlendMode.srcIn, child: const SizedBox())',
    'const':
        'ShaderMask(shaderCallback: (b) => const LinearGradient($colors).createShader(b), child: const SizedBox())',
    'block':
        'ShaderMask(shaderCallback: (b) { return const RadialGradient($colors, stops: [0, 1], radius: 0.7).createShader(b); }, child: const SizedBox())',
    'identifier':
        'ShaderMask(shaderCallback: (b) => gradient.createShader(b), child: const SizedBox())',
    'static const rotation':
        'ShaderMask(shaderCallback: (b) => Palette.gradient.createShader(b), child: const SizedBox())',
    'linear rotation':
        'ShaderMask(shaderCallback: (b) => const LinearGradient($colors, transform: GradientRotation(0.25), tileMode: TileMode.mirror).createShader(b), child: const SizedBox())',
    'radial rotation':
        'ShaderMask(shaderCallback: (b) => const RadialGradient($colors, transform: GradientRotation(0.25), tileMode: TileMode.repeated).createShader(b), child: const SizedBox())',
    'sweep rotation':
        'ShaderMask(shaderCallback: (b) => const SweepGradient($colors, transform: GradientRotation(0.25), tileMode: TileMode.mirror).createShader(b), child: const SizedBox())',
    'literal tear-off':
        'ShaderMask(shaderCallback: const LinearGradient($colors).createShader, child: const SizedBox())',
    'const tear-off':
        'ShaderMask(shaderCallback: gradient.createShader, child: const SizedBox())',
    'color filter':
        'ColorFiltered(colorFilter: const ColorFilter.mode(Colors.red, BlendMode.modulate), child: const SizedBox())',
  };
  for (final example in supported.entries) {
    test('${example.key} compiles and round-trips through RFW', () async {
      final result = await translate(example.value);
      expect(result.issues.where((i) => !i.code.isInformational), isEmpty);
      final library = fmt.parseLibraryFile(
          'import restage.core; widget main = ${result.dsl};');
      final decoded = fmt.decodeLibraryBlob(fmt.encodeLibraryBlob(library));
      final root = decoded.widgets.single.root as fmt.ConstructorCall;
      expect(root.name, 'RestageShaderMask');
      expect(root.arguments['child'], isA<fmt.ConstructorCall>());
      if (example.key.contains('rotation')) {
        expect(root.arguments['rotation'],
            example.key == 'static const rotation' ? 0.5 : 0.25);
      }
      if (example.key == 'color filter') {
        expect(root.arguments['color'], 0xFFF44336);
        expect(root.arguments['blendMode'], 'modulate');
      }
    });
  }

  const unsupported = <String, String>{
    'ui gradient':
        'ShaderMask(shaderCallback: (b) => ui.Gradient.linear(Offset.zero, const Offset(1, 1), [Colors.red, Colors.blue]), child: const SizedBox())',
    'image shader':
        'ShaderMask(shaderCallback: (b) => ui.ImageShader(image, TileMode.clamp, TileMode.clamp, matrix), child: const SizedBox())',
    'bounds math':
        'ShaderMask(shaderCallback: (b) => gradient.createShader(b.inflate(2)), child: const SizedBox())',
    'stored shader':
        'ShaderMask(shaderCallback: (b) => shader, child: const SizedBox())',
    'multiple statements':
        'ShaderMask(shaderCallback: (b) { final g = gradient; return g.createShader(b); }, child: const SizedBox())',
    'other transform':
        'ShaderMask(shaderCallback: (b) => LinearGradient($colors, transform: CustomTransform()).createShader(b), child: const SizedBox())',
    'matrix filter':
        'ColorFiltered(colorFilter: const ColorFilter.matrix([1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]), child: const SizedBox())',
    'other filter':
        'ColorFiltered(colorFilter: const ColorFilter.srgbToLinearGamma(), child: const SizedBox())',
  };
  for (final example in unsupported.entries) {
    test('${example.key} directs the author to custom widgets', () async {
      final result = await translate(example.value);
      expect(result.dsl, isEmpty);
      expect(
          result.issues,
          contains(isA<Issue>()
              .having(
                  (i) => i.code, 'code', IssueCode.shaderMaskFormUnsupported)
              .having(
                  (i) => i.message, 'message', contains('@RestageWidget'))));
    });
  }

  for (final type in ['RadialGradient', 'SweepGradient']) {
    test('$type decorations preserve tileMode and defer transforms', () async {
      final result = await translate(
          'DecoratedBox(decoration: BoxDecoration(gradient: $type($colors, tileMode: TileMode.repeated)), child: const SizedBox())');
      expect(result.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(result.dsl, contains('tileMode: "repeated"'));

      final transformed = await translate(
          'DecoratedBox(decoration: BoxDecoration(gradient: $type($colors, transform: GradientRotation(0.5))), child: const SizedBox())');
      expect(
          transformed.issues,
          contains(isA<Issue>().having((i) => i.message, 'message',
              contains('$type field(s) not yet supported: transform'))));
      expect(transformed.issues.any((i) => !i.code.isInformational), isTrue);
    });
  }

  test('child diagnostics keep their code, subject and message', () async {
    const declaration = '''
class MissingWidget extends StatelessWidget {
  const MissingWidget();
  Widget build(BuildContext context) => const SizedBox();
}
''';
    final direct =
        await translate('const MissingWidget()', declarations: declaration);
    final nested = await translate(
        'ShaderMask(shaderCallback: gradient.createShader, child: const MissingWidget())',
        declarations: declaration);
    final original = direct.issues.singleWhere((i) => !i.code.isInformational);
    final issue = nested.issues.singleWhere((i) => !i.code.isInformational);
    expect(issue.code, original.code);
    expect(issue.capabilityGapSubject, 'widget:MissingWidget');
    expect(issue.message, original.message);
  });

  test('the generated mount keeps the authored widget as its fallback',
      () async {
    const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
part 'restage.generated/masked.restage.g.dart';
@Screen(id: 'masked', surface: Surface.general)
class Masked extends StatelessWidget {
  const Masked({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    final gradient = const LinearGradient(colors: [Colors.red, Colors.blue], transform: GradientRotation(0.25));
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(bounds),
      child: GradientLabel(gradient: const LinearGradient(colors: [Colors.red, Colors.blue]), title: title),
    );
  }
}
@RestageWidget(name: 'GradientLabel', library: WidgetLibrary.custom('sample.widgets'), category: WidgetCategory.decoration, description: 'A gradient label.')
class GradientLabel extends StatelessWidget {
  const GradientLabel({required this.gradient, required this.title});
  final Gradient gradient;
  final String title;
  @override
  Widget build(BuildContext context) => ShaderMask(
    shaderCallback: gradient.createShader,
    blendMode: BlendMode.srcIn,
    child: Text(title),
  );
}
''';
    final readerWriter =
        await readerWriterWithFilesystemSources(rootPackage: 'apps_examples');
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      {'apps_examples|lib/masked.dart': source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = RestageSurfacePublicationBundle.fromJson(jsonDecode(
      readerWriter.testing.readString(AssetId(
          'apps_examples', kRestageSurfacePublicationCompilerBundlePath)),
    ));
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    final dsl = utf8
        .decode(bundle.ownedOutputs['assets/general/screens/masked.rfwtxt']!);
    final library = fmt.parseLibraryFile(dsl);
    final root = library.widgets
        .singleWhere((widget) => widget.name == 'OnboardingScreen')
        .root as fmt.ConstructorCall;
    expect(root.name, 'RestageShaderMask');
    expect((root.arguments['gradient']! as Map)['type'], 'linear');
    expect(root.arguments['rotation'], 0.25);
    final label = library.widgets
        .singleWhere((widget) => widget.name == 'GradientLabel')
        .root as fmt.ConstructorCall;
    expect(label.name, 'RestageShaderMask');
    expect((label.arguments['gradient']! as fmt.ArgsReference).parts,
        ['gradient']);
    final generated = utf8.decode(
        bundle.ownedOutputs['lib/restage.generated/masked.restage.g.dart']!);
    expect(generated, contains('builder: (context, error) => Masked('));
    expect(generated,
        isNot(contains('builder: (context, error) => RestageShaderMask(')));
  });

  test('a look-alike widget is never rewritten', () async {
    final result = await translate('ShaderMask()', declarations: '''
class ShaderMask extends StatelessWidget {
  const ShaderMask();
  Widget build(BuildContext context) => const SizedBox();
}
''');
    expect(result.dsl, isNot(contains('RestageShaderMask')));
  });
}
