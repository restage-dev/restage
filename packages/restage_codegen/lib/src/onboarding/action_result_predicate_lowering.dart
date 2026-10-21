import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_shared/restage_shared.dart';

/// The predicate forms a host action's `continueWhen` accepts, for messages.
const String kActionResultPredicateForms =
    'Write `(result) => true`, `(result) => result`, `!result`, '
    '`result.field`, or comparisons of the result or its final fields with '
    'literals (== and != for a bool, int or String; <, <=, > and >= for an '
    'int) joined with &&.';

/// Lowers a `continueWhen` predicate over a result of [resultType], or
/// returns why it cannot.
({FlowActionResultPredicate? predicate, String? refusal})
    lowerActionResultPredicate(Expression? expression, DartType? resultType) {
  ({FlowActionResultPredicate? predicate, String? refusal}) refuse(
    String why,
  ) =>
      (predicate: null, refusal: '$why $kActionResultPredicateForms');

  if (expression is! FunctionExpression ||
      expression.parameters?.parameters.length != 1 ||
      expression.body is! ExpressionFunctionBody) {
    return refuse('A host action predicate is a one-parameter arrow function.');
  }
  final parameter = expression.parameters!.parameters.single.name?.lexeme;
  final body = _unwrap((expression.body as ExpressionFunctionBody).expression);
  if (parameter == null || resultType == null) {
    return refuse('The host action predicate did not resolve.');
  }
  if (body is BooleanLiteral) {
    return body.value
        ? (predicate: const AlwaysActionResultPredicate(), refusal: null)
        : refuse('A predicate that is always false never continues.');
  }

  final lowering = _Lowering(parameter, resultType);
  if (resultType.isDartCoreBool) {
    final whole = lowering.boolSubject(body) ?? lowering.boolComparison(body);
    if (whole != null && whole.field == null) {
      return (
        predicate: whole.value
            ? const BoolEqualsActionResultPredicate(value: true)
            : const BoolEqualsActionResultPredicate(value: false),
        refusal: null,
      );
    }
  }
  final single = lowering.boolSubject(body) ?? lowering.boolComparison(body);
  if (single != null &&
      single.field != null &&
      lowering.isRequiredBoolField(single.field!)) {
    return (
      predicate: ObjectBoolFieldEqualsActionResultPredicate(
        field: single.field!,
        value: single.value,
      ),
      refusal: null,
    );
  }

  FlowPredicateCondition? whole;
  final fields = <String, FlowPredicateCondition>{};
  for (final conjunct in _conjuncts(body)) {
    final lowered = lowering.condition(conjunct);
    if (lowered == null) {
      return refuse('`${conjunct.toSource()}` is not a supported check.');
    }
    final field = lowered.field;
    if (field == null) {
      if (whole != null) {
        return refuse('The result is checked twice.');
      }
      whole = lowered.condition;
    } else {
      if (fields.containsKey(field)) {
        return refuse('The result field `$field` is checked twice.');
      }
      fields[field] = lowered.condition;
    }
  }
  return (
    predicate: MatchesActionResultPredicate(result: whole, fields: fields),
    refusal: null,
  );
}

Iterable<Expression> _conjuncts(Expression expression) sync* {
  final unwrapped = _unwrap(expression);
  if (unwrapped is BinaryExpression && unwrapped.operator.lexeme == '&&') {
    yield* _conjuncts(unwrapped.leftOperand);
    yield* _conjuncts(unwrapped.rightOperand);
  } else {
    yield unwrapped;
  }
}

Expression _unwrap(Expression expression) {
  var current = expression;
  while (current is ParenthesizedExpression) {
    current = current.expression;
  }
  return current;
}

final class _Lowering {
  _Lowering(this.parameter, this.resultType);

  final String parameter;
  final DartType resultType;

  /// `p`, `!p`, `p.f` or `!p.f`.
  ({String? field, bool value})? boolSubject(Expression expression) {
    final unwrapped = _unwrap(expression);
    if (unwrapped is PrefixExpression && unwrapped.operator.lexeme == '!') {
      final inner = boolSubject(unwrapped.operand);
      return inner == null ? null : (field: inner.field, value: !inner.value);
    }
    final subject = this.subject(unwrapped);
    if (subject == null) return null;
    final type =
        subject.field == null ? resultType : _fieldType(subject.field!);
    if (type == null ||
        !type.isDartCoreBool ||
        type.nullabilitySuffix != NullabilitySuffix.none) {
      return null;
    }
    return (field: subject.field, value: true);
  }

