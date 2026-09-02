import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/production_helpers.dart';
import 'package:restage_codegen/src/setstate_recognition.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Const and non-const values used by declaration-resolution tests.
const String _palette = '''
import 'package:flutter/material.dart' show Color, EdgeInsets;

const Color kBrand = Color(0xFF37B6FF);
const EdgeInsets kPad = EdgeInsets.all(12);
const double kGap = 16;
final Color kRuntime = const Color(0xFF000000);

enum Mood { calm, loud }

class Palette {
  static const Color brand = Color(0xFF37B6FF);
}
''';

void main() {
  group('isConstDeclarationReference (discriminator)', () {
    test('true for a bare top-level const structured identifier', () async {
      final e = await parseExpressionFromSourceForTest(
        '$_palette Object x() => kBrand;',
        rootPackage: 'apps_examples',
      );
      expect(isConstDeclarationReference(e), isTrue);
    });

    test('true for a bare top-level const scalar identifier', () async {
      final e = await parseExpressionFromSourceForTest(
        '$_palette Object x() => kGap;',
        rootPackage: 'apps_examples',
      );
      expect(isConstDeclarationReference(e), isTrue);
    });

    test('true for a static const field reference', () async {
      final e = await parseExpressionFromSourceForTest(
        '$_palette Object x() => Palette.brand;',
        rootPackage: 'apps_examples',
      );
      expect(isConstDeclarationReference(e), isTrue);
    });

    test('false for an enum constant', () async {
      final e = await parseExpressionFromSourceForTest(
        '$_palette Object x() => Mood.calm;',
        rootPackage: 'apps_examples',
      );
      expect(isConstDeclarationReference(e), isFalse);
    });

    test('false for a non-const (final) top-level variable', () async {
      final e = await parseExpressionFromSourceForTest(
        '$_palette Object x() => kRuntime;',
        rootPackage: 'apps_examples',
      );
      expect(isConstDeclarationReference(e), isFalse);
    });

    test('false for a const-object instance field', () async {
      final e = await parseExpressionFromSourceForTest(
        'class S { const S(this.h); final String h; } '
        "const _s = S('x'); Object x() => _s.h;",
      );
      expect(isConstDeclarationReference(e), isFalse);
      expect(isConstObjectFieldAccess(e), isTrue);
    });

    test('false for a plain literal', () async {
      final e = await parseExpressionFromSourceForTest('Object x() => 42;');
      expect(isConstDeclarationReference(e), isFalse);
    });

    test('false for an import-prefixed PropertyAccess', () async {
      final e = await parseExpressionFromSourceForTest(
        "import 'package:flutter/material.dart' as material; "
        'Object x() => material.Colors.red;',
        rootPackage: 'apps_examples',
      );
      expect(e, isA<PropertyAccess>());
      expect(isConstDeclarationReference(e), isFalse);
      expect(resolveConstIdentifierInitializer(e), isNull);
    });
  });

  group('resolveConstIdentifierInitializer', () {
    test('top-level const Color → the bound constructor expression', () async {
      final e = await parseExpressionFromSourceForTest(
        '$_palette Object x() => kBrand;',
        rootPackage: 'apps_examples',
      );
      final init = resolveConstIdentifierInitializer(e);
      expect(init, isA<InstanceCreationExpression>());
      expect(init!.toSource(), 'Color(0xFF37B6FF)');
    });

    test('top-level const EdgeInsets → the bound constructor expression',
        () async {
      final e = await parseExpressionFromSourceForTest(
        '$_palette Object x() => kPad;',
        rootPackage: 'apps_examples',
      );
      expect(
        resolveConstIdentifierInitializer(e)!.toSource(),
        'EdgeInsets.all(12)',
      );
    });

    test('static const field → the bound constructor expression', () async {
      final e = await parseExpressionFromSourceForTest(
        '$_palette Object x() => Palette.brand;',
        rootPackage: 'apps_examples',
      );
      expect(
        resolveConstIdentifierInitializer(e)!.toSource(),
        'Color(0xFF37B6FF)',
      );
    });

    test('returns null for a cross-file const', () async {
      final e = await parseExpressionFromSourceForTest(
        "import 'package:flutter/material.dart'; Object x() => Colors.red;",
        rootPackage: 'apps_examples',
      );
      expect(isConstDeclarationReference(e), isTrue);
      expect(resolveConstIdentifierInitializer(e), isNull);
    });

    test('returns null for an enum constant', () async {
      final e = await parseExpressionFromSourceForTest(
        '$_palette Object x() => Mood.calm;',
        rootPackage: 'apps_examples',
      );
      expect(resolveConstIdentifierInitializer(e), isNull);
    });

    test('returns null for a non-const identifier', () async {
      final e = await parseExpressionFromSourceForTest(
        '$_palette Object x() => kRuntime;',
        rootPackage: 'apps_examples',
      );
      expect(resolveConstIdentifierInitializer(e), isNull);
    });
  });

  group('tryFoldConstant accepts scalar consts only', () {
    test('folds a top-level const scalar to its declared-type value', () async {
      // Scalar folding uses the declared type rather than the initializer type.
      final e = await parseExpressionFromSourceForTest(
        '$_palette Object x() => kGap;',
        rootPackage: 'apps_examples',
      );
      expect(tryFoldConstant(e), 16.0);
    });

    test('does not fold a structured const identifier', () async {
      final e = await parseExpressionFromSourceForTest(
        '$_palette Object x() => kBrand;',
        rootPackage: 'apps_examples',
      );
      expect(tryFoldConstant(e), isNull);
    });
  });

  _translatorGroups();
  _classifierGroups();
}

/// Catalog used by slot translation assertions.
Catalog _slotCatalog() => catalogWith([
      entry(
        name: 'Icon',
        properties: [prop('color', PropertyType.color)],
      ),
      entry(
        name: 'Tile',
        childrenSlot: ChildrenSlot.single,
        properties: [
          prop('color', PropertyType.color),
          prop('padding', PropertyType.edgeInsets),
          prop('gap', PropertyType.real),
          prop('mode', PropertyType.enumValue),
          prop('alignment', PropertyType.alignmentXY),
          prop('child', PropertyType.widget),
        ],
      ),
      entry(
        name: 'SizedBox',
        childrenSlot: ChildrenSlot.single,
        properties: [
          prop('width', PropertyType.real),
          prop('child', PropertyType.widget),
        ],
      ),
    ]);

Future<String> _dsl(ExpressionTranslator t, String source) async {
  final r = await _result(t, source);
  expect(r.issues, isEmpty, reason: 'unexpected issues: ${r.issues}');
  return r.dsl;
}

Future<TranslationResult> _result(
  ExpressionTranslator t,
  String source,
) async =>
    t.translate(
      await parseExpressionFromSourceForTest(
        source,
        rootPackage: 'apps_examples',
      ),
    );

void _expectReservedOwnerRefusal(
  TranslationResult result,
  String owner, {
  IssueCode code = IssueCode.unresolvedIdentifier,
}) {
  expect(result.issues, hasLength(1));
  final issue = result.issues.single;
  expect(issue.code, code);
  expect(issue.message, contains("'$owner' is the name"));
  expect(issue.message, contains('Rename the class'));
  expect(issue.location, isNotEmpty);
}

void _expectDoubleListRefusal(
  TranslationResult result, {
  IssueCode code = IssueCode.unrecognizedMethodCall,
  String? message,
  String? location,
}) {
  expect(result.dsl, isEmpty);
  expect(result.dsl, isNot(contains('stops:')));
  expect(result.issues.map((issue) => issue.code), [code]);
  final issue = result.issues.single;
  if (message == null) {
    expect(issue.message, isNotEmpty);
  } else {
    expect(issue.message, message);
  }
  if (location == null) {
    expect(issue.location, isNotEmpty);
  } else {
    expect(issue.location, location);
  }
}

const String _flutterImport =
    "import 'package:flutter/material.dart' show Color, EdgeInsets, TextStyle, "
    'BorderRadius, Radius, Alignment, Icon, SizedBox, FontWeight, Colors, '
    'Icons, MainAxisAlignment, LinearGradient, RadialGradient;';

const String _doubleListSourcePath = 'lib/gradient_fixture.dart';

const List<({String name, String constructor, String wireType})>
    _doubleListSinks = [
  (name: 'structured', constructor: 'LinearGradient', wireType: 'linear'),
  (name: 'recipe', constructor: 'RadialGradient', wireType: 'radial'),
];

