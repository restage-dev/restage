import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'shared_resolvers.dart';

/// Outcome of transpiling a custom-widget fixture through the full
/// chain — classify → translate → emit → parse → validate → encode → decode.
class _TranspileResult {
  _TranspileResult(
    this.issues,
    this.decoded,
    this.translation,
    this.classification,
  );

  /// Every diagnostic from translation and catalog validation.
  final List<Issue> issues;

  /// The `.rfw` blob decoded back to a library — null when an earlier stage
  /// produced issues.
  final fmt.RemoteWidgetLibrary? decoded;

  /// Translation output used for exact-value refusal assertions.
  final TranslationResult translation;

  final ClassificationResult classification;
}

final _hostTextHelper = HelperDefinition(
  name: 'hostText',
  libraryOrigin: 'package:apps_examples',
  returnCategory: HelperReturnCategory.string,
  translate: (_) => 'data.context.label',
);

final class _ListDecoderCase {
  const _ListDecoderCase({
    required this.property,
    required this.decoder,
    required this.acceptedType,
    required this.siblingType,
    this.lookalikeType,
  });

  final String property;
  final PropertyType decoder;
  final String acceptedType;
  final String siblingType;
  final String? lookalikeType;
}

const _listDecoderCases = <_ListDecoderCase>[
  _ListDecoderCase(
    property: 'strings',
    decoder: PropertyType.stringList,
    acceptedType: 'String',
    siblingType: 'bool',
  ),
  _ListDecoderCase(
    property: 'flags',
    decoder: PropertyType.booleanList,
    acceptedType: 'bool',
    siblingType: 'String',
  ),
  _ListDecoderCase(
    property: 'boxShadows',
    decoder: PropertyType.boxShadowList,
    acceptedType: 'ui.BoxShadow',
    siblingType: 'ui.Shadow',
    lookalikeType: 'BoxShadow',
  ),
  _ListDecoderCase(
    property: 'shadows',
    decoder: PropertyType.shadowList,
    acceptedType: 'ui.Shadow',
    siblingType: 'ui.BoxShadow',
    lookalikeType: 'Shadow',
  ),
  _ListDecoderCase(
    property: 'features',
    decoder: PropertyType.fontFeatureList,
    acceptedType: 'ui.FontFeature',
    siblingType: 'ui.FontVariation',
    lookalikeType: 'FontFeature',
  ),
  _ListDecoderCase(
    property: 'variations',
    decoder: PropertyType.fontVariationList,
    acceptedType: 'ui.FontVariation',
    siblingType: 'ui.FontFeature',
    lookalikeType: 'FontVariation',
  ),
  _ListDecoderCase(
    property: 'options',
    decoder: PropertyType.selectionOptionList,
    acceptedType: 'core.RestageSelectionOption',
    siblingType: 'ui.Shadow',
    lookalikeType: 'RestageSelectionOption',
  ),
];

