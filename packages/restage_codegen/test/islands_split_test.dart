import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/islands/islands.dart';
import 'package:restage_codegen/src/surface_publication/host_data_contract.dart';
import 'package:restage_shared/restage_shared.dart'
    show SurfaceScreenHostDataContractHash;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _header = '''
import 'package:flutter/widgets.dart';

class Opaque extends StatelessWidget {
  const Opaque({super.key, required this.child, this.tint = 0, this.label});
  final Widget child;
  final int tint;
  final String? label;
  @override
  Widget build(BuildContext context) => ColoredBox(color: Color(0xFF000000 + tint), child: child);
}

class Shelf extends StatelessWidget {
  const Shelf({super.key, required this.children, this.gap = 0});
  final List<Widget> children;
  final double gap;
  @override
  Widget build(BuildContext context) => Column(children: children);
}

class Cubit {
  String get name => 'n';
  void buy() {}
  void pick(String id) {}
}

class Scope extends StatelessWidget {
  const Scope({super.key, required this.builder});
  final Widget Function(BuildContext context, int count) builder;
  @override
  Widget build(BuildContext context) => builder(context, 1);
}

abstract class OneChildStateful extends StatefulWidget {
  const OneChildStateful({super.key, Widget? child}) : _child = child;
  final Widget? _child;
}

abstract class OneChildState<T extends OneChildStateful> extends State<T> {
  Widget buildWithChild(BuildContext context, Widget? child);
  @override
  Widget build(BuildContext context) => buildWithChild(context, widget._child);
}

class Listens extends OneChildStateful {
  const Listens({super.key, required this.listener, Widget? child})
      : super(child: child);
  final void Function(int) listener;
  @override
  State<Listens> createState() => _ListensState();
}

class _ListensState extends OneChildState<Listens> {
  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    assert(child != null);
    return child!;
  }
}

abstract class CountBuilderBase extends StatefulWidget {
  const CountBuilderBase({super.key});
  Widget build(BuildContext context, int count);
  @override
  State<CountBuilderBase> createState() => _CountBuilderBaseState();
}

class _CountBuilderBaseState extends State<CountBuilderBase> {
  int _count = 0;
  @override
  Widget build(BuildContext context) {
    if (_count < 0) _count = 0;
    return Listens(
      listener: (value) => setState(() => _count = value),
      child: widget.build(context, _count),
    );
  }
}

class CountBuilder extends CountBuilderBase {
  const CountBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, int count) builder;
  @override
  Widget build(BuildContext context, int count) => builder(context, count);
}

class RenamedBuilder extends CountBuilderBase {
  const RenamedBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, int count) builder;
  @override
  Widget build(BuildContext ctx, int n) => builder(ctx, n);
}

mixin BuildsWithBuilder on CountBuilderBase {
  Widget Function(BuildContext context, int count) get builder;
  @override
  Widget build(BuildContext context, int count) => builder(context, count);
}

class MixedBuilder extends CountBuilderBase with BuildsWithBuilder {
  const MixedBuilder({super.key, required this.builder});
  @override
  final Widget Function(BuildContext context, int count) builder;
}

abstract class OneChildStateless extends StatelessWidget {
  const OneChildStateless({super.key, Widget? child}) : _child = child;
  final Widget? _child;
  Widget buildWithChild(BuildContext context, Widget? child);
  @override
  Widget build(BuildContext context) => buildWithChild(context, _child);
}

class Uses extends OneChildStateless {
  const Uses({
    super.key,
    required Widget Function(BuildContext context, int n, Widget? child)
        builder,
    super.child,
  }) : _builder = builder;
  final Widget Function(BuildContext context, int n, Widget? child) _builder;
  @override
  Widget buildWithChild(BuildContext context, Widget? child) =>
      _builder(context, 1, child);
}

class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

class Flip extends StatelessWidget {
  const Flip({super.key, required this.pick, required this.child});
  final TextDirection Function() pick;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: pick(), child: child);
}

class Shop {
  Shop(this.title, this.count, this._secret, this.ticks, this.onBuy, this.tags);
  final String title;
  final int count;
  final String _secret;
  final Stream<int> ticks;
  final void Function() onBuy;
  final List<String> tags;
  String get shout => title.toUpperCase() + _secret;
}

class ShopBuilder extends StatelessWidget {
  const ShopBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, Shop shop) builder;
  @override
  Widget build(BuildContext context) =>
      builder(context, Shop('a', 1, 's', const Stream.empty(), () {}, []));
}

class Track extends StatelessWidget {
  const Track(this.builder, {super.key});
  final Widget Function() builder;
  @override
  Widget build(BuildContext context) => builder();
}

class Labels {
  static Labels of(BuildContext context) => Labels();
  String get name => 'n';
}

class Plan {
  const Plan(this.id, this.rank, [this.features = const []]);
  final String id;
  final int rank;
  final List<String> features;
}
''';

Catalog _catalog() {
  final catalogs = [
    for (final package in ['restage_core', 'restage_material'])
      decodeCatalog(
        File(
          '../$package/lib/src/widget_catalog/catalog.json',
        ).readAsStringSync(),
      ),
  ];
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '',
    libraries: {for (final catalog in catalogs) ...catalog.libraries},
    widgets: [for (final catalog in catalogs) ...catalog.widgets],
    structuredTypes: [
      for (final catalog in catalogs) ...catalog.structuredTypes,
    ],
    unions: [for (final catalog in catalogs) ...catalog.unions],
  );
}

