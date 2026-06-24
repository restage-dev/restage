import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/theme_recognition.dart';

/// Flutter sheet functions recognised as declarative modal-sheet triggers.
enum ModalSheetFunction {
  /// `showModalBottomSheet(...)` from Flutter Material.
  showModalBottomSheet,

  /// `showCupertinoSheet(...)` from Flutter Cupertino.
  showCupertinoSheet,
}

/// A clean modal-sheet trigger call captured by the classifier.
final class RecognisedModalSheet {
  /// Creates a recognised modal-sheet trigger.
  const RecognisedModalSheet({required this.function, required this.call});

  /// Which Flutter sheet function was called.
  final ModalSheetFunction function;

  /// The exact `show*Sheet(...)` invocation in the source AST.
  final MethodInvocation call;
}

/// Result of recognising a possible modal-sheet trigger slot value.
sealed class ModalSheetTriggerOutcome {
  const ModalSheetTriggerOutcome();
}

/// The slot value is a clean synchronous modal-sheet trigger.
final class ModalSheetRecognised extends ModalSheetTriggerOutcome {
  /// Creates a recognised outcome.
  const ModalSheetRecognised(this.sheet);

  /// The recognised sheet trigger.
  final RecognisedModalSheet sheet;
}

/// The slot value references a sheet call but uses a result-bearing form.
final class ModalSheetResultDropped extends ModalSheetTriggerOutcome {
  /// Creates a result-drop outcome.
  const ModalSheetResultDropped(this.reason);

  /// Author-facing reason for the fatal defer.
  final String reason;
}

/// The slot value is not a modal-sheet trigger.
final class ModalSheetNotRecognised extends ModalSheetTriggerOutcome {
  /// Creates a not-recognised outcome.
  const ModalSheetNotRecognised();
}

/// Result of extracting a static modal-sheet builder body.
sealed class ModalSheetBuilderOutcome {
  const ModalSheetBuilderOutcome();
}

/// The builder closure reduces to one static widget expression.
final class ModalSheetBuilderRecognised extends ModalSheetBuilderOutcome {
  /// Creates a recognised builder outcome.
  const ModalSheetBuilderRecognised(this.body);

  /// The widget expression returned by the builder.
  final Expression body;
}

/// The builder closure cannot be carried into the declarative sheet child.
final class ModalSheetBuilderUnsupported extends ModalSheetBuilderOutcome {
  /// Creates an unsupported builder outcome.
  const ModalSheetBuilderUnsupported(this.reason);

  /// Author-facing reason for the fatal defer.
  final String reason;
}

/// Result of recognising an in-sheet close callback.
sealed class ModalSheetCloseOutcome {
  const ModalSheetCloseOutcome();
}

/// The callback is exactly `() => Navigator.pop(context)`.
final class ModalSheetCloseRecognised extends ModalSheetCloseOutcome {
  /// Creates a recognised close outcome.
  const ModalSheetCloseRecognised();
}

/// The callback uses `Navigator.pop` in a result-bearing or richer form.
final class ModalSheetCloseUnsupported extends ModalSheetCloseOutcome {
  /// Creates an unsupported close outcome.
  const ModalSheetCloseUnsupported(this.reason);

  /// Author-facing reason for the fatal defer.
  final String reason;
}

/// The callback is not a modal-sheet close form.
final class ModalSheetCloseNotRecognised extends ModalSheetCloseOutcome {
  /// Creates a not-recognised close outcome.
  const ModalSheetCloseNotRecognised();
}

/// How a `show*Sheet` named argument is handled by the lowering.
enum ModalSheetArgumentDisposition {
  /// The argument maps by name to a catalog slot.
  map,

  /// The argument supplies the sheet child builder.
  builder,

  /// The `pageBuilder` fallback for `showCupertinoSheet`.
  pageBuilder,

  /// The argument is intentionally ignored.
  drop,

  /// The `AnimationStyle(...)` aggregate maps to animation slots.
  animationStyle,

  /// The argument has no faithful declarative equivalent.
  defer,
}