void main() {
  group('custom-widget transpilation end-to-end', () {
    test('a pure-composition custom widget transpiles and round-trips',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard({this.label});
  final String? label;
  Widget build(BuildContext context) => Container(child: Text(label));
}

Object x() => AcmeCard(label: "Pro");
''',
        catalogWith([
          _entry('Container', [prop('child', PropertyType.widget)]),
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      // Two widgets: the inlined custom widget and the paywall root.
      expect(
        decoded.widgets.map((w) => w.name),
        containsAll(['AcmeCard', 'Paywall']),
      );
      // The paywall references the custom widget by name, passing the arg.
      final paywall = _widget(decoded, 'Paywall');
      expect(paywall.name, 'AcmeCard');
      expect(paywall.arguments['label'], 'Pro');
      // The definition body is the catalog-widget subtree, with the
      // constructor parameter lowered to an `args.` reference.
      final card = _widget(decoded, 'AcmeCard');
      expect(card.name, 'Container');
      final text = card.arguments['child'];
      expect(text, isA<fmt.ConstructorCall>());
      expect((text! as fmt.ConstructorCall).name, 'Text');
    });

    test('a custom widget inlines a run-time collection-`if`', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Column extends StatelessWidget {
  const Column({required this.children});
  final List<Widget> children;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String data;
  Widget build(BuildContext context) => const Widget();
}

class SizedBox extends StatelessWidget {
  const SizedBox();
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'PlanCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'plan card',
)
class PlanCard extends StatelessWidget {
  const PlanCard({required this.isPro, required this.plan});
  final bool isPro;
  final String plan;
  Widget build(BuildContext context) => Column(
        children: [
          Text('Plan'),
          if (isPro && plan == 'annual') Text('Best value'),
        ],
      );
}

Object x() => PlanCard(isPro: true, plan: "annual");
''',
        catalogWith([
          _entry('Column', [prop('children', PropertyType.widgetList)]),
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
          _entry('SizedBox', []),
        ]),
      );

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final classified = result.classification.classifications.values
          .whereType<ComposableWidget>();
      expect(classified, hasLength(1));
      expect(
        classified.single.requiredMechanisms,
        contains(InliningMechanism.conditionalElement),
      );
      final decoded = result.decoded!;
      expect(
        decoded.widgets.map((w) => w.name),
        containsAll(['PlanCard', 'Paywall']),
      );
      final card = _widget(decoded, 'PlanCard');
      final children = card.arguments['children']! as List<Object?>;
      expect(children, hasLength(2));
      // A guarded loop, not a placeholder child: the element is absent when
      // the condition does not hold.
      final gate = children[1]! as fmt.Loop;
      expect((gate.input as fmt.Switch).outputs[false], <Object?>[]);
    });

    test('a custom widget keys an equality chain on an int parameter',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Text extends StatelessWidget {
  const Text(this.data);
  final String data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'TierLabel',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'tier label',
)
class TierLabel extends StatelessWidget {
  const TierLabel({required this.tier});
  final int tier;
  Widget build(BuildContext context) =>
      Text(tier == 0 ? 'Basic' : tier == 1 ? 'Plus' : 'Max');
}

Object x() => TierLabel(tier: 1);
''',
        catalogWith([
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
        ]),
      );

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final decoded = result.decoded!;
      final label = _widget(decoded, 'TierLabel');
      final selection = label.arguments['text'];
      expect(selection, isA<fmt.Switch>());
      final chain = selection! as fmt.Switch;
      // One switch keyed on the parameter.
      expect((chain.input as fmt.ArgsReference).parts, ['tier']);
      expect(chain.outputs[0], 'Basic');
      expect(chain.outputs[1], 'Plus');
      expect(chain.outputs[null], 'Max');
      // The call site passes a bare int, so the keys match.
      expect(_widget(decoded, 'Paywall').arguments['tier'], 1);
    });

    test('an int parameter `!=` lowers to the swapped 2-arm form', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Text extends StatelessWidget {
  const Text(this.data);
  final String data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'TierNote',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'tier note',
)
class TierNote extends StatelessWidget {
  const TierNote({required this.tier});
  final int tier;
  Widget build(BuildContext context) =>
      Text(tier != 0 ? 'Paid' : 'Free');
}

Object x() => TierNote(tier: 0);
''',
        catalogWith([
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
        ]),
      );

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final note = _widget(result.decoded!, 'TierNote');
      final swapped = note.arguments['text']! as fmt.Switch;
      expect((swapped.input as fmt.ArgsReference).parts, ['tier']);
      expect(swapped.outputs[0], 'Free');
      expect(swapped.outputs[null], 'Paid');
    });

    test('a `<` comparison on an int parameter refuses loudly', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Text extends StatelessWidget {
  const Text(this.data);
  final String data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'TierRange',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'tier range',
)
class TierRange extends StatelessWidget {
  const TierRange({required this.tier});
  final int tier;
  Widget build(BuildContext context) => Text(tier < 2 ? 'Low' : 'High');
}

Object x() => TierRange(tier: 1);
''',
        catalogWith([
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
        ]),
      );

      // The classifier reaches it first, so an ordering comparison reads as
      // imperative rather than as the translator's equality-only defer.
      expect(
        result.issues.map((issue) => issue.code),
        contains(IssueCode.customWidgetImperative),
      );
      expect(result.decoded, isNull);
    });

    test('a custom widget emits statically repeated children in order',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Column extends StatelessWidget {
  const Column({required this.children});
  final List<Widget> children;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String data;
  Widget build(BuildContext context) => const Widget();
}

List<String> labels(String first) => [first, 'second'];

@RestageWidget(
  name: 'RepeatedLabels',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'repeated labels',
)
class RepeatedLabels extends StatelessWidget {
  const RepeatedLabels();
  Widget build(BuildContext context) => Column(
        children: [
          for (final label in labels('first')) Text(label),
        ],
      );
}

Object x() => const RepeatedLabels();
''',
        catalogWith([
          _entry(
            'Column',
            [prop('children', PropertyType.widgetList)],
          ),
          _entry(
            'Text',
            [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
      );

      expect(result.issues, isEmpty);
      expect(result.decoded, isNotNull);
      expect(
        result.translation.widgetDefinitions['RepeatedLabels'],
        'Column(children: [Text(text: "first"), Text(text: "second")])',
      );
    });

    test('a local list from a helper emits statically repeated children',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Column extends StatelessWidget {
  const Column({required this.children});
  final List<Widget> children;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String data;
  Widget build(BuildContext context) => const Widget();
}

List<String> labels(String first) => [first, 'second'];

@RestageWidget(
  name: 'LocalLabels',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'local labels',
)
class LocalLabels extends StatelessWidget {
  const LocalLabels();
  Widget build(BuildContext context) {
    final values = labels('first');
    return Column(
      children: [for (final label in values) Text(label)],
    );
  }
}

Object x() => const LocalLabels();
''',
        catalogWith([
          _entry(
            'Column',
            [prop('children', PropertyType.widgetList)],
          ),
          _entry(
            'Text',
            [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
      );

      expect(result.issues, isEmpty);
      expect(result.decoded, isNotNull);
      expect(
        result.translation.widgetDefinitions['LocalLabels'],
        'Column(children: [Text(text: "first"), Text(text: "second")])',
      );
    });

    test('nested sources expose a composed custom widget and its blueprint',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Column extends StatelessWidget {
  const Column({required this.children});
  final List<Widget> children;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String data;
  Widget build(BuildContext context) => const Widget();
}

class WidgetSet {
  const WidgetSet(this.widget);
  final Widget widget;
}

@RestageWidget(
  name: 'HiddenLabel',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.content,
  description: 'hidden label',
)
class HiddenLabel extends StatelessWidget {
  const HiddenLabel();
  Widget build(BuildContext context) => const Text('resolved');
}

@RestageWidget(
  name: 'NestedLabels',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'nested labels',
)
class NestedLabels extends StatelessWidget {
  const NestedLabels();
  static const hidden = HiddenLabel();
  static const set = WidgetSet(hidden);

  List<Widget> entries(Widget value) => [if (true) value];

  Widget build(BuildContext context) {
    final values = entries(set.widget);
    return Column(children: [...values]);
  }
}

Object x() => const NestedLabels();
''',
        catalogWith([
          _entry(
            'Column',
            [prop('children', PropertyType.widgetList)],
          ),
          _entry(
            'Text',
            [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
      );

      expect(result.issues, isEmpty);
      expect(result.decoded, isNotNull);
      expect(
        result.translation.widgetDefinitions['NestedLabels'],
        'Column(children: [HiddenLabel()])',
      );
      expect(
        result.translation.widgetDefinitions['HiddenLabel'],
        'Text(text: "resolved")',
      );
    });

    test('root collection sources expose a custom widget entry point',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Column extends StatelessWidget {
  const Column({required this.children});
  final List<Widget> children;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String data;
  Widget build(BuildContext context) => const Widget();
}

class WidgetSet {
  const WidgetSet(this.widget);
  final Widget widget;
}

@RestageWidget(
  name: 'HiddenRootLabel',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.content,
  description: 'hidden root label',
)
class HiddenRootLabel extends StatelessWidget {
  const HiddenRootLabel();
  Widget build(BuildContext context) => const Text('resolved');
}

const hiddenRootLabel = HiddenRootLabel();
const rootSet = WidgetSet(hiddenRootLabel);
const rootEntries = <Widget>[if (true) rootSet.widget];

Object x() => Column(children: [...rootEntries]);
''',
        catalogWith([
          _entry(
            'Column',
            [prop('children', PropertyType.widgetList)],
          ),
          _entry(
            'Text',
            [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
      );

      expect(result.issues, isEmpty);
      expect(result.decoded, isNotNull);
      expect(result.translation.dsl, 'Column(children: [HiddenRootLabel()])');
      expect(
        result.translation.widgetDefinitions['HiddenRootLabel'],
        'Text(text: "resolved")',
      );
    });

    test('custom discovery stops at a reused ordinary callback source',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Shell extends StatelessWidget {
  const Shell({required this.child, required this.children});
  final Widget child;
  final List<Widget> children;
  Widget build(BuildContext context) => const Widget();
}

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, required this.child});
  final void Function()? onTap;
  final Widget child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'HiddenAction',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.content,
  description: 'hidden action',
)
class HiddenAction extends StatelessWidget {
  const HiddenAction();
  Widget build(BuildContext context) => const Text('Hidden');
}

void activate() {}
const void Function() sharedAction = activate;

Object x() => Shell(
      child: GestureDetector(
        onTap: sharedAction,
        child: const Text('Visible'),
      ),
      children: [
        GestureDetector(
          onTap: sharedAction,
          child: const HiddenAction(),
        ),
      ],
    );
''',
        catalogWith([
          _entry(
            'Shell',
            [
              prop('child', PropertyType.widget),
              prop('children', PropertyType.widgetList),
            ],
          ),
          _entry(
            'GestureDetector',
            [
              prop('onTap', PropertyType.event),
              prop('child', PropertyType.widget),
            ],
          ),
          _entry(
            'Text',
            [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
      );
      const hiddenKey = 'package:restage_codegen/_e2e_probe.dart#HiddenAction';

      expect(result.issues, isNotEmpty);
      expect(result.classification.classifications, isNot(contains(hiddenKey)));
      expect(result.classification.blueprints, isNot(contains(hiddenKey)));
    });

    test('a mixed receiver creates no partial custom entry points', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Column extends StatelessWidget {
  const Column({required this.children});
  final List<Widget> children;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String data;
  Widget build(BuildContext context) => const Widget();
}

class WidgetSet {
  const WidgetSet(this.widgets);
  final List<Widget> widgets;
}

@RestageWidget(
  name: 'ConstantLabel',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.content,
  description: 'constant label',
)
class ConstantLabel extends StatelessWidget {
  const ConstantLabel();
  Widget build(BuildContext context) => const Text('constant');
}

@RestageWidget(
  name: 'RuntimeLabel',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.content,
  description: 'runtime label',
)
class RuntimeLabel extends StatelessWidget {
  const RuntimeLabel();
  Widget build(BuildContext context) => const Text('runtime');
}

Object x(bool selectConstant) => Column(
  children: [
    ...(selectConstant
          ? const WidgetSet(<Widget>[ConstantLabel()])
          : WidgetSet(<Widget>[const RuntimeLabel()]))
        .widgets,
  ],
);
''',
        catalogWith([
          _entry(
            'Column',
            [prop('children', PropertyType.widgetList)],
          ),
          _entry(
            'Text',
            [prop('text', PropertyType.string, positional: true)],
          ),
        ]),
      );
      expect(result.classification.classifications, isEmpty);
      expect(result.classification.blueprints, isEmpty);
      expect(result.translation.dsl, 'Column(children: [])');
      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, IssueCode.unsupportedCollectionFlow);
      expect(result.translation.widgetDefinitions, isEmpty);
    });

    test('a targeted virtual root exposes no custom widget identity', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Text extends StatelessWidget {
  const Text(this.data);
  final String data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'BaseLabel',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.content,
  description: 'base label',
)
class BaseLabel extends StatelessWidget {
  const BaseLabel();
  Widget build(BuildContext context) => const Text('base');
}

@RestageWidget(
  name: 'DerivedLabel',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.content,
  description: 'derived label',
)
class DerivedLabel extends StatelessWidget {
  const DerivedLabel();
  Widget build(BuildContext context) => const Text('derived');
}

class Provider {
  Widget action() => const BaseLabel();
}

class DerivedProvider extends Provider {
  @override
  Widget action() => const DerivedLabel();
}

Provider provider() => DerivedProvider();

Object x() => provider().action();
''',
        catalogWith([
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
        ]),
      );

      const baseKey = 'package:restage_codegen/_e2e_probe.dart#BaseLabel';
      const derivedKey = 'package:restage_codegen/_e2e_probe.dart#DerivedLabel';
      expect(result.issues, isNotEmpty);
      expect(result.classification.classifications, isNot(contains(baseKey)));
      expect(
        result.classification.classifications,
        isNot(contains(derivedKey)),
      );
      expect(result.classification.blueprints, isEmpty);
    });

    test(
        'a parameterless own helper inlines its body, round-tripping to the '
        'same blob as the hand-inlined composition', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget _header() => Text("hi");
  Widget build(BuildContext context) => Container(child: _header());
}

Object x() => AcmeCard();
''',
        catalogWith([
          _entry('Container', [prop('child', PropertyType.widget)]),
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      // The inlined definition body is `Container(child: Text("hi"))` — the
      // helper call replaced by the helper's body.
      final card = _widget(decoded, 'AcmeCard');
      expect(card.name, 'Container');
      final text = card.arguments['child'];
      expect(text, isA<fmt.ConstructorCall>());
      final textCall = text! as fmt.ConstructorCall;
      expect(textCall.name, 'Text');
      expect(textCall.arguments['text'], 'hi');
    });

    test(
        'a same-library top-level helper function inlines its body at the call '
        'site, round-tripping to the hand-inlined composition', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

Widget _header() => Text("hi");

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget build(BuildContext context) => Container(child: _header());
}

Object x() => AcmeCard();
''',
        catalogWith([
          _entry('Container', [prop('child', PropertyType.widget)]),
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final card = _widget(result.decoded!, 'AcmeCard');
      expect(card.name, 'Container');
      final text = card.arguments['child']! as fmt.ConstructorCall;
      expect(text.name, 'Text');
      expect(text.arguments['text'], 'hi');
    });

    test(
        'a same-library static helper method inlines its body at the call '
        'site, binding the argument 1:1', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

class Helpers {
  static Widget row(String s) => Text(s);
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget build(BuildContext context) => Container(child: Helpers.row("Pro"));
}

Object x() => AcmeCard();
''',
        catalogWith([
          _entry('Container', [prop('child', PropertyType.widget)]),
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final card = _widget(result.decoded!, 'AcmeCard');
      expect(card.name, 'Container');
      final text = card.arguments['child']! as fmt.ConstructorCall;
      expect(text.name, 'Text');
      // The parameter `s` lowered to the bound argument literal "Pro".
      expect(text.arguments['text'], 'Pro');
    });

    test(
        'a parameterized own helper binds its argument 1:1 and inlines, '
        'round-tripping like the hand-inlined composition', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget _row(String s) => Text(s);
  Widget build(BuildContext context) => Container(child: _row("Pro"));
}

Object x() => AcmeCard();
''',
        catalogWith([
          _entry('Container', [prop('child', PropertyType.widget)]),
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final card = _widget(result.decoded!, 'AcmeCard');
      expect(card.name, 'Container');
      final text = card.arguments['child'];
      expect(text, isA<fmt.ConstructorCall>());
      final textCall = text! as fmt.ConstructorCall;
      expect(textCall.name, 'Text');
      // The parameter `s` lowered to the bound argument literal "Pro".
      expect(textCall.arguments['text'], 'Pro');
    });

    test(
        'a parameterized helper bound to a constructor parameter lowers the '
        'parameter to an args. reference', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard({this.label});
  final String? label;
  Widget _row(String s) => Text(s);
  Widget build(BuildContext context) => Container(child: _row(label));
}

Object x() => AcmeCard(label: "Pro");
''',
        catalogWith([
          _entry('Container', [prop('child', PropertyType.widget)]),
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final card = _widget(result.decoded!, 'AcmeCard');
      final text = card.arguments['child']! as fmt.ConstructorCall;
      // `_row(label)` → `Text(label)` → the param resolves to the constructor
      // argument, lowered to an `args.label` reference (not a literal).
      expect(text.arguments['text'], isA<fmt.ArgsReference>());
      expect(
        (text.arguments['text']! as fmt.ArgsReference).parts,
        ['label'],
      );
      // The call site passes the literal through.
      expect(_widget(result.decoded!, 'Paywall').arguments['label'], 'Pro');
    });

    test(
        'a widget-valued final local binding inlines its initializer at the '
        'use site', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget build(BuildContext context) {
    final header = Text("hi");
    return Container(child: header);
  }
}

Object x() => AcmeCard();
''',
        catalogWith([
          _entry('Container', [prop('child', PropertyType.widget)]),
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final card = _widget(result.decoded!, 'AcmeCard');
      expect(card.name, 'Container');
      final text = card.arguments['child']! as fmt.ConstructorCall;
      expect(text.name, 'Text');
      expect(text.arguments['text'], 'hi');
    });

    test(
        'a final local shadowing a constructor parameter resolves-through to '
        'the local, not an args. reference', () async {
      // The element-keyed resolve-through must beat the name-based args/state
      // lowering — a local `child` shadowing the constructor param `child`
      // emits the local initializer, never `args.child` (a wrong value the
      // floor cannot catch).
      final result = await _transpile(
        '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard({this.child});
  final Widget? child;
  Widget build(BuildContext context) {
    final child = Text("local");
    return Container(child: child);
  }
}

Object x() => AcmeCard(child: Text("passed"));
''',
        catalogWith([
          _entry('Container', [prop('child', PropertyType.widget)]),
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final card = _widget(result.decoded!, 'AcmeCard');
      final inner = card.arguments['child']! as fmt.ConstructorCall;
      // The shadowing local won — the body's `child` is the local
      // Text("local"), NOT the args.child passed at the call site.
      expect(inner.name, 'Text');
      expect(inner.arguments['text'], 'local');
    });

    test('a final local cannot expose a const list to LinearGradient stops',
        () async {
      final result = await _transpile(
        _constStopsFixture(
          memberSource: '',
          buildSource: '''
  Widget build(BuildContext context) {
    final stops = kStops;
    return Box(
      gradient: LinearGradient(colors: kColors, stops: stops),
    );
  }
''',
        ),
        _gradientBoxCatalog(),
        rootPackage: 'apps_examples',
      );
      final definition = result.translation.widgetDefinitions['AcmeGradient'];
      expect(definition, isEmpty);
      expect(result.decoded, isNull);
      expect(
        result.issues.map((i) => i.code),
        [IssueCode.unrecognizedMethodCall],
      );
      expect(result.issues.single.location, isNotEmpty);
    });

    test('a final local cannot expose a const list to RadialGradient stops',
        () async {
      final result = await _transpile(
        _constStopsFixture(
          memberSource: '',
          buildSource: '''
  Widget build(BuildContext context) {
    final stops = kStops;
    return Box(
      gradient: RadialGradient(colors: kColors, stops: stops),
    );
  }
''',
        ),
        _gradientBoxCatalog(),
        rootPackage: 'apps_examples',
      );
      final definition = result.translation.widgetDefinitions['AcmeGradient'];
      expect(definition, isEmpty);
      expect(result.decoded, isNull);
      expect(
        result.issues.map((i) => i.code),
        [IssueCode.unrecognizedMethodCall],
      );
      expect(result.issues.single.location, isNotEmpty);
    });

    test('a helper parameter cannot expose a const list to LinearGradient',
        () async {
      final result = await _transpile(
        _constStopsFixture(
          memberSource: '''
  Gradient gradient(List<double> stops) =>
      LinearGradient(colors: kColors, stops: stops);
''',
          buildSource: '''
  Widget build(BuildContext context) =>
      Box(gradient: gradient(kStops));
''',
        ),
        _gradientBoxCatalog(),
        rootPackage: 'apps_examples',
      );
      final definition = result.translation.widgetDefinitions['AcmeGradient'];
      expect(definition, isEmpty);
      expect(result.decoded, isNull);
      expect(
        result.issues.map((i) => i.code),
        [IssueCode.unrecognizedMethodCall],
      );
      expect(result.issues.single.location, isNotEmpty);
    });

    test('a helper parameter cannot expose a const list to RadialGradient',
        () async {
      final result = await _transpile(
        _constStopsFixture(
          memberSource: '''
  Gradient gradient(List<double> stops) =>
      RadialGradient(colors: kColors, stops: stops);
''',
          buildSource: '''
  Widget build(BuildContext context) =>
      Box(gradient: gradient(kStops));
''',
        ),
        _gradientBoxCatalog(),
        rootPackage: 'apps_examples',
      );
      final definition = result.translation.widgetDefinitions['AcmeGradient'];
      expect(definition, isEmpty);
      expect(result.decoded, isNull);
      expect(
        result.issues.map((i) => i.code),
        [IssueCode.unrecognizedMethodCall],
      );
      expect(result.issues.single.location, isNotEmpty);
    });

    test('a diagnosed generic source suppresses a nested LinearGradient',
        () async {
      await _expectNestedGradientChildRefusal(
        'LinearGradient('
        'colors: kColors, stops: true ? [0, 1] : Colors.teal)',
        code: IssueCode.unrecognizedMethodCall,
      );
    });

    test('a diagnosed generic source suppresses a nested RadialGradient',
        () async {
      await _expectNestedGradientChildRefusal(
        'RadialGradient('
        'colors: kColors, stops: true ? [0, 1] : Colors.teal)',
        code: IssueCode.unrecognizedMethodCall,
      );
    });

    test('a diagnosed list element suppresses a nested LinearGradient',
        () async {
      await _expectNestedGradientChildRefusal(
        'LinearGradient(colors: kColors, stops: [0, Colors.teal])',
      );
    });

    test('a diagnosed list element suppresses a nested RadialGradient',
        () async {
      await _expectNestedGradientChildRefusal(
        'RadialGradient(colors: kColors, stops: [0, Colors.teal])',
      );
    });

    test('a final local list is double-coerced by LinearGradient', () async {
      final result = await _transpile(
        _constStopsFixture(
          memberSource: '',
          buildSource: '''
  Widget build(BuildContext context) {
    final stops = [0, 1];
    return Box(
      gradient: LinearGradient(colors: kColors, stops: stops),
    );
  }
''',
        ),
        _gradientBoxCatalog(),
        rootPackage: 'apps_examples',
      );
      final definition = result.translation.widgetDefinitions['AcmeGradient'];
      expect(result.issues, isEmpty);
      expect(result.decoded, isNotNull);
      expect(definition, contains('stops: [0.0, 1.0]'));
      expect(definition, isNot(contains('stops: [0, 1]')));
    });

    test('a final local list is double-coerced by RadialGradient', () async {
      final result = await _transpile(
        _constStopsFixture(
          memberSource: '',
          buildSource: '''
  Widget build(BuildContext context) {
    final stops = [0, 1];
    return Box(
      gradient: RadialGradient(colors: kColors, stops: stops),
    );
  }
''',
        ),
        _gradientBoxCatalog(),
        rootPackage: 'apps_examples',
      );
      final definition = result.translation.widgetDefinitions['AcmeGradient'];
      expect(result.issues, isEmpty);
      expect(result.decoded, isNotNull);
      expect(definition, contains('stops: [0.0, 1.0]'));
      expect(definition, isNot(contains('stops: [0, 1]')));
    });

    test('a helper argument list is double-coerced by LinearGradient',
        () async {
      final result = await _transpile(
        _constStopsFixture(
          memberSource: '''
  Gradient gradient(List<double> stops) =>
      LinearGradient(colors: kColors, stops: stops);
''',
          buildSource: '''
  Widget build(BuildContext context) =>
      Box(gradient: gradient([0, 1]));
''',
        ),
        _gradientBoxCatalog(),
        rootPackage: 'apps_examples',
      );
      final definition = result.translation.widgetDefinitions['AcmeGradient'];
      expect(result.issues, isEmpty);
      expect(result.decoded, isNotNull);
      expect(definition, contains('stops: [0.0, 1.0]'));
      expect(definition, isNot(contains('stops: [0, 1]')));
    });

    test('a helper argument list is double-coerced by RadialGradient',
        () async {
      final result = await _transpile(
        _constStopsFixture(
          memberSource: '''
  Gradient gradient(List<double> stops) =>
      RadialGradient(colors: kColors, stops: stops);
''',
          buildSource: '''
  Widget build(BuildContext context) =>
      Box(gradient: gradient([0, 1]));
''',
        ),
        _gradientBoxCatalog(),
        rootPackage: 'apps_examples',
      );
      final definition = result.translation.widgetDefinitions['AcmeGradient'];
      expect(result.issues, isEmpty);
      expect(result.decoded, isNotNull);
      expect(definition, contains('stops: [0.0, 1.0]'));
      expect(definition, isNot(contains('stops: [0, 1]')));
    });

    for (final gradient in ['LinearGradient', 'RadialGradient']) {
      test('$gradient validates a typed list through a helper and final local',
          () async {
        final matching = await _transpile(
          _indirectColorListFixture(
            gradient: gradient,
            alternateType: 'Color',
            helperType: 'Color',
          ),
          _gradientBoxCatalog(),
          rootPackage: 'apps_examples',
        );
        expect(matching.issues, isEmpty);
        expect(matching.decoded, isNotNull);
        expect(
          matching.translation.widgetDefinitions['AcmeGradient'],
          contains(
            'colors: switch args.flag { true: args.colors, '
            'false: args.alternate }',
          ),
        );

        final mismatched = await _transpile(
          _indirectColorListFixture(
            gradient: gradient,
            alternateType: 'double',
            helperType: 'Object',
          ),
          _gradientBoxCatalog(),
          rootPackage: 'apps_examples',
        );
        expect(mismatched.decoded, isNull);
        expect(
          mismatched.translation.widgetDefinitions['AcmeGradient'],
          isEmpty,
        );
        expect(
          mismatched.issues.map((issue) => issue.code),
          [IssueCode.propertyValueTypeMismatch],
        );
        expect(
          mismatched.issues.single.message,
          allOf(contains("'List<Object>'"), contains("'color' item decoder")),
        );
        expect(mismatched.issues.single.location, isNotEmpty);
      });
    }

    test('distinguishes every indirect list decoder by resolved item type',
        () async {
      final accepted = await _transpile(
        _listDecoderFixture(
          _listDecoderCases,
          (entry) => entry.acceptedType,
        ),
        _listDecoderCatalog(_listDecoderCases),
        rootPackage: 'apps_examples',
      );
      expect(accepted.issues, isEmpty);
      expect(accepted.decoded, isNotNull);
      final definition =
          accepted.translation.widgetDefinitions['TypedListValues'];
      for (final entry in _listDecoderCases) {
        expect(
          definition,
          contains(
            '${entry.property}: switch args.flag { '
            'true: args.${entry.property}, '
            'false: args.${entry.property}Alternate }',
          ),
          reason: entry.property,
        );
      }

      for (final entry in _listDecoderCases) {
        final siblings = await _transpile(
          _listDecoderFixture([entry], (entry) => entry.siblingType),
          _listDecoderCatalog([entry]),
          rootPackage: 'apps_examples',
        );
        expect(siblings.decoded, isNull, reason: entry.property);
        expect(siblings.issues, isNotEmpty, reason: entry.property);
        expect(
          siblings.issues.map((issue) => issue.code),
          everyElement(IssueCode.propertyValueTypeMismatch),
          reason: entry.property,
        );
        expect(
          siblings.issues.map((issue) => issue.location),
          everyElement(isNotEmpty),
          reason: entry.property,
        );
      }

      final lookalikeCases = _listDecoderCases
          .where((entry) => entry.lookalikeType != null)
          .toList();
      for (final entry in lookalikeCases) {
        final lookalikes = await _transpile(
          _listDecoderFixture(
            [entry],
            (entry) => entry.lookalikeType!,
            declareLookalikes: true,
          ),
          _listDecoderCatalog([entry]),
          rootPackage: 'apps_examples',
        );
        expect(lookalikes.decoded, isNull, reason: entry.property);
        expect(lookalikes.issues, isNotEmpty, reason: entry.property);
        expect(
          lookalikes.issues.map((issue) => issue.code),
          everyElement(IssueCode.propertyValueTypeMismatch),
          reason: entry.property,
        );
      }

      final declared = await _transpile(
        _declaredListFixture('ui.Shadow'),
        _declaredListCatalog(),
        rootPackage: 'apps_examples',
      );
      expect(declared.issues, isEmpty);
      expect(declared.decoded, isNotNull);
      expect(
        declared.translation.dsl,
        contains(
          'DeclaredListValue(values: switch true { true: [], false: [] })',
        ),
      );

      final unknown = await _transpile(
        _declaredListFixture('UnknownValue', declareType: true),
        _declaredListCatalog(),
        rootPackage: 'apps_examples',
      );
      expect(unknown.decoded, isNull);
      expect(
        unknown.issues.map((issue) => issue.code),
        [IssueCode.propertyValueTypeMismatch],
      );
    });

    test('composition with constant-folding transpiles and round-trips',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

const double kGap = 16;

class Box extends StatelessWidget {
  const Box({this.size});
  final double? size;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeGap',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'gap',
)
class AcmeGap extends StatelessWidget {
  const AcmeGap();
  Widget build(BuildContext context) => Box(size: kGap * 2);
}

Object x() => AcmeGap();
''',
        catalogWith([
          _entry('Box', [prop('size', PropertyType.real)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final gap = _widget(result.decoded!, 'AcmeGap');
      expect(gap.name, 'Box');
      // `kGap * 2` folded to a literal.
      expect(gap.arguments['size'], 32.0);
    });

    test(
        'a const local shadowing a constructor parameter folds to its value, '
        'not the args reference', () async {
      // A `const` local in build() whose name collides with a constructor
      // parameter must fold to the const value — NOT be mistaken for the
      // `args.` runtime reference (a value-wrong blob the floor cannot catch:
      // it would silently render the passed-in argument instead of the const).
      final result = await _transpile(
        '''
$kClassifierStubs

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeBadge',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'badge',
)
class AcmeBadge extends StatelessWidget {
  const AcmeBadge({this.label});
  final String? label;
  Widget build(BuildContext context) {
    const label = 'gold';
    return Text(label);
  }
}

Object x() => AcmeBadge(label: "Pro");
''',
        catalogWith([
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final badge = _widget(result.decoded!, 'AcmeBadge');
      expect(badge.name, 'Text');
      // The const local wins over the (shadowed) constructor parameter: the
      // definition renders the literal "gold", not `args.label`.
      expect(badge.arguments['text'], 'gold');
    });

    test('a custom widget inlines a platform-gated conditional element',
        () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Column extends StatelessWidget {
  const Column({required this.children, super.key});
  final List<Widget> children;
  Widget build(BuildContext context) => const SizedBox();
}

class Label extends StatelessWidget {
  const Label({required this.text, super.key});
  final String text;
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmePlatformNote',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'platform note',
)
class AcmePlatformNote extends StatelessWidget {
  const AcmePlatformNote({required this.verbose});
  final bool verbose;
  Widget build(BuildContext context) => Column(
        children: [
          Label(text: 'Always'),
          if (defaultTargetPlatform == TargetPlatform.iOS && verbose)
            Label(text: 'App Store'),
        ],
      );
}

Object x() => AcmePlatformNote(verbose: true);
''',
        catalogWith([
          _entry(
            'Column',
            [prop('children', PropertyType.widgetList)],
            rootPackage: 'apps_examples',
          ),
          _entry(
            'Label',
            [prop('text', PropertyType.string, required: true)],
            rootPackage: 'apps_examples',
          ),
          _entry('SizedBox', [], rootPackage: 'apps_examples'),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final classified = result.classification.classifications.values
          .whereType<ComposableWidget>()
          .single;
      expect(
        classified.requiredMechanisms,
        containsAll([
          InliningMechanism.conditionalElement,
          InliningMechanism.themeAsData,
        ]),
      );
      final note = _widget(result.decoded!, 'AcmePlatformNote');
      final children = note.arguments['children']! as List<Object?>;
      expect(children, hasLength(2));
      final gate = children[1]! as fmt.Loop;
      final outer = gate.input as fmt.Switch;
      expect(
        (outer.input as fmt.DataReference).parts,
        ['device', 'platform'],
      );
    });

    test('a custom widget inlines a brightness-gated conditional element',
        () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Column extends StatelessWidget {
  const Column({required this.children, super.key});
  final List<Widget> children;
  Widget build(BuildContext context) => const SizedBox();
}

class Label extends StatelessWidget {
  const Label({required this.text, super.key});
  final String text;
  Widget build(BuildContext context) => const SizedBox();
}

class Empty extends StatelessWidget {
  const Empty({super.key});
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeNightNote',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'night note',
)
class AcmeNightNote extends StatelessWidget {
  const AcmeNightNote({required this.dimmed});
  final bool dimmed;
  Widget build(BuildContext context) => Column(
        children: [
          Label(text: 'Always'),
          if (Theme.of(context).brightness == Brightness.dark && dimmed)
            Label(text: 'Night'),
        ],
      );
}

Object x() => AcmeNightNote(dimmed: true);
''',
        catalogWith([
          _entry(
            'Column',
            [prop('children', PropertyType.widgetList)],
            rootPackage: 'apps_examples',
          ),
          _entry(
            'Label',
            [prop('text', PropertyType.string, required: true)],
            rootPackage: 'apps_examples',
          ),
          _entry('SizedBox', [], rootPackage: 'apps_examples'),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final classified = result.classification.classifications.values
          .whereType<ComposableWidget>()
          .single;
      expect(
        classified.requiredMechanisms,
        containsAll([
          InliningMechanism.conditionalElement,
          InliningMechanism.themeAsData,
        ]),
      );
      final note = _widget(result.decoded!, 'AcmeNightNote');
      final children = note.arguments['children']! as List<Object?>;
      expect(children, hasLength(2));
      final gate = children[1]! as fmt.Loop;
      final outer = gate.input as fmt.Switch;
      expect(
        (outer.input as fmt.DataReference).parts,
        ['theme', 'brightness'],
      );
    });

    test('an object-valued const local lowers through its initializer',
        () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.color, super.key});
  final Color? color;
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeBrand',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'brand box',
)
class AcmeBrand extends StatelessWidget {
  const AcmeBrand();
  Widget build(BuildContext context) {
    const brand = Color(0xFF112233);
    return Box(color: brand);
  }
}

Object x() => AcmeBrand();
''',
        catalogWith([
          _entry(
            'Box',
            [prop('color', PropertyType.color)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      final brand = _widget(result.decoded!, 'AcmeBrand');
      expect(brand.name, 'Box');
      expect(brand.arguments['color'], 0xFF112233);
    });

    test('a custom widget composing another transpiles both definitions',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmePill',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'pill',
)
class AcmePill extends StatelessWidget {
  const AcmePill();
  Widget build(BuildContext context) => Text("pill");
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget build(BuildContext context) => Container(child: AcmePill());
}

Object x() => AcmeCard();
''',
        catalogWith([
          _entry('Container', [prop('child', PropertyType.widget)]),
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      // Both composed custom widgets emit a definition, alongside the paywall.
      expect(
        decoded.widgets.map((w) => w.name),
        containsAll(['AcmeCard', 'AcmePill', 'Paywall']),
      );
      // AcmeCard's body references the nested custom widget by name.
      final card = _widget(decoded, 'AcmeCard');
      expect(card.name, 'Container');
      final nested = card.arguments['child'];
      expect(nested, isA<fmt.ConstructorCall>());
      expect((nested! as fmt.ConstructorCall).name, 'AcmePill');
    });

    test('a numeric argument is coerced to a double literal', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Box extends StatelessWidget {
  const Box({this.width});
  final double? width;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeBox',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'box',
)
class AcmeBox extends StatelessWidget {
  const AcmeBox({this.gap});
  final double? gap;
  Widget build(BuildContext context) => Box(width: gap);
}

Object x() => AcmeBox(gap: 12);
''',
        catalogWith([
          _entry('Box', [prop('width', PropertyType.real)]),
        ]),
      );

      expect(result.issues, isEmpty);
      // `gap` is a double parameter — the integer literal 12 is emitted as a
      // double so it survives the rfw `source.v<double>` decode.
      expect(_widget(result.decoded!, 'Paywall').arguments['gap'], 12.0);
    });

    test(
        'a Theme.of(c).colorScheme.primary read transpiles to a '
        'data.theme.colorScheme.primary reference in the emitted blob',
        () async {
      // Mounts the fixture under `apps_examples` so `Theme` resolves to
      // the real `package:flutter/material.dart` class — the strict theme-
      // read recognizer requires a `package:flutter/` library URI. Uses a
      // local `Box` widget for catalog matching (decoupled from Flutter's
      // private `Container` library path).
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.color, super.key});
  final Color? color;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeBanner',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'banner',
)
class AcmeBanner extends StatelessWidget {
  const AcmeBanner({super.key});
  @override
  Widget build(BuildContext context) =>
      Box(color: Theme.of(context).colorScheme.primary);
}

Object x() => const AcmeBanner();
''',
        catalogWith([
          _entry(
            'Box',
            [prop('color', PropertyType.color)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      expect(
        decoded.widgets.map((w) => w.name),
        containsAll(['AcmeBanner', 'Paywall']),
      );
      // The inlined widget definition's body references the data.theme.*
      // namespace at the contract path the SDK publishes.
      final banner = _widget(decoded, 'AcmeBanner');
      expect(banner.name, 'Box');
      final color = banner.arguments['color'];
      expect(color, isA<fmt.DataReference>());
      expect(
        (color! as fmt.DataReference).parts,
        ['theme', 'colorScheme', 'primary'],
      );
    });

    test(
        'a final local bound to an Alignment lowers through a special-cased '
        'alignmentXY slot (resolve-through reaches the slot path)', () async {
      // Regression: the alignmentXY slot path (`_translateSlotValue`) calls
      // `_alignmentGeometry` directly, bypassing `_translate`'s
      // resolve-through. A `final` local (or helper param) bound to a
      // framework `Alignment(x, y)` and used in such a slot must still
      // resolve-through to the `{x, y}` map — not fall through to an
      // `unrecognizedMethodCall` over-claim.
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.align, this.child, super.key});
  final Alignment? align;
  final Widget? child;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeAligned',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'aligned',
)
class AcmeAligned extends StatelessWidget {
  const AcmeAligned({super.key});
  @override
  Widget build(BuildContext context) {
    final a = Alignment(1.0, 1.0);
    return Box(align: a);
  }
}

Object x() => const AcmeAligned();
''',
        catalogWith([
          _entry(
            'Box',
            [
              prop('align', PropertyType.alignmentXY),
              prop('child', PropertyType.widget),
            ],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      final aligned = _widget(result.decoded!, 'AcmeAligned');
      expect(aligned.name, 'Box');
      // The bound local resolved through to the {x, y} map at the slot.
      expect(aligned.arguments['align'], {'x': 1.0, 'y': 1.0});
    });

    test(
        'a final local bound to a LinearBorderEdge lowers through a nested '
        'LinearBorder edge (resolve-through reaches _linearBorderEdge)',
        () async {
      // `_linearBorderEdge` dispatches on the RAW expr shape (the
      // `LinearBorderEdge(...)` ctor) and diagnoses directly (no `_translate`
      // fallback), so a `final` local bound to a `LinearBorderEdge` used as a
      // nested edge must resolve-through here — otherwise it over-claims
      // (classifier inlinable, translator an `unrecognizedMethodCall`).
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.shape, this.child, super.key});
  final ShapeBorder? shape;
  final Widget? child;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeShaped',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'shaped',
)
class AcmeShaped extends StatelessWidget {
  const AcmeShaped({super.key});
  @override
  Widget build(BuildContext context) {
    final edge = LinearBorderEdge(size: 0.5, alignment: 1.0);
    return Box(shape: LinearBorder(start: edge));
  }
}

Object x() => const AcmeShaped();
''',
        catalogWith(
          [
            _entry(
              'Box',
              [
                prop('shape', PropertyType.shapeBorder),
                prop('child', PropertyType.widget),
              ],
              rootPackage: 'apps_examples',
            ),
          ],
          structuredTypes: [
            structuredEntry('LinearBorder'),
            structuredEntry('LinearBorderEdge'),
          ],
        ),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      final shaped = _widget(result.decoded!, 'AcmeShaped');
      expect(shaped.name, 'Box');
      final shape = shaped.arguments['shape']! as Map<Object?, Object?>;
      // The nested bound LinearBorderEdge resolved through to the edge map.
      expect(shape['start'], {'size': 0.5, 'alignment': 1.0});
    });

    test(
        'a whole-style theme read into a slot with no style decomposition '
        'transpiles to a themeReadOutOfContract diagnostic, no blob emitted',
        () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.style, super.key});
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeBanner',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'banner',
)
class AcmeBanner extends StatelessWidget {
  const AcmeBanner({super.key});
  @override
  Widget build(BuildContext context) =>
      Box(style: Theme.of(context).textTheme.bodyLarge);
}

Object x() => const AcmeBanner();
''',
        catalogWith([
          _entry(
            'Box',
            [prop('style', PropertyType.string)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.decoded, isNull);
      expect(
        result.issues.any((i) => i.code == IssueCode.themeReadOutOfContract),
        isTrue,
      );
    });

    test(
        'a bound whole text-theme style decomposes into the flat style '
        'properties', () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Label extends StatelessWidget {
  const Label({this.text, this.style, super.key});
  final String? text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeHeading',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration,
  description: 'heading',
)
class AcmeHeading extends StatelessWidget {
  const AcmeHeading({super.key});
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Label(text: 'Go Pro', style: text.titleLarge);
  }
}

Object x() => const AcmeHeading();
''',
        _styleDecomposeCatalog(),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      final heading = _widget(result.decoded!, 'AcmeHeading');
      expect(heading.name, 'Label');
      expect(heading.arguments['style'], isNull);
      for (final field in _publishedStyleFields) {
        final value = heading.arguments[field];
        expect(value, isA<fmt.DataReference>(), reason: field);
        expect(
          (value! as fmt.DataReference).parts,
          ['theme', 'textTheme', 'titleLarge', field],
        );
      }
    });

    test('copyWith on a bound whole-style read overrides the fields it names',
        () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Label extends StatelessWidget {
  const Label({this.text, this.style, super.key});
  final String? text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeHeading',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration,
  description: 'heading',
)
class AcmeHeading extends StatelessWidget {
  const AcmeHeading({super.key});
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Label(
      text: 'Go Pro',
      style: text.titleLarge!.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontFamily: 'Charter',
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
    );
  }
}

Object x() => const AcmeHeading();
''',
        _styleDecomposeCatalog(),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      // copyWith on a theme style must inline the widget, not defer it.
      const headingKey = 'package:apps_examples/_e2e_probe.dart#AcmeHeading';
      final classified = result.classification.classifications[headingKey];
      expect(classified, isA<ComposableWidget>());
      expect(
        (classified! as ComposableWidget).requiredMechanisms,
        {InliningMechanism.themeAsData},
      );
      expect(result.classification.blueprints, contains(headingKey));

      final heading = _widget(result.decoded!, 'AcmeHeading');
      expect(heading.name, 'Label');
      // A colour-role theme read as the override lands as its own binding.
      final color = heading.arguments['color'];
      expect(color, isA<fmt.DataReference>());
      expect(
        (color! as fmt.DataReference).parts,
        ['theme', 'colorScheme', 'primary'],
      );
      expect(heading.arguments['fontFamily'], 'Charter');
      expect(heading.arguments['fontWeight'], 'w700');
      expect(heading.arguments['height'], 1.4);
      // Unnamed fields stay bound to the style, the font style among them.
      const overridden = {'color', 'fontFamily', 'fontWeight', 'height'};
      for (final field
          in _publishedStyleFields.where((f) => !overridden.contains(f))) {
        final value = heading.arguments[field];
        expect(value, isA<fmt.DataReference>(), reason: field);
        expect(
          (value! as fmt.DataReference).parts,
          ['theme', 'textTheme', 'titleLarge', field],
        );
      }
    });

    test('copyWith naming a field the theme style does not carry is refused',
        () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Label extends StatelessWidget {
  const Label({this.text, this.style, super.key});
  final String? text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeHeading',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration,
  description: 'heading',
)
class AcmeHeading extends StatelessWidget {
  const AcmeHeading({super.key});
  @override
  Widget build(BuildContext context) => Label(
        text: 'Go Pro',
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(inherit: false),
      );
}

Object x() => const AcmeHeading();
''',
        _styleDecomposeCatalog(),
        rootPackage: 'apps_examples',
      );

      expect(result.decoded, isNull);
      final refusal = result.issues.singleWhere(
        (i) => i.code == IssueCode.themeReadOutOfContract,
      );
      expect(refusal.message, contains('inherit'));
      for (final field in _publishedStyleFields) {
        expect(refusal.message, contains(field), reason: field);
      }
    });

    test(
        'a `final cs = Theme.of(c).colorScheme` local resolves through: '
        'cs.primary lowers to data.theme.colorScheme.primary (rung 2)',
        () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.color, super.key});
  final Color? color;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeBanner',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'banner',
)
class AcmeBanner extends StatelessWidget {
  const AcmeBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Box(color: cs.primary);
  }
}

Object x() => const AcmeBanner();
''',
        catalogWith([
          _entry(
            'Box',
            [prop('color', PropertyType.color)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      final banner = _widget(result.decoded!, 'AcmeBanner');
      expect(banner.name, 'Box');
      final color = banner.arguments['color'];
      expect(color, isA<fmt.DataReference>());
      expect(
        (color! as fmt.DataReference).parts,
        ['theme', 'colorScheme', 'primary'],
      );
    });

    test(
        'the slot validator sees a bound-chain theme fallback: a color-kind '
        'read in a length slot is caught (propertyValueTypeMismatch)',
        () async {
      // A PropertyAccess-only validator would silently skip a bound-chain
      // fallback (`cs.primary` is a PrefixedIdentifier) and bypass the kind
      // check — this negative pins that the binding-aware recognizer is routed
      // through the slot validator, so the mismatch is caught.
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.width, super.key});
  final double? width;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeBanner',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'banner',
)
class AcmeBanner extends StatelessWidget {
  const AcmeBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Box(width: cs.primary);
  }
}

Object x() => const AcmeBanner();
''',
        catalogWith([
          _entry(
            'Box',
            [prop('width', PropertyType.length)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.decoded, isNull);
      expect(
        result.issues.any((i) => i.code == IssueCode.propertyValueTypeMismatch),
        isTrue,
      );
    });

    test(
        'an unfollowable theme-local use defers (out-of-contract, not silent): '
        'passing the whole colorScheme to a color slot', () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.color, super.key});
  final Color? color;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeBanner',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'banner',
)
class AcmeBanner extends StatelessWidget {
  const AcmeBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Box(color: cs);
  }
}