const String _constDoubleListMessage =
    'A const-derived list cannot be lowered at a double-decoded list slot. '
    'Inline the list so each element is coerced to a double.';

const String _conditionalDoubleListMessage =
    'A conditional list cannot be lowered at a double-decoded list slot. '
    'Write the selected list directly so each element is coerced to a double.';

const String _depthDoubleListMessage =
    'The list source is too deeply nested to lower at a double-decoded list '
    'slot. Simplify the source bindings.';

String _gradientSource(
  String constructor,
  String stops, {
  String declaration = '',
}) {
  final declarationLine = declaration.isEmpty ? '' : '$declaration\n';
  return '$_flutterImport\n'
      '$declarationLine'
      'Object x() => $constructor(\n'
      '  colors: [Colors.red, Colors.red],\n'
      '  stops: $stops,\n'
      ');';
}

Future<TranslationResult> _locatedResult(
  ExpressionTranslator translator,
  String source,
) async =>
    translator.translate(
      await parseExpressionFromSourceForTest(
        source,
        rootPackage: 'apps_examples',
      ),
      sourcePath: _doubleListSourcePath,
      lineInfo: LineInfo.fromContent(source),
    );

String _parenthesizedStops(int count) =>
    '${List.filled(count, '(').join()}[0, 1]'
    '${List.filled(count, ')').join()}';

String _gradientDsl(String wireType) =>
    '{type: "$wireType", colors: [0xFFF44336, 0xFFF44336], '
    'stops: [0.0, 1.0]}';