/// Per-function argument disposition tables. Keeping the tables public within
/// the package lets tests pin completeness without duplicating the list.
const Map<ModalSheetFunction, Map<String, ModalSheetArgumentDisposition>>
    kModalSheetArgumentDispositions = {
  ModalSheetFunction.showModalBottomSheet: {
    'context': ModalSheetArgumentDisposition.drop,
    'builder': ModalSheetArgumentDisposition.builder,
    'backgroundColor': ModalSheetArgumentDisposition.map,
    'barrierLabel': ModalSheetArgumentDisposition.map,
    'elevation': ModalSheetArgumentDisposition.map,
    'shape': ModalSheetArgumentDisposition.map,
    'clipBehavior': ModalSheetArgumentDisposition.map,
    'barrierColor': ModalSheetArgumentDisposition.map,
    'isScrollControlled': ModalSheetArgumentDisposition.map,
    'scrollControlDisabledMaxHeightRatio': ModalSheetArgumentDisposition.map,
    'isDismissible': ModalSheetArgumentDisposition.map,
    'enableDrag': ModalSheetArgumentDisposition.map,
    'showDragHandle': ModalSheetArgumentDisposition.map,
    'useSafeArea': ModalSheetArgumentDisposition.map,
    'anchorPoint': ModalSheetArgumentDisposition.map,
    'sheetAnimationStyle': ModalSheetArgumentDisposition.animationStyle,
    'constraints': ModalSheetArgumentDisposition.defer,
    'useRootNavigator': ModalSheetArgumentDisposition.defer,
    'routeSettings': ModalSheetArgumentDisposition.defer,
    'transitionAnimationController': ModalSheetArgumentDisposition.defer,
    'requestFocus': ModalSheetArgumentDisposition.defer,
  },
  ModalSheetFunction.showCupertinoSheet: {
    'context': ModalSheetArgumentDisposition.drop,
    'builder': ModalSheetArgumentDisposition.builder,
    'pageBuilder': ModalSheetArgumentDisposition.pageBuilder,
    'enableDrag': ModalSheetArgumentDisposition.map,
    'showDragHandle': ModalSheetArgumentDisposition.map,
    'useNestedNavigation': ModalSheetArgumentDisposition.defer,
    'topGap': ModalSheetArgumentDisposition.defer,
  },
};

/// The fixed sheet library each source function lowers to, matching Flutter:
/// `showModalBottomSheet` is always Material, `showCupertinoSheet` is always
/// Cupertino — on every platform. Emitted as the `RestageModalSheet`
/// `presentation` slot value. The widget default is adaptive (platform-driven,
/// for editor / direct-widget authoring); the lowering pins it per function so
/// a server-delivered sheet matches the source function's Flutter behaviour.
const Map<ModalSheetFunction, String> kModalSheetPresentation = {
  ModalSheetFunction.showModalBottomSheet: 'material',
  ModalSheetFunction.showCupertinoSheet: 'cupertino',
};

/// Fatal-defer reason for modal-sheet forms that observe the returned result.
const String kModalSheetResultDroppedReason =
    "the sheet's result value cannot be observed declaratively; drive a state "
    'field from the sheet instead';

/// Fatal-defer reason for `Navigator.pop(context, result)` in sheet content.
const String kModalSheetNavigatorPopResultReason =
    'Navigator.pop(context, result) returns a sheet result that cannot be '
    'observed declaratively; close the sheet without a result';

/// Fatal-defer reason for sheet calls outside the supported trigger slots.
const String kModalSheetTriggerSlotUnsupportedReason =
    'modal sheets can only be lowered from an onPressed or onTap callback';

/// Whether a catalog event slot can host a declarative modal-sheet trigger.
bool isModalSheetTriggerSlotName(String name) =>
    name == 'onPressed' || name == 'onTap';