  /// The result itself (field null) or one of its fields.
  ({String? field})? subject(Expression expression) {
    final unwrapped = _unwrap(expression);
    if (unwrapped is SimpleIdentifier && unwrapped.name == parameter) {
      return (field: null);
    }
    if (unwrapped is PrefixedIdentifier &&
        unwrapped.prefix.name == parameter &&
        _fieldType(unwrapped.identifier.name) != null) {
      return (field: unwrapped.identifier.name);
    }
    if (unwrapped is PropertyAccess &&
        unwrapped.target is SimpleIdentifier &&
        (unwrapped.target! as SimpleIdentifier).name == parameter &&
        _fieldType(unwrapped.propertyName.name) != null) {
      return (field: unwrapped.propertyName.name);
    }
    return null;
  }

  /// `p == true`, `p.f != false` and the like, as a bool subject.
  ({String? field, bool value})? boolComparison(Expression expression) {
    final unwrapped = _unwrap(expression);
    if (unwrapped is! BinaryExpression) return null;
    final operator = unwrapped.operator.lexeme;
    if (operator != '==' && operator != '!=') return null;
    for (final (subjectSide, literalSide) in [
      (unwrapped.leftOperand, unwrapped.rightOperand),
      (unwrapped.rightOperand, unwrapped.leftOperand),
    ]) {
      final subject = boolSubject(subjectSide);
      final literal = _unwrap(literalSide);
      if (subject == null || literal is! BooleanLiteral) continue;
      final matches = (operator == '==') == literal.value;
      return (field: subject.field, value: subject.value == matches);
    }
    return null;
  }

  bool isRequiredBoolField(String field) {
    final type = _fieldType(field);
    return type != null &&
        type.isDartCoreBool &&
        type.nullabilitySuffix == NullabilitySuffix.none;
  }

  ({String? field, FlowPredicateCondition condition})? condition(
    Expression expression,
  ) {
    final asBool = boolSubject(expression);
    if (asBool != null) {
      return (
        field: asBool.field,
        condition: EqualsFlowPredicateCondition(
          value: LiteralFlowValueSource(
            type: FlowDataType.bool,
            value: asBool.value,
          ),
        ),
      );
    }
    if (expression is! BinaryExpression) return null;
    var operator = expression.operator.lexeme;
    var left = subject(expression.leftOperand);
    var other = expression.rightOperand;
    if (left == null) {
      left = subject(expression.rightOperand);
      other = expression.leftOperand;
      operator = switch (operator) {
        '<' => '>',
        '<=' => '>=',
        '>' => '<',
        '>=' => '<=',
        _ => operator,
      };
    }
    if (left == null) return null;
    final literal = _literal(other);
    if (literal == null) return null;
    final condition = switch (operator) {
      '==' => EqualsFlowPredicateCondition(value: literal),
      '!=' => NotEqualsFlowPredicateCondition(value: literal),
      '>' => GreaterThanFlowPredicateCondition(value: literal),
      '>=' => GreaterThanOrEqualsFlowPredicateCondition(value: literal),
      '<' => LessThanFlowPredicateCondition(value: literal),
      '<=' => LessThanOrEqualsFlowPredicateCondition(value: literal),
      _ => null,
    };
    return condition == null ? null : (field: left.field, condition: condition);
  }

  LiteralFlowValueSource? _literal(Expression expression) {
    final value = tryFoldScalarConstant(_unwrap(expression));
    return switch (value) {
      final bool flag =>
        LiteralFlowValueSource(type: FlowDataType.bool, value: flag),
      final int number =>
        LiteralFlowValueSource(type: FlowDataType.int, value: number),
      final String text =>
        LiteralFlowValueSource(type: FlowDataType.string, value: text),
      _ => null,
    };
  }

  /// The type of a final instance field the result declares, the only kind
  /// a flow can read.
  DartType? _fieldType(String name) {
    final type = resultType;
    if (type is! InterfaceType) return null;
    for (final field in type.element.fields) {
      if (field.name == name &&
          !field.isStatic &&
          field.isFinal &&
          field.isOriginDeclaration) {
        return field.type;
      }
    }
    return null;
  }
}
