import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:test/test.dart';

/// Parses [snippet] — a single top-level function declaration — and returns
/// its `FunctionBody`.
FunctionBody _bodyOf(String snippet) {
  final unit = parseString(content: snippet, throwIfDiagnostics: false).unit;
  final fn = unit.declarations.whereType<FunctionDeclaration>().first;
  return fn.functionExpression.body;
}

void main() {
  group('singleReturnExpressionOf', () {
    test('returns the expression of an expression-bodied function', () {
      final body = _bodyOf('int f() => 1 + 2;');
      expect(singleReturnExpressionOf(body), isA<BinaryExpression>());
    });

    test('returns the expression of a single-return block body', () {
      final body = _bodyOf('int f() { return 42; }');
      expect(singleReturnExpressionOf(body), isA<IntegerLiteral>());
    });

    test('returns null for a non-const (final) local before the return', () {
      // `final` is not const → its reference cannot fold → still rejected
      // (that shape is A1 state-authoring territory, not a cheap win).
      final body = _bodyOf('int f() { final x = 1; return x; }');
      expect(singleReturnExpressionOf(body), isNull);
    });

    test('returns null for a non-const (var) local before the return', () {
      final body = _bodyOf('int f() { var x = 1; return x; }');
      expect(singleReturnExpressionOf(body), isNull);
    });

    test('returns the return expression past leading const locals', () {
      // A `const` local is inert (compile-time); its reference folds at the
      // translation site, so the body still reduces to one returned widget.
      final body =
          _bodyOf('int f() { const x = 1; const y = 2; return x + y; }');
      expect(singleReturnExpressionOf(body), isA<BinaryExpression>());
    });

    test('returns null when a const local is not followed by a return', () {
      final body = _bodyOf('void f() { const x = 1; print(x); }');
      expect(singleReturnExpressionOf(body), isNull);
    });

    test('returns null for a multi-statement block body', () {
      final body = _bodyOf('void f() { print(1); print(2); }');
      expect(singleReturnExpressionOf(body), isNull);
    });

    test('returns null for a bare value-less return', () {
      final body = _bodyOf('void f() { return; }');
      expect(singleReturnExpressionOf(body), isNull);
    });
  });
}