/// Recognises the only modal-sheet trigger form that can be lowered without
/// dropping the sheet result: `() => show*Sheet(...)` or
/// `() { show*Sheet(...); }`.
ModalSheetTriggerOutcome recogniseModalSheetTrigger(Expression slotValue) {
  if (slotValue is! FunctionExpression) {
    return const ModalSheetNotRecognised();
  }

  final sheetCallCount = _countModalSheetCalls(slotValue.body);
  if (sheetCallCount == 0) return const ModalSheetNotRecognised();

  if (slotValue.body.isAsynchronous || !_hasNoParameters(slotValue)) {
    return const ModalSheetResultDropped(kModalSheetResultDroppedReason);
  }

  // More than one sheet call means a nested sheet invocation inside the
  // trigger's arguments, whose result is observed. Never silently lower it.
  if (sheetCallCount != 1) {
    return const ModalSheetResultDropped(kModalSheetResultDroppedReason);
  }

  final call = _extractSingleCall(slotValue.body);
  if (call == null) {
    return const ModalSheetResultDropped(kModalSheetResultDroppedReason);
  }

  final function = _modalSheetFunctionOf(call);
  if (function == null) {
    return const ModalSheetResultDropped(kModalSheetResultDroppedReason);
  }

  return ModalSheetRecognised(
    RecognisedModalSheet(function: function, call: call),
  );
}

bool _hasNoParameters(FunctionExpression expression) {
  final parameters = expression.parameters;
  return parameters == null || parameters.parameters.isEmpty;
}

/// Returns the [MethodInvocation] the closure body reduces to when it is a
/// single expression-bodied or block-with-one-expression-statement closure, or
/// `null` for any richer shape.
MethodInvocation? _extractSingleCall(FunctionBody body) {
  if (body is ExpressionFunctionBody) {
    final expr = _unwrapParens(body.expression);
    if (expr is MethodInvocation) return expr;
    return null;
  }
  if (body is BlockFunctionBody) {
    final stmts = body.block.statements;
    if (stmts.length != 1) return null;
    final stmt = stmts.single;
    if (stmt is ExpressionStatement) {
      final expr = _unwrapParens(stmt.expression);
      if (expr is MethodInvocation) return expr;
    }
    return null;
  }
  return null;
}

/// Strips semantically-inert surrounding parentheses.
Expression _unwrapParens(Expression expr) =>
    expr is ParenthesizedExpression ? _unwrapParens(expr.expression) : expr;

int _countModalSheetCalls(AstNode node) =>
    _countMatchingInvocations(node, (n) => _modalSheetFunctionOf(n) != null);

/// Counts the [MethodInvocation]s in [node]'s subtree that [matches] accepts.
int _countMatchingInvocations(
  AstNode node,
  bool Function(MethodInvocation) matches,
) {
  final counter = _MethodInvocationCounter(matches);
  node.accept(counter);
  return counter.count;
}

class _MethodInvocationCounter extends RecursiveAstVisitor<void> {
  _MethodInvocationCounter(this.matches);

  final bool Function(MethodInvocation) matches;
  int count = 0;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (matches(node)) count++;
    super.visitMethodInvocation(node);
  }
}

ModalSheetFunction? _modalSheetFunctionOf(MethodInvocation invocation) {
  final byName = switch (invocation.methodName.name) {
    'showModalBottomSheet' => ModalSheetFunction.showModalBottomSheet,
    'showCupertinoSheet' => ModalSheetFunction.showCupertinoSheet,
    _ => null,
  };
  if (byName == null) return null;

  final element = invocation.methodName.element;
  if (element != null) {
    if (element is! TopLevelFunctionElement) return null;
    if (!libraryIsFlutter(element)) return null;
    return byName;
  }

  // Synthetic parser tests can leave a BARE top-level call unresolved.
  // Restrict the name-fallback to a receiver-less call: a call with a
  // receiver — including a `dynamic` one in a resolved production build, whose
  // method element is also null — is a method invocation, not the top-level
  // Flutter function, so a customer method named `showModalBottomSheet` must
  // not be lowered. A resolved customer top-level look-alike is already
  // rejected by the element path above.
  if (invocation.realTarget != null) return null;
  return byName;
}

