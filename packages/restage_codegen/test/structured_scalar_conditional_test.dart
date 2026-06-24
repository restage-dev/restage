// A conditional bound to a `double`-decoded scalar inside a structured value
// (border width, Offset, BorderRadius, BoxShadow blur, EdgeInsets, gradient
// stop, …) must coerce PER BRANCH to a double literal. The hand-authored
// structured translators and the recipe dispatcher previously did
// `asDoubleLiteral(_translate(expr))`, and `asDoubleLiteral` returns the
// assembled `switch state.X {…}` string unchanged (it `contains('.')` from
// `state.X`), leaving bare-int branches the runtime `v<double>` decode
// silently nulls — a silent fidelity loss. Per-branch coercion closes it.
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  ExpressionTranslator t() => ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry()..registerAll(paywallHelpers),
      );
  const annual = CustomWidgetStateField(
    name: 'annual',
    isNumeric: false,
    initialValue: true,
  );
  const tier = CustomWidgetStateField(
    name: 'selectedTier',
    isNumeric: false,
    initialValue: 0,
  );

  Future<({String dsl, bool clean})> emit(
    String expr, {
    List<CustomWidgetStateField> state = const [annual],
  }) async {
    final node = await parseExpressionFromSourceForTest(
      '''
      import 'package:flutter/material.dart';
      Object x() => $expr;
      ''',
      rootPackage: 'apps_examples',
    );
    final r = t().translate(node, rootState: state);
    return (dsl: r.dsl, clean: r.issues.isEmpty);
  }

  group('hand-authored structured translators coerce conditional scalars', () {
    test('Border.all width — UNPARENTHESIZED', () async {
      final r = await emit('Border.all(width: annual ? 1 : 2)');
      expect(r.clean, isTrue);
      expect(
        r.dsl,
        contains('width: switch state.annual { true: 1.0, false: 2.0 }'),
      );
    });

    test('Border.all width — PARENTHESIZED', () async {
      final r = await emit('Border.all(width: (annual ? 1 : 2))');
      expect(r.clean, isTrue);
      expect(
        r.dsl,
        contains('width: switch state.annual { true: 1.0, false: 2.0 }'),
      );
    });

    test('Border.all width — INT-STATE arm (composes with the N-arm switch)',
        () async {
      final r = await emit(
        'Border.all(width: selectedTier == 0 ? 1 : 2)',
        state: [tier],
      );
      expect(r.clean, isTrue);
      expect(
        r.dsl,
        contains(
          'width: switch state.selectedTier { 0: 1.0, default: 2.0 }',
        ),
      );
    });

    test('Offset — both coordinates', () async {
      final r = await emit('Offset(annual ? 0 : 4, 8)');
      expect(r.clean, isTrue);
      expect(
        r.dsl,
        contains('x: switch state.annual { true: 0.0, false: 4.0 }'),
      );
      expect(r.dsl, contains('y: 8.0'));
    });

    test('BorderRadius.circular', () async {
      final r = await emit('BorderRadius.circular(annual ? 8 : 16)');
      expect(r.clean, isTrue);
      expect(
        r.dsl,
        contains('switch state.annual { true: 8.0, false: 16.0 }'),
      );
    });

    test('BoxShadow blurRadius', () async {
      final r = await emit(
        'BoxShadow(blurRadius: annual ? 4 : 8, color: Color(0xFF000000))',
      );
      expect(r.clean, isTrue);
      expect(
        r.dsl,
        contains('blurRadius: switch state.annual { true: 4.0, false: 8.0 }'),
      );
    });

    test('EdgeInsets.symmetric', () async {
      final r = await emit(
        'EdgeInsets.symmetric(horizontal: annual ? 8 : 16, vertical: 4)',
      );
      expect(r.clean, isTrue);
      // horizontal maps to left+right; each coerces per-branch.
      expect(
        r.dsl,
        contains('switch state.annual { true: 8.0, false: 16.0 }'),
      );
    });
  });

  group('the recipe dispatcher coerces conditional scalars', () {
    test('gradient stops list — a bare-int conditional element', () async {
      final r = await emit(
        'LinearGradient(colors: [Color(0xFF000000), Color(0xFFFFFFFF)], '
        'stops: [0, annual ? 0 : 1])',
      );
      expect(r.clean, isTrue);
      expect(
        r.dsl,
        contains(
          'stops: [0.0, switch state.annual { true: 0.0, false: 1.0 }]',
        ),
      );
    });
  });
}
