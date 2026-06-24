// A2 — reconcile the inlining classifier's value vocabulary to the
// translator's. The classifier used to reject, inside an inlined custom
// widget, structured-value constructions / framework factory invocations /
// named constants that the shared ExpressionTranslator already lowers in a
// paywall body. These tests pin the reconciliation: the classifier recognises
// the same value vocabulary, so such a widget classifies ComposableWidget
// (and inlines) instead of falling out as Unclassifiable / Imperative.
//
// Recognition is name-based and deliberately over-broad in the SAFE direction:
// a value type the classifier recognises but the translator cannot lower
// produces a translator diagnostic (deferred), backstopped by the catalog
// value-type floor — never a silent wrong blob.

import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/translator_recipes.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A catalog advertising the [structured] decompose-able types plus stub
/// `Container` / `Text` / `Icon` widgets whose `flutterType` matches the
/// `<library URI>#<Class>` the classifier derives for the fixture file.
Catalog _a2Catalog({
  required String file,
  List<String> structured = const [],
}) =>
    catalogWith(
      [
        entry(
          name: 'Container',
          properties: [
            prop('child', PropertyType.widget),
            prop('color', PropertyType.color),
            prop('padding', PropertyType.edgeInsets),
            prop('decoration', PropertyType.structured),
            prop('width', PropertyType.real),
          ],
          flutterType: 'package:apps_examples/$file#Container',
        ),
        entry(
          name: 'Text',
          properties: [
            prop('text', PropertyType.string, positional: true),
            prop('style', PropertyType.structured),
          ],
          flutterType: 'package:apps_examples/$file#Text',
        ),
        entry(
          name: 'Icon',
          properties: [prop('icon', PropertyType.integer, positional: true)],
          flutterType: 'package:apps_examples/$file#Icon',
        ),
      ],
      structuredTypes: [for (final name in structured) structuredEntry(name)],
    );

