import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';

/// Resolved structural disposition for one constructor callback input.
///
/// The hierarchy is sealed so every target must classify every accepted shape
/// exhaustively. Adding a new accepted shape makes the RFW, A2UI, and
/// Widgetbook switches fail to compile until each target declares its payload
/// handling.
@immutable
sealed class ResolvedCallbackShape {
  const ResolvedCallbackShape();
}

/// A void callback with no arguments.
final class ZeroArgumentCallback extends ResolvedCallbackShape {
  /// Creates the zero-argument callback disposition.
  const ZeroArgumentCallback();
}

/// A void callback with exactly one required positional [valueType].
final class SingleValueCallback extends ResolvedCallbackShape {
  /// Creates the single-value callback disposition.
  const SingleValueCallback(this.valueType);

  /// Resolved callback payload type after typedef expansion and substitution.
  final DartType valueType;
}

/// A callable shape outside the structural set every target admits.
final class UnsupportedCallback extends ResolvedCallbackShape {
  /// Creates an unsupported callback disposition with a diagnostic [reason].
  const UnsupportedCallback(this.reason);

  /// Target-independent reason the shape is not accepted.
  final String reason;
}

/// Whether [type] is carried as an event handler at an event slot — a callable
/// returning `void`, or `Future<void>` for fire-and-forget handlers. A
/// deliberate event-slot widening of the structural set below.
bool isEventCallbackType(DartType type) {
  if (type is! FunctionType) return false;
  final returnType = type.returnType;
  if (returnType is VoidType) return true;
  return returnType is InterfaceType &&
      returnType.isDartAsyncFuture &&
      returnType.typeArguments.length == 1 &&
      returnType.typeArguments.single is VoidType;
}

/// Classifies [type] by the shared callback structure admitted by all targets.
ResolvedCallbackShape classifyResolvedCallbackShape(DartType type) {
  if (type is! FunctionType) {
    return UnsupportedCallback('${type.getDisplayString()} is not callable');
  }
  if (type.returnType is! VoidType) {
    return UnsupportedCallback(
      '${type.getDisplayString()} does not return void',
    );
  }
  final parameters = type.formalParameters;
  if (parameters.isEmpty) return const ZeroArgumentCallback();
  if (parameters.length == 1 && parameters.single.isRequiredPositional) {
    return SingleValueCallback(parameters.single.type);
  }
  return UnsupportedCallback(
    '${type.getDisplayString()} is neither a zero-argument callback nor a '
    'single-required-positional-value callback',
  );
}
