import 'dart:io';

import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Design tokens declared in another file of the package.
const _tokens = '''
import 'package:flutter/material.dart';

abstract final class Space {
  static const double l = 20;
  static const EdgeInsets screen = EdgeInsets.symmetric(horizontal: l);
}

abstract final class Type {
  static const TextStyle title = TextStyle(
    fontFamily: 'Serif',
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle rich = TextStyle(
    fontStyle: FontStyle.italic,
    overflow: TextOverflow.ellipsis,
    decoration: TextDecoration.underline,
  );
  static final TextStyle body = TextStyle(fontSize: 17);
  static const TextStyle packaged = TextStyle(
    fontFamily: 'Serif',
    package: 'acme',
  );
}

class Inner {
  const Inner({required this.pad});
  final EdgeInsets pad;
}

class Palette {
  const Palette({
    required this.ink,
    required this.primary,
    this.align = MainAxisAlignment.center,
    this.inner = const Inner(pad: EdgeInsets.all(4)),
  });
  final Color ink;
  final Color primary;
  final MainAxisAlignment align;
  final Inner inner;
  static const light = Palette(ink: Color(0xFF1F2A24), primary: Color(0xFF3D7A55));
}

const MainAxisAlignment kAlign = MainAxisAlignment.end;
const IconData kStar = Icons.star;
const Curve kCurve = Curves.easeIn;

const List<Color> kStripe = [Color(0xFF000000), Colors.white];
''';

Catalog _catalogAt(String package) => requireNativeCatalog(
      decodeCatalog(
        File('../$package/lib/src/widget_catalog/catalog.json')
            .readAsStringSync(),
      ),
    );

final Catalog _coreCatalog = _catalogAt('restage_core');
final Catalog _materialCatalog = _catalogAt('restage_material');

Future<TranslationResult> _translate(
  String expression, {
  Catalog? catalog,
}) async {
  final expr = await parseExpressionFromSourceForTest(
    '''
    import 'package:flutter/material.dart';
    import 'package:apps_examples/tokens.dart';
    Object x() => $expression;
    ''',
    rootPackage: 'apps_examples',
    otherFiles: {'lib/tokens.dart': _tokens},
  );
  return ExpressionTranslator(
    catalog: catalog ?? _coreCatalog,
    helpers: HelperRegistry(),
  ).translate(expr, sourcePath: 'lib/_expr_probe.dart');
}

Future<void> _expectSameAs(
  String folded,
  String inline, {
  Catalog? catalog,
}) async {
  final a = await _translate(folded, catalog: catalog);
  final b = await _translate(inline, catalog: catalog);
  expect(a.issues, isEmpty, reason: '${a.issues}');
  expect(b.issues, isEmpty, reason: '${b.issues}');
  expect(a.dsl, isNotEmpty);
  expect(a.dsl, b.dsl);
}

void main() {
  group('constants from another file fold like literals', () {
    test('an EdgeInsets constant', () async {
      await _expectSameAs(
        'Padding(padding: Space.screen, child: SizedBox())',
        'Padding(padding: EdgeInsets.symmetric(horizontal: 20), '
            'child: SizedBox())',
      );
    });

    test('a TextStyle constant', () async {
      await _expectSameAs(
        "Text('Hi', style: Type.title)",
        "Text('Hi', style: TextStyle(fontFamily: 'Serif', fontSize: 28, "
            'height: 1.2, fontWeight: FontWeight.w600))',
      );
    });

    test('a field of a constant object', () async {
      await _expectSameAs(
        'ColoredBox(color: Palette.light.primary)',
        'ColoredBox(color: Color(0xFF3D7A55))',
      );
    });

    test('a list of colors', () async {
      final result = await _translate('kStripe');
      expect(result.issues, isEmpty, reason: '${result.issues}');
      expect(result.dsl, '[0xFF000000, 0xFFFFFFFF]');
    });

    test('enum fields of a constant style', () async {
      await _expectSameAs(
        "Text('Hi', style: Type.rich)",
        "Text('Hi', style: TextStyle(fontStyle: FontStyle.italic, "
            'overflow: TextOverflow.ellipsis, '
            'decoration: TextDecoration.underline))',
      );
    });

    test('an enum constant and an enum field of a constant object', () async {
      await _expectSameAs(
        'Column(mainAxisAlignment: kAlign, children: [])',
        'Column(mainAxisAlignment: MainAxisAlignment.end, children: [])',
      );
      await _expectSameAs(
        'Column(mainAxisAlignment: Palette.light.align, children: [])',
        'Column(mainAxisAlignment: MainAxisAlignment.center, children: [])',
      );
    });

    test('a field of a nested constant object', () async {
      await _expectSameAs(
        'Padding(padding: Palette.light.inner.pad, child: SizedBox())',
        'Padding(padding: EdgeInsets.all(4), child: SizedBox())',
      );
    });

    test('constants declared as framework constants', () async {
      await _expectSameAs(
        'Icon(kStar)',
        'Icon(Icons.star)',
        catalog: _materialCatalog,
      );
      await _expectSameAs(
        'AnimatedOpacity(opacity: 1, duration: Duration(milliseconds: 200), '
            'curve: kCurve)',
        'AnimatedOpacity(opacity: 1, duration: Duration(milliseconds: 200), '
            'curve: Curves.easeIn)',
      );
    });

    test('a style naming its font package', () async {
      final result = await _translate("Text('Hi', style: Type.packaged)");
      expect(result.issues, isEmpty, reason: '${result.issues}');
      const expected =
          'Text(text: "Hi", fontFamily: "Serif", fontPackage: "acme")';
      expect(result.dsl, expected);
    });
  });

  group('copyWith on a constant style', () {
    test('a static final style says it exists only in the running app',
        () async {
      final result =
          await _translate("Text('Hi', style: Type.body.copyWith(height: 2))");
      const message = "'Type.body' is static final, so its value exists only "
          'in the running app. Make it const, or pass it in as a constructor '
          'input.';
      expect(result.issues.map((issue) => issue.message), [message]);
    });

    test('overrides the named fields', () async {
      await _expectSameAs(
        "Text('Hi', style: Type.title.copyWith(fontSize: 30, "
            'color: Color(0xFF112233)))',
        "Text('Hi', style: TextStyle(fontFamily: 'Serif', fontSize: 30, "
            'height: 1.2, fontWeight: FontWeight.w600, '
            'color: Color(0xFF112233)))',
      );
    });
  });
}