Object x() => const AcmeBanner();
''',
        catalogWith([
          _entry(
            'Box',
            [prop('color', PropertyType.color)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      // `cs` is the whole ColorScheme (path 'colorScheme', not a leaf role) —
      // it resolves through but is out of the published contract, a clean
      // diagnosed defer rather than a silent-wrong blob.
      expect(result.decoded, isNull);
      expect(
        result.issues.any((i) => i.code == IssueCode.themeReadOutOfContract),
        isTrue,
      );
    });

    test(
        'an optional `color ?? scheme.primary` property inlines: the body '
        'reads args.color and the omitting call site is completed with the '
        'fallback (c1 + rung 2)', () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.color, super.key});
  final Color? color;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeBanner',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'banner',
)
class AcmeBanner extends StatelessWidget {
  const AcmeBanner({this.color, super.key});
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Box(color: color ?? scheme.primary);
  }
}

Object x() => const AcmeBanner();
''',
        catalogWith([
          _entry(
            'Box',
            [prop('color', PropertyType.color)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      // The definition body reads `args.color` — the `??` rewritten away.
      final banner = _widget(decoded, 'AcmeBanner');
      expect(banner.name, 'Box');
      final bodyColor = banner.arguments['color'];
      expect(bodyColor, isA<fmt.ArgsReference>());
      expect((bodyColor! as fmt.ArgsReference).parts, ['color']);
      // The omitting call site is completed with the lowered fallback.
      final paywall = _widget(decoded, 'Paywall');
      expect(paywall.name, 'AcmeBanner');
      final completed = paywall.arguments['color'];
      expect(completed, isA<fmt.DataReference>());
      expect(
        (completed! as fmt.DataReference).parts,
        ['theme', 'colorScheme', 'primary'],
      );
    });

    test('a bound text-theme local reads through a null-aware field access',
        () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.width, super.key});
  final double? width;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeGap',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'gap',
)
class AcmeGap extends StatelessWidget {
  const AcmeGap({super.key});
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Box(width: text.titleLarge?.fontSize);
  }
}