void main() {
  group('A2 — mechanism 1: structured-value constructions', () {
    test('a TextStyle construction (catalog structuredType) is Composable',
        () async {
      final result = await classifyFixture(
        {
          'lib/styled.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class TextStyle {
  const TextStyle({this.fontSize});
  final double? fontSize;
}

class Text extends StatelessWidget {
  const Text(this.data, {this.style});
  final String? data;
  final TextStyle? style;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'StyledLabel',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'styled label',
)
class StyledLabel extends StatelessWidget {
  const StyledLabel({this.label});
  final String? label;
  Widget build(BuildContext context) =>
      Text(label, style: TextStyle(fontSize: 18));
}
''',
        },
        inputPath: 'lib/styled.dart',
        widgetName: 'StyledLabel',
        catalog: _a2Catalog(file: 'styled.dart', structured: ['TextStyle']),
      );

      expect(result, isA<ComposableWidget>());
    });

    test(
        'nested BoxDecoration + BorderRadius.circular named-ctor constructions '
        'are Composable', () async {
      final result = await classifyFixture(
        {
          'lib/decorated.dart': '''
$kClassifierStubs

class BorderRadius {
  const BorderRadius.circular(this.radius);
  final double radius;
}

class BoxDecoration {
  const BoxDecoration({this.borderRadius});
  final BorderRadius? borderRadius;
}

class Container extends StatelessWidget {
  const Container({this.decoration});
  final BoxDecoration? decoration;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'RoundedBox',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'rounded box',
)
class RoundedBox extends StatelessWidget {
  const RoundedBox();
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      );
}
''',
        },
        inputPath: 'lib/decorated.dart',
        widgetName: 'RoundedBox',
        catalog: _a2Catalog(
          file: 'decorated.dart',
          structured: ['BoxDecoration', 'BorderRadius'],
        ),
      );

      expect(result, isA<ComposableWidget>());
    });

    test('an EdgeInsets.all named-ctor (residual value type) is Composable',
        () async {
      final result = await classifyFixture(
        {
          'lib/padded.dart': '''
$kClassifierStubs

class EdgeInsets {
  const EdgeInsets.all(this.value);
  final double value;
}

class Container extends StatelessWidget {
  const Container({this.padding});
  final EdgeInsets? padding;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'PaddedBox',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'padded box',
)
class PaddedBox extends StatelessWidget {
  const PaddedBox();
  Widget build(BuildContext context) =>
      Container(padding: EdgeInsets.all(8));
}
''',
        },
        inputPath: 'lib/padded.dart',
        widgetName: 'PaddedBox',
        catalog: _a2Catalog(file: 'padded.dart'),
      );

      expect(result, isA<ComposableWidget>());
    });
  });

  group('A2 — structured-value factory constructors (construction path)', () {
    test('a Border.all factory constructor is Composable', () async {
      // `Border.all(...)` is a *factory constructor* (not a static method), so
      // it parses as InstanceCreationExpression and is recognised via the
      // construction path (`Border` ∈ the value-type set). Real Flutter's
      // EdgeInsets.all / BorderRadius.circular / Color.fromARGB are likewise
      // named/factory constructors handled the same way.
      final result = await classifyFixture(
        {
          'lib/bordered.dart': '''
$kClassifierStubs

class Border {
  const Border();
  factory Border.all({double width}) = Border;
}

class BoxDecoration {
  const BoxDecoration({this.border});
  final Border? border;
}

class Container extends StatelessWidget {
  const Container({this.decoration});
  final BoxDecoration? decoration;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'BorderedBox',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'bordered box',
)
class BorderedBox extends StatelessWidget {
  const BorderedBox();
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(border: Border.all(width: 1)),
      );
}
''',
        },
        inputPath: 'lib/bordered.dart',
        widgetName: 'BorderedBox',
        catalog: _a2Catalog(
          file: 'bordered.dart',
          structured: ['BoxDecoration', 'Border'],
        ),
      );

      expect(result, isA<ComposableWidget>());
    });

    test(
        'a non-lowered static method on a value type stays a reducible '
        'dartCall (no classifierOnly over-claim)', () async {
      // `ButtonStyle.styleFrom(...)` is a true static method the translator
      // does NOT lower. The classifier must keep it a `dartCall` (reducible —
      // "not supported yet"), NOT claim it composable and let emit silently
      // fail. This is the safe boundary the chapter's honesty invariant wants.
      final result = await classifyFixture(
        {
          'lib/styled_button.dart': '''
$kClassifierStubs

class ButtonStyle {
  const ButtonStyle();
  static ButtonStyle styleFrom({Object? backgroundColor}) =>
      const ButtonStyle();
}

class FilledButton extends StatelessWidget {
  const FilledButton({this.style, this.child});
  final ButtonStyle? style;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'CtaButton',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'cta button',
)
class CtaButton extends StatelessWidget {
  const CtaButton({this.child});
  final Widget? child;
  Widget build(BuildContext context) =>
      FilledButton(style: ButtonStyle.styleFrom(), child: child);
}
''',
        },
        inputPath: 'lib/styled_button.dart',
        widgetName: 'CtaButton',
        catalog: catalogWith(
          [
            entry(
              name: 'FilledButton',
              properties: [
                prop('style', PropertyType.structured),
                prop('child', PropertyType.widget),
              ],
              flutterType:
                  'package:apps_examples/styled_button.dart#FilledButton',
            ),
          ],
          structuredTypes: [structuredEntry('ButtonStyle')],
        ),
      );

      expect(result, isA<ImperativeWidget>());
      expect(
        (result as ImperativeWidget).blockers.first.kind,
        BlockerKind.dartCall,
      );
    });
  });

  group('A2 — mechanism 3: framework named constants', () {
    test(
        'real Flutter Colors.* / Icons.* (resolved to package:flutter) are '
        'Composable', () async {
      // Real-Flutter resolution: `Colors`/`Icons` resolve to a package:flutter
      // class, so the element-resolved namespace check recognises them. (A
      // local `Box` stands in as the catalog widget — only the value refs need
      // to be real Flutter.)
      final result = await classifyFixture(
        {
          'lib/framework_consts.dart': '''
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Box extends StatelessWidget {
  const Box({this.color, this.glyph, super.key});
  final Color? color;
  final IconData? glyph;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'FrameworkConsts',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration,
  description: 'framework const refs',
)
class FrameworkConsts extends StatelessWidget {
  const FrameworkConsts({super.key});
  @override
  Widget build(BuildContext context) =>
      Box(color: Colors.transparent, glyph: Icons.star);
}
''',
        },
        inputPath: 'lib/framework_consts.dart',
        widgetName: 'FrameworkConsts',
        catalog: catalogWith([
          entry(
            name: 'Box',
            properties: [
              prop('color', PropertyType.color),
              prop('glyph', PropertyType.integer),
            ],
            flutterType: 'package:apps_examples/framework_consts.dart#Box',
          ),
        ]),
      );

      expect(result, isA<ComposableWidget>());
    });

    test(
        'a customer class named Colors (NOT package:flutter) is NOT recognised '
        '— the lookalike defers, never a silent wrong blob', () async {
      // The recognition is element-resolved: a customer class that happens to
      // be named `Colors` must NOT be promoted to composable, or the translator
      // would silently lower `Colors.brand` against its hard-coded Material
      // table (emitting the wrong int, which the colour floor accepts).
      final result = await classifyFixture(
        {
          'lib/lookalike.dart': '''
$kClassifierStubs

class Color {
  const Color(this.value);
  final int value;
}

// A customer class that happens to be named `Colors` — not package:flutter.
class Colors {
  Colors._();
  static const Color brand = Color(0xFF112233);
}

class Box extends StatelessWidget {
  const Box({this.color});
  final Color? color;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'BrandBox',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'brand box',
)
class BrandBox extends StatelessWidget {
  const BrandBox();
  Widget build(BuildContext context) => Box(color: Colors.brand);
}
''',
        },
        inputPath: 'lib/lookalike.dart',
        widgetName: 'BrandBox',
        catalog: catalogWith([
          entry(
            name: 'Box',
            properties: [prop('color', PropertyType.color)],
            flutterType: 'package:apps_examples/lookalike.dart#Box',
          ),
        ]),
      );

      expect(result, isA<UnclassifiableWidget>());
    });
  });

  group('A2 — boundary: the safe direction holds (negatives still reject)', () {
    test('an arbitrary Dart call is still ImperativeWidget / dartCall',
        () async {
      // `shout` is a same-library top-level helper (now resolve-through
      // eligible), but its body performs a genuine Dart computation
      // (`s.toString()`) the transpiler cannot compose — so the inlined body
      // still defers as a `dartCall`. The safe direction holds: a helper that
      // does real Dart work rejects, even when its declaration is
      // inline-eligible.
      final result = await classifyFixture(
        {
          'lib/dyn.dart': '''
$kClassifierStubs

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

String shout(String? s) => s.toString();

@RestageWidget(
  name: 'Shouter',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'shouter',
)
class Shouter extends StatelessWidget {
  const Shouter({this.label});
  final String? label;
  Widget build(BuildContext context) => Text(shout(label));
}
''',
        },
        inputPath: 'lib/dyn.dart',
        widgetName: 'Shouter',
        catalog: _a2Catalog(file: 'dyn.dart'),
      );

      expect(result, isA<ImperativeWidget>());
      expect(
        (result as ImperativeWidget).blockers.first.kind,
        BlockerKind.dartCall,
      );
    });

    test(
        'a construction of an unrecognised non-widget type is still '
        'Unclassifiable', () async {
      final result = await classifyFixture(
        {
          'lib/mystery.dart': '''
$kClassifierStubs

class Mystery {
  const Mystery();
}

class Container extends StatelessWidget {
  const Container({this.child});
  final Object? child;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'MysteryBox',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'mystery box',
)
class MysteryBox extends StatelessWidget {
  const MysteryBox();
  Widget build(BuildContext context) => Container(child: Mystery());
}
''',
        },
        inputPath: 'lib/mystery.dart',
        widgetName: 'MysteryBox',
        catalog: _a2Catalog(file: 'mystery.dart'),
      );

      expect(result, isA<UnclassifiableWidget>());
    });
  });

  group('A2 — blob identity (the literal-Color workaround is removable)', () {
    test(
        'Colors.transparent lowers to the identical value as the '
        'Color(0x00000000) workaround', () async {
      final catalog = catalogWith([
        entry(
          name: 'Container',
          properties: [prop('color', PropertyType.color)],
        ),
      ]);
      final translator = ExpressionTranslator(
        catalog: catalog,
        helpers: HelperRegistry(),
      );

      // Real-flutter resolution: the translator's `Colors` arm is gated to
      // package:flutter, so the named-constant path must exercise the real
      // `Colors` (showing only `Colors`/`Color` to keep the local `Container`
      // stub). `Colors.transparent` is the curated `0x00000000`.
      final named = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show Colors, Color;
        class Container { const Container({this.color}); final Color? color; }
        Object x() => Container(color: Colors.transparent);
        ''',
        rootPackage: 'apps_examples',
      );
      final literal = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart' show Color;
        class Container { const Container({this.color}); final Color? color; }
        Object x() => Container(color: Color(0x00000000));
        ''',
        rootPackage: 'apps_examples',
      );

      final namedDsl = translator.translate(named).dsl;
      final literalDsl = translator.translate(literal).dsl;

      // Same ARGB → byte-identical emitted DSL → byte-identical .rfw blob. So
      // an author who wrote the literal `Color(0x00000000)` to work around the
      // classifier not recognising `Colors.transparent` can now use the named
      // constant directly, changing no committed blob (strict-drift 0/0).
      expect(namedDsl, literalDsl);
      expect(namedDsl, contains('0x00000000'));
    });
  });

  group('A2 — drift guard', () {
    test('every hand-authored recipe value type is in the classifier base set',
        () {
      // The hand-authored recipes carry the bespoke value types the translator
      // lowers outside the catalog decompose path. Each must be in the
      // classifier's base value-type set, so a future recipe addition cannot
      // silently regress the classifier↔translator reconciliation. (Drift on
      // the decompose types is structurally impossible — both the classifier
      // and the translator read the catalog's `structuredTypes`.)
      final recipeTypes = kHandAuthoredRecipes.map((r) => r.typeName).toSet();
      expect(
        recipeTypes.difference(kStructuredValueTypeNames),
        isEmpty,
        reason: 'a recipe value type is missing from kStructuredValueTypeNames '
            '— the classifier would reject a value the translator lowers',
      );
    });
  });
}
