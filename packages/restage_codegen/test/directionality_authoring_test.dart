import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';

import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_native_value_plan.dart';
import 'package:rfw_catalog_compiler/src/walker/default_value_resolver.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final catalog = decodeCatalog(
    File(
      '../restage_core/lib/src/widget_catalog/catalog.json',
    ).readAsStringSync(),
  );

  Future<TranslationResult> translate(
    String body, {
    String declarations = '',
  }) async {
    final expression = await parseExpressionFromSourceForTest(
      '''
import 'package:flutter/widgets.dart';
$declarations
Widget x() => $body;
''',
      rootPackage: 'apps_examples',
    );
    return ExpressionTranslator(
      catalog: catalog,
      helpers: HelperRegistry(),
    ).translate(expression);
  }

  void qualifyRadiusFixture(String name, List<String> declarations) {
    final text = 'import restage.core;\n${declarations.join('\n')}\n';
    final fixture = File('../restage_core/test/fixtures/$name');
    if (Platform.environment['WRITE_DIRECTIONAL_RADIUS_FIXTURES'] == '1') {
      fixture.writeAsStringSync(text);
    }
    expect(
      fmt.encodeLibraryBlob(fmt.parseLibraryFile(text)),
      fmt.encodeLibraryBlob(
        fmt.parseLibraryFile(fixture.readAsStringSync()),
      ),
    );
  }

  test(
    'authored directionality fixture preserves physical and logical insets',
    () async {
      final result = await translate(
        '''Directionality(textDirection: TextDirection.rtl, child: Row(children: [
      Padding(padding: EdgeInsets.only(left: 7), child: Text('physical')),
      Padding(padding: EdgeInsetsDirectional.only(start: 11), child: Text('logical')),
    ]))''',
      );
      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      final text = 'import restage.core;\nwidget Surface = ${result.dsl};\n';
      final fixture = File(
        '../restage_core/test/fixtures/directionality.rfwtxt',
      );
      if (Platform.environment['WRITE_DIRECTIONALITY_FIXTURE'] == '1') {
        fixture.parent.createSync(recursive: true);
        fixture.writeAsStringSync(text);
      }
      expect(
        fmt.encodeLibraryBlob(fmt.parseLibraryFile(text)),
        fmt.encodeLibraryBlob(
          fmt.parseLibraryFile(fixture.readAsStringSync()),
        ),
      );
      final validation = validateModelAgainstCatalog(
        fmt.parseLibraryFile(text),
        catalog,
      );
      expect(validation, isEmpty);
      expect(
        deriveSurfaceCapability(
          fmt.parseLibraryFile(text),
          catalog,
        ).builtInFloor,
        17,
      );
      expect(result.dsl, contains('left: 7.0'));
      expect(result.dsl, contains('start: 11.0'));
      final directionality = catalog.widgets.singleWhere(
        (w) => w.name == 'Directionality',
      );
      expect(directionality.sinceVersion, 17);
      final padding = catalog.widgets.singleWhere((w) => w.name == 'Padding');
      expect(
        padding.properties.singleWhere((p) => p.name == 'padding').sinceVersion,
        kBaselineCatalogVersion,
      );
    },
  );

  for (final body in [
    'Padding(padding: EdgeInsetsDirectional.fromSTEB(1, 2, 3, 4), child: Text("x"))',
    'Padding(padding: EdgeInsetsDirectional.symmetric(horizontal: 2), child: Text("x"))',
    'Padding(padding: logical, child: Text("x"))',
    'Padding(padding: EdgeInsetsDirectional.zero, child: Text("x"))',
    'Padding(padding: EdgeInsetsDirectional.all(3), child: Text("x"))',
    'ClipRRect(borderRadius: corners, child: Text("x"))',
    'ClipRRect(borderRadius: BorderRadiusDirectional.circular(8), child: Text("x"))',
    'ClipRRect(borderRadius: BorderRadiusDirectional.all(Radius.circular(8)), child: Text("x"))',
    'ClipRRect(borderRadius: BorderRadiusDirectional.zero, child: Text("x"))',
    'ClipRRect(borderRadius: BorderRadiusDirectional.horizontal(start: Radius.circular(4)), child: Text("x"))',
    'DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: AlignmentDirectional.centerStart, end: AlignmentDirectional(1, 0), colors: [Color(0xFF000000), Color(0xFFFFFFFF)])))',
    'DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(center: AlignmentDirectional.centerEnd, colors: [Color(0xFF000000), Color(0xFFFFFFFF)])))',
    'Container(decoration: BoxDecoration(image: DecorationImage(image: AssetImage("image.png"), alignment: AlignmentDirectional.centerEnd)))',
    'ClipRRect(borderRadius: BorderRadiusDirectional.only(topStart: Radius.circular(13)), child: Text("x"))',
    'Container(decoration: BoxDecoration(borderRadius: BorderRadiusDirectional.only(topStart: Radius.circular(13))))',
    'Row(textDirection: TextDirection.rtl, children: [Text("x", textDirection: TextDirection.ltr)])',
  ]) {
    test('native value authoring: $body', () async {
      final result = await translate(
        body,
        declarations:
            'const logical = EdgeInsetsDirectional.only(start: 9); const corners = BorderRadiusDirectional.only(topEnd: Radius.circular(8));',
      );
      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(result.dsl, isNotEmpty);
      final model = fmt.parseLibraryFile(
        'import restage.core; widget Surface = ${result.dsl};',
      );
      // Directional gradient alignments were already decoded by rfw.
      expect(
        deriveSurfaceCapability(model, catalog).builtInFloor,
        body.contains('gradient:') ? kBaselineCatalogVersion : 17,
      );
      if (body.contains('BorderRadiusDirectional') ||
          body.contains('borderRadius: corners')) {
        expect(result.dsl, contains('borderRadiusTop'));
      }
      if (body.contains('AlignmentDirectional')) {
        expect(result.dsl, contains('{start:'));
      }
    });
  }

  test('nested radius aliases match inline native corners', () async {
    final declarations = <String>[];
    for (final widget in ['Container', 'AnimatedContainer']) {
      for (final directional in [false, true]) {
        final radiusType = directional
            ? 'BorderRadiusDirectional'
            : 'BorderRadius';
        final corner = directional ? 'topStart' : 'topLeft';
        final radius = '$radiusType.only($corner: Radius.circular(13))';
        String body(String value) =>
            '$widget(${widget == 'AnimatedContainer' ? 'duration: Duration(milliseconds: 1), ' : ''}decoration: BoxDecoration(borderRadius: $value), child: SizedBox(width: 40, height: 30))';
        final inline = await translate(body(radius));
        final alias = await translate(
          body('alias'),
          declarations: 'const corners = $radius; const alias = corners;',
        );
        for (final result in [inline, alias]) {
          expect(
            result.issues.where((issue) => !issue.code.isInformational),
            isEmpty,
          );
        }
        final inlineModel = fmt.parseLibraryFile(
          'import restage.core; widget Surface = ${inline.dsl};',
        );
        final aliasModel = fmt.parseLibraryFile(
          'import restage.core; widget Surface = ${alias.dsl};',
        );
        final inlineArgs =
            (inlineModel.widgets.single.root as fmt.ConstructorCall).arguments;
        final aliasArgs =
            (aliasModel.widgets.single.root as fmt.ConstructorCall).arguments;
        final cornerNames = directional
            ? ['TopStart', 'TopEnd', 'BottomStart', 'BottomEnd']
            : ['TopLeft', 'TopRight', 'BottomLeft', 'BottomRight'];
        for (final name in cornerNames) {
          expect(
            aliasArgs['borderRadius$name'] ?? 0.0,
            inlineArgs['borderRadius$name'] ?? 0.0,
          );
        }
        expect(aliasArgs['borderRadius${cornerNames.first}'], 13.0);
        expect(
          deriveSurfaceCapability(aliasModel, catalog).builtInFloor,
          directional
              ? 17
              : deriveSurfaceCapability(inlineModel, catalog).builtInFloor,
        );
        declarations.add(
          'widget ${widget}${directional ? 'Logical' : 'Physical'}Alias = ${alias.dsl};',
        );
      }
    }
    for (final widget in ['Container', 'AnimatedContainer']) {
      final result = await translate(
        '$widget(${widget == 'AnimatedContainer' ? 'duration: Duration(milliseconds: 1), ' : ''}decoration: BoxDecoration(borderRadius: alias))',
        declarations:
            'const radius = BorderRadius.circular(13); const alias = radius;',
      );
      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      final model = fmt.parseLibraryFile(
        'import restage.core; widget Surface = ${result.dsl};',
      );
      expect(
        (model.widgets.single.root as fmt.ConstructorCall)
            .arguments['borderRadius'],
        13.0,
      );
    }
    final lookalike = await translate(
      'Container(decoration: BoxDecoration(borderRadius: alias))',
      declarations: """
class BorderRadiusDirectional {
  const BorderRadiusDirectional.only({Radius? topStart});
}
const alias = BorderRadiusDirectional.only(topStart: Radius.circular(13));
""",
    );
    expect(
      lookalike.issues.where((issue) => !issue.code.isInformational),
      isNotEmpty,
    );
    qualifyRadiusFixture('directional_radius_aliases.rfwtxt', declarations);
  });

  test(
    'empty directional radius constructors preserve explicit logical zero',
    () async {
      final declarations = <String>[];
      for (final constructor in [
        'only()',
        'vertical()',
        'horizontal()',
        'zero',
      ]) {
        for (final nested in [false, true]) {
          final radius = 'BorderRadiusDirectional.$constructor';
          final result = await translate(
            nested
                ? 'Container(decoration: BoxDecoration(borderRadius: $radius), child: SizedBox(width: 40, height: 30))'
                : 'ClipRRect(borderRadius: $radius, child: SizedBox(width: 40, height: 30))',
          );
          expect(
            result.issues.where((issue) => !issue.code.isInformational),
            isEmpty,
          );
          final model = fmt.parseLibraryFile(
            'import restage.core; widget Surface = ${result.dsl};',
          );
          final args =
              (model.widgets.single.root as fmt.ConstructorCall).arguments;
          for (final corner in [
            'TopStart',
            'TopEnd',
            'BottomStart',
            'BottomEnd',
          ]) {
            expect(
              args['borderRadius$corner'],
              0.0,
              reason: '$constructor ${nested ? 'nested' : 'direct'}',
            );
          }
          expect(deriveSurfaceCapability(model, catalog).builtInFloor, 17);
          final name = constructor.replaceAll('()', '');
          declarations.add(
            'widget ${nested ? 'Nested' : 'Direct'}$name = ${result.dsl};',
          );
        }
      }
      qualifyRadiusFixture('directional_radius_empty.rfwtxt', declarations);
    },
  );

  test('lookalike directional inset constructor is refused', () async {
    final result = await translate(
      'Padding(padding: EdgeInsetsDirectional.only(start: 9), child: Text("x"))',
      declarations: '''
class EdgeInsetsDirectional {
  const EdgeInsetsDirectional.only({double start = 0});
}
''',
    );
    expect(
      result.issues.where((issue) => !issue.code.isInformational),
      isNotEmpty,
    );
  });

  test('concrete Alignment slots do not admit directional values', () async {
    final result = await translate(
      'AnimatedScale(scale: 2, duration: Duration.zero, alignment: AlignmentDirectional.centerStart, child: Text("x"))',
    );
    expect(
      result.issues.where((issue) => !issue.code.isInformational),
      isNotEmpty,
    );
  });

  test(
    'concrete inset factories and typed defaults keep their Flutter subtype',
    () {
      for (final name in [
        'EdgeInsets',
        'EdgeInsetsDirectional',
        'EdgeInsetsGeometry',
      ]) {
        final entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          childrenSlot: ChildrenSlot.none,
          name: 'InsetWidget',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: '',
          flutterType: 'package:example/widget.dart#InsetWidget',
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'padding',
              type: PropertyType.edgeInsets,
              description: '',
              valueShape: ScalarShape(
                propertyType: PropertyType.edgeInsets,
                dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: name,
                ),
              ),
              defaultSource: LiteralDefault(
                name == 'EdgeInsetsDirectional'
                    ? {'start': 1.0, 'top': 2.0, 'end': 3.0, 'bottom': 4.0}
                    : {'left': 1.0, 'top': 2.0, 'right': 3.0, 'bottom': 4.0},
              ),
            ),
          ],
        );
        final emitted = emitFactoryFunction(entry)!;
        expect(
          emitted,
          contains(
            name == 'EdgeInsetsDirectional'
                ? 'directionalEdgeInsets'
                : name == 'EdgeInsets'
                ? 'physicalEdgeInsets'
                : 'RestageDecoders.edgeInsets',
          ),
        );
        expect(
          emitted,
          contains(
            name == 'EdgeInsetsDirectional'
                ? 'EdgeInsetsDirectional.fromSTEB(1.0, 2.0, 3.0, 4.0)'
                : 'EdgeInsets.fromLTRB(1.0, 2.0, 3.0, 4.0)',
          ),
        );
      }
    },
  );

  test(
    'resolved native defaults retain physical and directional keys',
    () async {
      final expression = await parseExpressionFromSourceForTest(
        """
import 'package:flutter/widgets.dart';
class InsetsDefaults {
  const InsetsDefaults({this.physical = const EdgeInsets.only(left: 7), this.logical = const EdgeInsetsDirectional.only(start: 11)});
  final EdgeInsets physical;
  final EdgeInsetsDirectional logical;
}
Object x() => const InsetsDefaults();
""",
        rootPackage: 'apps_examples',
      );
      final constructor =
          (expression as InstanceCreationExpression).constructorName.element!;
      final parameters = constructor.formalParameters;
      expect(
        resolveParameterDefault(
          parameters[0],
          targetType: PropertyType.edgeInsets,
        ),
        const LiteralDefault(
          {'left': 7.0, 'top': 0.0, 'right': 0.0, 'bottom': 0.0},
        ),
      );
      expect(
        resolveParameterDefault(
          parameters[1],
          targetType: PropertyType.edgeInsets,
        ),
        const LiteralDefault(
          {'start': 11.0, 'top': 0.0, 'end': 0.0, 'bottom': 0.0},
        ),
      );
    },
  );

  test('Widgetbook geometry literals preserve native inset subclasses', () {
    for (final directional in [false, true]) {
      final value = WidgetbookFrameworkValuePlan(
        type: const WidgetbookDartTypePlan(
          libraryUri: 'package:flutter/painting.dart',
          symbol: 'EdgeInsetsGeometry',
        ),
        kind: WidgetbookFrameworkLiteralKind.edgeInsets,
        value: directional
            ? {'start': 1.0, 'top': 2.0, 'end': 3.0, 'bottom': 4.0}
            : {'left': 1.0, 'top': 2.0, 'right': 3.0, 'bottom': 4.0},
      );
      final renderer = WidgetbookNativeDartRenderer(
        currentLibraryUri: 'package:example/widget.dart',
        values: [value],
      );
      expect(
        renderer.renderValue(value),
        contains(
          directional
              ? 'EdgeInsetsDirectional.fromSTEB(1.0, 2.0, 3.0, 4.0)'
              : 'EdgeInsets.fromLTRB(1.0, 2.0, 3.0, 4.0)',
        ),
      );
    }
  });

  test('generated factories retain native direction and geometry decoders', () {
    final factories = catalog.widgets.where(
      (entry) => [
        'Directionality',
        'Row',
        'Stack',
        'Text',
        'TextRich',
        'Semantics',
      ].contains(entry.name),
    );
    for (final entry in factories) {
      final direction = entry.properties.singleWhere(
        (p) => p.name == 'textDirection',
      );
      expect(direction.sinceVersion, 17);
      expect(
        emitFactoryFunction(entry, nativeIndex: NativeCatalogIndex(catalog)),
        contains('textDirection:'),
      );
      if (entry.name != 'Directionality') {
        expect(direction.defaultValue, isNull);
      }
    }
  });
}
