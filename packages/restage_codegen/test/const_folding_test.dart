import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Resolves [source] (which must define `Object x() => <expr>;`) and folds
/// the returned expression.
Future<Object?> _fold(String source) async =>
    tryFoldConstant(await parseExpressionFromSourceForTest(source));

Future<Object?> _scalar(String source) async =>
    tryFoldScalarConstant(await parseExpressionFromSourceForTest(source));

void main() {
  group('tryFoldConstant', () {
    test('folds an integer literal', () async {
      expect(await _fold('Object x() => 42;'), 42);
    });

    test('folds a const variable reference', () async {
      expect(
        await _fold('const double kGap = 16; Object x() => kGap;'),
        16.0,
      );
    });

    test('folds const arithmetic', () async {
      expect(
        await _fold('const int a = 4; const int b = 3; Object x() => a * b;'),
        12,
      );
    });

    test('folds a unary minus over a const', () async {
      expect(await _fold('const int g = 8; Object x() => -g;'), -8);
    });

    test('folds const string concatenation', () async {
      expect(
        await _fold(
          'const String a = "x"; const String b = "y"; Object x() => a + b;',
        ),
        'xy',
      );
    });

    test('returns null for a runtime value', () async {
      expect(await _fold('int counter = 0; Object x() => counter;'), isNull);
    });

    test('returns null for a non-arithmetic operator', () async {
      expect(
        await _fold('const int a = 4; const int b = 3; Object x() => a == b;'),
        isNull,
      );
    });

    test('returns null for an enum constant', () async {
      expect(await _fold('enum E { a, b } Object x() => E.a;'), isNull);
    });

    test('returns null for truncating division by zero (does not throw)',
        () async {
      expect(
        await _fold('const int a = 1; const int b = 0; Object x() => a ~/ b;'),
        isNull,
      );
    });

    test('returns null for modulo by zero (does not throw)', () async {
      expect(
        await _fold('const int a = 1; const int b = 0; Object x() => a % b;'),
        isNull,
      );
    });

    test('returns null for a non-finite division result', () async {
      // 1 / 0 is double.infinity — no valid RFW numeric literal.
      expect(
        await _fold('const int a = 1; const int b = 0; Object x() => a / b;'),
        isNull,
      );
    });

    test('returns null for a non-finite constant reference', () async {
      expect(
        await _fold('const double k = double.infinity; Object x() => k;'),
        isNull,
      );
    });

    test('returns null for an operation on a non-finite operand', () async {
      // `infinity ~/ 2` throws in Dart — a non-finite operand must be
      // rejected before the operation runs.
      expect(
        await _fold(
          'const double k = double.infinity; '
          'const int b = 2; Object x() => k ~/ b;',
        ),
        isNull,
      );
    });

    test('returns null for a non-finite double literal (overflow)', () async {
      // `1e400` parses to a non-finite double (Infinity). The `DoubleLiteral`
      // arm must filter it like its sibling fold arms (`decodeConstScalar`,
      // `_foldBinary`) so the state-field / setState path — which consumes
      // folds directly, bypassing the translator's emit guard — can never
      // capture a bare `Infinity`.
      expect(await _fold('Object x() => 1e400;'), isNull);
    });

    test('returns null for a negative non-finite double literal', () async {
      // `-1e400` folds through the unary-minus arm over the same non-finite
      // `DoubleLiteral`; the operand filter makes the whole expression null.
      expect(await _fold('Object x() => -1e400;'), isNull);
    });

    test('returns null for a String.fromEnvironment constant', () async {
      expect(
        await _fold(
          "const String flavor = String.fromEnvironment('FLAVOR'); "
          'Object x() => flavor;',
        ),
        isNull,
      );
    });

    test('returns null for an int.fromEnvironment constant', () async {
      expect(
        await _fold(
          "const int build = int.fromEnvironment('BUILD'); "
          'Object x() => build;',
        ),
        isNull,
      );
    });

    test('returns null for a bool.fromEnvironment constant', () async {
      expect(
        await _fold(
          "const bool verbose = bool.fromEnvironment('VERBOSE'); "
          'Object x() => verbose;',
        ),
        isNull,
      );
    });

    test('returns null for a bool.hasEnvironment constant', () async {
      expect(
        await _fold(
          "const bool declared = bool.hasEnvironment('FLAVOR'); "
          'Object x() => declared;',
        ),
        isNull,
      );
    });

    test('returns null for a constant derived from the build environment',
        () async {
      expect(
        await _fold(
          "const int build = int.fromEnvironment('BUILD'); "
          'const int next = build + 1; Object x() => next;',
        ),
        isNull,
      );
    });

    test('returns null for an operation over a build-environment operand',
        () async {
      expect(
        await _fold(
          "const int build = int.fromEnvironment('BUILD'); "
          'const int base = 2; Object x() => base + build;',
        ),
        isNull,
      );
    });

    test('still folds a const whose initializer names another plain const',
        () async {
      expect(
        await _fold(
          'const int base = 2; const int total = base + 3; '
          'Object x() => total;',
        ),
        5,
      );
    });
  });

  group('tryFoldScalarConstant', () {
    test('bound operands match inline scalar values and verdicts', () async {
      const skin = '''
class Skin {
  const Skin({required this.prefix});
  final String prefix;
}
const skin = Skin(prefix: 'restage');
''';
      final cases = <(String, String, String, Object?)>[
        (
          'string',
          'Object value(String p, String s) => p + s; '
              "Object x() => value('restage', 'Nav0');",
          "Object x() => 'restage' + 'Nav0';",
          'restageNav0',
        ),
        (
          'number',
          'Object value(int a, int b, int c) => a * b + c; '
              'Object x() => value(6, 7, 1);',
          'Object x() => 6 * 7 + 1;',
          43
        ),
        (
          'boolean',
          'Object value(bool enabled) => enabled; '
              'Object x() => value(true);',
          'Object x() => true;',
          true
        ),
        (
          'const object field',
          '$skin\nObject value(String p, String s) => p + s; '
              "Object x() => value(skin.prefix, 'Nav0');",
          "$skin\nObject x() => skin.prefix + 'Nav0';",
          'restageNav0'
        ),
        (
          'const object local receiver',
          '''
$skin
Object value() {
  final selected = skin;
  return selected.prefix + 'Nav0';
}
Object x() => value();''',
          "$skin\nObject x() => skin.prefix + 'Nav0';",
          'restageNav0'
        ),
        (
          'const object parameter receiver',
          '''
$skin
Object value(Skin selected) => selected.prefix + 'Nav0';
Object x() => value(skin);''',
          "$skin\nObject x() => skin.prefix + 'Nav0';",
          'restageNav0'
        ),
        (
          'conditional',
          "Object value(bool pick) => pick ? 'first' : 'second'; "
              'Object x() => value(true);',
          "Object x() => true ? 'first' : 'second';",
          null
        ),
        (
          'interpolation',
          r"Object value(String p) => '${p}Nav0'; "
              "Object x() => value('restage');",
          r"Object x() => '${'restage'}Nav0';",
          null
        ),
      ];
      for (final (name, boundSource, inlineSource, expected) in cases) {
        final probe = await _boundScalarProbe(boundSource);
        final bound = tryFoldScalarConstant(
          probe.expression,
          localBindings: probe.bindings,
        );
        final direct = await _scalar(inlineSource);
        expect((bound, direct), (expected, expected), reason: name);
      }
    });

    test('exposes a bound conditional without folding it', () async {
      final probe = await _boundScalarProbe(
        "Object value(bool pick) => pick ? 'continue' : 'restore'; "
        'Object x() => value(false);',
      );
      final inspection = inspectScalarConstant(
        probe.expression,
        localBindings: probe.bindings,
      );

      expect(inspection.complete, isTrue);
      expect(
        inspection.expression.toSource(),
        "pick ? 'continue' : 'restore'",
      );
      expect(inspection.value, isNull);
    });

    test('bounds a cyclic final-local binding', () async {
      final expression = await parseExpressionFromSourceForTest(
        "Object x() => (() { final value = 'ready'; return value; })();",
      );
      final collector = _LocalIdentifierCollector()..visit(expression);
      final identifier = collector.identifiers.singleWhere(
        (candidate) => candidate.element is LocalVariableElement,
      );
      final element = identifier.element;
      expect(element, isA<LocalVariableElement>());

      expect(
        tryFoldScalarConstant(
          identifier,
          localBindings: <Element, Expression>{element!: identifier},
        ),
        isNull,
      );
      expect(
        inspectScalarConstant(
          identifier,
          localBindings: <Element, Expression>{element: identifier},
        ).complete,
        isFalse,
      );
    });

    test('bounds a cycle reached through an operand', () async {
      final probe = await _boundScalarProbe(
        'Object value(String first, String second) => first + second; '
        "Object x() => value('ready', 'set');",
      );
      probe.bindings[probe.bindings.keys.first] = probe.expression;
      expect(
        tryFoldScalarConstant(
          probe.expression,
          localBindings: probe.bindings,
        ),
        isNull,
      );
    });

    test('keeps the exact scalar binding depth boundary', () async {
      final names = List<String>.generate(256, (index) => 'value$index');
      final expression = await parseExpressionFromSourceForTest(
        'Object x(${names.map((name) => 'String $name').join(', ')}) => '
        '[${names.join(', ')}, "ready"];',
      );
      final values = (expression as ListLiteral)
          .elements
          .whereType<SimpleIdentifier>()
          .toList(growable: false);
      final terminal =
          expression.elements.whereType<SimpleStringLiteral>().single;

      Map<Element, Expression> chain(int count) {
        final bindings = Map<Element, Expression>.identity();
        for (var index = 0; index < count; index++) {
          bindings[values[index].element!] =
              index + 1 == count ? terminal : values[index + 1];
        }
        return bindings;
      }

      expect(
        tryFoldScalarConstant(values.first, localBindings: chain(255)),
        'ready',
      );
      expect(
        tryFoldScalarConstant(values.first, localBindings: chain(256)),
        isNull,
      );
      expect(
        inspectScalarConstant(
          values.first,
          localBindings: chain(255),
        ).complete,
        isTrue,
      );
      expect(
        inspectScalarConstant(
          values.first,
          localBindings: chain(256),
        ).complete,
        isFalse,
      );
    });

    test('does not use a same-spelling binding for an unresolved name',
        () async {
      final probe = await _boundScalarProbe(
        'Object value(String value) => value; '
        "Object x() => value('ready');",
      );
      final unresolved = await parseExpressionFromSourceForTest(
        'Object x() => value;',
      );
      expect((unresolved as SimpleIdentifier).element, isNull);
      expect(
        tryFoldScalarConstant(
          unresolved,
          localBindings: probe.bindings,
        ),
        isNull,
      );
      final inspection = inspectScalarConstant(
        unresolved,
        localBindings: probe.bindings,
      );
      expect(inspection.complete, isTrue);
      expect(inspection.expression, same(unresolved));
    });
  });
}

Future<({Expression expression, Map<Element, Expression> bindings})>
    _boundScalarProbe(String source) async {
  final call = await parseExpressionFromSourceForTest(source);
  final unit = call.root as CompilationUnit;
  final helper = unit.declarations
      .whereType<FunctionDeclaration>()
      .singleWhere((declaration) => declaration.name.lexeme == 'value');
  final helperBody = extractInlinableBuildBody(
    helper.functionExpression.body,
  )!;
  final parameters = helper.functionExpression.parameters!.parameters;
  final arguments = (call as MethodInvocation).argumentList.arguments;
  return (
    expression: helperBody.expression,
    bindings: <Element, Expression>{
      ...helperBody.localBindings,
      for (var index = 0; index < parameters.length; index++)
        parameters[index].declaredFragment!.element: arguments[index],
    },
  );
}

final class _LocalIdentifierCollector extends RecursiveAstVisitor<void> {
  final List<SimpleIdentifier> identifiers = <SimpleIdentifier>[];

  void visit(AstNode node) => node.accept(this);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    identifiers.add(node);
    super.visitSimpleIdentifier(node);
  }
}