final _sharedCatalog = _catalog();

Future<TranslationResult> _split(
  String body, {
  String fields = '',
  String params = '',
  String extra = '',
  bool stateful = false,
  String? entryId,
  Catalog? catalog,
}) async {
  final source = stateful
      ? '''
$_header
$extra
class Surface extends StatefulWidget {
  const Surface({super.key});
  @override
  State<Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<Surface> {
$fields
  @override
  Widget build(BuildContext context) $body
}
'''
      : '''
$_header
$extra
class Surface extends StatelessWidget {
  const Surface({super.key${params.isEmpty ? '' : ', $params'}});
$fields
  @override
  Widget build(BuildContext context) $body
}
''';
  final owner = stateful ? '_SurfaceState' : 'Surface';
  final probe = await parseMethodExpressionFromSourceForTest(
    source,
    className: owner,
    rootPackage: 'apps_examples',
    contentFree: true,
  );
  return ExpressionTranslator(
    catalog: catalog ?? _sharedCatalog,
    helpers: HelperRegistry(),
  ).translate(
    probe.expression,
    hoistInMount: true,
    entryId: entryId,
    liftedState: stateful ? probe.classes[owner] : null,
    contentFree: probe.contentFree,
    buildContextParameter: probe.expression
        .thisOrAncestorOfType<MethodDeclaration>()!
        .declaredFragment!
        .element
        .formalParameters
        .first,
    rootParams: [
      for (final parameter
          in probe.classes['Surface']!.unnamedConstructor!.formalParameters)
        if (parameter is FieldFormalParameterElement)
          RootContextParam(
            name: parameter.name!,
            type: parameter.type,
            typeCode: parameter.type.getDisplayString(),
            kind: RootContextParamKind.named,
            hostDataShape: deriveHostDataShape(
              parameter.type,
              root: parameter.name!,
            ).shape,
            field: parameter.field,
            isRequired: parameter.isRequired,
            defaultValueCode: null,
            hasNullDefault: false,
          ),
    ],
  );
}

List<String> _values(TranslationResult result) => [
  for (final value in result.hoisted)
    if (!isIslandAction(value)) value.label,
]..sort();

List<String> _actions(TranslationResult result) => [
  for (final value in result.hoisted)
    if (isIslandAction(value)) value.label,
];

List<String> _mount(TranslationResult result) => [
  for (final node in [...?result.split?.shell])
    '${node.widget} ${node.reason.name}',
  if (result.split?.state case final state?) '${state.name} state',
];

String _describe(TranslationResult result) => [
  for (final island in result.islands)
    '${island.id} slots=${island.slots.map((s) => s.name).join(',')} '
        'props=${island.properties.map((p) => p.name).join(',')}'
        '${island.items.isEmpty ? '' : ' item'} '
        'reason=${island.reason?.code.name}',
].join('\n');

typedef _Row = ({
  String name,
  String body,
  String fields,
  String params,
  bool stateful,
  List<String> mount,
  String dsl,
  String islands,
  List<String> values,
  List<String> actions,
});