/// Extracts the widget expression from a static builder closure:
/// `(_) => Widget(...)` or `(_) { return Widget(...); }`.
ModalSheetBuilderOutcome recogniseStaticModalSheetBuilder(Expression builder) {
  if (builder is! FunctionExpression) {
    return const ModalSheetBuilderUnsupported(
      'the builder must be a static widget-returning closure',
    );
  }
  if (builder.body.isAsynchronous) {
    return const ModalSheetBuilderUnsupported(
      'the builder must be synchronous',
    );
  }

  final parameterNames = _parameterNames(builder);
  if (parameterNames.length != 1) {
    return const ModalSheetBuilderUnsupported(
      'the builder must take exactly one context parameter',
    );
  }

  final body = _singleReturnedExpression(builder.body);
  if (body == null) {
    return const ModalSheetBuilderUnsupported(
      'the builder must return exactly one widget expression',
    );
  }
  if (body is ConditionalExpression) {
    return const ModalSheetBuilderUnsupported(
      'conditional builders cannot be lowered to a single static sheet child',
    );
  }

  final contextName = parameterNames.single;
  if (contextName != '_' && _identifierIsReferenced(body, contextName)) {
    return const ModalSheetBuilderUnsupported(
      'builders that read their BuildContext cannot be lowered statically',
    );
  }

  return ModalSheetBuilderRecognised(body);
}

/// Recognises the only in-sheet close form that can lower without dropping a
/// result: `() => Navigator.pop(context)` or the block equivalent.
ModalSheetCloseOutcome recogniseModalSheetCloseHandler(Expression slotValue) {
  if (slotValue is! FunctionExpression) {
    return const ModalSheetCloseNotRecognised();
  }

  final popCount = _countNavigatorPopCalls(slotValue.body);
  if (popCount == 0) return const ModalSheetCloseNotRecognised();
  if (slotValue.body.isAsynchronous || !_hasNoParameters(slotValue)) {
    return const ModalSheetCloseUnsupported(
      kModalSheetNavigatorPopResultReason,
    );
  }
  if (popCount != 1) {
    return const ModalSheetCloseUnsupported(
      kModalSheetNavigatorPopResultReason,
    );
  }

  final call = _extractSingleCall(slotValue.body);
  if (call == null || !_isNavigatorPop(call)) {
    return const ModalSheetCloseUnsupported(
      kModalSheetNavigatorPopResultReason,
    );
  }
  if (call.argumentList.arguments.length != 1) {
    return const ModalSheetCloseUnsupported(
      kModalSheetNavigatorPopResultReason,
    );
  }
  return const ModalSheetCloseRecognised();
}

List<String> _parameterNames(FunctionExpression expression) {
  final parameters =
      expression.parameters?.parameters ?? const <FormalParameter>[];
  final names = <String>[];
  for (final parameter in parameters) {
    final name = parameter.name;
    if (name is Token) names.add(name.lexeme);
  }
  return names;
}

Expression? _singleReturnedExpression(FunctionBody body) {
  if (body is ExpressionFunctionBody) {
    return _unwrapParens(body.expression);
  }
  if (body is BlockFunctionBody) {
    final stmts = body.block.statements;
    if (stmts.length != 1) return null;
    final stmt = stmts.single;
    if (stmt is ReturnStatement) {
      final expr = stmt.expression;
      return expr == null ? null : _unwrapParens(expr);
    }
  }
  return null;
}

bool _identifierIsReferenced(AstNode node, String name) {
  final finder = _IdentifierReferenceFinder(name);
  node.accept(finder);
  return finder.found;
}

class _IdentifierReferenceFinder extends RecursiveAstVisitor<void> {
  _IdentifierReferenceFinder(this.name);

  final String name;
  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == name) found = true;
    super.visitSimpleIdentifier(node);
  }
}

int _countNavigatorPopCalls(AstNode node) =>
    _countMatchingInvocations(node, _isNavigatorPop);

bool _isNavigatorPop(MethodInvocation invocation) {
  if (invocation.methodName.name != 'pop') return false;
  final target = invocation.realTarget;
  if (target is! SimpleIdentifier || target.name != 'Navigator') return false;
  final element = target.element;
  // Resolved: must be the framework `Navigator` (a static `Navigator.pop`). A
  // customer look-alike named `Navigator` — a shadowing parameter/local or a
  // customer class — is rejected so its `pop` is not lowered as the sheet
  // close. Unresolved (synthetic parser-test input): fall back to the name.
  if (element != null) return libraryIsFlutter(element);
  return true;
}
