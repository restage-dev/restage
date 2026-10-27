import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('authored span collection fixture preserves native collection structure',
      () async {
    final probe = await parseMethodExpressionFromSourceForTest(r'''
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:restage/restage.dart';
class P extends StatelessWidget {
  const P({required this.labels, required this.groups, required this.show});
  final List<String> labels;
  final List<List<String>> groups;
  final bool show;
  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: [
    ...const [TextSpan(text: 'start')],
    if (show) const TextSpan(text: 'heading'),
    ...?(show ? const [TextSpan(text: 'nullable')] : null),
    ...?(true ? [if (show) const TextSpan(text: 'selected')] : null),
    for (final label in labels) ...[
      TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w600), recognizer: TapGestureRecognizer()
        ..onTap = paywallEvent('pick', args: {'value': label})),
      if (show) const TextSpan(text: '|'),
      const TextSpan(text: '(', children: [TextSpan(text: ')')]),
    ],
    for (final extra in const ['x', 'y']) ...[
      TextSpan(text: extra),
      if (show) const TextSpan(text: '~'),
    ],
    for (final group in groups) ...[
      for (final item in group) TextSpan(text: item),
    ],
    const TextSpan(text: 'end', children: []),
  ]));
}
''', className: 'P');
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    final result = ExpressionTranslator(
            catalog: catalog,
            helpers: HelperRegistry()..registerAll(paywallHelpers))
        .translate(
      probe.expression,
      rootParams: [
        for (final parameter
            in probe.classes['P']!.unnamedConstructor!.formalParameters)
          RootContextParam(
              name: parameter.name!,
              type: parameter.type,
              typeCode: parameter.type.getDisplayString(),
              kind: RootContextParamKind.named,
              hostDataShape:
                  deriveHostDataShape(parameter.type, root: parameter.name!)
                      .shape,
              field: (parameter as FieldFormalParameterElement).field,
              isRequired: true,
              defaultValueCode: null,
              hasNullDefault: false)
      ],
    );
    expect(
        result.issues.where((issue) => !issue.code.isInformational), isEmpty);
    final source = 'import restage.core; widget Root = ${result.dsl};\n';
    rfw.parseLibraryFile(source);
    expect(result.dsl, contains('...for label in data.context.labels: ['));
    final fixture = File(Platform.environment['SPAN_COLLECTION_FIXTURE_PATH'] ??
        '../restage_core/test/fixtures/span_collections_compiled.rfwtxt');
    if (Platform.environment['REGEN_SPAN_COLLECTION_FIXTURE'] == '1')
      fixture.writeAsStringSync(source);
    expect(fixture.readAsStringSync(), source);
  });

  test('span collections preserve callback-local builder frames', () async {
    final probe = await parseMethodExpressionFromSourceForTest(r'''
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:restage/restage.dart';
class P extends StatelessWidget {
  const P({required this.labels});
  final List<String> labels;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) =>
    Text.rich(TextSpan(children: [for (final label in labels)
      TextSpan(text: '[$label:${c.maxWidth}]', recognizer: TapGestureRecognizer()
        ..onTap = paywallEvent('pick', args: {'label': label, 'width': c.maxWidth})),
    ])));
}
''', className: 'P');
    final parameter =
        probe.classes['P']!.unnamedConstructor!.formalParameters.single;
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    final result = ExpressionTranslator(
            catalog: catalog,
            helpers: HelperRegistry()..registerAll(paywallHelpers))
        .translate(
      probe.expression,
      rootParams: [
        RootContextParam(
            name: parameter.name!,
            type: parameter.type,
            typeCode: parameter.type.getDisplayString(),
            kind: RootContextParamKind.named,
            hostDataShape:
                deriveHostDataShape(parameter.type, root: parameter.name!)
                    .shape,
            field: (parameter as FieldFormalParameterElement).field,
            isRequired: true,
            defaultValueCode: null,
            hasNullDefault: false)
      ],
    );
    expect(
        result.issues.where((issue) => !issue.code.isInformational), isEmpty);
    final library = rfw
        .parseLibraryFile('import restage.core; widget Root = ${result.dsl};');
    final fixture = File(Platform
            .environment['SPAN_COLLECTION_BUILDER_FIXTURE_PATH'] ??
        '../restage_core/test/fixtures/span_collection_builder_compiled.rfwtxt');
    final source = 'import restage.core; widget Root = ${result.dsl};\n';
    if (Platform.environment['REGEN_SPAN_COLLECTION_FIXTURE'] == '1')
      fixture.writeAsStringSync(source);
    expect(fixture.readAsStringSync(), source);
    final root = library.widgets.single.root as rfw.ConstructorCall;
    final envelope = decodeRfwProgramEnvelope(root.arguments['builder'])!;
    expect(envelope.bodies, hasLength(1));
    expect(
        envelope
            .frameTypes(0)
            .values
            .expand((types) => types)
            .map((type) => type.kind),
        contains('double'));
  });

  test('span collection controls preserve builder and helper bindings',
      () async {
    final probe = await parseMethodExpressionFromSourceForTest(r'''
import 'package:flutter/widgets.dart';
List<InlineSpan> choose(bool flag, String label) =>
    flag && flag ? [TextSpan(text: label)] : [];
List<InlineSpan> signs(List<bool> values) => [for (final flag in values)
  if (flag) const TextSpan(text: '+') else const TextSpan(text: '-')];
class P extends StatelessWidget {
  const P({required this.flags, required this.show});
  final List<bool> flags;
  final bool show;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) =>
    Text.rich(TextSpan(children: [
      for (final flag in flags)
        if (flag) const TextSpan(text: 'yes') else const TextSpan(text: 'no'),
      ...choose(show, 'ok'),
      for (final label in const ['a', 'b'])
        if (label == 'a') TextSpan(text: label),
      for (final flag in flags) ...choose(flag, 'local'),
      ...signs(flags),
    ])));
}
''', className: 'P');
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    final result =
        ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
            .translate(
      probe.expression,
      rootParams: [
        for (final parameter
            in probe.classes['P']!.unnamedConstructor!.formalParameters)
          RootContextParam(
              name: parameter.name!,
              type: parameter.type,
              typeCode: parameter.type.getDisplayString(),
              kind: RootContextParamKind.named,
              hostDataShape:
                  deriveHostDataShape(parameter.type, root: parameter.name!)
                      .shape,
              field: (parameter as FieldFormalParameterElement).field,
              isRequired: true,
              defaultValueCode: null,
              hasNullDefault: false)
      ],
    );
    expect(
        result.issues.where((issue) => !issue.code.isInformational), isEmpty);
    final source = 'import restage.core; widget Root = ${result.dsl};\n';
    rfw.parseLibraryFile(source);
    final fixture = File(Platform
            .environment['SPAN_COLLECTION_CONTROLS_FIXTURE_PATH'] ??
        '../restage_core/test/fixtures/span_collection_controls_compiled.rfwtxt');
    if (Platform.environment['REGEN_SPAN_COLLECTION_FIXTURE'] == '1')
      fixture.writeAsStringSync(source);
    expect(fixture.readAsStringSync(), source);
  });

  test('authored span events retain typed builder frames in installed fixture',
      () async {
    final probe = await parseMethodExpressionFromSourceForTest(r'''
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:restage/restage.dart';
class P extends StatelessWidget {
  const P({required this.tag});
  final String tag;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
    final captured = '$tag:${c.maxWidth}';
    if (tag == 'old') {
      return Text.rich(TextSpan(text: 'Tap', recognizer:
        TapGestureRecognizer()..onTap = paywallEvent('pick.old', args: {'value': captured})));
    }
    return Text.rich(TextSpan(text: 'Tap', recognizer:
      TapGestureRecognizer()..onTap = paywallEvent('pick.new', args: {'value': captured})));
  });
}
''', className: 'P');
    final parameter =
        probe.classes['P']!.unnamedConstructor!.formalParameters.single;
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    final result = ExpressionTranslator(
            catalog: catalog,
            helpers: HelperRegistry()..registerAll(paywallHelpers))
        .translate(
      probe.expression,
      rootParams: [
        RootContextParam(
            name: 'tag',
            type: parameter.type,
            typeCode: 'String',
            kind: RootContextParamKind.named,
            hostDataShape:
                deriveHostDataShape(parameter.type, root: 'tag').shape,
            field: (parameter as FieldFormalParameterElement).field,
            isRequired: true,
            defaultValueCode: null,
            hasNullDefault: false)
      ],
    );
    expect(
        result.issues.where((issue) => !issue.code.isInformational), isEmpty);
    final source = 'import restage.core; widget Root = ${result.dsl};\n';
    final library = rfw.parseLibraryFile(source);
    final root = library.widgets.single.root as rfw.ConstructorCall;
    final envelope = decodeRfwProgramEnvelope(root.arguments['builder'])!;
    expect(envelope.bodies, hasLength(2));
    for (var body = 0; body < 2; body++) {
      expect(
          envelope
              .frameTypes(body)
              .values
              .expand((types) => types)
              .map((type) => type.kind),
          contains('String'));
    }
    expect(deriveSurfaceCapability(library, catalog).builtInFloor, 22);
    expect(
        surfaceScreenContractGaps(library,
            events: SurfaceScreenEventSchema(events: [
              for (final name in ['pick.old', 'pick.new'])
                SurfaceScreenEvent(
                    id: name,
                    arguments: SurfaceScreenEventObjectArguments(
                        const SurfaceScreenEventMapShapeV1(
                            SurfaceScreenEventScalarShapeV1(
                                SurfaceScreenEventScalarKind.string))))
            ]),
            context: SurfaceScreenHostDataSchema(const {
              'tag': SurfaceScreenHostDataScalarShapeV1(
                  SurfaceScreenHostDataScalarKind.string)
            })),
        isEmpty);
    final fixture =
        File('../restage_core/test/fixtures/span_builder_compiled.rfwtxt');
    if (Platform.environment['REGEN_SPAN_BUILDER_FIXTURE'] == '1')
      fixture.writeAsStringSync(source);
    expect(fixture.readAsStringSync(), source);
  });
}