void _translatorGroups() {
  late ExpressionTranslator translator;
  setUp(() {
    translator = ExpressionTranslator(
      catalog: _slotCatalog(),
      helpers: HelperRegistry(),
    );
  });

  group('structured const identifiers lower like inline values', () {
    test('top-level const Color at a property slot', () async {
      final folded = await _dsl(translator, '''
        $_flutterImport
        const Color _blue = Color(0xFF37B6FF);
        Object x() => Icon(color: _blue);
      ''');
      final inline = await _dsl(translator, '''
        $_flutterImport
        Object x() => Icon(color: Color(0xFF37B6FF));
      ''');
      expect(folded, 'Icon(color: 0xFF37B6FF)');
      expect(folded, inline);
    });

    test('the same const inside a const enclosing context', () async {
      final folded = await _dsl(translator, '''
        $_flutterImport
        const Color _blue = Color(0xFF37B6FF);
        Object x() => const SizedBox(child: Icon(color: _blue));
      ''');
      final inline = await _dsl(translator, '''
        $_flutterImport
        Object x() => const SizedBox(child: Icon(color: Color(0xFF37B6FF)));
      ''');
      expect(folded, inline);
      expect(folded, contains('0xFF37B6FF'));
    });

    test('a bare const Color identifier translated on its own', () async {
      expect(
        await _dsl(translator, '''
          $_flutterImport
          const Color _blue = Color(0xFF37B6FF);
          Object x() => _blue;
        '''),
        '0xFF37B6FF',
      );
    });

    test('top-level const EdgeInsets at an edgeInsets slot', () async {
      final folded = await _dsl(translator, '''
        $_flutterImport
        const EdgeInsets kPad = EdgeInsets.all(12);
        Object x() => Tile(padding: kPad);
      ''');
      final inline = await _dsl(translator, '''
        $_flutterImport
        Object x() => Tile(padding: EdgeInsets.all(12));
      ''');
      expect(folded, inline);
    });

    test('top-level const TextStyle', () async {
      final folded = await _dsl(translator, '''
        $_flutterImport
        const TextStyle kBody = TextStyle(fontSize: 16, color: Color(0xFF111111));
        Object x() => kBody;
      ''');
      final inline = await _dsl(translator, '''
        $_flutterImport
        Object x() => const TextStyle(fontSize: 16, color: Color(0xFF111111));
      ''');
      expect(folded, inline);
      expect(folded, isNotEmpty);
    });

    test('top-level const BorderRadius', () async {
      final folded = await _dsl(translator, '''
        $_flutterImport
        const BorderRadius kRadius =
            BorderRadius.all(Radius.circular(8));
        Object x() => kRadius;
      ''');
      final inline = await _dsl(translator, '''
        $_flutterImport
        Object x() => const BorderRadius.all(Radius.circular(8));
      ''');
      expect(folded, inline);
      expect(folded, isNotEmpty);
    });

    test('a static const Color field lowers at all three positions', () async {
      const decl =
          'class Palette { static const Color brand = Color(0xFF37B6FF); }';
      final bare = await _dsl(translator, '''
        $_flutterImport
        $decl
        Object x() => Palette.brand;
      ''');
      final slot = await _dsl(translator, '''
        $_flutterImport
        $decl
        Object x() => Icon(color: Palette.brand);
      ''');
      final nested = await _dsl(translator, '''
        $_flutterImport
        $decl
        Object x() => const SizedBox(child: Icon(color: Palette.brand));
      ''');
      final inlineSlot = await _dsl(translator, '''
        $_flutterImport
        Object x() => Icon(color: Color(0xFF37B6FF));
      ''');
      final inlineNested = await _dsl(translator, '''
        $_flutterImport
        Object x() => const SizedBox(child: Icon(color: Color(0xFF37B6FF)));
      ''');
      expect(bare, '0xFF37B6FF');
      expect(slot, inlineSlot);
      expect(nested, inlineNested);
    });
  });

  group('scalar const folding uses declared numeric types', () {
    test('a top-level const double declared from an int literal emits 16.0',
        () async {
      expect(
        await _dsl(translator, 'const double kGap = 16; Object x() => kGap;'),
        '16.0',
      );
    });

    test('a static const double field emits 16.0', () async {
      expect(
        await _dsl(
          translator,
          'class Tokens { static const double gap = 16; } '
          'Object x() => Tokens.gap;',
        ),
        '16.0',
      );
    });
  });

  group('framework constants use curated translations', () {
    test('framework constants emit their documented values', () async {
      const cases = <({String expr, String? dsl, IssueCode? code})>[
        (expr: 'Colors.red', dsl: '0xFFF44336', code: null),
        (expr: 'Icons.add', dsl: '57415', code: null),
        (expr: 'Alignment.center', dsl: '"center"', code: null),
        (expr: 'FontWeight.bold', dsl: '"w700"', code: null),
        (expr: 'EdgeInsets.zero', dsl: '[0.0, 0.0, 0.0, 0.0]', code: null),
        (
          expr: 'double.infinity',
          dsl: '',
          code: IssueCode.nonFiniteNumericValue,
        ),
      ];
      for (final c in cases) {
        final r = await _result(
          translator,
          '$_flutterImport Object x() => ${c.expr};',
        );
        expect(r.dsl, c.dsl, reason: '${c.expr} emitted ${r.dsl}');
        if (c.code == null) {
          expect(r.issues, isEmpty, reason: '${c.expr}: ${r.issues}');
        } else {
          expect(r.issues.map((i) => i.code), contains(c.code));
        }
      }
    });
  });

  group('reserved custom const owners', () {
    const lookalike = '''
      class Alignment {
        const Alignment(this.x, this.y);
        final double x;
        final double y;
        static const Alignment topLeft = Alignment(-1.0, -1.0);
      }
    ''';

    test('a same-file look-alike is refused at a bare position', () async {
      final r = await _result(
        translator,
        '$lookalike Object x() => Alignment.topLeft;',
      );
      expect(r.dsl, isEmpty);
      _expectReservedOwnerRefusal(r, 'Alignment');
    });

    test('the diagnostic names the reserved class', () async {
      final r = await _result(
        translator,
        '$lookalike Object x() => Alignment.topLeft;',
      );
      _expectReservedOwnerRefusal(r, 'Alignment');
      expect(r.issues.first.message, contains('framework value type'));
    });

    test('a same-file look-alike never substitutes its own value at a slot',
        () async {
      final r = await _result(translator, '''
        $_flutterImport
        class Colors { static const Color red = Color(0xFF00FF00); }
        Object x() => Icon(color: Colors.red);
      ''');
      expect(r.dsl, isNot(contains('0xFF00FF00')));
      _expectReservedOwnerRefusal(r, 'Colors');
    });

    test('a custom double member reports a non-finite numeric diagnostic',
        () async {
      final r = await _result(translator, '''
        $_flutterImport
        class double {
          static const Color infinity = Color(0xFF00FF00);
        }
        Object x() => Icon(color: double.infinity);
      ''');
      expect(r.dsl, isNot(contains('0xFF00FF00')));
      _expectReservedOwnerRefusal(
        r,
        'double',
        code: IssueCode.nonFiniteNumericValue,
      );
    });

    test('an unqualified static const uses its resolved owner identity',
        () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        $_flutterImport
        class Colors {
          static const Color red = Color(0xFF00FF00);
          Object x() => red;
        }
        ''',
        rootPackage: 'apps_examples',
        enclosingClassName: 'Colors',
      );
      final r = translator.translate(expr);
      expect(r.dsl, isNot(contains('0xFF00FF00')));
      _expectReservedOwnerRefusal(
        r,
        'Colors',
        code: IssueCode.unrecognizedMethodCall,
      );
    });

    test('a typedef alias cannot hide a reserved const owner', () async {
      final r = await _result(translator, '''
        $_flutterImport
        class Colors { static const Color red = Color(0xFF00FF00); }
        typedef Palette = Colors;
        Object x() => Palette.red;
      ''');
      expect(r.dsl, isNot(contains('0xFF00FF00')));
      _expectReservedOwnerRefusal(r, 'Colors');
      expect(r.issues.single.message, isNot(contains("'Palette' is the name")));
    });

    test('a prefixed scalar emits its declared value', () async {
      final r = await _result(translator, '''
        class Alignment { static const double gap = 7; }
        Object x() => Alignment.gap;
      ''');
      expect(r.issues, isEmpty);
      expect(r.dsl, '7.0');
    });

    test('an unqualified scalar emits its declared value', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        class Alignment {
          static const double gap = 7;
          Object x() => gap;
        }
        ''',
        rootPackage: 'apps_examples',
        enclosingClassName: 'Alignment',
      );
      final r = translator.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, '7.0');
    });

    test('a typedef-aliased scalar emits its declared value', () async {
      final r = await _result(translator, '''
        class Alignment { static const double gap = 7; }
        typedef Layout = Alignment;
        Object x() => Layout.gap;
      ''');
      expect(r.issues, isEmpty);
      expect(r.dsl, '7.0');
    });

    test('a scalar at a typed slot emits its declared value', () async {
      final r = await _result(translator, '''
        $_flutterImport
        class Alignment { static const double gap = 7; }
        Object x() => Tile(gap: Alignment.gap, child: SizedBox());
      ''');
      expect(r.issues, isEmpty);
      expect(r.dsl, 'Tile(gap: 7.0, child: SizedBox())');
    });

    test('an unrelated unqualified const owner lowers', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        $_flutterImport
        class Palette {
          static const Color red = Color(0xFF00FF00);
          Object x() => red;
        }
        ''',
        rootPackage: 'apps_examples',
        enclosingClassName: 'Palette',
      );
      final r = translator.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, '0xFF00FF00');
    });
  });

  group('scalar readers', () {
    test('map keys accept custom static string constants', () async {
      final r = await _result(translator, '''
        class Colors { static const String key = 'x'; }
        Object x() => {Colors.key: 1};
      ''');
      expect(r.issues, isEmpty);
      expect(r.dsl, '{ x: 1 }');
    });

    test('Duration units accept custom static integer constants', () async {
      final r = await _result(translator, '''
        class Colors { static const int seconds = 1; }
        Object x() => Duration(seconds: Colors.seconds);
      ''');
      expect(r.issues, isEmpty);
      expect(r.dsl, '1000');
    });

    test('commerce matching reads custom static event names', () async {
      final eventTranslator = ExpressionTranslator(
        catalog: _slotCatalog(),
        helpers: productionPaywallHelperRegistry(),
      );
      final r = await _result(eventTranslator, '''
        import 'package:restage/restage.dart';
        class Colors { static const String event = 'restore'; }
        Object x() => paywallEvent(Colors.event);
      ''');
      expect(
        r.issues.map((issue) => issue.code),
        [IssueCode.unsupportedCommerceAuthoring],
      );
      expect(r.dsl, isEmpty);
    });
  });

  group('enum constants are not captured', () {
    test('a custom enum constant lowers to its bare name', () async {
      expect(
        await _dsl(
          translator,
          'enum Mood { calm, loud } Object x() => Mood.calm;',
        ),
        '"calm"',
      );
    });

    test('a reserved custom enum emits at a direct route', () async {
      const declaration = 'enum Alignment { center }';
      expect(
        await _dsl(
          translator,
          '$declaration Object x() => Alignment.center;',
        ),
        '"center"',
      );
    });

    test('a reserved custom enum emits at a generic slot route', () async {
      const declaration = 'enum Alignment { center }';
      expect(
        await _dsl(
          translator,
          '$_flutterImport $declaration '
          'Object x() => Tile(mode: Alignment.center, child: SizedBox());',
        ),
        'Tile(mode: "center", child: SizedBox())',
      );
    });

    test('a framework enum constant lowers to its bare name', () async {
      expect(
        await _dsl(
          translator,
          '$_flutterImport Object x() => MainAxisAlignment.center;',
        ),
        '"center"',
      );
    });
  });

  group('cross-file structured consts report unsupported folding', () {
    test('a bare cross-file const reports its source constraint', () async {
      final r = await _result(
        translator,
        "import 'package:flutter/material.dart'; "
        'Object x() => kThemeAnimationDuration;',
      );
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      expect(r.issues.first.message, contains('same file'));
    });

    test('a prefixed cross-file const reports its source constraint', () async {
      final r = await _result(
        translator,
        "import 'package:flutter/material.dart'; "
        'Object x() => Duration.zero;',
      );
      expect(r.dsl, isEmpty);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unresolvedIdentifier),
      );
      expect(r.issues.first.message, contains('same file'));
    });
  });

  group('slot-specific translation accepts resolved consts', () {
    test('a const Alignment folds at the alignmentXY slot', () async {
      expect(
        await _dsl(translator, '''
          $_flutterImport
          const Alignment kTopLeft = Alignment.topLeft;
          Object x() => Tile(alignment: kTopLeft, child: SizedBox());
        '''),
        contains('alignment: {x: -1.0, y: -1.0}'),
      );
    });

    test('a const scalar at a real slot uses double formatting', () async {
      expect(
        await _dsl(translator, '''
          $_flutterImport
          const double kGap = 16;
          Object x() => Tile(gap: kGap, child: SizedBox());
        '''),
        contains('gap: 16.0'),
      );
    });

    test('a const Alignment folds at a gradient alignment argument', () async {
      // A gradient's begin/end reach the alignment emitter outside the slot
      // path, so the const has to resolve there too.
      expect(
        await _dsl(translator, '''
          $_flutterImport
          const Alignment kStart = Alignment.topLeft;
          Object x() => LinearGradient(
            colors: [Colors.red, Colors.red],
            begin: kStart,
          );
        '''),
        contains('begin: {x: -1.0, y: -1.0}'),
      );
    });

    test('an alignment const chain folds at a gradient alignment argument',
        () async {
      expect(
        await _dsl(translator, '''
          $_flutterImport
          const Alignment kBase = Alignment.bottomRight;
          const Alignment kStart = kBase;
          Object x() => LinearGradient(
            colors: [Colors.red, Colors.red],
            begin: kStart,
          );
        '''),
        contains('begin: {x: 1.0, y: 1.0}'),
      );
    });

    test('an unresolvable alignment const refuses instead of defaulting',
        () async {
      // A typedef alias keeps the const in another library, so nothing can be
      // folded — the refusal must not read as a centred alignment.
      final r = await _result(translator, '''
        $_flutterImport
        typedef Anchor = Alignment;
        Object x() => LinearGradient(
          colors: [Colors.red, Colors.red],
          begin: Anchor.center,
        );
      ''');
      expect(r.issues, isNotEmpty);
      expect(r.issues.first.location, isNotEmpty);
      expect(r.dsl, isNot(contains('{x: 0.0, y: 0.0}')));
    });

    test('a framework const outside the Alignment set keeps usable advice',
        () async {
      final r = await _result(translator, '''
        $_flutterImport
        import 'package:flutter/material.dart' show AlignmentDirectional;
        Object x() => LinearGradient(
          colors: [Colors.red, Colors.red],
          begin: AlignmentDirectional.centerStart,
        );
      ''');
      expect(r.issues, isNotEmpty);
      expect(r.issues.first.message, contains('Alignment(x, y)'));
      expect(r.issues.first.message, isNot(contains('another file')));
    });
  });

  group('double-list const sources report diagnostics', () {
    for (final sink in _doubleListSinks) {
      test('the ${sink.name} gradient path refuses a const stops list',
          () async {
        final r = await _locatedResult(
          translator,
          _gradientSource(
            sink.constructor,
            'kStops',
            declaration: 'const List<double> kStops = [0, 1];',
          ),
        );
        _expectDoubleListRefusal(
          r,
          message: _constDoubleListMessage,
          location: '$_doubleListSourcePath:3:15',
        );
      });
    }

    test('the structured path refuses a parenthesized const list', () async {
      final r = await _result(translator, '''
        $_flutterImport
        const List<double> kStops = [0, 1];
        Object x() => LinearGradient(
          colors: [Colors.red, Colors.red],
          stops: (kStops),
        );
      ''');
      expect(r.dsl, isNot(contains('stops: [0, 1]')));
      expect(r.issues, isNotEmpty);
    });

    test('the recipe path refuses a parenthesized const list', () async {
      final r = await _result(translator, '''
        $_flutterImport
        const List<double> kStops = [0, 1];
        Object x() => RadialGradient(
          colors: [Colors.red, Colors.red],
          stops: (kStops),
        );
      ''');
      expect(r.dsl, isNot(contains('stops: [0, 1]')));
      expect(r.issues, isNotEmpty);
    });

    test('the structured path coerces a literal int list', () async {
      final r = await _result(translator, '''
        $_flutterImport
        Object x() => LinearGradient(
          colors: [Colors.red, Colors.red],
          stops: [0, 1],
        );
      ''');
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('stops: [0.0, 1.0]'));
    });

    test('the recipe path coerces a literal int list', () async {
      final r = await _result(translator, '''
        $_flutterImport
        Object x() => RadialGradient(
          colors: [Colors.red, Colors.red],
          stops: [0, 1],
        );
      ''');
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('stops: [0.0, 1.0]'));
    });

    test('the structured path coerces a parenthesized int list', () async {
      final r = await _result(translator, '''
        $_flutterImport
        Object x() => LinearGradient(
          colors: [Colors.red, Colors.red],
          stops: ([0, 1]),
        );
      ''');
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('stops: [0.0, 1.0]'));
      expect(r.dsl, isNot(contains('stops: [0, 1]')));
    });

    test('the recipe path coerces a parenthesized int list', () async {
      final r = await _result(translator, '''
        $_flutterImport
        Object x() => RadialGradient(
          colors: [Colors.red, Colors.red],
          stops: ([0, 1]),
        );
      ''');
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('stops: [0.0, 1.0]'));
      expect(r.dsl, isNot(contains('stops: [0, 1]')));
    });

    for (final sink in _doubleListSinks) {
      test('the ${sink.name} path coerces a list inside 255 parentheses',
          () async {
        final r = await _locatedResult(
          translator,
          _gradientSource(sink.constructor, _parenthesizedStops(255)),
        );
        expect(r.issues, isEmpty);
        expect(r.dsl, _gradientDsl(sink.wireType));
      });

      for (final count in const [256, 257]) {
        test('the ${sink.name} path refuses a list inside $count parentheses',
            () async {
          final r = await _locatedResult(
            translator,
            _gradientSource(sink.constructor, _parenthesizedStops(count)),
          );
          _expectDoubleListRefusal(
            r,
            message: _depthDoubleListMessage,
            location: '$_doubleListSourcePath:2:15',
          );
        });
      }
    }

    test('a structured explicit const list matches non-const bytes', () async {
      final ordinary = await _result(translator, '''
        $_flutterImport
        Object x() => LinearGradient(
          colors: [Colors.red, Colors.red],
          stops: [0, 1],
        );
      ''');
      final explicitConst = await _result(translator, '''
        $_flutterImport
        Object x() => LinearGradient(
          colors: [Colors.red, Colors.red],
          stops: const [0, 1],
        );
      ''');
      expect(ordinary.issues, isEmpty);
      expect(
        ordinary.dsl,
        '{type: "linear", colors: [0xFFF44336, 0xFFF44336], '
        'stops: [0.0, 1.0]}',
      );
      expect(explicitConst.issues, isEmpty);
      expect(explicitConst.dsl, ordinary.dsl);
    });

    test('a recipe explicit const list matches non-const bytes', () async {
      final ordinary = await _result(translator, '''
        $_flutterImport
        Object x() => RadialGradient(
          colors: [Colors.red, Colors.red],
          stops: [0, 1],
        );
      ''');
      final explicitConst = await _result(translator, '''
        $_flutterImport
        Object x() => RadialGradient(
          colors: [Colors.red, Colors.red],
          stops: const [0, 1],
        );
      ''');
      expect(ordinary.issues, isEmpty);
      expect(
        ordinary.dsl,
        '{type: "radial", colors: [0xFFF44336, 0xFFF44336], '
        'stops: [0.0, 1.0]}',
      );
      expect(explicitConst.issues, isEmpty);
      expect(explicitConst.dsl, ordinary.dsl);
    });

    for (final sink in _doubleListSinks) {
      test('the ${sink.name} path refuses a conditional list', () async {
        final r = await _locatedResult(
          translator,
          _gradientSource(
            sink.constructor,
            'true ? [0, 1] : [1, 0]',
          ),
        );
        _expectDoubleListRefusal(
          r,
          message: _conditionalDoubleListMessage,
          location: '$_doubleListSourcePath:2:15',
        );
      });
    }

    test('the structured path refuses a diagnosed list element', () async {
      final r = await _result(translator, '''
        $_flutterImport
        Object x() => LinearGradient(
          colors: [Colors.red, Colors.red],
          stops: [0, Colors.teal],
        );
      ''');
      _expectDoubleListRefusal(r, code: IssueCode.unresolvedIdentifier);
    });

    test('the recipe path refuses a diagnosed list element', () async {
      final r = await _result(translator, '''
        $_flutterImport
        Object x() => RadialGradient(
          colors: [Colors.red, Colors.red],
          stops: [0, Colors.teal],
        );
      ''');
      _expectDoubleListRefusal(r, code: IssueCode.unresolvedIdentifier);
    });

    test('the structured path refuses a const conditional list', () async {
      final r = await _result(translator, '''
        $_flutterImport
        const bool usePrimary = true;
        const List<double> kStops =
            usePrimary ? [0, 1] : [1, 0];
        Object x() => LinearGradient(
          colors: [Colors.red, Colors.red],
          stops: kStops,
        );
      ''');
      _expectDoubleListRefusal(r);
    });

    test('the recipe path refuses a const conditional list', () async {
      final r = await _result(translator, '''
        $_flutterImport
        const bool usePrimary = true;
        const List<double> kStops =
            usePrimary ? [0, 1] : [1, 0];
        Object x() => RadialGradient(
          colors: [Colors.red, Colors.red],
          stops: kStops,
        );
      ''');
      _expectDoubleListRefusal(r);
    });

    test('the structured path refuses collection flow', () async {
      final r = await _result(translator, '''
        $_flutterImport
        Object x() => LinearGradient(
          colors: [Colors.red, Colors.red],
          stops: [0, if (true) 1],
        );
      ''');
      _expectDoubleListRefusal(
        r,
        code: IssueCode.unsupportedCollectionFlow,
      );
      expect(r.issues.single.message, contains('double-decoded list slot'));
    });

    test('the recipe path refuses collection flow', () async {
      final r = await _result(translator, '''
        $_flutterImport
        Object x() => RadialGradient(
          colors: [Colors.red, Colors.red],
          stops: [0, if (true) 1],
        );
      ''');
      _expectDoubleListRefusal(
        r,
        code: IssueCode.unsupportedCollectionFlow,
      );
      expect(r.issues.single.message, contains('double-decoded list slot'));
    });

    test('the structured path refuses a direct source cycle', () async {
      final r = await _result(translator, '''
        $_flutterImport
        const List<double> stops = stops;
        Object x() => LinearGradient(
          colors: [Colors.red, Colors.red],
          stops: stops,
        );
      ''');
      _expectDoubleListRefusal(r);
      expect(r.issues.single.message, contains('cyclic list binding'));
    });

    test('the recipe path refuses a direct source cycle', () async {
      final r = await _result(translator, '''
        $_flutterImport
        const List<double> stops = stops;
        Object x() => RadialGradient(
          colors: [Colors.red, Colors.red],
          stops: stops,
        );
      ''');
      _expectDoubleListRefusal(r);
      expect(r.issues.single.message, contains('cyclic list binding'));
    });

    test('the structured path refuses a mutual source cycle', () async {
      final r = await _result(translator, '''
        $_flutterImport
        const List<double> first = second;
        const List<double> second = first;
        Object x() => LinearGradient(
          colors: [Colors.red, Colors.red],
          stops: first,
        );
      ''');
      _expectDoubleListRefusal(r);
      expect(r.issues.single.message, contains('cyclic list binding'));
    });

    test('the recipe path refuses a mutual source cycle', () async {
      final r = await _result(translator, '''
        $_flutterImport
        const List<double> first = second;
        const List<double> second = first;
        Object x() => RadialGradient(
          colors: [Colors.red, Colors.red],
          stops: first,
        );
      ''');
      _expectDoubleListRefusal(r);
      expect(r.issues.single.message, contains('cyclic list binding'));
    });
  });

  group('const declaration cycles fail closed', () {
    test('a self-cycle reports a located direct-reference diagnostic',
        () async {
      final r = await _result(
        translator,
        'const Object value = value; Object x() => value;',
      );
      expect(r.dsl, isEmpty);
      expect(r.issues.map((i) => i.code), [IssueCode.unrecognizedMethodCall]);
      expect(r.issues.single.message, contains('cyclic'));
      expect(r.issues.single.location, isNotEmpty);
    });

    test('a mutual static-field cycle stops on a prefixed reference', () async {
      final r = await _result(translator, '''
        class Tokens {
          static const Object first = Tokens.second;
          static const Object second = Tokens.first;
        }
        Object x() => Tokens.first;
      ''');
      expect(r.dsl, isEmpty);
      expect(r.issues.map((i) => i.code), [IssueCode.unresolvedIdentifier]);
      expect(r.issues.single.message, contains('cyclic'));
      expect(r.issues.single.location, isNotEmpty);
    });

    test('a mutual cycle at a property slot emits no value', () async {
      final r = await _result(translator, '''
        $_flutterImport
        const Color first = second;
        const Color second = first;
        Object x() => Icon(color: first);
      ''');
      expect(r.dsl, isNot(contains('0x')));
      expect(r.issues.single.message, contains('cyclic'));
      expect(r.issues.single.location, isNotEmpty);
    });
  });

  group('a name collision resolves to the identifier binding', () {
    test(
        'a constructor parameter in scope wins over a same-named top-level '
        'const', () async {
      const cardKey = 'package:apps_examples/_expr_probe.dart#AcmeCard';
      // The field is in scope inside the body, so Dart binds `brand` to it.
      final body = await parseExpressionFromSourceForTest(
        '''
        $_flutterImport
        const Color brand = Color(0xFF37B6FF);
        class AcmeCard {
          const AcmeCard({this.brand});
          final Color? brand;
          Object x() => Icon(color: brand);
        }
      ''',
        rootPackage: 'apps_examples',
        enclosingClassName: 'AcmeCard',
      );
      final t = ExpressionTranslator(
        catalog: _slotCatalog(),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          cardKey: ComposableWidget(
            cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          cardKey: CustomWidgetBlueprint(
            classKey: cardKey,
            rfwName: 'AcmeCard',
            buildExpression: body,
            params: const [
              CustomWidgetParam(
                name: 'brand',
                isNumeric: false,
                defaultValue: null,
              ),
            ],
          ),
        },
      );
      final result = t.translate(
        await parseExpressionFromSourceForTest(
          '''
          $_flutterImport
          class AcmeCard {
            const AcmeCard({this.brand});
            final Color? brand;
          }
          Object x() => AcmeCard(brand: Color(0xFF000000));
        ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(result.issues, isEmpty);
      expect(result.widgetDefinitions['AcmeCard'], 'Icon(color: args.brand)');
    });

    test('a top-level const wins where no parameter is in scope', () async {
      const cardKey = 'package:apps_examples/_expr_probe.dart#AcmeCard';
      // A State body reaches constructor parameters only via `widget.X`, so a
      // bare `brand` here is the const and must emit its value.
      final body = await parseExpressionFromSourceForTest(
        '''
        $_flutterImport
        const Color brand = Color(0xFF37B6FF);
        Object x() => Icon(color: brand);
      ''',
        rootPackage: 'apps_examples',
      );
      final t = ExpressionTranslator(
        catalog: _slotCatalog(),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          cardKey: ComposableWidget(
            cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          cardKey: CustomWidgetBlueprint(
            classKey: cardKey,
            rfwName: 'AcmeCard',
            buildExpression: body,
            params: const [
              CustomWidgetParam(
                name: 'brand',
                isNumeric: false,
                defaultValue: null,
              ),
            ],
          ),
        },
      );
      final result = t.translate(
        await parseExpressionFromSourceForTest(
          '''
          $_flutterImport
          class AcmeCard {
            const AcmeCard({this.brand});
            final Color? brand;
          }
          Object x() => AcmeCard(brand: Color(0xFF000000));
        ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(result.issues, isEmpty);
      expect(result.widgetDefinitions['AcmeCard'], 'Icon(color: 0xFF37B6FF)');
      expect(result.widgetDefinitions['AcmeCard'], isNot(contains('args.')));
    });
  });

  group('a substituted initializer is translated in declaration scope', () {
    // Initializer identifiers resolve in the declaration's source scope.
    const cardKey = 'package:apps_examples/_expr_probe.dart#AcmeCard';

    Future<Map<String, String>> definitionsFor(
      String paramName, {
      List<CustomWidgetStateField>? state,
      Map<String, RecognisedSetState> eventHandlers = const {},
    }) async {
      final body = await parseExpressionFromSourceForTest(
        '''
        $_flutterImport
        const Color kBase = Color(0xFF37B6FF);
        const Color kBrand = kBase;
        Object x() => Icon(color: kBrand);
      ''',
        rootPackage: 'apps_examples',
      );
      final t = ExpressionTranslator(
        catalog: _slotCatalog(),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          cardKey: ComposableWidget(
            cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          cardKey: CustomWidgetBlueprint(
            classKey: cardKey,
            rfwName: 'AcmeCard',
            buildExpression: body,
            params: [
              CustomWidgetParam(
                name: paramName,
                isNumeric: false,
                defaultValue: null,
              ),
            ],
            state: state,
            eventHandlers: eventHandlers,
          ),
        },
      );
      final result = t.translate(
        await parseExpressionFromSourceForTest(
          '''
          $_flutterImport
          class AcmeCard {
            const AcmeCard({this.$paramName});
            final Color? $paramName;
          }
          Object x() => AcmeCard($paramName: Color(0xFF000000));
        ''',
          rootPackage: 'apps_examples',
        ),
      );
      expect(result.issues, isEmpty, reason: '${result.issues}');
      return result.widgetDefinitions;
    }

    test('an alias chain colliding with an argument name emits the value',
        () async {
      final definitions = await definitionsFor('kBase');
      expect(definitions['AcmeCard'], 'Icon(color: 0xFF37B6FF)');
      expect(definitions['AcmeCard'], isNot(contains('args.')));
    });

    test('an alias chain colliding with a State field emits the value',
        () async {
      final definitions = await definitionsFor(
        'tint',
        state: const [
          CustomWidgetStateField(
            name: 'kBase',
            isNumeric: false,
            initialValue: false,
          ),
        ],
      );
      expect(definitions['AcmeCard'], 'Icon(color: 0xFF37B6FF)');
      expect(definitions['AcmeCard'], isNot(contains('state.')));
    });

    test('an alias chain colliding with an event handler emits the value',
        () async {
      final definitions = await definitionsFor(
        'tint',
        state: const [
          CustomWidgetStateField(
            name: 'flag',
            isNumeric: false,
            initialValue: false,
          ),
        ],
        eventHandlers: const {
          'kBase': SetStateLiteral(fieldName: 'flag', value: true),
        },
      );
      expect(definitions['AcmeCard'], 'Icon(color: 0xFF37B6FF)');
      expect(definitions['AcmeCard'], isNot(contains('event ')));
      expect(definitions['AcmeCard'], isNot(contains('set state.')));
    });

    test('an unrelated argument name leaves the same fold untouched', () async {
      final definitions = await definitionsFor('tint');
      expect(definitions['AcmeCard'], 'Icon(color: 0xFF37B6FF)');
    });

    test('a root State widget-prefix collision emits the declaration value',
        () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        $_flutterImport
        class widget { static const Color brand = Color(0xFF37B6FF); }
        const Color kBrand = widget.brand;
        Object x() => [kBrand];
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(
        expr,
        rootState: const [
          CustomWidgetStateField(
            name: 'active',
            isNumeric: false,
            initialValue: false,
          ),
        ],
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '[0xFF37B6FF]');
    });

    test('a const initializer cannot borrow a coalesced parameter scope',
        () async {
      final body = await parseExpressionFromSourceForTest(
        '''
        $_flutterImport
        const Color? color = null;
        const Color kBrand = color ?? Color(0xFF37B6FF);
        Object x() => Icon(color: kBrand);
        ''',
        rootPackage: 'apps_examples',
      );
      final fallback = await parseExpressionFromSourceForTest(
        '$_flutterImport Object x() => const Color(0xFF000000);',
        rootPackage: 'apps_examples',
      );
      final t = ExpressionTranslator(
        catalog: _slotCatalog(),
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          cardKey: ComposableWidget(
            cardKey,
            requiredMechanisms: const {},
            composedCustomWidgets: const [],
          ),
        },
        customWidgetBlueprints: {
          cardKey: CustomWidgetBlueprint(
            classKey: cardKey,
            rfwName: 'AcmeCard',
            buildExpression: body,
            params: [
              CustomWidgetParam(
                name: 'color',
                isNumeric: false,
                defaultValue: null,
                coalesceFallback: fallback,
              ),
            ],
          ),
        },
      );
      final r = await _result(t, '''
        $_flutterImport
        class AcmeCard {
          const AcmeCard({this.color});
          final Color? color;
        }
        Object x() => AcmeCard(color: Color(0xFF000000));
      ''');
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      expect(r.widgetDefinitions['AcmeCard'], isNot(contains('args.color')));
    });

    test('nested substitutions restore the root State namespace', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        $_flutterImport
        class widget {
          static const Color first = Color(0xFF111111);
          static const Color second = Color(0xFF222222);
        }
        const Color kInner = widget.first;
        const Color kOuter = kInner;
        Object x() => [kOuter, widget.second];
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(
        expr,
        rootState: const [
          CustomWidgetStateField(
            name: 'active',
            isNumeric: false,
            initialValue: false,
          ),
        ],
      );
      expect(r.dsl, startsWith('[0xFF111111'));
      expect(r.dsl, isNot(contains('0xFF222222')));
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.stateShapeUnsupported),
      );
    });

    test('a throwing substitution restores the next translation', () async {
      var throwFromFrameworkCheck = true;
      final t = ExpressionTranslator.forTesting(
        catalog: _slotCatalog(),
        helpers: HelperRegistry(),
        frameworkLibraryPredicate: (element) {
          if (throwFromFrameworkCheck) {
            throwFromFrameworkCheck = false;
            throw StateError('framework probe');
          }
          return syntheticFrameworkLibrary(element);
        },
      );
      final throwing = await parseExpressionFromSourceForTest(
        '''
        $_flutterImport
        const Color kBrand = Color(0xFF37B6FF);
        Object x() => kBrand;
        ''',
        rootPackage: 'apps_examples',
      );
      expect(() => t.translate(throwing), throwsStateError);

      final next = await parseExpressionFromSourceForTest(
        '''
        $_flutterImport
        class widget { static const Color brand = Color(0xFF00FF00); }
        Object x() => widget.brand;
        ''',
        rootPackage: 'apps_examples',
      );
      final r = t.translate(
        next,
        rootState: const [
          CustomWidgetStateField(
            name: 'active',
            isNumeric: false,
            initialValue: false,
          ),
        ],
      );
      expect(r.dsl, isNot(contains('0xFF00FF00')));
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.stateShapeUnsupported),
      );
    });
  });

  group('const identifiers translate in every supported position', () {
    test('one const identifier lowers identically at four positions', () async {
      const decl = 'const Color _blue = Color(0xFF37B6FF);';
      final bare = await _dsl(translator, '''
        $_flutterImport
        $decl
        Object x() => _blue;
      ''');
      final slot = await _dsl(translator, '''
        $_flutterImport
        $decl
        Object x() => Icon(color: _blue);
      ''');
      final nestedConst = await _dsl(translator, '''
        $_flutterImport
        $decl
        Object x() => const SizedBox(child: Icon(color: _blue));
      ''');
      final nestedRuntime = await _dsl(translator, '''
        $_flutterImport
        $decl
        Object x() => SizedBox(child: Tile(color: _blue, child: SizedBox()));
      ''');
      expect(bare, '0xFF37B6FF');
      for (final dsl in [slot, nestedConst, nestedRuntime]) {
        expect(dsl, contains('0xFF37B6FF'));
      }
    });
  });
}

void _classifierGroups() {
  Catalog iconCatalog() => catalogWith([
        entry(
          name: 'Icon',
          properties: [prop('color', PropertyType.color)],
          flutterType: 'package:apps_examples/palette_widget.dart#Icon',
        ),
      ]);

  group('classification matches translation capabilities', () {
    test('a resolved Alignment const classifies and emits coordinates',
        () async {
      final classification = await classifyFixture(
        {
          'lib/alignment_widget.dart': '''
$kFlutterClassifierStubs

const Alignment kAnchor = Alignment.topLeft;

class AnchorBox extends StatelessWidget {
  const AnchorBox({this.alignment, super.key});
  final Alignment? alignment;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeAnchor',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'anchor',
)
class AcmeAnchor extends StatelessWidget {
  const AcmeAnchor({super.key});
  @override
  Widget build(BuildContext context) =>
      AnchorBox(alignment: kAnchor);
}
''',
        },
        inputPath: 'lib/alignment_widget.dart',
        widgetName: 'AcmeAnchor',
        catalog: catalogWith([
          entry(
            name: 'AnchorBox',
            properties: [prop('alignment', PropertyType.alignmentXY)],
            flutterType:
                'package:apps_examples/alignment_widget.dart#AnchorBox',
          ),
        ]),
      );
      expect(classification, isA<ComposableWidget>());

      final translated = await _result(
        ExpressionTranslator(
          catalog: _slotCatalog(),
          helpers: HelperRegistry(),
        ),
        '''
          $_flutterImport
          const Alignment kAnchor = Alignment.topLeft;
          Object x() => Tile(
            alignment: kAnchor,
            child: const SizedBox(),
          );
        ''',
      );
      expect(translated.issues, isEmpty);
      expect(translated.dsl, contains('alignment: {x: -1.0, y: -1.0}'));
    });

    test('an unsupported Alignment member remains unclassifiable and diagnosed',
        () async {
      final classification = await classifyFixture(
        {
          'lib/alignment_widget.dart': '''
$kFlutterClassifierStubs

class AnchorBox extends StatelessWidget {
  const AnchorBox({this.alignment, super.key});
  final Object? alignment;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeAnchor',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'anchor',
)
class AcmeAnchor extends StatelessWidget {
  const AcmeAnchor({super.key});
  @override
  Widget build(BuildContext context) =>
      AnchorBox(alignment: Alignment.lerp);
}
''',
        },
        inputPath: 'lib/alignment_widget.dart',
        widgetName: 'AcmeAnchor',
        catalog: catalogWith([
          entry(
            name: 'AnchorBox',
            properties: [prop('alignment', PropertyType.alignmentXY)],
            flutterType:
                'package:apps_examples/alignment_widget.dart#AnchorBox',
          ),
        ]),
      );
      expect(classification, isA<UnclassifiableWidget>());

      final translated = await _result(
        ExpressionTranslator(
          catalog: _slotCatalog(),
          helpers: HelperRegistry(),
        ),
        '''
          $_flutterImport
          Object x() => Tile(
            alignment: Alignment.lerp,
            child: const SizedBox(),
          );
        ''',
      );
      expect(
        translated.issues.map((issue) => issue.code),
        [IssueCode.unresolvedIdentifier],
      );
      expect(translated.issues.single.message, contains('Alignment.lerp'));
      expect(translated.issues.single.location, isNotEmpty);
    });

    test('an aliased framework Alignment const remains unclassifiable',
        () async {
      // The translator lowers on the prefix, which an alias hides, so
      // classification must refuse rather than promise a lowering.
      final classification = await classifyFixture(
        {
          'lib/alignment_widget.dart': '''
$kFlutterClassifierStubs

typedef Anchor = Alignment;

class AnchorBox extends StatelessWidget {
  const AnchorBox({this.alignment, super.key});
  final Alignment? alignment;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeAnchor',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'anchor',
)
class AcmeAnchor extends StatelessWidget {
  const AcmeAnchor({super.key});
  @override
  Widget build(BuildContext context) =>
      AnchorBox(alignment: Anchor.center);
}
''',
        },
        inputPath: 'lib/alignment_widget.dart',
        widgetName: 'AcmeAnchor',
        catalog: catalogWith([
          entry(
            name: 'AnchorBox',
            properties: [prop('alignment', PropertyType.alignmentXY)],
            flutterType:
                'package:apps_examples/alignment_widget.dart#AnchorBox',
          ),
        ]),
      );
      expect(classification, isA<UnclassifiableWidget>());
    });

    test('an application-defined Alignment const remains unclassifiable',
        () async {
      const alignment = '''
class Alignment {
  const Alignment(this.x, this.y);
  final double x;
  final double y;
  static const Alignment topLeft = Alignment(-1.0, -1.0);
}
''';
      final classification = await classifyFixture(
        {
          'lib/alignment_widget.dart': '''
$kClassifierStubs
$alignment

class AnchorBox extends StatelessWidget {
  const AnchorBox({this.alignment});
  final Alignment? alignment;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeAnchor',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'anchor',
)
class AcmeAnchor extends StatelessWidget {
  const AcmeAnchor();
  Widget build(BuildContext context) =>
      AnchorBox(alignment: Alignment.topLeft);
}
''',
        },
        inputPath: 'lib/alignment_widget.dart',
        widgetName: 'AcmeAnchor',
        catalog: catalogWith([
          entry(
            name: 'AnchorBox',
            properties: [prop('alignment', PropertyType.alignmentXY)],
            flutterType:
                'package:apps_examples/alignment_widget.dart#AnchorBox',
          ),
        ]),
      );
      expect(classification, isA<UnclassifiableWidget>());

      final translated = await _result(
        ExpressionTranslator(
          catalog: _slotCatalog(),
          helpers: HelperRegistry(),
        ),
        '''
          import 'package:flutter/material.dart' show SizedBox;
          $alignment
          Object x() => Tile(
            alignment: Alignment.topLeft,
            child: const SizedBox(),
          );
        ''',
      );
      expect(translated.dsl, isEmpty);
      _expectReservedOwnerRefusal(translated, 'Alignment');
    });

    test('a foldable const identifier marks constantFolding (transpilable)',
        () async {
      final result = await classifyFixture(
        {
          'lib/palette_widget.dart': '''
$kClassifierStubs

class Color { const Color(this.value); final int value; }
const Color kBrand = Color(0xFF37B6FF);

class Icon extends StatelessWidget {
  const Icon({this.color});
  final Color? color;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmePalette',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'palette',
)
class AcmePalette extends StatelessWidget {
  const AcmePalette();
  Widget build(BuildContext context) => Icon(color: kBrand);
}
''',
        },
        inputPath: 'lib/palette_widget.dart',
        widgetName: 'AcmePalette',
        catalog: iconCatalog(),
      );
      expect(result, isA<ComposableWidget>());
      expect(
        (result as ComposableWidget).requiredMechanisms,
        contains(InliningMechanism.constantFolding),
      );
    });

    test('a framework-named look-alike const is unclassifiable', () async {
      final result = await classifyFixture(
        {
          'lib/palette_widget.dart': '''
$kClassifierStubs

class Alignment {
  const Alignment(this.x, this.y);
  final double x;
  final double y;
  static const Alignment topLeft = Alignment(-1.0, -1.0);
}

class Icon extends StatelessWidget {
  const Icon({this.color});
  final Object? color;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeLookalike',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'lookalike',
)
class AcmeLookalike extends StatelessWidget {
  const AcmeLookalike();
  Widget build(BuildContext context) => Icon(color: Alignment.topLeft);
}
''',
        },
        inputPath: 'lib/palette_widget.dart',
        widgetName: 'AcmeLookalike',
        catalog: iconCatalog(),
      );
      expect(result, isA<UnclassifiableWidget>());
    });

    test('a framework-named scalar owner is composable', () async {
      final result = await classifyFixture(
        {
          'lib/palette_widget.dart': '''
$kClassifierStubs

class Alignment { static const double gap = 7; }

class GapBox extends StatelessWidget {
  const GapBox({this.gap});
  final double? gap;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeSpacing',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'spacing',
)
class AcmeSpacing extends StatelessWidget {
  const AcmeSpacing();
  Widget build(BuildContext context) => GapBox(gap: Alignment.gap);
}
''',
        },
        inputPath: 'lib/palette_widget.dart',
        widgetName: 'AcmeSpacing',
        catalog: catalogWith([
          entry(
            name: 'GapBox',
            properties: [prop('gap', PropertyType.real)],
            flutterType: 'package:apps_examples/palette_widget.dart#GapBox',
          ),
        ]),
      );
      expect(result, isA<ComposableWidget>());
      expect(
        (result as ComposableWidget).requiredMechanisms,
        contains(InliningMechanism.constantFolding),
      );
    });

    test('a framework-named look-alike cannot compose its const initializer',
        () async {
      const outerKey =
          'package:apps_examples/palette_widget.dart#AcmeLookalike';
      const pillKey = 'package:apps_examples/palette_widget.dart#AcmePill';
      final probe = await classifyFixtureResult(
        {
          'lib/palette_widget.dart': '''
$kClassifierStubs

class Icon extends StatelessWidget {
  const Icon();
  Widget build(BuildContext context) => const Widget();
}

class Colors { static const Widget red = AcmePill(); }

@RestageWidget(
  name: 'AcmePill',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'pill',
)
class AcmePill extends StatelessWidget {
  const AcmePill();
  Widget build(BuildContext context) => const Icon();
}

@RestageWidget(
  name: 'AcmeLookalike',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'lookalike',
)
class AcmeLookalike extends StatelessWidget {
  const AcmeLookalike();
  Widget build(BuildContext context) => Colors.red;
}
''',
        },
        inputPath: 'lib/palette_widget.dart',
        widgetName: 'AcmeLookalike',
        catalog: iconCatalog(),
      );
      final classification = probe.classifications[outerKey]!;
      final mechanisms = classification is ComposableWidget
          ? classification.requiredMechanisms
          : const <InliningMechanism>{};
      final edges = classification is ComposableWidget
          ? classification.composedCustomWidgets
          : const <String>[];
      expect(classification, isA<UnclassifiableWidget>());
      expect(mechanisms, isNot(contains(InliningMechanism.constantFolding)));
      expect(edges, isNot(contains(pillKey)));
      expect(probe.blueprints, isNot(contains(outerKey)));
    });

    test('an unqualified look-alike field cannot compose its initializer',
        () async {
      const ownerKey = 'package:apps_examples/palette_widget.dart#Colors';
      const pillKey = 'package:apps_examples/palette_widget.dart#AcmePill';
      final probe = await classifyFixtureResult(
        {
          'lib/palette_widget.dart': '''
$kClassifierStubs

class Icon extends StatelessWidget {
  const Icon();
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
  Widget build(BuildContext context) => const Icon();
}

@RestageWidget(
  name: 'AcmeColors',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'colors',
)
class Colors extends StatelessWidget {
  const Colors();
  static const Widget red = AcmePill();
  Widget build(BuildContext context) => red;
}
''',
        },
        inputPath: 'lib/palette_widget.dart',
        widgetName: 'Colors',
        catalog: iconCatalog(),
      );
      final classification = probe.classifications[ownerKey];
      final edges = classification is ComposableWidget
          ? classification.composedCustomWidgets
          : const <String>[];
      expect(classification, isA<UnclassifiableWidget>());
      expect(edges, isNot(contains(pillKey)));
      expect(probe.blueprints, isNot(contains(ownerKey)));
    });

    test('a typedef alias cannot hide a look-alike owner from classification',
        () async {
      const outerKey = 'package:apps_examples/palette_widget.dart#AcmeOuter';
      const pillKey = 'package:apps_examples/palette_widget.dart#AcmePill';
      final probe = await classifyFixtureResult(
        {
          'lib/palette_widget.dart': '''
$kClassifierStubs

class Icon extends StatelessWidget {
  const Icon();
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
  Widget build(BuildContext context) => const Icon();
}

class Colors { static const Widget red = AcmePill(); }
typedef Palette = Colors;

@RestageWidget(
  name: 'AcmeOuter',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'outer',
)
class AcmeOuter extends StatelessWidget {
  const AcmeOuter();
  Widget build(BuildContext context) => Palette.red;
}
''',
        },
        inputPath: 'lib/palette_widget.dart',
        widgetName: 'AcmeOuter',
        catalog: iconCatalog(),
      );
      final classification = probe.classifications[outerKey];
      final edges = classification is ComposableWidget
          ? classification.composedCustomWidgets
          : const <String>[];
      expect(classification, isA<UnclassifiableWidget>());
      expect(edges, isNot(contains(pillKey)));
      expect(probe.blueprints, isNot(contains(outerKey)));
    });

    test('a genuine framework owner is composable', () async {
      final result = await classifyFixture(
        {
          'lib/palette_widget.dart': '''
import 'package:flutter/material.dart' show Color, Colors;
$kClassifierStubs

class Icon extends StatelessWidget {
  const Icon({this.color});
  final Color? color;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeOuter',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'outer',
)
class AcmeOuter extends StatelessWidget {
  const AcmeOuter();
  Widget build(BuildContext context) => Icon(color: Colors.red);
}
''',
        },
        inputPath: 'lib/palette_widget.dart',
        widgetName: 'AcmeOuter',
        catalog: iconCatalog(),
      );
      expect(result, isA<ComposableWidget>());
    });

    test('an unrelated const owner is composable and records its edge',
        () async {
      const outerKey = 'package:apps_examples/palette_widget.dart#AcmeOuter';
      const pillKey = 'package:apps_examples/palette_widget.dart#AcmePill';
      final probe = await classifyFixtureResult(
        {
          'lib/palette_widget.dart': '''
$kClassifierStubs

class Icon extends StatelessWidget {
  const Icon();
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
  Widget build(BuildContext context) => const Icon();
}

class Palette { static const Widget red = AcmePill(); }

@RestageWidget(
  name: 'AcmeOuter',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'outer',
)
class AcmeOuter extends StatelessWidget {
  const AcmeOuter();
  Widget build(BuildContext context) => Palette.red;
}
''',
        },
        inputPath: 'lib/palette_widget.dart',
        widgetName: 'AcmeOuter',
        catalog: iconCatalog(),
      );
      final classification = probe.classifications[outerKey];
      expect(classification, isA<ComposableWidget>());
      expect(
        (classification! as ComposableWidget).composedCustomWidgets,
        contains(pillKey),
      );
    });

    test('a const custom-widget construction records its composed edge',
        () async {
      const outerKey = 'package:apps_examples/palette_widget.dart#AcmeOuter';
      const pillKey = 'package:apps_examples/palette_widget.dart#AcmePill';
      final probe = await classifyFixtureResult(
        {
          'lib/palette_widget.dart': '''
$kClassifierStubs

class Icon extends StatelessWidget {
  const Icon();
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
  Widget build(BuildContext context) => const Icon();
}

const Widget kPill = AcmePill();

@RestageWidget(
  name: 'AcmeOuter',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'outer',
)
class AcmeOuter extends StatelessWidget {
  const AcmeOuter();
  Widget build(BuildContext context) => kPill;
}
''',
        },
        inputPath: 'lib/palette_widget.dart',
        widgetName: 'AcmeOuter',
        catalog: iconCatalog(),
      );
      final classification = probe.classifications[outerKey];
      expect(classification, isA<ComposableWidget>());
      final composable = classification! as ComposableWidget;
      expect(
        composable.requiredMechanisms,
        contains(InliningMechanism.constantFolding),
      );
      expect(composable.composedCustomWidgets, contains(pillKey));
    });

    test('a const construction carries an imperative child classification',
        () async {
      final result = await classifyFixture(
        {
          'lib/palette_widget.dart': '''
$kClassifierStubs

class CustomPainter { const CustomPainter(); }
class CustomPaint extends StatelessWidget {
  const CustomPaint({this.painter});
  final CustomPainter? painter;
  Widget build(BuildContext context) => const Widget();
}
class ChartPainter extends CustomPainter { const ChartPainter(); }

@RestageWidget(
  name: 'AcmeChart',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'chart',
)
class AcmeChart extends StatelessWidget {
  const AcmeChart();
  Widget build(BuildContext context) =>
      CustomPaint(painter: ChartPainter());
}

const Widget kChart = AcmeChart();

@RestageWidget(
  name: 'AcmeOuter',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'outer',
)
class AcmeOuter extends StatelessWidget {
  const AcmeOuter();
  Widget build(BuildContext context) => kChart;
}
''',
        },
        inputPath: 'lib/palette_widget.dart',
        widgetName: 'AcmeOuter',
      );
      expect(result, isA<ImperativeWidget>());
      expect(
        (result as ImperativeWidget).blockers.first.kind,
        BlockerKind.composesImperativeWidget,
      );
    });

    test('an unsupported const value is unclassifiable', () async {
      final result = await classifyFixture(
        {
          'lib/palette_widget.dart': '''
$kClassifierStubs

class Token { const Token(); }
const Object kToken = Token();

class Label extends StatelessWidget {
  const Label({this.value});
  final Object? value;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeOuter',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'outer',
)
class AcmeOuter extends StatelessWidget {
  const AcmeOuter();
  Widget build(BuildContext context) => Label(value: kToken);
}
''',
        },
        inputPath: 'lib/palette_widget.dart',
        widgetName: 'AcmeOuter',
        catalog: catalogWith([
          entry(
            name: 'Label',
            properties: [prop('value', PropertyType.string)],
            flutterType: 'package:apps_examples/palette_widget.dart#Label',
          ),
        ]),
      );
      expect(result, isA<UnclassifiableWidget>());
    });

    test('a self-cyclic const is unclassifiable with no blueprint', () async {
      const outerKey = 'package:apps_examples/palette_widget.dart#AcmeOuter';
      final probe = await classifyFixtureResult(
        {
          'lib/palette_widget.dart': '''
$kClassifierStubs

const Widget value = value;

@RestageWidget(
  name: 'AcmeOuter',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'outer',
)
class AcmeOuter extends StatelessWidget {
  const AcmeOuter();
  Widget build(BuildContext context) => value;
}
''',
        },
        inputPath: 'lib/palette_widget.dart',
        widgetName: 'AcmeOuter',
      );
      expect(probe.classifications[outerKey], isA<UnclassifiableWidget>());
      expect(probe.blueprints, isNot(contains(outerKey)));
    });

    test('mutually cyclic consts are unclassifiable with no blueprint',
        () async {
      const outerKey = 'package:apps_examples/palette_widget.dart#AcmeOuter';
      final probe = await classifyFixtureResult(
        {
          'lib/palette_widget.dart': '''
$kClassifierStubs

const Widget first = second;
const Widget second = first;

@RestageWidget(
  name: 'AcmeOuter',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'outer',
)
class AcmeOuter extends StatelessWidget {
  const AcmeOuter();
  Widget build(BuildContext context) => first;
}
''',
        },
        inputPath: 'lib/palette_widget.dart',
        widgetName: 'AcmeOuter',
      );
      expect(probe.classifications[outerKey], isA<UnclassifiableWidget>());
      expect(probe.blueprints, isNot(contains(outerKey)));
    });

    test('an unfoldable cross-file const is unclassifiable', () async {
      final result = await classifyFixture(
        {
          'lib/palette_shared.dart': '''
class Color { const Color(this.value); final int value; }
const Color kSharedBrand = Color(0xFF37B6FF);
''',
          'lib/palette_widget.dart': '''
import 'package:apps_examples/palette_shared.dart';

$kClassifierStubs

class Icon extends StatelessWidget {
  const Icon({this.color});
  final Color? color;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCrossFile',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'cross-file',
)
class AcmeCrossFile extends StatelessWidget {
  const AcmeCrossFile();
  Widget build(BuildContext context) => Icon(color: kSharedBrand);
}
''',
        },
        inputPath: 'lib/palette_widget.dart',
        widgetName: 'AcmeCrossFile',
        catalog: iconCatalog(),
      );
      expect(result, isA<UnclassifiableWidget>());
    });
  });
}
