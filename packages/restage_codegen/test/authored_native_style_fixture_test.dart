import 'dart:io';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as wire;
import 'package:test/test.dart';
import 'helpers.dart' as helpers;

void main() {
  test('custom structured values preserve native base subtype requirements',
      () async {
    final catalog = helpers.nativeProbeCatalog([
      ('style', PropertyType.structured),
      ('child', PropertyType.widget),
    ], required: {
      'style',
      'child'
    }, structured: {
      'style': 'TextStyle'
    });
    for (final field in [
      'color:Theme.of(context).colorScheme.primary',
      'color:Colors.red',
      'fontWeight:DefaultTextStyle.of(context).style.fontWeight',
      'color:Colors.black',
      'color:const Color(0xff123456)',
      'fontWeight:const FontWeight(550)',
      'fontWeight:FontWeight.bold',
      'fontSize:c.maxWidth'
    ]) {
      final expression = await helpers.parseExpressionFromSourceForTest("""
import 'package:flutter/material.dart';
Widget x()=>LayoutBuilder(builder:(context,c)=>Probe(style:TextStyle($field),child:ColoredBox(color:Theme.of(context).colorScheme.primary,child:const SizedBox())));
class Probe extends StatelessWidget {
  const Probe({required this.style,required this.child});
  final TextStyle style;
  final Widget child;
  Widget build(BuildContext context)=>child;
}
""", rootPackage: 'apps_examples');
      final translated =
          ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
              .translate(expression);
      if (field.startsWith('color:Theme') ||
          field.startsWith('fontWeight:DefaultTextStyle')) {
        expect(translated.issues.map((issue) => issue.message),
            contains(contains('runtime subtype')));
      } else {
        expect(translated.issues, isEmpty,
            reason: translated.issues.map((issue) => issue.message).join('\n'));
        if (field.contains('Colors.red') || field == 'color:declaredRed') {
          expect(translated.dsl, contains('material: "red"'), reason: field);
        }
      }
    }
  });

  test('custom constructors require native Color and FontWeight base types',
      () async {
    final catalog = helpers.nativeProbeCatalog([
      ('color', PropertyType.color),
      ('weight', PropertyType.fontWeight),
    ], keep: (entry) => entry.name == 'LayoutBuilder');
    for (final (field, rejected) in [
      ('color:Theme.of(context).colorScheme.primary', true),
      ('color:Colors.red', false),
      ('color:declaredRed', false),
      ('color:c.maxWidth > 0 ? Colors.red : Colors.black', false),
      ('weight:DefaultTextStyle.of(context).style.fontWeight', true),
      ('weight:const TaggedWeight()', true),
      ('color:Colors.black', false),
      ('color:baseColor', false),
      ('color:c.maxWidth > 0 ? Colors.black : const Color(0xff123456)', false),
      ('color:const Color(0xff123456)', false),
      ('weight:const FontWeight(550)', false),
      ('weight:FontWeight.bold', false),
    ]) {
      final expression = await helpers.parseExpressionFromSourceForTest("""
import 'package:flutter/material.dart';
Widget x()=>LayoutBuilder(builder:(context,c)=>Probe($field));
const Color declaredRed=Colors.red;
const Color baseColor=Color(0xff123456);
class TaggedWeight extends FontWeight { const TaggedWeight():super(550); }
class Probe extends StatelessWidget {
  const Probe({this.color,this.weight});
  final Color? color;
  final FontWeight? weight;
  Widget build(BuildContext context)=>const SizedBox();
}
""", rootPackage: 'apps_examples');
      final translated =
          ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
              .translate(expression);
      if (rejected) {
        expect(translated.issues.map((issue) => issue.message),
            contains(contains('runtime subtype')),
            reason: field);
      } else {
        expect(translated.issues, isEmpty,
            reason: translated.issues.map((issue) => issue.message).join('\n'));
        if (field.contains('? Colors.red')) {
          final root = wire
              .parseLibraryFile(
                  'import restage.core; widget Root=${translated.dsl};')
              .widgets
              .single
              .root as wire.ConstructorCall;
          final continuation =
              root.arguments['builder']! as wire.ConstructorCall;
          final program = BuilderProgram.decode(
              continuation.arguments['program']! as String);
          for (final width in [-1.0, 1.0]) {
            final frame = program.invoke(captures: _NoCaptures(), parameters: {
              'arg1': {'maxWidth': width},
            });
            expect(frame.values.values, contains(width > 0 ? 'red' : ''),
                reason: field);
          }
        } else if (field.contains('Colors.red') ||
            field == 'color:declaredRed') {
          expect(translated.dsl, contains('material: "red"'), reason: field);
        }
      }
    }
    final ordinary = await helpers.parseExpressionFromSourceForTest("""
import 'package:flutter/material.dart';
Widget x()=>Probe(color:Colors.red);
class Probe extends StatelessWidget {
  const Probe({required this.color});
  final Color color;
  Widget build(BuildContext context)=>const SizedBox();
}
""", rootPackage: 'apps_examples');
    final existing =
        ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
            .translate(ordinary);
    expect(existing.issues, isEmpty);
  });

  test('authored style fixture preserves exact native values through consumers',
      () async {
    final expression = await helpers.parseExpressionFromSourceForTest('''
import 'package:flutter/material.dart';
Widget x()=>LayoutBuilder(builder:(context,c)=>ColoredBox(
  color:Theme.of(context).colorScheme.primary,
  child:Text('exact',style:TextStyle(
    color:Theme.of(context).textTheme.bodyMedium!.color,
    fontWeight:Theme.of(context).textTheme.bodyMedium!.fontWeight,
    decoration:Theme.of(context).textTheme.bodyMedium!.decoration))));
''', rootPackage: 'apps_examples');
    final file = File(Directory('packages/restage_core').existsSync()
        ? 'packages/restage_core/lib/src/widget_catalog/catalog.json'
        : '../restage_core/lib/src/widget_catalog/catalog.json');
    final catalog = decodeCatalog(file.readAsStringSync());
    final translated =
        ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
            .translate(expression);
    expect(translated.issues, isEmpty,
        reason: translated.issues.map((issue) => issue.message).join('\n'));
    final text = 'import restage.core; widget Root=${translated.dsl};';
    final library = wire.parseLibraryFile(text);
    expect(deriveSurfaceCapability(library, catalog).builtInFloor,
        greaterThanOrEqualTo(19));
    expect(
        surfaceScreenContractGaps(library,
            events: SurfaceScreenEventSchema(events: []),
            context: SurfaceScreenHostDataSchema(const {})),
        isEmpty);
    expect(
        emitFactoryFunction(
            catalog.widgets.firstWhere((entry) => entry.name == 'ColoredBox'),
            nativeIndex: NativeCatalogIndex(catalog)),
        contains('RestageDecoders.color(source,'));
    final fileOut = File(Directory('packages/restage_core').existsSync()
        ? 'packages/restage_core/test/fixtures/authored_native_style.rfwtxt'
        : '../restage_core/test/fixtures/authored_native_style.rfwtxt');
    if (Platform.environment['UPDATE_STYLE_FIXTURE'] == '1') {
      fileOut.parent.createSync(recursive: true);
      fileOut.writeAsStringSync(text);
    }
    expect(fileOut.readAsStringSync(), text);
  });
}

final class _NoCaptures implements ValueReader {
  @override
  Object? read(List<Object> path, ValueType type) => throw StateError('$path');
  @override
  int length(List<Object> path) => throw StateError('$path');
}
