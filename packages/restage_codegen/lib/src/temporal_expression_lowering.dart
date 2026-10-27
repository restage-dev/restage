import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_shared/restage_shared.dart';

bool _member(Element? element, String owner) =>
    element?.enclosingElement?.name == owner &&
    element?.library?.identifier == 'dart:core';

bool _date(DartType? type) =>
    type is InterfaceType &&
    type.element.name == 'DateTime' &&
    type.element.library.identifier == 'dart:core';

const _dateMethods = {
  'difference',
  'compareTo',
  'isBefore',
  'isAfter',
  'isAtSameMomentAs',
  'add',
  'subtract',
};

/// Recognition is broad; the lowerer validates each resolved native call shape.
bool isTemporalValueExpression(Expression expression) => switch (expression) {
      InstanceCreationExpression() =>
        _member(expression.constructorName.element, 'DateTime') ||
            _member(expression.constructorName.element, 'Duration'),
      MethodInvocation() =>
        _member(expression.methodName.element, 'DateTime') &&
            ({'parse', 'toUtc', 'toLocal', ..._dateMethods})
                .contains(expression.methodName.name),
      PropertyAccess() =>
        _member(expression.propertyName.element, 'DateTime') &&
                dateTimeGetters.containsKey(expression.propertyName.name) ||
            _member(expression.propertyName.element, 'Duration') &&
                durationGetters.contains(expression.propertyName.name),
      PrefixedIdentifier() =>
        _member(expression.identifier.element, 'DateTime') &&
                dateTimeGetters.containsKey(expression.identifier.name) ||
            _member(expression.identifier.element, 'Duration') &&
                durationGetters.contains(expression.identifier.name),
      BinaryExpression() =>
        const {'==', '!='}.contains(expression.operator.lexeme) &&
            _date(expression.leftOperand.staticType) &&
            _date(expression.rightOperand.staticType),
      _ => false,
    };

/// Lowers only fixed dart:core temporal members into the common ValueProgram.
int? lowerTemporalValue(
    Expression expression, BuilderExpressionLowering lowerer) {
  final e = expression;
  int add(String op, ValueType type, List<int> inputs, [Object? value]) =>
      lowerer.add(ValueNode(op, type, inputs: inputs, value: value));
  Never refuse(String reason) => throw BuilderLoweringException(e, reason);
  if (e is InstanceCreationExpression) {
    final ctor = e.constructorName.element;
    if (_member(ctor, 'DateTime') && e.constructorName.name?.name == 'now') {
      if (e.argumentList.arguments.isNotEmpty)
        refuse('DateTime.now takes no arguments');
      return add('clock.now', dateTimeValueType, []);
    }
    if (_member(ctor, 'Duration')) {
      if (e.constructorName.name != null &&
          e.constructorName.name!.name != 'new')
        refuse('Unsupported native Duration constructor');
      final names = <String>[];
      final inputs = <int>[];
      for (final argument in e.argumentList.arguments) {
        if (argument is! NamedArgument ||
            !durationArguments.contains(argument.name.lexeme))
          refuse('Duration requires native named unit arguments');
        names.add(argument.name.lexeme);
        inputs.add(lowerer.lower(argument.argumentExpression));
      }
      return add('temporal.duration.new', durationValueType, inputs, names);
    }
  }
  final (Element? member, Expression? target, String? getter) = switch (e) {
    PropertyAccess() => (e.propertyName.element, e.target, e.propertyName.name),
    PrefixedIdentifier() => (e.identifier.element, e.prefix, e.identifier.name),
    _ => (null, null, null),
  };
  if (target != null && getter != null) {
    if (_member(member, 'DateTime') && dateTimeGetters.containsKey(getter))
      return add('temporal.datetime.get', dateTimeGetters[getter]!,
          [lowerer.lower(target)], getter);
    if (_member(member, 'Duration') && durationGetters.contains(getter))
      return add('temporal.duration.get', ValueType.integer,
          [lowerer.lower(target)], getter);
  }
  if (e is MethodInvocation &&
      _member(e.methodName.element, 'DateTime') &&
      _dateMethods.contains(e.methodName.name)) {
    final args = e.argumentList.arguments;
    if (e.target == null || args.length != 1 || args.single is NamedArgument)
      refuse('Unsupported native DateTime method arguments');
    final name = e.methodName.name;
    final type = switch (name) {
      'difference' => durationValueType,
      'add' || 'subtract' => dateTimeValueType,
      'compareTo' => ValueType.integer,
      _ => ValueType.boolean,
    };
    return add('temporal.datetime.$name', type, [
      lowerer.lower(e.target!),
      lowerer.lower(args.single.argumentExpression)
    ]);
  }
  if (e is BinaryExpression &&
      const {'==', '!='}.contains(e.operator.lexeme) &&
      _date(e.leftOperand.staticType) &&
      _date(e.rightOperand.staticType)) {
    final same = add('temporal.datetime.equals', ValueType.boolean,
        [lowerer.lower(e.leftOperand), lowerer.lower(e.rightOperand)]);
    return e.operator.lexeme == '=='
        ? same
        : add('!', ValueType.boolean, [same]);
  }
  return null;
}
