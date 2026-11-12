import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

const String _kRestageOrigin = 'package:restage/';

/// The event names a paywall's `@Paywall(completesOn:)` declares.
Set<String> paywallCompletionEvents(ClassElement paywall) {
  for (final annotation in paywall.metadata.annotations) {
    final value = annotation.computeConstantValue();
    final type = value?.type?.element;
    if (value == null ||
        type?.name != 'Paywall' ||
        !(type?.library?.identifier.startsWith(_kRestageOrigin) ?? false)) {
      continue;
    }
    return {
      for (final event
          in value.getField('completesOn')?.toListValue() ?? <DartObject>[])
        if (event.getField('id')?.toStringValue() case final id?) id,
    };
  }
  return const {};
}

/// The event names app code in [node] fires by calling
/// `context.surfaceEvent(event)()`, as opposed to passing it as a callback.
Set<String> appFiredEventNamesIn(AstNode? node) {
  if (node == null) return const {};
  final visitor = _AppFiredEvents();
  node.accept(visitor);
  return visitor.names;
}

final class _AppFiredEvents extends RecursiveAstVisitor<void> {
  final names = <String>{};

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final function = node.function;
    if (function is MethodInvocation) {
      if (authoredEventName(function) case final name?) names.add(name);
    }
    super.visitFunctionExpressionInvocation(node);
  }
}

/// The event names [callback] fires from any branch of a conditional.
Set<String> authoredEventNames(Expression callback) {
  final expression = callback is ParenthesizedExpression
      ? callback.expression
      : callback;
  if (expression is ConditionalExpression) {
    return {
      ...authoredEventNames(expression.thenExpression),
      ...authoredEventNames(expression.elseExpression),
    };
  }
  return {if (authoredEventName(expression) case final name?) name};
}

/// The event name a `context.surfaceEvent(event)` callback fires, or null for
/// any other callback.
String? authoredEventName(Expression callback) {
  final expression = callback is ParenthesizedExpression
      ? callback.expression
      : callback;
  if (expression is! MethodInvocation) return null;
  final name = expression.methodName.name;
  if (name != 'surfaceEvent') return null;
  final arguments = expression.argumentList.arguments;
  if (arguments.isEmpty) return null;
  final first = arguments.first.argumentExpression;
  final element = switch (first) {
    SimpleIdentifier(:final element) => element,
    PrefixedIdentifier(:final element) => element,
    PropertyAccess(:final propertyName) => propertyName.element,
    _ => null,
  };
  final variable = element is PropertyAccessorElement
      ? element.variable
      : element is VariableElement
      ? element
      : null;
  return variable?.computeConstantValue()?.getField('id')?.toStringValue();
}
