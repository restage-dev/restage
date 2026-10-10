import 'package:analyzer/dart/ast/ast.dart';
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

/// The event name a `paywallEvent('name')` or `surfaceEvent(event)` callback
/// fires, or null for any other callback.
String? authoredEventName(Expression callback) {
  final expression =
      callback is ParenthesizedExpression ? callback.expression : callback;
  if (expression is! MethodInvocation) return null;
  final name = expression.methodName.name;
  if (name != 'paywallEvent' && name != 'surfaceEvent') return null;
  final arguments = expression.argumentList.arguments;
  if (arguments.isEmpty) return null;
  final first = arguments.first.argumentExpression;
  if (first is SimpleStringLiteral) return first.value;
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