void main() {
  final rows = <_Row>[
    (
      name: 'the innermost widget is the island; slots and literals',
      body:
          '=> Column(children: [Text(title), '
          'Opaque(tint: 3, label: title, child: Text(title))]);',
      fields: 'final String title;',
      params: 'required this.title',
      stateful: false,
      mount: [],
      dsl:
          'Column(children: [Text(text: data.context.title), '
          'Surface_Opaque_0(tint: 3, child: Text(text: data.context.title))])',
      islands:
          'Surface.build/Opaque#0 slots=child props=tint '
          'reason=unknownWidget',
      values: [],
      actions: [],
    ),
    (
      name: 'islands and delivered nodes nest to any depth',
      body:
          "=> Column(children: [Opaque(child: Center(child: Shelf(gap: 4, "
          "children: [Text('a'), Opaque(child: Text('b'))])))]);",
      fields: '',
      params: '',
      stateful: false,
      mount: [],
      dsl:
          'Column(children: [Surface_Opaque_0(child: Center(child: '
          'Surface_Shelf_0(gap: 4.0, children: [Text(text: "a"), '
          'Surface_Opaque_1(child: Text(text: "b"))])))])',
      islands:
          'Surface.build/Opaque#0 slots=child props= '
          'reason=unknownWidget\n'
          'Surface.build/Opaque#1 slots=child props= reason=unknownWidget\n'
          'Surface.build/Shelf#0 slots=children props=gap '
          'reason=unknownWidget',
      values: [],
      actions: [],
    ),
    (
      name: 'an island in a delivered loop takes the item',
      body:
          '=> Column(children: [for (final p in plans) '
          'Opaque(tint: p.rank, child: Text(p.id))]);',
      fields: 'final List<Plan> plans;',
      params: 'required this.plans',
      stateful: false,
      mount: [],
      dsl:
          'Column(children: [...for p in data.context.plans: '
          'Surface_Opaque_0(child: Text(text: p.id), '
          'restageItems: [p._hc95ca01d90])])',
      islands:
          'Surface.build/Opaque#0 slots=child props= item '
          'reason=unknownWidget',
      values: ['index of p in plans'],
      actions: [],
    ),
    (
      name: 'an island in a loop takes its position without reading the item',
      body:
          '=> Column(children: [for (final p in plans) '
          "Opaque(label: 'x', child: Text(p.id))]);",
      fields: 'final List<Plan> plans;',
      params: 'required this.plans',
      stateful: false,
      mount: [],
      dsl:
          'Column(children: [...for p in data.context.plans: '
          'Surface_Opaque_0(label: "x", child: Text(text: p.id), '
          'restageItems: [p._hc95ca01d90])])',
      islands:
          'Surface.build/Opaque#0 slots=child props=label item '
          'reason=unknownWidget',
      values: ['index of p in plans'],
      actions: [],
    ),
    (
      name:
          'an island in a nested loop reading the outer item takes both '
          'positions',
      body:
          '=> Column(children: [for (final p in plans) for (final f in '
          'p.features) Opaque(tint: p.rank, child: Text(f))]);',
      fields: 'final List<Plan> plans;',
      params: 'required this.plans',
      stateful: false,
      mount: [],
      dsl:
          'Column(children: [...for p in data.context.plans: '
          '[...for presence in [0]: [...for f in p._h107688f0bd: '
          'Surface_Opaque_0(child: Text(text: f._h53ed5e36fb), '
          'restageItems: [p._hc95ca01d90, f._h08142d463b])]]])',
      islands:
          'Surface.build/Opaque#0 slots=child props= item '
          'reason=unknownWidget',
      values: [
        'f',
        'index of f in p.features',
        'index of p in plans',
        'p.features',
      ],
      actions: [],
    ),
    (
      name: 'a value the mount computes and an action it holds',
      body:
          '=> GestureDetector(onTap: () => cubit.pick(title.trim()), '
          'child: Text(title.toUpperCase()));',
      fields: 'final Cubit cubit; final String title;',
      params: 'required this.cubit, required this.title',
      stateful: false,
      mount: [],
      dsl: '',
      islands: '',
      values: ['cubit', 'title', 'title.toUpperCase()'],
      actions: ['() => _restageInput0.pick(_restageInput1.trim())'],
    ),
    (
      name: 'an island whose rest the mount cannot evaluate moves outward',
      body:
          '=> Column(children: [LayoutBuilder(builder: (context, constraints) '
          '=> Opaque(tint: constraints.maxWidth.round(), '
          'child: const Text("a")))]);',
      fields: '',
      params: '',
      stateful: false,
      mount: [],
      dsl: 'Column(children: [Surface_LayoutBuilder_0()])',
      islands:
          'Surface.build/LayoutBuilder#0 slots= props= '
          'reason=unknownWidget',
      values: [],
      actions: [],
    ),
    (
      name: 'the root shell stays in the mount; a root builder dissolves',
      body:
          r"=> Opaque(child: Scope(builder: (context, count) { "
          r"final label = 'x$count'; "
          r"return Column(children: [Text(label), Text(title)]); }));",
      fields: 'final String title;',
      params: 'required this.title',
      stateful: false,
      mount: ['Opaque notDelivered', 'Scope builder'],
      dsl:
          'Column(children: [TextRich(textSpan: '
          '{ text: data.context._h894f555429 }), '
          'Text(text: data.context.title)])',
      islands: '',
      values: [r"'x$count'", 'count'],
      actions: [],
    ),
    (
      name: 'copy around an app value stays in the payload',
      body: r"=> Text('Hello ${Labels.of(context).name} and welcome');",
      fields: '',
      params: '',
      stateful: false,
      mount: [],
      dsl:
          'TextRich(textSpan: { children: [{ text: "Hello " }, '
          '{ text: data.context._h3e085f21c9 }, { text: " and welcome" }] })',
      islands: '',
      values: ['Labels.of(context).name'],
      actions: [],
    ),
    (
      name: 'copy around a value only the app has stays in the payload',
      body: r"=> Text('Hello ${cubit.name} and welcome');",
      fields: 'final Cubit cubit;',
      params: 'required this.cubit',
      stateful: false,
      mount: [],
      dsl:
          'TextRich(textSpan: { children: [{ text: "Hello " }, '
          '{ text: data.context._h292b3bb4c3 }, { text: " and welcome" }] })',
      islands: '',
      values: ['cubit.name'],
      actions: [],
    ),
    (
      name: 'each unrolled iteration is its own island',
      body:
          "=> Column(children: [for (final label in const ['a', 'b']) "
          'Opaque(label: label.toUpperCase(), child: Text(label))]);',
      fields: '',
      params: '',
      stateful: false,
      mount: [],
      dsl:
          'Column(children: [Surface_0_Opaque_0(child: Text(text: "a")), '
          'Surface_1_Opaque_0(child: Text(text: "b"))])',
      islands:
          'Surface.build>0/Opaque#0 slots=child props= '
          'reason=unknownWidget\n'
          'Surface.build>1/Opaque#0 slots=child props= reason=unknownWidget',
      values: [],
      actions: [],
    ),
    (
      name:
          'a loop over strings whose body needs its item walks a '
          'published list',
      body:
          '=> Column(children: [for (final name in names) '
          'Opaque(tint: name.length, child: Text(name))]);',
      fields: 'final List<String> names;',
      params: 'required this.names',
      stateful: false,
      mount: [],
      dsl:
          'Column(children: [...for name in data.context._h936348a2cc: '
          'Surface_Opaque_0(child: Text(text: name._hec510a767b), '
          'restageItems: [name._hdde93e85c5])])',
      islands:
          'Surface.build/Opaque#0 slots=child props= item '
          'reason=unknownWidget',
      values: ['index of name in names', 'name', 'names'],
      actions: [],
    ),
    (
      name: 'a destructuring loop over a screen input walks a published list',
      body:
          '=> Column(children: [for (final Plan(:id, :rank) in plans) '
          'Opaque(tint: rank, child: Text(id))]);',
      fields: 'final List<Plan> plans;',
      params: 'required this.plans',
      stateful: false,
      mount: [],
      dsl:
          'Column(children: [...for presence in data.context._h90ce0887a0: '
          'Surface_Opaque_0(child: Text(text: presence._ha8039807f7), '
          'restageItems: [presence._h5ae10a4cf6])])',
      islands:
          'Surface.build/Opaque#0 slots=child props= item '
          'reason=unknownWidget',
      values: ['id', 'index of Plan(:id, :rank) in plans', 'plans'],
      actions: [],
    ),
    (
      name: 'a loop over a filtered list walks a published list',
      body:
          '=> Column(children: [for (final p in plans.where((p) => '
          'p.rank > 0)) Opaque(tint: p.rank, child: Text(p.id))]);',
      fields: 'final List<Plan> plans;',
      params: 'required this.plans',
      stateful: false,
      mount: [],
      dsl:
          'Column(children: [...for p in data.context._he4d5ff1be1: '
          'Surface_Opaque_0(child: Text(text: p._ha87659f9d1), '
          'restageItems: [p._hb37da99029])])',
      islands:
          'Surface.build/Opaque#0 slots=child props= item '
          'reason=unknownWidget',
      values: [
        'index of p in plans.where((p) => p.rank > 0)',
        'p.id',
        'plans.where((p) => p.rank > 0)',
      ],
      actions: [],
    ),
    (
      name: "a stateless surface's own members are read from an instance",
      body:
          "=> Column(children: [Opaque(tint: _count + 1, child: "
          "const Text('a')), _row('b')]);",
      fields:
          'int get _count => 2; Widget _row(String s) { '
          'if (s.isEmpty) return const SizedBox(); return Text(s); }',
      params: '',
      stateful: false,
      mount: [],
      dsl:
          'Column(children: [Surface_Opaque_0(child: Text(text: "a")), '
          'Surface__row_0()])',
      islands:
          'Surface.build/Opaque#0 slots=child props= '
          'reason=unknownWidget\n'
          'Surface.build/_row#0 slots= props= '
          'reason=customWidgetInliningDeferred',
      values: [],
      actions: [],
    ),
    (
      name: "a lifted State's inherited members are the mount's",
      body:
          "=> Column(children: [Opaque(tint: _hits, child: "
          "GestureDetector(onTap: () => setState(() => _atEnd = true), "
          "child: const Text('x')))]);",
      fields: 'int _hits = 0; bool _atEnd = false;',
      params: '',
      stateful: true,
      mount: ['_SurfaceState state'],
      dsl:
          'Column(children: [Surface_Opaque_0(child: GestureDetector('
          'onTap: {nativeEvent: data.context._hf9e924df52}, '
          'child: Text(text: "x")))])',
      islands:
          'Surface.build/Opaque#0 slots=child props= '
          'reason=unknownWidget',
      values: [],
      actions: ['() => setState(() => _atEnd = true)'],
    ),
    (
      name: 'an island in a nested loop reads both loop positions',
      body:
          '=> Column(children: [for (final p in plans) for (final f in '
          'p.features) Opaque(label: f, child: Text(f))]);',
      fields: 'final List<Plan> plans;',
      params: 'required this.plans',
      stateful: false,
      mount: [],
      dsl:
          'Column(children: [...for p in data.context.plans: '
          '[...for presence in [0]: [...for f in p._h107688f0bd: '
          'Surface_Opaque_0(child: Text(text: f._h53ed5e36fb), '
          'restageItems: [p._hc95ca01d90, f._h08142d463b])]]])',
      islands:
          'Surface.build/Opaque#0 slots=child props= item '
          'reason=unknownWidget',
      values: [
        'f',
        'index of f in p.features',
        'index of p in plans',
        'p.features',
      ],
      actions: [],
    ),
    (
      name: 'an island three loops deep reads all three positions',
      body:
          '=> Column(children: [for (final p in plans) for (final f in '
          'p.features) for (final c in f.codeUnits) '
          'Opaque(tint: c, child: Text(f))]);',
      fields: 'final List<Plan> plans;',
      params: 'required this.plans',
      stateful: false,
      mount: [],
      dsl:
          'Column(children: [...for p in data.context.plans: '
          '[...for presence in [0]: [...for f in p._h107688f0bd: '
          '[...for presence in [0]: [...for c in f._h6ae1c15a35: '
          'Surface_Opaque_0(child: Text(text: f._h53ed5e36fb), '
          'restageItems: [p._hc95ca01d90, f._h08142d463b, '
          'c._h23b9d20057])]]]]])',
      islands:
          'Surface.build/Opaque#0 slots=child props= item '
          'reason=unknownWidget',
      values: [
        'f',
        'f.codeUnits',
        'index of c in f.codeUnits',
        'index of f in p.features',
        'index of p in plans',
        'p.features',
      ],
      actions: [],
    ),
    (
      name: 'a parenthesized root keeps its shell',
      body: '=> (Opaque(child: Column(children: [Text(title)])));',
      fields: 'final String title;',
      params: 'required this.title',
      stateful: false,
      mount: ['Opaque notDelivered'],
      dsl: 'Column(children: [Text(text: data.context.title)])',
      islands: '',
      values: [],
      actions: [],
    ),
    (
      name: 'a root builder that also takes a child stays in the design',
      body:
          '=> ValueListenableBuilder<int>(valueListenable: count, '
          'builder: (context, value, child) => child!, '
          'child: Text(title));',
      fields: 'final ValueNotifier<int> count; final String title;',
      params: 'required this.count, required this.title',
      stateful: false,
      mount: [],
      dsl:
          'Surface_ValueListenableBuilder_0(child: '
          'Text(text: data.context.title))',
      islands:
          'Surface.build/ValueListenableBuilder#0 slots=child props= '
          'reason=unknownWidget',
      values: [],
      actions: [],
    ),
    (
      name: 'a root builder without a child joins the shell',
      body:
          '=> ValueListenableBuilder<int>(valueListenable: count, '
          'builder: (context, value, child) => Text(title));',
      fields: 'final ValueNotifier<int> count; final String title;',
      params: 'required this.count, required this.title',
      stateful: false,
      mount: ['ValueListenableBuilder builder'],
      dsl: 'Text(text: data.context.title)',
      islands: '',
      values: ['value'],
      actions: [],
    ),
    for (final (widget, builder, count) in [
      ('CountBuilder', '(context, count)', 'count'),
      ('RenamedBuilder', '(context, count)', 'count'),
      ('MixedBuilder', '(context, count)', 'count'),
      ('Uses', '(context, n, child)', 'n'),
    ])
      (
        name: 'a root $widget built through templates joins the shell',
        body:
            '=> $widget(builder: $builder => '
            "Column(children: [Text(title), const Text('Static copy')]));",
        fields: 'final String title;',
        params: 'required this.title',
        stateful: false,
        mount: ['$widget builder'],
        dsl:
            'Column(children: [Text(text: data.context.title), '
            'Text(text: "Static copy")])',
        islands: '',
        values: [count],
        actions: [],
      ),
    // A wrapper below delivered content stays where the app put it, whatever
    // the behavior under it looks up.
    for (final (crossed, callback) in [
      ('SafeArea(', 'Navigator.of(context).maybePop()'),
      ('SafeArea(', 'MediaQuery.of(context)'),
      (
        'Directionality(textDirection: TextDirection.ltr, ',
        'Directionality.of(context)',
      ),
      ('Padding(padding: EdgeInsets.zero, ', 'context.size'),
      ('SafeArea(', 'Navigator.of(gate.currentContext!).maybePop()'),
    ])
      (
        name:
            '${crossed.split('(').first} with ${callback.split('(').first}: '
            'the wrapper stays in the app',
        body:
            '=> Opaque(child: ${crossed}child: Hears(onContext: (context) '
            '{ $callback; }, child: Text(title))));',
        fields: 'final String title; final GlobalKey gate;',
        params: 'required this.title, required this.gate',
        stateful: false,
        mount: [
          'Opaque notDelivered',
          '${crossed.split('(').first} notDelivered',
          'Hears notDelivered',
        ],
        dsl: 'Text(text: data.context.title)',
        islands: '',
        values: [],
        actions: [],
      ),
    (
      name: 'a dissolved builder publishes all of its public data fields',
      body: '=> ShopBuilder(builder: (context, shop) => Text(shop.title));',
      fields: '',
      params: '',
      stateful: false,
      mount: ['ShopBuilder builder'],
      dsl: '',
      islands: '',
      values: ['shop.count', 'shop.tags', 'shop.title'],
      actions: [],
    ),
    for (final (name, body, fields, dsl, islands, values) in [
      (
        'a value key in a loop is carried per item',
        '=> Column(children: [for (final p in plans) '
            'Text(p.id, key: ValueKey(p.id))]);',
        'final List<Plan> plans;',
        'Column(children: [...for p in data.context.plans: '
            'Text(text: p.id, key: p._h76b52a15a7)])',
        '',
        ['ValueKey(p.id)'],
      ),
      (
        'a value key of any type is carried',
        '=> Text(title, key: ValueKey(step));',
        'final String title; final Axis step;',
        'Text(text: data.context.title, key: data.context._hb64799c558)',
        '',
        ['ValueKey(step)'],
      ),
      (
        'a key over an object the app holds keeps its holder in the app',
        '=> Center(child: Text(title, key: ObjectKey(plans.first)));',
        'final String title; final List<Plan> plans;',
        'Center(child: Surface_Text_0())',
        'Surface.build/Text#0 slots= props= reason=propertyValueTypeMismatch',
        <String>[],
      ),
      (
        'a global key keeps its holder in the app',
        '=> Center(child: Text(title, key: gate));',
        'final String title; final GlobalKey gate;',
        'Center(child: Surface_Text_0())',
        'Surface.build/Text#0 slots= props= reason=propertyValueTypeMismatch',
        <String>[],
      ),
    ])
      (
        name: name,
        body: body,
        fields: fields,
        params: [
          for (final field in fields.split(';'))
            if (field.trim().isNotEmpty)
              'required this.${field.trim().split(' ').last}',
        ].join(', '),
        stateful: false,
        mount: [],
        dsl: dsl,
        islands: islands,
        values: values,
        actions: [],
      ),
    (
      name: 'a root reactive scope stays in the mount around its reads',
      body: '=> Track(() => Text(title.toUpperCase()));',
      fields: 'final String title;',
      params: 'required this.title',
      stateful: false,
      mount: ['Track builder'],
      dsl: '',
      islands: '',
      values: ['title.toUpperCase()'],
      actions: [],
    ),
    (
      name: 'a nested reactive scope renders from the app',
      body: '=> Column(children: [Track(() => Text(title.toUpperCase()))]);',
      fields: 'final String title;',
      params: 'required this.title',
      stateful: false,
      mount: [],
      dsl: 'Column(children: [Surface_Track_0()])',
      islands: 'Surface.build/Track#0 slots= props= reason=unknownWidget',
      values: [],
      actions: [],
    ),
    for (final crossed in [
      'SafeArea',
      'SingleChildScrollView',
      'AnimatedOpacity(opacity: 1, duration: Duration.zero, ',
    ])
      (
        name:
            'a notification listener crossing ${crossed.split('(').first}: '
            'the wrapper stays in the app',
        body:
            '=> ${crossed.contains('(') ? crossed : '$crossed('}'
            'child: NotificationListener<ScrollNotification>('
            'onNotification: (_) => false, child: Text(title)));',
        fields: 'final String title;',
        params: 'required this.title',
        stateful: false,
        mount: [
          '${crossed.split('(').first} notDelivered',
          'NotificationListener notDelivered',
        ],
        dsl: 'Text(text: data.context.title)',
        islands: '',
        values: [],
        actions: [],
      ),
    // The design reads whichever of two providers of one type is nearer.
    (
      name: 'a same-type provider stays below the delivered one',
      body:
          '=> Directionality(textDirection: TextDirection.ltr, '
          'child: Flip(pick: () => TextDirection.rtl, child: Text(title)));',
      fields: 'final String title;',
      params: 'required this.title',
      stateful: false,
      mount: ['Directionality notDelivered', 'Flip notDelivered'],
      dsl: 'Text(text: data.context.title)',
      islands: '',
      values: [],
      actions: [],
    ),
    // A focus node takes its context and keeps it, which nothing decides.
    (
      name: 'a focus node stays below the wrapper it was written under',
      body:
          '=> SafeArea(child: Focus(includeSemantics: false, '
          'child: Text(title)));',
      fields: 'final String title;',
      params: 'required this.title',
      stateful: false,
      mount: ['SafeArea notDelivered', 'Focus notDelivered'],
      dsl: 'Text(text: data.context.title)',
      islands: '',
      values: [],
      actions: [],
    ),
    // Behavior inside a widget that builds all its children moves too.
    for (final (name, body, mount, dsl, islands, values) in [
      (
        'a listener among delivered siblings is an island',
        '=> Column(children: [Text(title), Hears(onContext: (context) '
            '{ Navigator.of(context).maybePop(); }, child: Text(title))]);',
        <String>[],
        'Column(children: [Text(text: data.context.title), '
            'Surface_Hears_0(child: Text(text: data.context.title))])',
        'Surface.build/Hears#0 slots=child props= reason=unknownWidget',
        <String>[],
      ),
      (
        'a provider a sibling looks up stays',
        '=> Column(children: [Text(title), MediaQuery(data: '
            'const MediaQueryData(), child: Text(title))]);',
        <String>[],
        '',
        'Surface.build/MediaQuery#0 slots=child props= '
            'reason=unknownWidget',
        <String>[],
      ),
      (
        'a listener in a lazy list stays',
        '=> ListView(children: [Hears(onContext: (context) {}, '
            'child: Text(title))]);',
        <String>[],
        '',
        'Surface.build/Hears#0 slots=child props= reason=unknownWidget',
        <String>[],
      ),
      (
        'a listener under a condition stays',
        '=> Column(children: [if (title.isEmpty) Hears(onContext: '
            '(context) {}, child: Text(title))]);',
        <String>[],
        '',
        'Surface.build/Hears#0 slots=child props= reason=unknownWidget',
        ['title.isEmpty'],
      ),
    ])
      (
        name: name,
        body: body,
        fields: 'final String title;',
        params: 'required this.title',
        stateful: false,
        mount: mount,
        dsl: dsl,
        islands: islands,
        values: values,
        actions: [],
      ),
    (
      name: 'a provider stays below a wrapper that looks up what it provides',
      body:
          '=> SafeArea(child: MediaQuery(data: const MediaQueryData(), '
          'child: Text(title)));',
      fields: 'final String title;',
      params: 'required this.title',
      stateful: false,
      mount: ['SafeArea notDelivered', 'MediaQuery notDelivered'],
      dsl: 'Text(text: data.context.title)',
      islands: '',
      values: [],
      actions: [],
    ),
    for (final (read, moves) in [
      ('title', true),
      ('MediaQuery.of(context).size.width.toString()', false),
    ])
      (
        name:
            'a dissolving builder reading ${read.split('(').first}: '
            'the wrapper stays in the app',
        body:
            '=> SafeArea(child: Scope(builder: (context, count) => '
            'Text($read)));',
        fields: 'final String title;',
        params: 'required this.title',
        stateful: false,
        mount: ['SafeArea notDelivered', 'Scope builder'],
        dsl: moves ? 'Text(text: data.context.title)' : '',
        islands: '',
        values: [
          if (!moves) 'MediaQuery.of(context).size.width.toString()',
          'count',
        ],
        actions: [],
      ),
    (
      name: "a State that does not lower moves into the mount",
      body:
          "=> Stack(children: [Opaque(tint: _hits, "
          "child: const Text('a')), if (!_atEnd) const Text('fade')]);",
      fields:
          'int _hits = 0; bool _atEnd = false; '
          '@override void initState() { super.initState(); }',
      params: '',
      stateful: true,
      mount: ['_SurfaceState state'],
      dsl: '',
      islands:
          'Surface.build/Opaque#0 slots=child props= '
          'reason=unknownWidget',
      values: ['_atEnd'],
      actions: [],
    ),
  ];
  for (final row in rows) {
    test(row.name, () async {
      final result = await _split(
        row.body,
        fields: row.fields,
        params: row.params,
        stateful: row.stateful,
      );
      expect(
        result.issues.where((issue) => !issue.code.isBuildNotice),
        isEmpty,
        reason: result.issues.map((issue) => issue.message).join('\n'),
      );
      if (row.dsl.isNotEmpty) expect(result.dsl, row.dsl);
      expect(_describe(result), row.islands);
      expect(_values(result), row.values);
      expect(_actions(result), row.actions);
      expect(_mount(result), row.mount);
      for (final value in result.hoisted) {
        expect(result.locationOf(value), isNotNull, reason: value.label);
      }
    });
  }

  test('a lifted State without a shell records its own build', () async {
    final result = await _split(
      "=> ListView(controller: _scroll, children: [const Text('a')]);",
      fields: 'final ScrollController _scroll = ScrollController();',
      stateful: true,
    );
    final split = result.split!;
    expect([split.shell, split.state?.name], [isEmpty, '_SurfaceState']);
    expect(split.recordedSource((name) => name), contains('ListView('));
  });

  test('island names start with the surface id, encoded one to one', () async {
    const body = "=> Column(children: [Opaque(child: const Text('a'))]);";
    final names = [
      for (final id in ['spring-sale', 'spring_sale', '2024-sale'])
        for (final island in (await _split(body, entryId: id)).islands)
          island.name,
    ];
    expect(names, [
      'spring_x2d_sale_Opaque_0',
      'spring__sale_Opaque_0',
      'Island_d2024_x2d_sale_Opaque_0',
    ]);
  });

  group('edits that change nothing', () {
    const fields = 'final String title; final Cubit cubit;';
    const params = 'required this.title, required this.cubit';

    Future<TranslationResult> split(String body, {Catalog? catalog}) =>
        _split(body, fields: fields, params: params, catalog: catalog);

    String fingerprint(TranslationResult result) => [
      result.dsl,
      for (final island in result.islands)
        [
          island.id,
          island.interface,
          island.implementation,
          island.token,
        ].join(' '),
      for (final value in result.hoisted) value.key,
      SurfaceScreenHostDataContractHash.hash(
        hostDataContractOf(const [], hoisted: result.hoisted),
      ),
    ].join('\n');

    const base =
        '=> Column(children: [Text(title.toUpperCase()), '
        'Opaque(tint: 3, child: Text(title)), '
        'GestureDetector(onTap: () => Navigator.of(context).maybePop(), '
        "child: const Text('x'))]);";
    const call =
        "=> GestureDetector(onTap: () => cubit.pick(title.trim()), "
        "child: const Text('x'));";
    // Each row: the edited source either keeps the whole output, or keeps the
    // listed island IDs.
    for (final (name, before, after, ids) in [
      ('a rebuild', base, base, null),
      (
        'a comment-only edit',
        base,
        '=> Column(children: [Text(title /* shown */ .toUpperCase()), '
            '// the island\n'
            'Opaque(tint: 3, /* app widget */ child: Text(title)), '
            'GestureDetector(onTap: () => Navigator.of(context) /* back */ '
            ".maybePop(), child: const Text('x'))]);",
        null,
      ),
      (
        'a format-only edit',
        base,
        '''=> Column(
      children: [
        Text(title.toUpperCase(),),
        Opaque(
          tint: 3,
          child: Text(title),
        ),
        GestureDetector(
          onTap: () =>
              Navigator.of(context).maybePop(),
          child: const Text('x'),
        ),
      ],
    );''',
        null,
      ),
      (
        'a comment edit in an installed native call action',
        call,
        '=> GestureDetector(onTap: () => cubit.pick(\n'
            "  /* trimmed */ title.trim(), ), child: const Text('x'));",
        null,
      ),
      (
        'reordering unrelated code',
        "=> Column(children: [Text('a'), Text('b'), "
            "Opaque(child: Text('c'))]);",
        "=> Column(children: [Text('b'), Center(child: Text('new')), "
            "Text('a'), Opaque(child: Text('c'))]);",
        ['Surface.build/Opaque#0'],
      ),
      (
        'an edit inside an island',
        "=> Column(children: [Opaque(label: title.trim(), child: Text('c'))]);",
        "=> Column(children: [Opaque(label: title.toUpperCase(), "
            "child: Text('c'))]);",
        ['Surface.build/Opaque#0'],
      ),
    ]) {
      test(
        '$name keeps ${ids == null ? 'the output' : 'island IDs'}',
        () async {
          final prior = await split(before);
          final current = await split(after);
          expect(
            current.issues.where((issue) => !issue.code.isBuildNotice),
            isEmpty,
          );
          if (ids == null) {
            expect(fingerprint(current), fingerprint(prior));
          } else {
            expect([for (final island in current.islands) island.id], ids);
            expect([for (final island in prior.islands) island.id], ids);
          }
        },
      );
    }

    // Each row: whether published content for the first island still fits.
    const one =
        '=> Column(children: [Opaque(label: title.trim(), '
        "child: Text('c'))]);";
    const two =
        '=> Column(children: [Opaque(label: title.trim(), '
        "child: Text('c')), Opaque(label: title, child: Text('d'))]);";
    for (final (name, before, after, fits) in [
      (
        'an edit inside a lone island',
        one,
        one.replaceFirst('trim', 'toUpperCase'),
        true,
      ),
      (
        'an input change',
        one,
        one.replaceFirst('label:', 'tint: 1, label:'),
        false,
      ),
      (
        'an edit inside one of two same-type islands',
        two,
        two.replaceFirst('trim', 'toUpperCase'),
        false,
      ),
      (
        'adding a same-type island with other inputs',
        one,
        one.replaceFirst(
          ']);',
          ", Opaque(tint: 1, label: title, child: Text('d'))]);",
        ),
        true,
      ),
      (
        'swapping two same-type islands',
        two,
        "=> Column(children: [Opaque(label: title, child: Text('c')), "
            "Opaque(label: title.trim(), child: Text('d'))]);",
        false,
      ),
    ]) {
      test('$name ${fits ? 'keeps' : 'changes'} the fit token', () async {
        final prior = (await split(before)).islands.first;
        final current = (await split(after)).islands.first;
        expect(current.id, prior.id);
        expect(current.token == prior.token, fits);
      });
    }

    test('changing inputs changes the interface, not the ID', () async {
      final prior = (await split(
        "=> Column(children: [Opaque(tint: 1, child: Text('c'))]);",
      )).islands.single;
      final current = (await split(
        "=> Column(children: [Opaque(child: Text('c'))]);",
      )).islands.single;
      expect(current.id, prior.id);
      expect(current.interface, isNot(prior.interface));
    });

    test("a library on the package's island namespace is refused", () async {
      const taken = WidgetLibrary.custom('apps_examples.islands');
      final result = await split(
        "=> Column(children: [Opaque(label: title.trim(), child: Text('c'))]);",
        catalog: Catalog(
          schemaVersion: _sharedCatalog.schemaVersion,
          generatedAt: _sharedCatalog.generatedAt,
          libraries: {
            ..._sharedCatalog.libraries,
            taken: const LibraryInfo(version: '1.0.0', capabilityVersion: 1),
          },
          widgets: _sharedCatalog.widgets,
          structuredTypes: _sharedCatalog.structuredTypes,
          unions: _sharedCatalog.unions,
        ),
      );
      expect(
        [for (final issue in result.issues) issue.message],
        contains(
          "The library namespace `'apps_examples.islands'` is reserved "
          'for widgets Restage generates for this package. Try choosing '
          'another namespace.',
        ),
      );
    });

    test(
      'same-type islands read apart, in the order the screen uses them',
      () async {
        final islands = (await split(two)).islands;
        expect(
          [for (final island in islands) island.label],
          ['Opaque in Surface', 'Opaque in Surface (2nd)'],
        );
      },
    );

    test(
      'identical islands share one implementation with distinct IDs',
      () async {
        final islands = (await split(
          "=> Column(children: [Opaque(tint: 2, child: Text('x')), "
          "Opaque(tint: 2, child: Text('x'))]);",
        )).islands;
        expect(
          [for (final island in islands) island.id],
          ['Surface.build/Opaque#0', 'Surface.build/Opaque#1'],
        );
        expect({
          for (final island in islands) island.implementation,
        }, hasLength(1));
      },
    );
  });
}