Object x() => const AcmeGap();
''',
        catalogWith([
          _entry(
            'Box',
            [prop('width', PropertyType.length)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      final width = _widget(result.decoded!, 'AcmeGap').arguments['width'];
      expect(width, isA<fmt.DataReference>());
      expect(
        (width! as fmt.DataReference).parts,
        ['theme', 'textTheme', 'titleLarge', 'fontSize'],
      );
    });

    test(
        'a device read through a bound `final` local inlines to a '
        'data.device reference', () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.width, super.key});
  final double? width;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeStrip',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'strip',
)
class AcmeStrip extends StatelessWidget {
  const AcmeStrip({super.key});
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Box(width: size.width);
  }
}

Object x() => const AcmeStrip();
''',
        catalogWith([
          _entry(
            'Box',
            [prop('width', PropertyType.length)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      final strip = _widget(result.decoded!, 'AcmeStrip');
      expect(strip.name, 'Box');
      final width = strip.arguments['width'];
      expect(width, isA<fmt.DataReference>());
      expect((width! as fmt.DataReference).parts, ['device', 'screenWidth']);
    });

    // The null-coalescing completion table, value-asserted per branch. A
    // numeric property with a literal `?? 8.0` fallback keeps the assertions
    // concrete: the body reads `args.width`; each call site completes per its
    // Dart semantics.
    const meterBox = '''
class Box extends StatelessWidget {
  const Box({this.width});
  final double? width;
  Widget build(BuildContext context) => const Widget();
}
''';

    test(
        'completion row 1: an omitted property with a constructor default '
        'emits the default (the `??` never fires), NOT the fallback', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

$meterBox

@RestageWidget(name: 'Meter', library: WidgetLibrary.custom('acme.ds'), category: WidgetCategory.layout, description: 'm')
class Meter extends StatelessWidget {
  const Meter({this.width = 4.0});
  final double? width;
  Widget build(BuildContext context) => Box(width: width ?? 8.0);
}

Object x() => const Meter();
''',
        catalogWith([
          _entry('Box', [prop('width', PropertyType.length)]),
        ]),
      );

      expect(result.issues, isEmpty);
      // The default 4.0 completes the call site — distinct from the 8.0
      // fallback (row 2). This boundary is where a regression would silently
      // swap a constructor default for the coalesce fallback.
      expect(_widget(result.decoded!, 'Paywall').arguments['width'], 4.0);
    });

    test(
        'completion row 2: an omitted property with no default emits the '
        'fallback', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

$meterBox

@RestageWidget(name: 'Meter', library: WidgetLibrary.custom('acme.ds'), category: WidgetCategory.layout, description: 'm')
class Meter extends StatelessWidget {
  const Meter({this.width});
  final double? width;
  Widget build(BuildContext context) => Box(width: width ?? 8.0);
}

Object x() => const Meter();
''',
        catalogWith([
          _entry('Box', [prop('width', PropertyType.length)]),
        ]),
      );

      expect(result.issues, isEmpty);
      expect(_widget(result.decoded!, 'Paywall').arguments['width'], 8.0);
    });

    test(
        'completion row 3: an explicit `null` fires the `??` and emits the '
        'fallback (distinct from an omitted default)', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

$meterBox

@RestageWidget(name: 'Meter', library: WidgetLibrary.custom('acme.ds'), category: WidgetCategory.layout, description: 'm')
class Meter extends StatelessWidget {
  const Meter({this.width});
  final double? width;
  Widget build(BuildContext context) => Box(width: width ?? 8.0);
}

Object x() => const Meter(width: null);
''',
        catalogWith([
          _entry('Box', [prop('width', PropertyType.length)]),
        ]),
      );

      expect(result.issues, isEmpty);
      expect(_widget(result.decoded!, 'Paywall').arguments['width'], 8.0);
    });

    test('completion row 4: a passed value is used unchanged, NOT the fallback',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

$meterBox

@RestageWidget(name: 'Meter', library: WidgetLibrary.custom('acme.ds'), category: WidgetCategory.layout, description: 'm')
class Meter extends StatelessWidget {
  const Meter({this.width});
  final double? width;
  Widget build(BuildContext context) => Box(width: width ?? 8.0);
}

Object x() => const Meter(width: 2.0);
''',
        catalogWith([
          _entry('Box', [prop('width', PropertyType.length)]),
        ]),
      );

      expect(result.issues, isEmpty);
      expect(_widget(result.decoded!, 'Paywall').arguments['width'], 2.0);
    });

    test(
        'gate 3: a runtime-nullable passed value to a coalesced property '
        'defers (the fallback would be lost), never a silent blob', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

$meterBox

@RestageWidget(name: 'Meter', library: WidgetLibrary.custom('acme.ds'), category: WidgetCategory.layout, description: 'm')
class Meter extends StatelessWidget {
  const Meter({this.width});
  final double? width;
  Widget build(BuildContext context) => Box(width: width ?? 8.0);
}

@RestageWidget(name: 'Outer', library: WidgetLibrary.custom('acme.ds'), category: WidgetCategory.layout, description: 'o')
class Outer extends StatelessWidget {
  const Outer({this.w});
  final double? w;
  Widget build(BuildContext context) => Meter(width: w);
}

Object x() => const Outer();
''',
        catalogWith([
          _entry('Box', [prop('width', PropertyType.length)]),
        ]),
      );

      expect(result.decoded, isNull);
      expect(
        result.issues
            .any((i) => i.code == IssueCode.customWidgetUnsupportedReducible),
        isTrue,
      );
    });

    test(
        'gate 1: a property read both directly and coalesced defers '
        '(it cannot be completed consistently)', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Box extends StatelessWidget {
  const Box({this.width, this.extra});
  final double? width;
  final double? extra;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(name: 'Meter', library: WidgetLibrary.custom('acme.ds'), category: WidgetCategory.layout, description: 'm')
class Meter extends StatelessWidget {
  const Meter({this.width});
  final double? width;
  Widget build(BuildContext context) => Box(width: width ?? 8.0, extra: width);
}

Object x() => const Meter();
''',
        catalogWith([
          _entry('Box', [
            prop('width', PropertyType.length),
            prop('extra', PropertyType.length),
          ]),
        ]),
      );

      expect(result.decoded, isNull);
      expect(
        result.issues.any((i) => i.code == IssueCode.customWidgetUnclassified),
        isTrue,
      );
    });

    test(
        'a framework FontWeight.<member> static-const lowers to its enum '
        'string and transpiles through the classified path end-to-end',
        () async {
      // Mounted under apps_examples so `FontWeight` resolves to the real
      // package:flutter class — the element gate (look-alike-safe) requires it.
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Label extends StatelessWidget {
  const Label({this.weight, super.key});
  final FontWeight? weight;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Heading',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'heading',
)
class Heading extends StatelessWidget {
  const Heading({super.key});
  @override
  Widget build(BuildContext context) => Label(weight: FontWeight.w600);
}

Object x() => const Heading();
''',
        catalogWith([
          _entry(
            'Label',
            [prop('weight', PropertyType.fontWeight)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      // The classified path produces a decodable blob carrying the enum string
      // `"w600"` — exactly the key the generated factory's
      // `ArgumentDecoders.enumValue<FontWeight>(FontWeight.values, …)` resolves
      // to the real `FontWeight.w600` (proven decoder-side in flutter_sdk).
      expect(result.issues, isEmpty);
      expect(_widget(result.decoded!, 'Heading').arguments['weight'], 'w600');
    });

    test(
        'a framework FontWeight alias (.bold) canonicalises to its wN name '
        'through the classified path end-to-end', () async {
      // `FontWeight.bold` aliases `w700`; the bare alias name `"bold"` is not
      // in `FontWeight.values[].name`, so without canonicalisation the decoder
      // would null it (a silent drop). The classified path must carry `"w700"`.
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Label extends StatelessWidget {
  const Label({this.weight, super.key});
  final FontWeight? weight;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Heading',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'heading',
)
class Heading extends StatelessWidget {
  const Heading({super.key});
  @override
  Widget build(BuildContext context) => Label(weight: FontWeight.bold);
}

Object x() => const Heading();
''',
        catalogWith([
          _entry(
            'Label',
            [prop('weight', PropertyType.fontWeight)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      expect(_widget(result.decoded!, 'Heading').arguments['weight'], 'w700');
    });

    test(
        'a custom FontWeight look-alike (a non-Flutter class) defers — '
        'no enum string is emitted (element-gated)', () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class FontWeight {
  const FontWeight._();
  static const FontWeight w600 = FontWeight._();
}

class Label extends StatelessWidget {
  const Label({this.weight, super.key});
  final Object? weight;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Heading',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'heading',
)
class Heading extends StatelessWidget {
  const Heading({super.key});
  @override
  Widget build(BuildContext context) => Label(weight: FontWeight.w600);
}

Object x() => const Heading();
''',
        catalogWith([
          _entry(
            'Label',
            [prop('weight', PropertyType.string)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      // The custom `FontWeight` is not the framework class, so the widget
      // defers — no blob, and crucially no `"w600"` string substituted for the
      // app's value (the value-substitution silent-wrong stays closed).
      expect(result.decoded, isNull);
      expect(result.issues, isNotEmpty);
    });

    test(
        'a framework TextDecoration.<member> static-const lowers to its enum '
        'string and transpiles through the classified path end-to-end',
        () async {
      // `TextDecoration` is the same non-enum static-const-class shape as
      // FontWeight; the general framework enum-like-const recogniser classifies
      // it as composition and the translator lowers it to its member-name
      // string, which `RestageDecoders.textDecoration` decodes.
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Label extends StatelessWidget {
  const Label({this.deco, super.key});
  final TextDecoration? deco;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Heading',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'heading',
)
class Heading extends StatelessWidget {
  const Heading({super.key});
  @override
  Widget build(BuildContext context) => Label(deco: TextDecoration.underline);
}

Object x() => const Heading();
''',
        catalogWith([
          _entry(
            'Label',
            [prop('deco', PropertyType.textDecoration)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      expect(
        _widget(result.decoded!, 'Heading').arguments['deco'],
        'underline',
      );
    });

    test(
        'a custom TextDecoration look-alike (a non-Flutter class) defers — '
        'no enum string is emitted (element-gated)', () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class TextDecoration {
  const TextDecoration._();
  static const TextDecoration underline = TextDecoration._();
}

class Label extends StatelessWidget {
  const Label({this.deco, super.key});
  final Object? deco;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Heading',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'heading',
)
class Heading extends StatelessWidget {
  const Heading({super.key});
  @override
  Widget build(BuildContext context) => Label(deco: TextDecoration.underline);
}

Object x() => const Heading();
''',
        catalogWith([
          _entry(
            'Label',
            [prop('deco', PropertyType.string)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      // The custom `TextDecoration` is not the framework class, so the widget
      // defers — no blob, and no `"underline"` string substituted for the
      // app's value (the value-substitution silent-wrong stays closed).
      expect(result.decoded, isNull);
      expect(result.issues, isNotEmpty);
    });

    test(
        'a framework Curves.<supported> member lowers to its name and '
        'transpiles through the classified path end-to-end', () async {
      // `Curves` is the third framework enum-like-const class; a supported
      // member is composition and lowers to its name, which the curve decoder
      // resolves. Element-gated to the real package:flutter Curves.
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Motion extends StatelessWidget {
  const Motion({this.curve, super.key});
  final Curve? curve;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Anim',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'anim',
)
class Anim extends StatelessWidget {
  const Anim({super.key});
  @override
  Widget build(BuildContext context) => Motion(curve: Curves.easeInOut);
}

Object x() => const Anim();
''',
        catalogWith([
          _entry(
            'Motion',
            [prop('curve', PropertyType.curve)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      expect(_widget(result.decoded!, 'Anim').arguments['curve'], 'easeInOut');
    });

    test(
        'a framework Curves.fastEaseInToSlowEaseOut (a real-but-unsupported '
        'member) DEFERS — never a silent drop', () async {
      // fastEaseInToSlowEaseOut is the ONE real Flutter Curves member outside
      // the supported decoder set. The custom-widget body path has NO curve
      // validator backstop (the floor backstops the catalog/translator path
      // only), so recognising it would emit the name to a path that nulls it —
      // a silent drop. The classifier pin to the supported set defers it.
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Motion extends StatelessWidget {
  const Motion({this.curve, super.key});
  final Curve? curve;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Anim',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'anim',
)
class Anim extends StatelessWidget {
  const Anim({super.key});
  @override
  Widget build(BuildContext context) =>
      Motion(curve: Curves.fastEaseInToSlowEaseOut);
}

Object x() => const Anim();
''',
        catalogWith([
          _entry(
            'Motion',
            [prop('curve', PropertyType.curve)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      // Deferred, not dropped: no blob, a diagnostic instead of a degraded one.
      expect(result.decoded, isNull);
      expect(result.issues, isNotEmpty);
    });

    test(
        'a custom Curves look-alike (a non-Flutter class) defers — no curve '
        'name is emitted (element-gated)', () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Curves {
  const Curves._();
  static const Curves easeInOut = Curves._();
}

class Motion extends StatelessWidget {
  const Motion({this.curve, super.key});
  final Object? curve;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Anim',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'anim',
)
class Anim extends StatelessWidget {
  const Anim({super.key});
  @override
  Widget build(BuildContext context) => Motion(curve: Curves.easeInOut);
}

Object x() => const Anim();
''',
        catalogWith([
          _entry(
            'Motion',
            [prop('curve', PropertyType.string)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      // The custom `Curves` is not the framework class, so the widget defers
      // — no blob, and no `"easeInOut"` string substituted for the author's
      // own value (the value-substitution silent-wrong stays closed).
      expect(result.decoded, isNull);
      expect(result.issues, isNotEmpty);
    });

    // -- structured-value static-const members (BorderSide.none + the .zero
    //    const-factory siblings). The translator already lowers each to its
    //    map/list/scalar shape (each arm element-gated); the classifier now
    //    recognises the curated (class, member) pairs so a custom-widget body
    //    using them inlines instead of deferring.
    test(
        'the .zero structured-const siblings (EdgeInsets/Offset/BorderRadius) '
        'lower to their structured values through the classified path',
        () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.padding, this.offset, this.radius, super.key});
  final EdgeInsetsGeometry? padding;
  final Offset? offset;
  final BorderRadiusGeometry? radius;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Acme',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'acme',
)
class Acme extends StatelessWidget {
  const Acme({super.key});
  @override
  Widget build(BuildContext context) => Box(
        padding: EdgeInsets.zero,
        offset: Offset.zero,
        radius: BorderRadius.zero,
      );
}

Object x() => const Acme();
''',
        catalogWith([
          _entry(
            'Box',
            [
              prop('padding', PropertyType.edgeInsets),
              prop('offset', PropertyType.offset),
              prop('radius', PropertyType.real),
            ],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      final box = _widget(result.decoded!, 'Acme');
      expect(box.arguments['padding'], [0.0, 0.0, 0.0, 0.0]);
      expect(box.arguments['offset'], {'x': 0.0, 'y': 0.0});
      expect(box.arguments['radius'], 0);
    });

    test(
        'the Directional .zero siblings (EdgeInsetsDirectional/'
        'BorderRadiusDirectional) lower to the same structured values',
        () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.padding, this.radius, super.key});
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry? radius;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Acme',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'acme',
)
class Acme extends StatelessWidget {
  const Acme({super.key});
  @override
  Widget build(BuildContext context) => Box(
        padding: EdgeInsetsDirectional.zero,
        radius: BorderRadiusDirectional.zero,
      );
}

Object x() => const Acme();
''',
        catalogWith([
          _entry(
            'Box',
            [
              prop('padding', PropertyType.edgeInsets),
              prop('radius', PropertyType.real),
            ],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      final box = _widget(result.decoded!, 'Acme');
      expect(box.arguments['padding'], [0.0, 0.0, 0.0, 0.0]);
      expect(box.arguments['radius'], 0);
    });

    test(
        'a direct BorderSide.none inside a real shape border lowers to the '
        'framework none-map through the classified path', () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.shape, super.key});
  final ShapeBorder? shape;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Acme',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'acme',
)
class Acme extends StatelessWidget {
  const Acme({super.key});
  @override
  Widget build(BuildContext context) =>
      Box(shape: RoundedRectangleBorder(side: BorderSide.none));
}

Object x() => const Acme();
''',
        catalogWith(
          [
            _entry(
              'Box',
              [prop('shape', PropertyType.shapeBorder)],
              rootPackage: 'apps_examples',
            ),
          ],
          structuredTypes: [structuredEntry('RoundedRectangleBorder')],
        ),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      final box = _widget(result.decoded!, 'Acme');
      final shape = box.arguments['shape']! as Map<Object?, Object?>;
      expect(shape['side'], {'width': 0.0, 'style': 'none'});
    });

    test(
        'a bound `final s = BorderSide.none` resolves through the nested border '
        'value-helper end-to-end (the carried obligation)', () async {
      // BorderSide.none now classifies, so a bound local reaches
      // `_borderSideExpression`'s resolve-through (landed defensively in the
      // nested-value-helper cut) for the first time.
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.shape, super.key});
  final ShapeBorder? shape;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Acme',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'acme',
)
class Acme extends StatelessWidget {
  const Acme({super.key});
  @override
  Widget build(BuildContext context) {
    final s = BorderSide.none;
    return Box(shape: RoundedRectangleBorder(side: s));
  }
}

Object x() => const Acme();
''',
        catalogWith(
          [
            _entry(
              'Box',
              [prop('shape', PropertyType.shapeBorder)],
              rootPackage: 'apps_examples',
            ),
          ],
          structuredTypes: [structuredEntry('RoundedRectangleBorder')],
        ),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      final box = _widget(result.decoded!, 'Acme');
      final shape = box.arguments['shape']! as Map<Object?, Object?>;
      expect(shape['side'], {'width': 0.0, 'style': 'none'});
    });

    test(
        'a custom EdgeInsets.zero look-alike (a non-Flutter class) defers — '
        'no zero list substituted', () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class EdgeInsets {
  const EdgeInsets._();
  static const EdgeInsets zero = EdgeInsets._();
}

class Box extends StatelessWidget {
  const Box({this.padding, super.key});
  final Object? padding;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Acme',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'acme',
)
class Acme extends StatelessWidget {
  const Acme({super.key});
  @override
  Widget build(BuildContext context) => Box(padding: EdgeInsets.zero);
}

Object x() => const Acme();
''',
        catalogWith([
          _entry(
            'Box',
            [prop('padding', PropertyType.string)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.decoded, isNull);
      expect(result.issues, isNotEmpty);
    });

    test(
        'a custom BorderSide.none look-alike (a non-Flutter class) defers — '
        'no framework none-map substituted', () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class BorderSide {
  const BorderSide._();
  static const BorderSide none = BorderSide._();
}

class Box extends StatelessWidget {
  const Box({this.side, super.key});
  final Object? side;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Acme',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'acme',
)
class Acme extends StatelessWidget {
  const Acme({super.key});
  @override
  Widget build(BuildContext context) => Box(side: BorderSide.none);
}

Object x() => const Acme();
''',
        catalogWith([
          _entry(
            'Box',
            [prop('side', PropertyType.string)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.decoded, isNull);
      expect(result.issues, isNotEmpty);
    });

    test(
        'a direct BorderSide.none inside a box Border(top:) lowers to the '
        'none-map, not a bare string, through the classified path', () async {
      // The box `Border(top:/right:/bottom:/left:)` constructor lowers each
      // side through `_borderSideExpression` (the same look-alike-safe,
      // none-map-aware helper the shape-border `side:` arms use), so a
      // recognised `BorderSide.none` becomes the framework none-map. This is
      // the semantic identity Flutter gives an explicit `BorderSide.none` and
      // an OMITTED side — `_borderDefault` already serialises omitted sides as
      // `{width: 0.0, style: "none"}`, and the explicit member now matches.
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.border, super.key});
  final Border? border;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Acme',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'acme',
)
class Acme extends StatelessWidget {
  const Acme({super.key});
  @override
  Widget build(BuildContext context) => Box(
        border: Border(
          top: BorderSide.none,
          left: BorderSide(color: Color(0xFFFFFFFF), width: 2),
        ),
      );
}

Object x() => const Acme();
''',
        catalogWith([
          _entry(
            'Box',
            [prop('border', PropertyType.border)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      // The border list is [left/start, top, right/end, bottom]; the top side
      // (index 1) must be the none-map, not the bare string "none" the generic
      // translate path would emit (which rfw's borderSide decoder ignores,
      // silently inheriting the start side — the value-wrong shape this closes).
      final border = _widget(result.decoded!, 'Acme').arguments['border']!
          as List<Object?>;
      expect(border[1], {'width': 0.0, 'style': 'none'});
    });

    test(
        'a bound `final s = BorderSide.none` resolves through a box Border(top:) '
        'end-to-end (the resolve-through, parallel to the shape-border case)',
        () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.border, super.key});
  final Border? border;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Acme',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'acme',
)
class Acme extends StatelessWidget {
  const Acme({super.key});
  @override
  Widget build(BuildContext context) {
    final s = BorderSide.none;
    return Box(
      border: Border(
        top: s,
        left: BorderSide(color: Color(0xFFFFFFFF), width: 2),
      ),
    );
  }
}

Object x() => const Acme();
''',
        catalogWith([
          _entry(
            'Box',
            [prop('border', PropertyType.border)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty);
      final border = _widget(result.decoded!, 'Acme').arguments['border']!
          as List<Object?>;
      expect(border[1], {'width': 0.0, 'style': 'none'});
    });

    test(
        'gate 1 (distinct fallbacks): a property read with two different '
        '`?? fallback` values defers — it cannot be completed consistently',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Box extends StatelessWidget {
  const Box({this.width, this.height});
  final double? width;
  final double? height;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(name: 'Meter', library: WidgetLibrary.custom('acme.ds'), category: WidgetCategory.layout, description: 'm')
class Meter extends StatelessWidget {
  const Meter({this.size});
  final double? size;
  Widget build(BuildContext context) =>
      Box(width: size ?? 8.0, height: size ?? 9.0);
}

Object x() => const Meter();
''',
        catalogWith([
          _entry('Box', [
            prop('width', PropertyType.length),
            prop('height', PropertyType.length),
          ]),
        ]),
      );

      // `size` is coalesced with two DIFFERENT fallbacks; the call site cannot
      // complete it with a single value, so the widget defers, never emits one.
      expect(result.decoded, isNull);
      expect(result.issues, isNotEmpty);
    });

    test(
        'gate 2 (binding-hidden context): a fallback reading own args through '
        'a captured `final` local defers', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Box extends StatelessWidget {
  const Box({this.width});
  final double? width;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(name: 'Meter', library: WidgetLibrary.custom('acme.ds'), category: WidgetCategory.layout, description: 'm')
class Meter extends StatelessWidget {
  const Meter({this.width, this.other});
  final double? width;
  final double? other;
  Widget build(BuildContext context) {
    final f = other;
    return Box(width: width ?? f);
  }
}

Object x() => const Meter(other: 2.0);
''',
        catalogWith([
          _entry('Box', [prop('width', PropertyType.length)]),
        ]),
      );

      // The fallback `f` is a local bound to the own property `other` — a
      // context-dependent value. Hoisting it to the call site would emit
      // `args.other` in the wrong scope, so the widget defers.
      expect(result.decoded, isNull);
      expect(result.issues, isNotEmpty);
    });

    test(
        'gate 3 (data-ref passed value): a value lowering to a '
        'possibly-missing data ref (a host-data helper) passed to a coalesced '
        'property defers — the fallback would be lost at runtime', () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs
import 'package:restage/restage.dart';

class Label extends StatelessWidget {
  const Label({this.text, super.key});
  final String? text;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Price',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.action,
  description: 'p',
)
class Price extends StatelessWidget {
  const Price({this.label, super.key});
  final String? label;
  @override
  Widget build(BuildContext context) => Label(text: label ?? "Free");
}

String hostText() => '';

Object x() => Price(label: hostText());
''',
        catalogWith([
          _entry(
            'Label',
            [prop('text', PropertyType.string)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
        extraHelpers: [_hostTextHelper],
      );

      // The non-null String lowers to host-provided data that can be absent.
      // Completing the coalesced `label` with it would use the factory default
      // instead of "Free", so the static-nullability gate defers.
      expect(result.decoded, isNull);
      expect(
        result.issues
            .any((i) => i.code == IssueCode.customWidgetUnsupportedReducible),
        isTrue,
      );
    });

    test('a coalesced widget list item validates its fallback before emission',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Column extends StatelessWidget {
  const Column({this.children});
  final List<Widget>? children;
  Widget build(BuildContext context) => const Widget();
}

class Box extends StatelessWidget {
  const Box();
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(name: 'Wrap', library: WidgetLibrary.custom('acme.ds'), category: WidgetCategory.layout, description: 'w')
class Wrap extends StatelessWidget {
  const Wrap({this.child});
  final Widget? child;
  Widget build(BuildContext context) =>
      Column(children: [child ?? const Box()]);
}

Object x() => const Wrap();
''',
        catalogWith([
          _entry('Column', [prop('children', PropertyType.widgetList)]),
          _entry('Box', const []),
        ]),
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      final wrap = _widget(decoded, 'Wrap');
      expect(wrap.name, 'Column');
      final children = wrap.arguments['children']! as List<Object?>;
      expect((children.single! as fmt.ArgsReference).parts, ['child']);
      final paywall = _widget(decoded, 'Paywall');
      expect(paywall.name, 'Wrap');
      expect((paywall.arguments['child']! as fmt.ConstructorCall).name, 'Box');
    });

    test('a coalesced widget list item refuses a color fallback', () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Column extends StatelessWidget {
  const Column({this.children, super.key});
  final List<Widget>? children;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'Wrap',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'w',
)
class Wrap extends StatelessWidget {
  const Wrap({this.child, super.key});
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [child ?? scheme.primary]);
  }
}

Object x() => const Wrap();
''',
        catalogWith([
          _entry(
            'Column',
            [prop('children', PropertyType.widgetList)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.decoded, isNull);
      expect(
        result.issues.map((issue) => issue.code),
        contains(IssueCode.propertyValueTypeMismatch),
      );
      expect(
        result.issues.map((issue) => issue.message).join('\n'),
        contains("cannot be assigned to a 'widget' property type"),
      );
    });

    test('coalesced widget items retain mixed static collection traversal',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Column extends StatelessWidget {
  const Column({required this.children});
  final List<Widget> children;
  Widget build(BuildContext context) => const Widget();
}

class Box extends StatelessWidget {
  const Box();
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(name: 'Wrap', library: WidgetLibrary.custom('acme.ds'), category: WidgetCategory.layout, description: 'w')
class Wrap extends StatelessWidget {
  const Wrap({this.child});
  final Widget? child;
  Widget build(BuildContext context) => Column(
        children: [
          const Box(),
          for (final include in const [true]) child ?? const Box(),
          if (true) const Box(),
        ],
      );
}

Object x() => const Wrap();
''',
        catalogWith([
          _entry('Column', [prop('children', PropertyType.widgetList)]),
          _entry('Box', const []),
        ]),
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      final wrap = _widget(decoded, 'Wrap');
      final children = wrap.arguments['children']! as List<Object?>;
      expect(children, hasLength(3));
      expect((children[0]! as fmt.ConstructorCall).name, 'Box');
      expect((children[1]! as fmt.ArgsReference).parts, ['child']);
      expect((children[2]! as fmt.ConstructorCall).name, 'Box');
      final paywall = _widget(decoded, 'Paywall');
      expect((paywall.arguments['child']! as fmt.ConstructorCall).name, 'Box');
    });

    test(
        "gate 2: a fallback reading the widget's own args defers "
        '(context-dependent, not hoistable)', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Box extends StatelessWidget {
  const Box({this.width});
  final double? width;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(name: 'Meter', library: WidgetLibrary.custom('acme.ds'), category: WidgetCategory.layout, description: 'm')
class Meter extends StatelessWidget {
  const Meter({this.width, this.other});
  final double? width;
  final double? other;
  Widget build(BuildContext context) => Box(width: width ?? other);
}

Object x() => const Meter(width: 1.0, other: 2.0);
''',
        catalogWith([
          _entry('Box', [prop('width', PropertyType.length)]),
        ]),
      );

      expect(result.decoded, isNull);
      expect(
        result.issues.any((i) => i.code == IssueCode.customWidgetImperative),
        isTrue,
      );
    });

    test(
        'a stateful widget with primitive State fields transpiles its '
        'initial state into a `widget X { name: init } = body` block and '
        'lowers state-field reads to `state.<name>`', () async {
      // No setState in this fixture — pure state-block + state-read
      // emission. setState recognition + the bool-flip switch form lands in
      // a sibling milestone; this test isolates the state-emission half.
      final result = await _transpile(
        '''
$kClassifierStubs

class Box extends StatelessWidget {
  const Box({this.label, this.prefix});
  final String? label;
  final String? prefix;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeDisplay',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'display',
)
class AcmeDisplay extends StatefulWidget {
  const AcmeDisplay({this.prefix});
  final String? prefix;
  _AcmeDisplayState createState() => _AcmeDisplayState();
}

class _AcmeDisplayState extends State<AcmeDisplay> {
  String message = "hello";
  Widget build(BuildContext context) =>
      Box(label: message, prefix: widget.prefix);
}

Object x() => AcmeDisplay(prefix: "P");
''',
        catalogWith([
          _entry('Box', [
            prop('label', PropertyType.string),
            prop('prefix', PropertyType.string),
          ]),
        ]),
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      // The stateful definition's initial state is carried on the
      // declaration — the canonical RFW state container.
      final display =
          decoded.widgets.firstWhere((w) => w.name == 'AcmeDisplay');
      expect(display.initialState, isNotNull);
      expect(display.initialState!['message'], 'hello');
      // The body reads the State field as `state.message` and the
      // constructor parameter as `args.prefix`.
      final root = display.root as fmt.ConstructorCall;
      expect(root.name, 'Box');
      final label = root.arguments['label'];
      expect(label, isA<fmt.StateReference>());
      expect((label! as fmt.StateReference).parts, ['message']);
      final prefix = root.arguments['prefix'];
      expect(prefix, isA<fmt.ArgsReference>());
      expect((prefix! as fmt.ArgsReference).parts, ['prefix']);
      // The paywall calls the inlined widget with the constructor param.
      final paywall = _widget(decoded, 'Paywall');
      expect(paywall.name, 'AcmeDisplay');
      expect(paywall.arguments['prefix'], 'P');
    });

    test(
        'a State body reading a top-level const emits the constant, not the '
        'same-named constructor parameter', () async {
      // In `State.build()` a bare name reaches a constructor parameter only
      // through `widget.X`, so `gap` here is the top-level const.
      final result = await _transpile(
        '''
$kClassifierStubs

class Box extends StatelessWidget {
  const Box({this.size, this.label});
  final double? size;
  final String? label;
  Widget build(BuildContext context) => const Widget();
}

const double gap = 8;

@RestageWidget(
  name: 'AcmeGapped',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'gapped',
)
class AcmeGapped extends StatefulWidget {
  const AcmeGapped({this.gap});
  final double? gap;
  _AcmeGappedState createState() => _AcmeGappedState();
}

class _AcmeGappedState extends State<AcmeGapped> {
  String label = "hi";
  Widget build(BuildContext context) => Box(size: gap, label: label);
}

Object x() => AcmeGapped(gap: 24);
''',
        catalogWith([
          _entry('Box', [
            prop('size', PropertyType.real),
            prop('label', PropertyType.string),
          ]),
        ]),
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      final definition = _widget(decoded, 'AcmeGapped');
      expect(definition.name, 'Box');
      final size = definition.arguments['size'];
      expect(
        size,
        isNot(isA<fmt.ArgsReference>()),
        reason: 'the caller argument must not substitute for the constant',
      );
      expect(size, 8.0);
      // The State field still lowers to `state.`, so this is a stateful walk.
      expect(definition.arguments['label'], isA<fmt.StateReference>());
      final paywall = _widget(decoded, 'Paywall');
      expect(paywall.name, 'AcmeGapped');
      expect(paywall.arguments['gap'], 24.0);
    });

    test(
        'a stateless body reading its own constructor parameter still emits '
        'an args reference when a same-named const is in scope', () async {
      // The stateless `build()` has the parameter in scope, so Dart binds
      // `gap` to it and the const is shadowed.
      final result = await _transpile(
        '''
$kClassifierStubs

class Box extends StatelessWidget {
  const Box({this.size});
  final double? size;
  Widget build(BuildContext context) => const Widget();
}

const double gap = 8;

@RestageWidget(
  name: 'AcmeSpaced',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'spaced',
)
class AcmeSpaced extends StatelessWidget {
  const AcmeSpaced({this.gap});
  final double? gap;
  Widget build(BuildContext context) => Box(size: gap);
}

Object x() => AcmeSpaced(gap: 24);
''',
        catalogWith([
          _entry('Box', [prop('size', PropertyType.real)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      final definition = _widget(decoded, 'AcmeSpaced');
      final size = definition.arguments['size'];
      expect(size, isA<fmt.ArgsReference>());
      expect((size! as fmt.ArgsReference).parts, ['gap']);
      final paywall = _widget(decoded, 'Paywall');
      expect(paywall.arguments['gap'], 24.0);
    });

    test(
        'a stateful toggle widget emits its setState bool-flip as the '
        'no-negation switch form RFW data accepts', () async {
      // The canonical bool-flip pattern: `setState(() => on = !on);`. RFW
      // has no negation operator in data, so the flip emits as
      // `set state.on = switch state.on { true: false, false: true }`.
      final result = await _transpile(
        '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Box extends StatelessWidget {
  const Box({this.label});
  final String? label;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeToggle',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'toggle',
)
class AcmeToggle extends StatefulWidget {
  const AcmeToggle();
  _AcmeToggleState createState() => _AcmeToggleState();
}

class _AcmeToggleState extends State<AcmeToggle> {
  bool on = false;
  void toggle() => setState(() => on = !on);
  Widget build(BuildContext context) =>
      GestureDetector(onTap: toggle, child: Box(label: "tap"));
}

Object x() => AcmeToggle();
''',
        catalogWith([
          _entry('GestureDetector', [
            prop('onTap', PropertyType.event),
            prop('child', PropertyType.widget),
          ]),
          _entry('Box', [prop('label', PropertyType.string)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      final toggle = decoded.widgets.firstWhere((w) => w.name == 'AcmeToggle');
      expect(toggle.initialState!['on'], isFalse);
      final root = toggle.root as fmt.ConstructorCall;
      expect(root.name, 'GestureDetector');
      final onTap = root.arguments['onTap'];
      expect(onTap, isA<fmt.SetStateHandler>());
      final handler = onTap! as fmt.SetStateHandler;
      // The handler writes to `state.on`.
      expect((handler.stateReference as fmt.StateReference).parts, ['on']);
      // The value is a switch on `state.on` mapping true→false and
      // false→true — the no-negation flip form.
      expect(handler.value, isA<fmt.Switch>());
      final flip = handler.value as fmt.Switch;
      expect(
        (flip.input as fmt.StateReference).parts,
        ['on'],
      );
      expect(flip.outputs[true], isFalse);
      expect(flip.outputs[false], isTrue);
    });

    test(
        'a stateful counter widget emits its setState literal assignment '
        'as the canonical `set state.x = N` shape', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Box extends StatelessWidget {
  const Box({this.label});
  final String? label;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeReset',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'reset',
)
class AcmeReset extends StatefulWidget {
  const AcmeReset();
  _AcmeResetState createState() => _AcmeResetState();
}

class _AcmeResetState extends State<AcmeReset> {
  int count = 7;
  void reset() => setState(() => count = 0);
  Widget build(BuildContext context) =>
      GestureDetector(onTap: reset, child: Box(label: "reset"));
}

Object x() => AcmeReset();
''',
        catalogWith([
          _entry('GestureDetector', [
            prop('onTap', PropertyType.event),
            prop('child', PropertyType.widget),
          ]),
          _entry('Box', [prop('label', PropertyType.string)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      final reset = decoded.widgets.firstWhere((w) => w.name == 'AcmeReset');
      expect(reset.initialState!['count'], 7);
      final onTap = (reset.root as fmt.ConstructorCall).arguments['onTap'];
      expect(onTap, isA<fmt.SetStateHandler>());
      final handler = onTap! as fmt.SetStateHandler;
      expect((handler.stateReference as fmt.StateReference).parts, ['count']);
      expect(handler.value, 0);
    });

    test(
        'a stateful segmented-selector widget emits one `set state.index = '
        'N` handler per segment from its setState literal assignments',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Row extends StatelessWidget {
  const Row({this.children});
  final List<Widget>? children;
  Widget build(BuildContext context) => const Widget();
}

class Box extends StatelessWidget {
  const Box({this.label});
  final String? label;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeSegmented',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'segmented',
)
class AcmeSegmented extends StatefulWidget {
  const AcmeSegmented();
  _AcmeSegmentedState createState() => _AcmeSegmentedState();
}

class _AcmeSegmentedState extends State<AcmeSegmented> {
  int index = 0;
  void selectAt0() => setState(() => index = 0);
  void selectAt1() => setState(() => index = 1);
  void selectAt2() => setState(() => index = 2);
  Widget build(BuildContext context) => Row(
        children: [
          GestureDetector(onTap: selectAt0, child: Box(label: "0")),
          GestureDetector(onTap: selectAt1, child: Box(label: "1")),
          GestureDetector(onTap: selectAt2, child: Box(label: "2")),
        ],
      );
}

Object x() => AcmeSegmented();
''',
        catalogWith([
          _entry('GestureDetector', [
            prop('onTap', PropertyType.event),
            prop('child', PropertyType.widget),
          ]),
          _entry('Row', [prop('children', PropertyType.widgetList)]),
          _entry('Box', [prop('label', PropertyType.string)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      final segmented =
          decoded.widgets.firstWhere((w) => w.name == 'AcmeSegmented');
      expect(segmented.initialState!['index'], 0);
      final row = segmented.root as fmt.ConstructorCall;
      expect(row.name, 'Row');
      final children = row.arguments['children']! as List<dynamic>;
      expect(children, hasLength(3));
      for (var i = 0; i < 3; i++) {
        final segment = children[i] as fmt.ConstructorCall;
        expect(segment.name, 'GestureDetector');
        final handler = segment.arguments['onTap']! as fmt.SetStateHandler;
        expect(
          (handler.stateReference as fmt.StateReference).parts,
          ['index'],
        );
        expect(
          handler.value,
          i,
          reason: 'segment $i must set state.index to $i',
        );
      }
    });

    test(
        'a stateful expand-collapse widget lowers a Dart ternary on bool '
        'State to the no-`!` switch shape RFW data accepts', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Column extends StatelessWidget {
  const Column({this.children});
  final List<Widget>? children;
  Widget build(BuildContext context) => const Widget();
}

class Box extends StatelessWidget {
  const Box({this.label});
  final String? label;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeExpander',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'expander',
)
class AcmeExpander extends StatefulWidget {
  const AcmeExpander();
  _AcmeExpanderState createState() => _AcmeExpanderState();
}

class _AcmeExpanderState extends State<AcmeExpander> {
  bool expanded = false;
  void toggle() => setState(() => expanded = !expanded);
  Widget build(BuildContext context) => Column(
        children: [
          GestureDetector(onTap: toggle, child: Box(label: "header")),
          expanded ? Box(label: "body") : Box(label: ""),
        ],
      );
}

Object x() => AcmeExpander();
''',
        catalogWith([
          _entry('GestureDetector', [
            prop('onTap', PropertyType.event),
            prop('child', PropertyType.widget),
          ]),
          _entry('Column', [prop('children', PropertyType.widgetList)]),
          _entry('Box', [prop('label', PropertyType.string)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      final expander =
          decoded.widgets.firstWhere((w) => w.name == 'AcmeExpander');
      expect(expander.initialState!['expanded'], isFalse);
      final column = expander.root as fmt.ConstructorCall;
      expect(column.name, 'Column');
      final children = column.arguments['children']! as List<dynamic>;
      expect(children, hasLength(2));
      // The Dart ternary's switch shape is the canonical no-`!` form:
      // `switch state.expanded { true: …, false: … }`.
      final body = children[1];
      expect(body, isA<fmt.Switch>());
      final switchNode = body as fmt.Switch;
      expect((switchNode.input as fmt.StateReference).parts, ['expanded']);
      expect(switchNode.outputs.keys, containsAll([true, false]));
    });

    test(
        'a stateful widget with a non-foldable State initialiser produces a '
        'stateShapeUnsupported diagnostic, no blob emitted', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

int _nonConst() => 42;

@RestageWidget(
  name: 'AcmeBad',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'bad',
)
class AcmeBad extends StatefulWidget {
  const AcmeBad();
  _AcmeBadState createState() => _AcmeBadState();
}

class _AcmeBadState extends State<AcmeBad> {
  int count = _nonConst();
  void reset() => setState(() => count = 0);
  Widget build(BuildContext context) => GestureDetector(onTap: reset);
}

Object x() => AcmeBad();
''',
        catalogWith([
          _entry('GestureDetector', [prop('onTap', PropertyType.event)]),
        ]),
      );

      expect(result.decoded, isNull);
      expect(
        result.issues.any((i) => i.code == IssueCode.stateShapeUnsupported),
        isTrue,
        reason: 'a non-foldable State initialiser must diagnose '
            'stateShapeUnsupported',
      );
    });

    test(
        'a stateful widget with an unrecognised setState body produces a '
        'stateShapeUnsupported diagnostic, no blob emitted', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeWeird',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'weird',
)
class AcmeWeird extends StatefulWidget {
  const AcmeWeird();
  _AcmeWeirdState createState() => _AcmeWeirdState();
}

class _AcmeWeirdState extends State<AcmeWeird> {
  int a = 0;
  int b = 0;
  void update() => setState(() {
        a = 1;
        b = 2;
      });
  Widget build(BuildContext context) => GestureDetector(onTap: update);
}

Object x() => AcmeWeird();
''',
        catalogWith([
          _entry('GestureDetector', [prop('onTap', PropertyType.event)]),
        ]),
      );

      expect(result.decoded, isNull);
      expect(
        result.issues.any((i) => i.code == IssueCode.stateShapeUnsupported),
        isTrue,
      );
    });

    test(
        'a setState literal int RHS into a double State field coerces to '
        'a double in the emitted set handler', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeScale',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'scale',
)
class AcmeScale extends StatefulWidget {
  const AcmeScale();
  _AcmeScaleState createState() => _AcmeScaleState();
}

class _AcmeScaleState extends State<AcmeScale> {
  double scale = 0.0;
  void grow() => setState(() => scale = 1);
  Widget build(BuildContext context) => GestureDetector(onTap: grow);
}

Object x() => AcmeScale();
''',
        catalogWith([
          _entry('GestureDetector', [prop('onTap', PropertyType.event)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      final scale = decoded.widgets.firstWhere((w) => w.name == 'AcmeScale');
      // Initial value is already double-coerced — confirms the regression
      // is the setState RHS, not the initial.
      expect(scale.initialState!['scale'], 0.0);
      final handler = (scale.root as fmt.ConstructorCall).arguments['onTap']!
          as fmt.SetStateHandler;
      // The Dart int literal `1` lands as a double `1.0` so a runtime
      // `source.v<double>` read after the tap doesn't silently null out.
      // (Dart's `1 == 1.0` is `true`, so an int sneaking through compares
      // equal to a double — `isA<double>` is the strict gate.)
      expect(handler.value, isA<double>());
      expect(handler.value, 1.0);
    });

    test(
        'a non-finite overflow-literal State-field initialiser defers loud, '
        'never emitting a bare Infinity (the const-fold boundary closes it)',
        () async {
      // The declarative-state path consumes `tryFoldConstant` directly,
      // bypassing the translator's non-finite emit guard. Before the const-fold
      // `DoubleLiteral` finite filter, `1e400` folded to Infinity and was
      // emitted as the bare token `set state.scale = Infinity` — which is not a
      // representable RFW value. The filter makes it fold to null
      // (captured-but-unfoldable), so the state shape defers loud via
      // `stateShapeUnsupported` and NO blob is emitted. (The state-path keeps
      // the generic-but-loud code by design; the precise code is the
      // slot-path's, not this one's.)
      final result = await _transpile(
        '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeNonFiniteState',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'non-finite state',
)
class AcmeNonFiniteState extends StatefulWidget {
  const AcmeNonFiniteState();
  _AcmeNonFiniteStateState createState() => _AcmeNonFiniteStateState();
}

class _AcmeNonFiniteStateState extends State<AcmeNonFiniteState> {
  double scale = 1e400;
  void grow() => setState(() => scale = 1.0);
  Widget build(BuildContext context) => GestureDetector(onTap: grow);
}

Object x() => AcmeNonFiniteState();
''',
        catalogWith([
          _entry('GestureDetector', [prop('onTap', PropertyType.event)]),
        ]),
      );

      expect(
        result.decoded,
        isNull,
        reason: 'a non-finite State-field initialiser must not emit a blob '
            'carrying a bare Infinity token',
      );
      expect(
        result.issues.any((i) => i.code == IssueCode.stateShapeUnsupported),
        isTrue,
        reason:
            'a non-finite (1e400) State-field initialiser folds to null and '
            'must defer loud via stateShapeUnsupported, never a bare Infinity',
      );
    });

    test(
        'a `widget.X` method tear-off on the StatefulWidget side surfaces a '
        'stateShapeUnsupported diagnostic, no blob emitted', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeMixed',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'mixed',
)
class AcmeMixed extends StatefulWidget {
  const AcmeMixed();
  void tap() {}
  _AcmeMixedState createState() => _AcmeMixedState();
}

class _AcmeMixedState extends State<AcmeMixed> {
  bool on = false;
  Widget build(BuildContext context) => GestureDetector(onTap: widget.tap);
}

Object x() => AcmeMixed();
''',
        catalogWith([
          _entry('GestureDetector', [prop('onTap', PropertyType.event)]),
        ]),
      );

      expect(result.decoded, isNull);
      expect(
        result.issues.any((i) => i.code == IssueCode.stateShapeUnsupported),
        isTrue,
        reason: 'a method tear-off on the StatefulWidget side is not a '
            'setState handler — must diagnose stateShapeUnsupported',
      );
    });

    test(
        'a State method that both mutates state and invokes a callback defers '
        'with stateShapeUnsupported', () async {
      // A multi-statement handler cannot lower as a single state update.
      final result = await _transpile(
        '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

void Function() notifySelection({String? choice}) => () {};

@RestageWidget(
  name: 'AcmeSelectAndBuy',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'select and buy',
)
class AcmeSelectAndBuy extends StatefulWidget {
  const AcmeSelectAndBuy();
  _AcmeSelectAndBuyState createState() => _AcmeSelectAndBuyState();
}

class _AcmeSelectAndBuyState extends State<AcmeSelectAndBuy> {
  bool annual = true;
  void selectAndBuy() {
    setState(() => annual = !annual);
    notifySelection(choice: annual ? 'annual' : 'monthly')();
  }
  Widget build(BuildContext context) =>
      GestureDetector(onTap: selectAndBuy);
}

Object x() => AcmeSelectAndBuy();
''',
        catalogWith([
          _entry('GestureDetector', [prop('onTap', PropertyType.event)]),
        ]),
      );

      expect(
        result.decoded,
        isNull,
        reason: 'a combined state-and-callback handler must not emit a blob',
      );
      expect(
        result.issues.any((i) => i.code == IssueCode.stateShapeUnsupported),
        isTrue,
        reason: 'the combined body is not a single setState and must defer',
      );
    });

    test(
        'a stateless widget with a method tear-off as an event handler is '
        'not inlinable — surfaces as an imperative-widget diagnostic',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeButton',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'button',
)
class AcmeButton extends StatelessWidget {
  const AcmeButton();
  void handleTap() {}
  Widget build(BuildContext context) => GestureDetector(onTap: handleTap);
}

Object x() => AcmeButton();
''',
        catalogWith([
          _entry('GestureDetector', [prop('onTap', PropertyType.event)]),
        ]),
      );

      expect(result.decoded, isNull);
      // The diagnostic must fire at the classification gate — the
      // alternative ("unrecognized expression" from the bare-identifier
      // fallback in the translator) would be a leak of the
      // false-inlineable-classification invariant.
      final relevant = result.issues.where(
        (i) =>
            i.code == IssueCode.customWidgetUnclassified ||
            i.code == IssueCode.customWidgetImperative ||
            i.code == IssueCode.stateShapeUnsupported,
      );
      expect(
        relevant,
        isNotEmpty,
        reason: 'a stateless widget composing a Dart method tear-off must '
            'be rejected at the classification boundary, not at the '
            'identifier-fallback path',
      );
      expect(
        result.issues.any((i) => i.code == IssueCode.unrecognizedMethodCall),
        isFalse,
        reason: 'the fallback "Unsupported expression" path indicates the '
            'widget reached body translation — the gate failed',
      );
    });

    test('an omitted parameter emits its constructor default', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Box extends StatelessWidget {
  const Box({this.width});
  final double? width;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeBox',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'box',
)
class AcmeBox extends StatelessWidget {
  const AcmeBox({this.gap = 8});
  final double? gap;
  Widget build(BuildContext context) => Box(width: gap);
}

Object x() => AcmeBox();
''',
        catalogWith([
          _entry('Box', [prop('width', PropertyType.real)]),
        ]),
      );

      expect(result.issues, isEmpty);
      // The call omits `gap`; the constructor default (8) is emitted so the
      // inlined widget renders with the value the Dart widget would.
      expect(_widget(result.decoded!, 'Paywall').arguments['gap'], 8.0);
    });
  });

  // A REGISTERED custom widget (one present in the merged catalog, as it is
  // once its package emits catalog.json) keeps its inline-vs-reference choice by
  // class: an inlineable widget still inlines — its composition travels
  // in the blob and renders with no runtime factory; an imperative widget
  // widget references the catalog entry, resolved by the runtime factory.
  group('registered custom widget — inlineable inlines, app-backed references',
      () {
    Catalog catalogWithCustom(List<WidgetEntry> widgets) => Catalog(
          schemaVersion: kSupportedSchemaVersion,
          generatedAt: '1970-01-01T00:00:00Z',
          libraries: {
            WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
            WidgetLibrary.custom('acme.ds'):
                const LibraryInfo(version: '0.1.0'),
          },
          widgets: widgets,
        );

    WidgetEntry customEntry(
      String name,
      List<PropertyEntry> properties, {
      String rootPackage = 'restage_codegen',
    }) =>
        entry(
          name: name,
          properties: properties,
          library: WidgetLibrary.custom('acme.ds'),
          category: WidgetCategory.decoration,
          flutterType: 'package:$rootPackage/_e2e_probe.dart#$name',
        );

    test('a registered inlineable custom widget emits a definition', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(name: 'InlineBadge',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration, description: 'b')
class InlineBadge extends StatelessWidget {
  const InlineBadge({this.label});
  final String? label;
  Widget build(BuildContext context) => Text(label); // pure composition
}

Object x() => InlineBadge(label: "Pro");
''',
        catalogWithCustom([
          _entry('Text', [prop('text', PropertyType.string, positional: true)]),
          customEntry('InlineBadge', [prop('label', PropertyType.string)]),
        ]),
      );

      expect(result.issues, isEmpty);
      final decoded = result.decoded!;
      // The widget is inlined: its definition body travels in the blob.
      expect(
        decoded.widgets.map((w) => w.name),
        containsAll(['InlineBadge', 'Paywall']),
      );
      expect(_widget(decoded, 'InlineBadge').name, 'Text');
      expect(_widget(decoded, 'Paywall').name, 'InlineBadge');
    });

    test('registered inline calls use exact catalog property types', () async {
      final result = await _transpile(
        '''
$kFlutterClassifierStubs

class Pair extends StatelessWidget {
  const Pair({this.first, this.second, super.key});
  final Widget? first;
  final Widget? second;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class Cell extends StatelessWidget {
  const Cell({this.color, this.size, super.key});
  final Color? color;
  final double? size;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(name: 'DayTile',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration, description: 'day')
class DayTile extends StatelessWidget {
  const DayTile({required this.color, this.size = 20, super.key});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Cell(color: color, size: size);
}

Object x(BuildContext context) => Pair(
  first: const DayTile(color: Color(0xFF112233)),
  second: DayTile(color: Theme.of(context).colorScheme.primary),
);
''',
        catalogWithCustom([
          _entry(
            'Pair',
            [
              prop('first', PropertyType.widget),
              prop('second', PropertyType.widget),
            ],
            rootPackage: 'apps_examples',
          ),
          _entry(
            'Cell',
            [
              prop('color', PropertyType.color),
              prop('size', PropertyType.real),
            ],
            rootPackage: 'apps_examples',
          ),
          customEntry(
            'DayTile',
            [
              prop('color', PropertyType.color, required: true),
              prop('size', PropertyType.real),
            ],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(result.translation.widgetDefinitions.keys, contains('DayTile'));
      expect(
        result.translation.widgetDefinitions.keys
            .where((name) => name == 'DayTile'),
        hasLength(1),
      );
      expect(result.translation.referencedCustomLibraries, isEmpty);
      final root = _widget(result.decoded!, 'Paywall');
      final literal = root.arguments['first']! as fmt.ConstructorCall;
      final themed = root.arguments['second']! as fmt.ConstructorCall;
      expect(literal.name, 'DayTile');
      expect(themed.name, 'DayTile');
      expect(literal.arguments['color'], 0xFF112233);
      final themedColor = themed.arguments['color'];
      expect(themedColor, isA<fmt.DataReference>());
      expect(
        (themedColor! as fmt.DataReference).parts,
        ['theme', 'colorScheme', 'primary'],
      );
      expect(literal.arguments['size'], 20.0);
      expect(themed.arguments['size'], 20.0);
    });

    test('registered call fallback applies to every matching occurrence',
        () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Pair extends StatelessWidget {
  const Pair({this.first, this.second});
  final Widget? first;
  final Widget? second;
  Widget build(BuildContext context) => const Widget();
}

class MapSink extends StatelessWidget {
  const MapSink({this.values});
  final Map<String, String>? values;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(name: 'InlinePanel',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration, description: 'panel')
class InlinePanel extends StatelessWidget {
  const InlinePanel({this.values});
  final Map<String, String>? values;
  Widget build(BuildContext context) => MapSink(values: values);
}

Object x() => Pair(
  first: InlinePanel(),
  second: InlinePanel(values: const {'a': 'b'}),
);
''',
        catalogWithCustom([
          _entry('Pair', [
            prop('first', PropertyType.widget),
            prop('second', PropertyType.widget),
          ]),
          _entry('MapSink', [prop('values', PropertyType.unknown)]),
          customEntry(
            'InlinePanel',
            [prop('values', PropertyType.unknown)],
          ),
        ]),
      );

      expect(
        result.issues.where((issue) => !issue.code.isBuildNotice),
        isEmpty,
        reason: result.issues.join('\n'),
      );
      final notice = result.issues.singleWhere(
        (issue) => issue.code == IssueCode.customWidgetAppFactoryUsed,
      );
      expect(notice.code.isBuildNotice, isTrue);
      expect(notice.location, contains('#InlinePanel'));
      expect(notice.message, contains("Custom widget 'InlinePanel'"));
      expect(notice.message, contains("registered 'acme.ds' app factory"));
      expect(notice.message, contains('Local RFW output was unavailable:'));
      expect(notice.message, contains("installed app's compiled widget body"));
      expect(notice.message, contains('defaults remain authoritative'));
      expect(notice.message, contains('requires an app release'));
      expect(notice.message, contains('Explicit call values remain supplied'));
      expect(
        result.translation.widgetDefinitions.keys,
        isNot(contains('InlinePanel')),
      );
      expect(result.translation.referencedCustomLibraries, {'acme.ds'});
      final root = _widget(result.decoded!, 'Paywall');
      final first = root.arguments['first']! as fmt.ConstructorCall;
      final second = root.arguments['second']! as fmt.ConstructorCall;
      expect(first.name, 'InlinePanel');
      expect(first.arguments, isEmpty);
      expect(second.name, 'InlinePanel');
      expect(second.arguments['values'], {'a': 'b'});
    });

    test(
        'an app-backed custom widget is referenced (no inline definition, '
        'no customWidgetUnclassified)', () async {
      final result = await _transpile(
        '''
$kClassifierStubs

class Box extends StatelessWidget {
  const Box({this.width});
  final double? width;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(name: 'AppBackedBadge',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration, description: 'b')
class AppBackedBadge extends StatelessWidget {
  const AppBackedBadge({this.label, this.count});
  final String? label;
  final int? count;
  // Runtime arithmetic on a constructor arg is not blob-expressible.
  Widget build(BuildContext context) => Box(width: count! * 2.0);
}

Object x() => AppBackedBadge(label: "Pro", count: 3);
''',
        catalogWithCustom([
          _entry('Box', [prop('width', PropertyType.real)]),
          customEntry('AppBackedBadge', [
            prop('label', PropertyType.string),
            prop('count', PropertyType.integer),
          ]),
        ]),
      );

      expect(
        result.issues
            .where((i) => i.code == IssueCode.customWidgetUnclassified),
        isEmpty,
      );
      final decoded = result.decoded!;
      // The paywall references AppBackedBadge; no local definition is emitted.
      expect(_widget(decoded, 'Paywall').name, 'AppBackedBadge');
      expect(
        decoded.widgets.map((w) => w.name),
        isNot(contains('AppBackedBadge')),
      );
    });

    test(
        'an app-backed custom widget named like a surface root fails loud '
        '(never a silent self-reference)', () async {
      // A registered custom widget whose name is the reserved paywall root
      // name would emit `Paywall(...)` into the blob, which name-resolution
      // binds to the surface root itself (self-recursion). The reference path
      // must diagnose it, not emit an admitted-but-wrong reference. Referenced
      // as a child (a root custom widget would inline instead) and imperative (so it
      // takes the reference path, not the inline path).
      final result = await _transpile(
        '''
$kClassifierStubs

class Box extends StatelessWidget {
  const Box({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Uncatalogued extends StatelessWidget {
  const Uncatalogued();
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(name: 'Paywall',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration, description: 'b')
class AcmeReserved extends StatelessWidget {
  const AcmeReserved();
  // Composes a non-catalog widget, so it takes the reference path.
  Widget build(BuildContext context) => Uncatalogued();
}

Object x() => Box(child: AcmeReserved());
''',
        catalogWithCustom([
          _entry('Box', [prop('child', PropertyType.widget)]),
          entry(
            name: 'Paywall',
            properties: const [],
            library: WidgetLibrary.custom('acme.ds'),
            category: WidgetCategory.decoration,
            flutterType: 'package:restage_codegen/_e2e_probe.dart#AcmeReserved',
          ),
        ]),
      );

      expect(result.decoded, isNull);
      expect(
        result.issues.any((i) => i.code == IssueCode.customWidgetNameCollision),
        isTrue,
      );
    });
  });
}

String _constStopsFixture({
  required String memberSource,
  required String buildSource,
}) =>
    '''
$kFlutterClassifierStubs

const List<double> kStops = [0, 1];
const List<Color> kColors = [Color(0xFF000000), Color(0xFFFFFFFF)];

class Box extends StatelessWidget {
  const Box({this.gradient, super.key});
  final Gradient? gradient;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeGradient',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration,
  description: 'gradient',
)
class AcmeGradient extends StatelessWidget {
  const AcmeGradient({super.key});
$memberSource
$buildSource
}

Object x() => const AcmeGradient();
''';

Catalog _gradientBoxCatalog() => catalogWith([
      _entry(
        'Box',
        [prop('gradient', PropertyType.gradient)],
        rootPackage: 'apps_examples',
      ),
    ]);

Catalog _listDecoderCatalog(List<_ListDecoderCase> cases) => catalogWith([
      _entry(
        'ListDecoderSink',
        [
          for (final entry in cases) prop(entry.property, entry.decoder),
        ],
        rootPackage: 'apps_examples',
      ),
    ]);

Catalog _declaredListCatalog() => catalogWith([
      entry(
        name: 'SizedBox',
        properties: const [],
        flutterType: 'package:flutter/src/widgets/basic.dart#SizedBox',
      ),
    ]);

String _listDecoderFixture(
  List<_ListDecoderCase> cases,
  String Function(_ListDecoderCase) itemType, {
  bool declareLookalikes = false,
}) {
  final declarations = declareLookalikes
      ? cases.map((entry) => 'class ${entry.lookalikeType} {}').join('\n')
      : '';
  final sinkParameters =
      cases.map((entry) => 'this.${entry.property},').join('\n');
  final sinkFields =
      cases.map((entry) => 'final Object? ${entry.property};').join('\n');
  final valueParameters = cases
      .expand(
        (entry) => [
          'required this.${entry.property},',
          'required this.${entry.property}Alternate,',
        ],
      )
      .join('\n');
  final valueFields = cases.expand((entry) {
    final type = itemType(entry);
    return [
      'final List<$type> ${entry.property};',
      'final List<$type> ${entry.property}Alternate;',
    ];
  }).join('\n');
  final localValues = cases
      .map(
        (entry) => 'final ${entry.property}Value = flag ? ${entry.property} : '
            '${entry.property}Alternate;',
      )
      .join('\n');
  final sinkArguments = cases
      .map((entry) => '${entry.property}: ${entry.property}Value,')
      .join('\n');
  final rootArguments = cases.expand((entry) {
    final type = itemType(entry);
    return [
      '${entry.property}: const <$type>[],',
      '${entry.property}Alternate: const <$type>[],',
    ];
  }).join('\n');

  return '''
import 'package:flutter/material.dart' as ui;
import 'package:restage_core/restage_core.dart' as core;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

$declarations

class ListDecoderSink extends ui.StatelessWidget {
  const ListDecoderSink({$sinkParameters});
  $sinkFields

  @override
  ui.Widget build(ui.BuildContext context) => const ui.SizedBox();
}

@RestageWidget(
  name: 'TypedListValues',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'typed list values',
)
class TypedListValues extends ui.StatelessWidget {
  const TypedListValues({
    required this.flag,
    $valueParameters
  });

  final bool flag;
  $valueFields

  @override
  ui.Widget build(ui.BuildContext context) {
    $localValues
    return ListDecoderSink($sinkArguments);
  }
}

Object x() => TypedListValues(
  flag: true,
  $rootArguments
);
''';
}

String _declaredListFixture(String itemType, {bool declareType = false}) => '''
import 'package:flutter/material.dart' as ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

${declareType ? 'class $itemType {}' : ''}

@RestageWidget(
  name: 'DeclaredListValue',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'declared list value',
)
class DeclaredListValue extends ui.StatelessWidget {
  const DeclaredListValue({required this.values});
  final List<$itemType> values;

  @override
  ui.Widget build(ui.BuildContext context) => const ui.SizedBox();
}

Object x() => DeclaredListValue(
  values: true ? const <$itemType>[] : const <$itemType>[],
);
''';

String _indirectColorListFixture({
  required String gradient,
  required String alternateType,
  required String helperType,
}) {
  final alternateValue = alternateType == 'Color'
      ? 'const [Color(0xFF111111), Color(0xFFEEEEEE)]'
      : 'const <double>[0.0, 1.0]';
  return '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.gradient, super.key});
  final Gradient? gradient;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeGradient',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration,
  description: 'gradient',
)
class AcmeGradient extends StatelessWidget {
  const AcmeGradient({
    required this.flag,
    required this.colors,
    required this.alternate,
    super.key,
  });
  final bool flag;
  final List<Color> colors;
  final List<$alternateType> alternate;

  List<$helperType> selected() => flag ? colors : alternate;

  @override
  Widget build(BuildContext context) {
    final selectedColors = selected();
    return Box(
      gradient: $gradient(colors: selectedColors),
    );
  }
}

Object x() => AcmeGradient(
  flag: true,
  colors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
  alternate: $alternateValue,
);
''';
}

Future<void> _expectNestedGradientChildRefusal(
  String gradient, {
  IssueCode code = IssueCode.unresolvedIdentifier,
}) async {
  final result = await _transpile(
    _constStopsFixture(
      memberSource: '',
      buildSource: '''
  Widget build(BuildContext context) => Box(gradient: $gradient);
''',
    ),
    _gradientBoxCatalog(),
    rootPackage: 'apps_examples',
  );
  final definition = result.translation.widgetDefinitions['AcmeGradient'];
  expect(definition, isEmpty);
  expect(result.decoded, isNull);
  expect(result.issues.map((issue) => issue.code), [
    code,
  ]);
  expect(result.issues.single.location, isNotEmpty);
}

/// The root [fmt.ConstructorCall] of the widget named [name] in [library].
fmt.ConstructorCall _widget(fmt.RemoteWidgetLibrary library, String name) =>
    library.widgets.firstWhere((w) => w.name == name).root
        as fmt.ConstructorCall;

/// A catalog [WidgetEntry] for a stub widget [name] mounted in the e2e
/// probe source. The `flutterType` defaults to the probe URI under
/// `package:restage_codegen/...`; pass [rootPackage]`: 'apps_examples'`
/// for fixtures that need real `package:flutter/` resolution.
WidgetEntry _entry(
  String name,
  List<PropertyEntry> properties, {
  String rootPackage = 'restage_codegen',
}) =>
    entry(
      name: name,
      properties: properties,
      flutterType: 'package:$rootPackage/_e2e_probe.dart#$name',
    );

/// Transpiles [source] (which defines the custom widgets and a paywall
/// root `Object x() => <root>;`) through the full transpile chain against
/// [catalog]. Pass [rootPackage]`: 'apps_examples'` for fixtures that
/// need real `package:flutter/material.dart` resolution (the strict
/// theme-read recognizer requires a `package:flutter/` library URI).
Future<_TranspileResult> _transpile(
  String source,
  Catalog catalog, {
  String rootPackage = 'restage_codegen',
  Iterable<HelperDefinition> extraHelpers = const [],
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: rootPackage,
  );
  final assetKey = '$rootPackage|lib/_e2e_probe.dart';
  readerWriter.testing.writeString(AssetId.parse(assetKey), source);

  _TranspileResult? result;
  await testBuilder(
    _TranspileProbeBuilder(
      catalog,
      (r) => result = r,
      extraHelpers: extraHelpers,
    ),
    {assetKey: source},
    rootPackage: rootPackage,
    readerWriter: readerWriter,
    resolvers: sharedResolvers,
  );
  final resolved = result;
  if (resolved == null) {
    throw StateError('the transpile probe did not run');
  }
  return resolved;
}

/// Builder that runs the full transpile chain over the e2e probe library.
class _TranspileProbeBuilder implements Builder {
  _TranspileProbeBuilder(
    this.catalog,
    this.onResult, {
    this.extraHelpers = const [],
  });

  final Catalog catalog;
  final void Function(_TranspileResult) onResult;
  final Iterable<HelperDefinition> extraHelpers;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.e2e'],
      };

  @override
  Future<void> build(BuildStep step) async {
    if (!step.inputId.path.endsWith('_e2e_probe.dart')) return;
    final library = await step.inputLibrary;
    final fn = library.topLevelFunctions.firstWhere((f) => f.name == 'x');
    final resolvedLib =
        await library.session.getResolvedLibraryByElement(library);
    if (resolvedLib is! ResolvedLibraryResult) {
      throw StateError('e2e probe: library did not resolve');
    }
    final node = resolvedLib.getFragmentDeclaration(fn.firstFragment)?.node;
    final body =
        node is FunctionDeclaration ? node.functionExpression.body : null;
    if (body is! ExpressionFunctionBody) {
      throw StateError('e2e probe: `x` must be `Object x() => <root>;`');
    }
    final root = body.expression;

    final helpers = HelperRegistry()
      ..registerAll(paywallHelpers)
      ..registerAll(extraHelpers);
    final classification = await classifyReferencedCustomWidgets(
      rootExpressions: [root],
      catalog: catalog,
      helpers: helpers,
      astNodeFor: (fragment) =>
          step.resolver.astNodeFor(fragment, resolve: true),
    );
    final translator = ExpressionTranslator(
      catalog: catalog,
      helpers: helpers,
      customWidgetClassifications: classification.classifications,
      customWidgetBlueprints: classification.blueprints,
    );
    final translation = translator.translate(root);
    if (translation.issues.any((issue) => !issue.code.isBuildNotice)) {
      onResult(
        _TranspileResult(
          translation.issues,
          null,
          translation,
          classification,
        ),
      );
      return;
    }

    final text = emitPaywallLibrary(
      translation.dsl,
      widgetDefinitions: translation.widgetDefinitions,
      widgetDefinitionStates: translation.widgetDefinitionStates,
    );
    try {
      final parsed = fmt.parseLibraryFile(text, sourceIdentifier: 'e2e');
      final validation = validateModelAgainstCatalog(parsed, catalog);
      if (validation.isNotEmpty) {
        onResult(
          _TranspileResult(
            [...translation.issues, ...validation],
            null,
            translation,
            classification,
          ),
        );
        return;
      }
      final bytes = fmt.encodeLibraryBlob(parsed);
      final decoded = fmt.decodeLibraryBlob(Uint8List.fromList(bytes));
      onResult(
        _TranspileResult(
          translation.issues,
          decoded,
          translation,
          classification,
        ),
      );
    } on fmt.ParserException catch (e) {
      onResult(
        _TranspileResult(
          [
            Issue(
              code: IssueCode.malformedTranslatorOutput,
              message: 'emitted DSL failed to parse: $e',
              location: 'e2e',
            ),
          ],
          null,
          translation,
          classification,
        ),
      );
    }
  }
}

/// Every field a published theme style carries — the set a whole-style read
/// expands to. Pinned literally so a contract change shows up here.
const List<String> _publishedStyleFields = [
  'color',
  'backgroundColor',
  'fontFamily',
  'fontFamilyFallback',
  'fontSize',
  'fontWeight',
  'fontStyle',
  'letterSpacing',
  'wordSpacing',
  'height',
  'leadingDistribution',
  'textBaseline',
  'overflow',
  'decoration',
  'decorationColor',
  'decorationStyle',
  'decorationThickness',
];

/// A catalog whose `Label` widget decomposes a `style:` argument into one flat
/// property per published style field, as the shipped `Text` entry does.
Catalog _styleDecomposeCatalog() {
  final styleRef = WireIdRef(library: 'restage.core', wireId: WireId('s8100'));
  final ctorRef = WireIdRef(library: 'restage.core', wireId: WireId('v8100'));
  final textProp = WireId('p8101');
  final colorProp = WireId('p8102');
  final fontSizeProp = WireId('p8103');
  final fontWeightProp = WireId('p8104');
  final letterSpacingProp = WireId('p8105');
  final heightProp = WireId('p8106');
  final fontFamilyProp = WireId('p8107');
  final fontStyleProp = WireId('p8108');
  final backgroundColorProp = WireId('p8109');
  final fontFamilyFallbackProp = WireId('p8110');
  final wordSpacingProp = WireId('p8111');
  final leadingDistributionProp = WireId('p8112');
  final textBaselineProp = WireId('p8113');
  final overflowProp = WireId('p8114');
  final decorationProp = WireId('p8115');
  final decorationColorProp = WireId('p8116');
  final decorationStyleProp = WireId('p8117');
  final decorationThicknessProp = WireId('p8118');
  final colorField = WireId('p8202');
  final fontSizeField = WireId('p8203');
  final fontWeightField = WireId('p8204');
  final letterSpacingField = WireId('p8205');
  final heightField = WireId('p8206');
  final fontFamilyField = WireId('p8207');
  final fontStyleField = WireId('p8208');
  final backgroundColorField = WireId('p8209');
  final fontFamilyFallbackField = WireId('p8210');
  final wordSpacingField = WireId('p8211');
  final leadingDistributionField = WireId('p8212');
  final textBaselineField = WireId('p8213');
  final overflowField = WireId('p8214');
  final decorationField = WireId('p8215');
  final decorationColorField = WireId('p8216');
  final decorationStyleField = WireId('p8217');
  final decorationThicknessField = WireId('p8218');

  PropertyEntry property(WireId wireId, String name, PropertyType type) =>
      PropertyEntry(
        wireId: wireId,
        name: name,
        type: type,
        description: '',
      );
  StructuredField field(WireId wireId, String name, PropertyType type) =>
      StructuredField(
        wireId: wireId,
        name: name,
        type: type,
        description: '',
      );
  PropertyEntry enumProperty(WireId wireId, String name, String symbol) =>
      PropertyEntry(
        wireId: wireId,
        name: name,
        type: PropertyType.enumValue,
        description: '',
        valueShape: EnumShape(
          propertyType: PropertyType.enumValue,
          enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: symbol),
        ),
      );
  DecompositionFieldMapping mapping(WireId fieldRef, WireId propertyRef) =>
      DecompositionFieldMapping(
        fieldRef: fieldRef,
        propertyRef: propertyRef,
        transform: const IdentityTransform(),
      );

  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {WidgetLibrary.core: const LibraryInfo(version: '0.1.0')},
    widgets: [
      WidgetEntry(
        wireId: WireId('w8100'),
        name: 'Label',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:apps_examples/_e2e_probe.dart#Label',
        childrenSlot: ChildrenSlot.none,
        properties: [
          property(textProp, 'text', PropertyType.string),
          property(colorProp, 'color', PropertyType.color),
          property(fontSizeProp, 'fontSize', PropertyType.length),
          property(fontWeightProp, 'fontWeight', PropertyType.fontWeight),
          property(letterSpacingProp, 'letterSpacing', PropertyType.length),
          property(heightProp, 'height', PropertyType.length),
          property(fontFamilyProp, 'fontFamily', PropertyType.string),
          enumProperty(fontStyleProp, 'fontStyle', 'FontStyle'),
          property(backgroundColorProp, 'backgroundColor', PropertyType.color),
          property(
            fontFamilyFallbackProp,
            'fontFamilyFallback',
            PropertyType.stringList,
          ),
          property(wordSpacingProp, 'wordSpacing', PropertyType.length),
          enumProperty(
            leadingDistributionProp,
            'leadingDistribution',
            'TextLeadingDistribution',
          ),
          enumProperty(textBaselineProp, 'textBaseline', 'TextBaseline'),
          enumProperty(overflowProp, 'overflow', 'TextOverflow'),
          property(decorationProp, 'decoration', PropertyType.textDecoration),
          property(decorationColorProp, 'decorationColor', PropertyType.color),
          enumProperty(
            decorationStyleProp,
            'decorationStyle',
            'TextDecorationStyle',
          ),
          property(
            decorationThicknessProp,
            'decorationThickness',
            PropertyType.length,
          ),
        ],
        decomposes: [
          DecompositionRecipe(
            structuredRef: styleRef,
            flatProperties: const {},
            targetArg: 'style',
            construction: FactoryInvocation(
              variantRef: ctorRef,
              receiver: const ResultStructuredTypeReceiver(),
            ),
            fieldMappings: [
              mapping(colorField, colorProp),
              mapping(fontSizeField, fontSizeProp),
              mapping(fontWeightField, fontWeightProp),
              mapping(letterSpacingField, letterSpacingProp),
              mapping(heightField, heightProp),
              mapping(fontFamilyField, fontFamilyProp),
              mapping(fontStyleField, fontStyleProp),
              mapping(backgroundColorField, backgroundColorProp),
              mapping(fontFamilyFallbackField, fontFamilyFallbackProp),
              mapping(wordSpacingField, wordSpacingProp),
              mapping(leadingDistributionField, leadingDistributionProp),
              mapping(textBaselineField, textBaselineProp),
              mapping(overflowField, overflowProp),
              mapping(decorationField, decorationProp),
              mapping(decorationColorField, decorationColorProp),
              mapping(decorationStyleField, decorationStyleProp),
              mapping(decorationThicknessField, decorationThicknessProp),
            ],
          ),
        ],
      ),
    ],
    structuredTypes: [
      StructuredEntry(
        wireId: styleRef.wireId,
        name: 'TextStyle',
        library: WidgetLibrary.core,
        description: '',
        sourceType: 'package:flutter/src/painting/text_style.dart#TextStyle',
        fields: [
          field(colorField, 'color', PropertyType.color),
          field(fontSizeField, 'fontSize', PropertyType.length),
          field(fontWeightField, 'fontWeight', PropertyType.fontWeight),
          field(letterSpacingField, 'letterSpacing', PropertyType.length),
          field(heightField, 'height', PropertyType.length),
          field(fontFamilyField, 'fontFamily', PropertyType.string),
          field(fontStyleField, 'fontStyle', PropertyType.enumValue),
          field(backgroundColorField, 'backgroundColor', PropertyType.color),
          field(
            fontFamilyFallbackField,
            'fontFamilyFallback',
            PropertyType.stringList,
          ),
          field(wordSpacingField, 'wordSpacing', PropertyType.length),
          field(
            leadingDistributionField,
            'leadingDistribution',
            PropertyType.enumValue,
          ),
          field(textBaselineField, 'textBaseline', PropertyType.enumValue),
          field(overflowField, 'overflow', PropertyType.enumValue),
          field(decorationField, 'decoration', PropertyType.textDecoration),
          field(decorationColorField, 'decorationColor', PropertyType.color),
          field(
            decorationStyleField,
            'decorationStyle',
            PropertyType.enumValue,
          ),
          field(
            decorationThicknessField,
            'decorationThickness',
            PropertyType.length,
          ),
        ],
        variants: [
          ConstructorVariant(
            wireId: ctorRef.wireId,
            argMappings: {
              'color': ArgMapping(targetFields: [colorField]),
              'fontSize': ArgMapping(targetFields: [fontSizeField]),
              'fontWeight': ArgMapping(targetFields: [fontWeightField]),
              'letterSpacing': ArgMapping(targetFields: [letterSpacingField]),
              'height': ArgMapping(targetFields: [heightField]),
              'fontFamily': ArgMapping(targetFields: [fontFamilyField]),
              'fontStyle': ArgMapping(targetFields: [fontStyleField]),
              'backgroundColor':
                  ArgMapping(targetFields: [backgroundColorField]),
              'fontFamilyFallback':
                  ArgMapping(targetFields: [fontFamilyFallbackField]),
              'wordSpacing': ArgMapping(targetFields: [wordSpacingField]),
              'leadingDistribution':
                  ArgMapping(targetFields: [leadingDistributionField]),
              'textBaseline': ArgMapping(targetFields: [textBaselineField]),
              'overflow': ArgMapping(targetFields: [overflowField]),
              'decoration': ArgMapping(targetFields: [decorationField]),
              'decorationColor':
                  ArgMapping(targetFields: [decorationColorField]),
              'decorationStyle':
                  ArgMapping(targetFields: [decorationStyleField]),
              'decorationThickness':
                  ArgMapping(targetFields: [decorationThicknessField]),
            },
            parameters: const [],
          ),
        ],
      ),
    ],
  );
}
