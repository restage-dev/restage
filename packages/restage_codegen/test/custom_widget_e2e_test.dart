import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Outcome of transpiling a custom-widget fixture through the full Phase-3
/// chain — classify → translate → emit → parse → validate → encode → decode.
class _TranspileResult {
  _TranspileResult(this.issues, this.decoded);

  /// Every diagnostic from translation and catalog validation.
  final List<Issue> issues;

  /// The `.rfw` blob decoded back to a library — null when an earlier stage
  /// produced issues.
  final fmt.RemoteWidgetLibrary? decoded;
}

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
      // emits the local initializer, never `args.child` (the value-wrong class
      // the floor cannot catch; the const-local analog was caught at the C1f
      // close-review).
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

    test('an object-valued const local defers (not a scalar fold)', () async {
      // The const-local fold is for SCALARS. An object-valued const local
      // (`const c = Color(0x..)`) does not fold to a scalar, so the widget
      // is not inlinable — it must DEFER with a diagnostic, never silently
      // mis-emit. (Guards the body-shape relaxation against object consts.)
      final result = await _transpile(
        '''
$kClassifierStubs

class Color { const Color(this.value); final int value; }

class Box extends StatelessWidget {
  const Box({this.color});
  final Color? color;
  Widget build(BuildContext context) => const Widget();
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
          _entry('Box', [prop('color', PropertyType.color)]),
        ]),
      );

      // Deferred: the unclassifiable custom widget cannot inline, so the
      // pipeline surfaces a diagnostic rather than emitting a wrong blob.
      expect(result.issues, isNotEmpty);
      expect(result.decoded, isNull);
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
      // internal `Container` library path).
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
        'an out-of-contract theme read transpiles to a themeReadOutOfContract '
        'diagnostic, no blob emitted', () async {
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
        'a customer FontWeight look-alike (a non-Flutter class) defers — '
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

      // The customer `FontWeight` is not the framework class, so the widget
      // defers — no blob, and crucially no `"w600"` string substituted for the
      // customer's value (the value-substitution silent-wrong stays closed).
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
        'a customer TextDecoration look-alike (a non-Flutter class) defers — '
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

      // The customer `TextDecoration` is not the framework class, so the widget
      // defers — no blob, and no `"underline"` string substituted for the
      // customer's value (the value-substitution silent-wrong stays closed).
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
        'a customer Curves look-alike (a non-Flutter class) defers — no curve '
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

      // The customer `Curves` is not the framework class, so the widget defers
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
        'a customer EdgeInsets.zero look-alike (a non-Flutter class) defers — '
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
        'a customer BorderSide.none look-alike (a non-Flutter class) defers — '
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
        'possibly-missing data ref (a price helper) passed to a coalesced '
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

Object x() => Price(label: paywallPriceFor(slot: 'annual'));
''',
        catalogWith([
          _entry(
            'Label',
            [prop('text', PropertyType.string)],
            rootPackage: 'apps_examples',
          ),
        ]),
        rootPackage: 'apps_examples',
      );

      // `paywallPriceFor(...)` is a non-null String but lowers to
      // `data.products.annual.localizedPrice`, populated only for priced
      // products. Completing the coalesced `label` with it (row 4) would, for
      // an unpriced product, fall to the factory default instead of "Free" —
      // a silent-wrong the static-nullability gate misses. So it defers.
      expect(result.decoded, isNull);
      expect(
        result.issues
            .any((i) => i.code == IssueCode.customWidgetUnsupportedReducible),
        isTrue,
      );
    });

    test(
        'gate 4 (unvalidated position): a coalesced `??` the slot validator '
        'does not reach (a list element) defers rather than hoist an '
        'unvalidated fallback', () async {
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

      // The `??` sits inside a list literal, which the slot validator does not
      // descend into — so the fallback is never kind-checked. Rather than
      // rewrite + hoist an unvalidated fallback, the widget defers.
      expect(result.decoded, isNull);
      expect(
        result.issues
            .any((i) => i.code == IssueCode.customWidgetUnsupportedReducible),
        isTrue,
      );
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
        'a State method that BOTH mutates state and fires a purchase does NOT '
        'lower to a combined handler — it defers with stateShapeUnsupported '
        '(the select-and-purchase staleness tripwire)', () async {
      // TRIPWIRE — do not loosen the rejection below without reading this.
      // RFW resolves an EventHandler's arguments at FETCH/build time and
      // caches them; it does NOT re-resolve the arg switch inside the fired
      // callback (rfw-1.1.3 runtime.dart `_fix`/`_resolveFrom`). So a SINGLE
      // handler that mutates `state.X` and THEN fires
      // `event "restage.purchase" { slot: switch state.X {...} }` in the same
      // callback would charge the PRE-mutation slot. Codegen avoids this by
      // emitting exactly one handler per onTap and rejecting any State method
      // that is not a single setState — so the toggle and the purchase are
      // always SEPARATE handlers/buttons. If a future increment ever supports
      // a richer "select this plan AND buy in one tap" action, it MUST NOT
      // emit a single handler list with the purchase event resolving against
      // pre-mutation state (re-order, read the post-mutation value, or
      // reject) — tracked as a follow-up: RFW event-arg switches are
      // resolved at fetch-time, not in-callback.
      final result = await _transpile(
        '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

void Function() paywallPurchase({String? slot}) => () {};

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
    paywallPurchase(slot: annual ? 'annual' : 'monthly')();
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
        reason: 'a combined mutate+purchase handler must not emit a blob',
      );
      expect(
        result.issues.any((i) => i.code == IssueCode.stateShapeUnsupported),
        isTrue,
        reason: 'the combined body is not a single setState — must defer with '
            'stateShapeUnsupported, never emit a stale-prone combined handler',
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
      // `false-4a-into-inlinable` invariant.
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
/// root `Object x() => <root>;`) through the full Phase-3 chain against
/// [catalog]. Pass [rootPackage]`: 'apps_examples'` for fixtures that
/// need real `package:flutter/material.dart` resolution (the strict
/// theme-read recognizer requires a `package:flutter/` library URI).
Future<_TranspileResult> _transpile(
  String source,
  Catalog catalog, {
  String rootPackage = 'restage_codegen',
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: rootPackage,
  );
  final assetKey = '$rootPackage|lib/_e2e_probe.dart';
  readerWriter.testing.writeString(AssetId.parse(assetKey), source);

  _TranspileResult? result;
  await testBuilder(
    _TranspileProbeBuilder(catalog, (r) => result = r),
    {assetKey: source},
    rootPackage: rootPackage,
    readerWriter: readerWriter,
  );
  final resolved = result;
  if (resolved == null) {
    throw StateError('the transpile probe did not run');
  }
  return resolved;
}

/// Builder that runs the Phase-3 transpile chain over the e2e probe library.
class _TranspileProbeBuilder implements Builder {
  _TranspileProbeBuilder(this.catalog, this.onResult);

  final Catalog catalog;
  final void Function(_TranspileResult) onResult;

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

    final helpers = HelperRegistry()..registerAll(paywallHelpers);
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
    if (translation.issues.isNotEmpty) {
      onResult(_TranspileResult(translation.issues, null));
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
        onResult(_TranspileResult(validation, null));
        return;
      }
      final bytes = fmt.encodeLibraryBlob(parsed);
      final decoded = fmt.decodeLibraryBlob(Uint8List.fromList(bytes));
      onResult(_TranspileResult(const [], decoded));
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
        ),
      );
    }
  }
}
