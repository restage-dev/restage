import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/type.dart';

/// The condition [test] stands for when it evaluates to [held], as source.
String conditionSource(Expression test, {required bool held}) {
  if (held) return test.toSource();
  final inner = _unwrap(test);
  return switch (inner) {
    PrefixExpression(operator: Token(lexeme: '!'), :final operand) =>
      operand.toSource(),
    BinaryExpression(
      operator: Token(lexeme: '=='),
      :final leftOperand,
      :final rightOperand,
    ) =>
      '${leftOperand.toSource()} != ${rightOperand.toSource()}',
    BinaryExpression(
      operator: Token(lexeme: '!='),
      :final leftOperand,
      :final rightOperand,
    ) =>
      '${leftOperand.toSource()} == ${rightOperand.toSource()}',
    Identifier() || PropertyAccess() => '!${inner.toSource()}',
    _ => '!(${inner.toSource()})',
  };
}

/// [test] holding as [held], in plain words: `x != null` is "when there's
/// a x", a bool field `x` "when x is on" and `!x` "when x is off",
/// `xs.isEmpty` "when there are no xs" and `xs.isNotEmpty` "when there are
/// xs"; anything else is "when" and its source in backticks.
String plainCondition(Expression test, {required bool held}) {
  final inner = _unwrap(test);
  switch (inner) {
    case PrefixExpression(operator: Token(lexeme: '!'), :final operand):
      return plainCondition(operand, held: !held);
    case BinaryExpression(
          :final operator,
          :final leftOperand,
          rightOperand: NullLiteral(),
        )
        when (operator.lexeme == '!=') == held &&
            (operator.lexeme == '!=' || operator.lexeme == '=='):
      if (_label(leftOperand) case final label?) {
        return "when there's ${_article(label)} $label";
      }
    case PrefixedIdentifier(:final prefix, :final identifier)
        when _emptiness.containsKey(identifier.name) && _isCollection(prefix):
      if (_label(prefix) case final label?) {
        final some = _emptiness[identifier.name]! != held;
        return 'when there are ${some ? '' : 'no '}$label';
      }
    case PropertyAccess(:final target?, :final propertyName)
        when _emptiness.containsKey(propertyName.name) && _isCollection(target):
      if (_label(target) case final label?) {
        final some = _emptiness[propertyName.name]! != held;
        return 'when there are ${some ? '' : 'no '}$label';
      }
    // A read typed as something other than a bool is not on or off.
    case Identifier() || PropertyAccess()
        when inner.staticType?.isDartCoreBool ?? true:
      if (_label(inner) case final label? when !_predicate(label)) {
        return 'when $label is ${held ? 'on' : 'off'}';
      }
  }
  return 'when `${conditionSource(test, held: held)}`';
}

/// The condition [subject] matching [pattern] stands for, in plain words: a
/// null-check pattern is "when there's a x".
String plainCase(Expression subject, DartPattern pattern) {
  if (pattern is NullCheckPattern) {
    if (_label(subject) case final label?) {
      return "when there's ${_article(label)} $label";
    }
  }
  return 'when `${subject.toSource()} case ${pattern.toSource()}`';
}

// Whether each emptiness getter holds when the collection is empty.
const _emptiness = {'isEmpty': true, 'isNotEmpty': false};

// Whether [read] is a list, set, map or other iterable, or of unknown type.
bool _isCollection(Expression read) {
  final type = read.staticType;
  if (type == null) return true;
  return type.isDartCoreList ||
      type.isDartCoreSet ||
      type.isDartCoreMap ||
      type.isDartCoreIterable ||
      (type is InterfaceType &&
          type.allSupertypes.any((t) => t.isDartCoreIterable));
}

// Whether [label] already reads as a question, as "is trial" or "has plan"
// do, so "is on" can't follow it.
bool _predicate(String label) => const {
  'is',
  'has',
  'can',
  'should',
  'was',
  'were',
  'will',
  'did',
  'does',
  'are',
  'needs',
  'must',
}.contains(label.split(' ').first);

Expression _unwrap(Expression test) =>
    test is ParenthesizedExpression ? _unwrap(test.expression) : test;

// The last name of a read, in words: `widget.showBanner` is "show banner".
String? _label(Expression read) {
  final name = switch (_unwrap(read)) {
    SimpleIdentifier(:final name) => name,
    PrefixedIdentifier(:final identifier) => identifier.name,
    PropertyAccess(:final propertyName) => propertyName.name,
    _ => null,
  };
  if (name == null) return null;
  return name
      .replaceFirst(RegExp(r'^_+'), '')
      .replaceAllMapped(RegExp('(?<=[a-z0-9])([A-Z])'), (m) => ' ${m[1]}')
      .toLowerCase();
}

String _article(String label) =>
    RegExp('^[aeiou]').hasMatch(label) ? 'an' : 'a';
