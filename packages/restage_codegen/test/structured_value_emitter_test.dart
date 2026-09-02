import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/structured_value_emitter.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final emitter = StructuredValueEmitter(
    translate: (expression, issues) => expression.toSource(),
    translateSlotValue: (expression, type, issues) {
      final source = expression.toSource();
      if (source == 'bad') {
        issues.add(
          const Issue(
            code: IssueCode.propertyValueTypeMismatch,
            message: 'Expected a text decoration value.',
            location: 'decoration.dart@1:1',
          ),
        );
        return '';
      }
      if (source == 'deferred') {
        issues.add(
          const Issue(
            code: IssueCode.customWidgetInliningDeferred,
            message: 'The value cannot emit here.',
            location: 'decoration.dart@1:1',
          ),
        );
        return '';
      }
      if (source == 'silent') return '';
      if (source == 'noticed') {
        issues.add(
          const Issue(
            code: IssueCode.idiomAutoSubstituted,
            message: 'The value uses its canonical representation.',
            location: 'decoration.dart@1:1',
          ),
        );
      }
      return source;
    },
    translateDoubleScalar: (expression, issues) => expression.toSource(),
    stripParens: (expression) => expression,
    stringLiteral: (value) => '"$value"',
    frameworkOrUnresolved: (_) => true,
    resolveBoundIdentifier: (expression) => expression,
    isResolvedNonFrameworkCtor: (_) => false,
    deferFrameworkConstLookalike: (expression, typeName, memberName, issues) =>
        '',
    deferFrameworkCtorLookalike: (expression, typeName, issues) => '',
    locationOf: (_) => 'decoration.dart@1:1',
  );

  Future<NodeList<Expression>> argumentsOf(String source) async {
    final expression = await parseExpressionForTest(source);
    return (expression as MethodInvocation).argumentList.arguments;
  }

  test('a typed item error suppresses the complete structured list', () async {
    expect(
      emitter.textDecorationCombine(
        await argumentsOf(
          'TextDecoration.combine(<TextDecoration>[underline, overline])',
        ),
        <Issue>[],
        'decoration.dart@1:1',
      ),
      '[underline, overline]',
    );
    final issues = <Issue>[];
    expect(
      emitter.textDecorationCombine(
        await argumentsOf(
          'TextDecoration.combine(<TextDecoration>[underline, bad])',
        ),
        issues,
        'decoration.dart@1:1',
      ),
      isEmpty,
    );
    expect(issues.single.code, IssueCode.propertyValueTypeMismatch);
  });

  test('structured lists distinguish refusal from a build notice', () async {
    final deferredIssues = <Issue>[];
    final deferred = emitter.textDecorationCombine(
      await argumentsOf(
        'TextDecoration.combine(<TextDecoration>[underline, deferred])',
      ),
      deferredIssues,
      'decoration.dart@1:1',
    );
    expect(deferred, isEmpty);
    expect(deferred, isNot(equals('[underline, ]')));
    expect(
      deferredIssues.single.code,
      IssueCode.customWidgetInliningDeferred,
    );

    expect(
      emitter.textDecorationCombine(
        await argumentsOf(
          'TextDecoration.combine(<TextDecoration>[underline, silent])',
        ),
        <Issue>[],
        'decoration.dart@1:1',
      ),
      isEmpty,
    );

    final noticeIssues = <Issue>[];
    expect(
      emitter.textDecorationCombine(
        await argumentsOf(
          'TextDecoration.combine(<TextDecoration>[underline, noticed])',
        ),
        noticeIssues,
        'decoration.dart@1:1',
      ),
      '[underline, noticed]',
    );
    expect(noticeIssues.single.code, IssueCode.idiomAutoSubstituted);
  });

  test('structured lists suppress every collection-flow form', () async {
    expect(
      emitter.textDecorationCombine(
        await argumentsOf(
          'TextDecoration.combine(<TextDecoration>[underline, overline])',
        ),
        <Issue>[],
        'decoration.dart@1:1',
      ),
      '[underline, overline]',
    );

    for (final (name, tail) in const <(String, String)>[
      ('spread', '...more'),
      ('collection-if', 'if (enabled) overline'),
      ('collection-for', 'for (final value in more) value'),
    ]) {
      final issues = <Issue>[];
      final value = emitter.textDecorationCombine(
        await argumentsOf(
          'TextDecoration.combine(<TextDecoration>[underline, $tail])',
        ),
        issues,
        'decoration.dart@1:1',
      );

      expect(issues, hasLength(1), reason: name);
      expect(
        issues.single.code,
        IssueCode.unsupportedCollectionFlow,
        reason: name,
      );
      expect(issues.single.location, 'decoration.dart@1:1', reason: name);
      expect(value, isEmpty, reason: name);
      expect(value, isNot(contains('underline')), reason: name);
    }
  });
}
