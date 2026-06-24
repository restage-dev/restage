import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/theme_recognition.dart';

/// How a `DraggableScrollableSheet` named argument is handled when lowering it
/// to the declarative draggable surface. Keeping the table public within the
/// package lets a test pin completeness against the live Flutter signature
/// without duplicating the list.
enum DraggableSheetArgumentDisposition {
  /// Maps 1:1 onto a catalog slot of the same name (a static literal value).
  map,

  /// Supplies the builder closure whose inner content becomes the child.
  builder,

  /// Intentionally ignored (the universal super-key convention).
  drop,

  /// Dedicated handling: a non-empty list has no wire slot, so it fatal-defers;
  /// an absent / empty list is dropped.
  snapSizes,

  /// Dedicated handling: the persistent surface never closes, so a `true`
  /// (a closeable sheet) fatal-defers; `false` / absent is dropped.
  shouldCloseOnMinExtent,

  /// Dedicated handling: an author-supplied controller is an imperative escape
  /// hatch with no declarative equivalent — always fatal-defer.
  controller,
}

/// Per-parameter disposition table for the `DraggableScrollableSheet`
/// constructor. A test pins these keys to the current Flutter signature.
const Map<String, DraggableSheetArgumentDisposition>
    kDraggableSheetArgumentDispositions = {
  'key': DraggableSheetArgumentDisposition.drop,
  'initialChildSize': DraggableSheetArgumentDisposition.map,
  'minChildSize': DraggableSheetArgumentDisposition.map,
  'maxChildSize': DraggableSheetArgumentDisposition.map,
  'expand': DraggableSheetArgumentDisposition.map,
  'snap': DraggableSheetArgumentDisposition.map,
  'snapAnimationDuration': DraggableSheetArgumentDisposition.map,
  'snapSizes': DraggableSheetArgumentDisposition.snapSizes,
  'shouldCloseOnMinExtent':
      DraggableSheetArgumentDisposition.shouldCloseOnMinExtent,
  'controller': DraggableSheetArgumentDisposition.controller,
  'builder': DraggableSheetArgumentDisposition.builder,
};

/// Fatal-defer reason: `snapSizes` carries intermediate snap stops that have no
/// declarative slot, and dropping one would change a multi-stop sheet into a
/// two-stop one.
const String kDraggableSheetSnapSizesUnsupportedReason =
    'snapSizes has no declarative equivalent — dropping an intermediate snap '
    'stop would change the sheet behaviour; remove snapSizes or render this '
    'sheet in your app';

/// Fatal-defer reason: the surface owns its drag controller internally, so an
/// author-supplied controller cannot be threaded.
const String kDraggableSheetControllerUnsupportedReason =
    'an author-supplied controller is an imperative escape hatch with no '
    'declarative equivalent — drive expansion through a bound state field '
    'instead, or render this sheet in your app';

/// Fatal-defer reason: a `true` value makes the sheet closeable, which the
/// persistent surface does not support.
const String kDraggableSheetShouldCloseOnMinExtentReason =
    'shouldCloseOnMinExtent: true makes the sheet closeable, which this '
    'persistent surface does not support — use a modal sheet for a dismissible '
    'sheet, or render this sheet in your app';

/// Fatal-defer reason: the builder is not a static two-parameter closure that
/// returns a single widget.
const String kDraggableSheetBuilderUnsupportedReason =
    'the builder must be a static (context, scrollController) closure that '
    'returns a single widget';

/// Fatal-defer reason: the builder body is not the canonical single
/// `SingleChildScrollView(controller: scrollController, child: ...)` form.
const String kDraggableSheetScrollableChildUnsupportedReason =
    'the builder must return a single '
    'SingleChildScrollView(controller: scrollController, child: ...) whose '
    'controller is exactly the builder scroll controller and whose child is '
    'ordinary (non-scrollable) content; a scrollable body, a body that ignores '
    'the controller, or a controller bound elsewhere has no faithful '
    'declarative equivalent — wrap your content as '
    'SingleChildScrollView(controller: scrollController, child: ...) at the '
    'builder top level, or render this sheet in your app';

/// Fatal-defer reason: the builder's `SingleChildScrollView` carries an
/// argument beyond `key` / `controller` / `child`, which the wrapper cannot
/// reproduce.
const String kDraggableSheetScrollViewArgUnsupportedReason =
    'the builder SingleChildScrollView may carry only key, controller, and '
    'child — any other argument (padding, physics, reverse, scrollDirection, '
    'and so on) cannot be reproduced declaratively; remove it so the content '
    'reduces to SingleChildScrollView(controller: scrollController, '
    'child: ...) or render this sheet in your app';

/// Outcome of reconciling a `DraggableScrollableSheet` builder to the inert
/// `child` content the declarative surface re-wraps.
sealed class DraggableSheetBuilderOutcome {
  const DraggableSheetBuilderOutcome();
}

/// The builder reduces to the canonical scroll-view form; [content] is the
/// inner child to lower onto the declarative `child` slot.
final class DraggableSheetRecognised extends DraggableSheetBuilderOutcome {
  /// Creates a recognised outcome carrying the inner child [content].
  const DraggableSheetRecognised(this.content);

  /// The inner widget expression to translate onto the `child` slot.
  final Expression content;
}

/// The builder is a recognised closure shape but cannot lower faithfully;
/// [reason] is the author-facing fatal-defer message.
final class DraggableSheetDeferred extends DraggableSheetBuilderOutcome {
  /// Creates a fatal-defer outcome carrying the author-facing [reason].
  const DraggableSheetDeferred(this.reason);

  /// Author-facing reason for the fatal defer.
  final String reason;
}

/// The builder is not even a static two-parameter widget-returning closure.
final class DraggableSheetNotRecognised extends DraggableSheetBuilderOutcome {
  /// Creates a not-recognised outcome.
  const DraggableSheetNotRecognised();
}

/// Reconciles a `DraggableScrollableSheet` builder closure to the inert child
/// content the declarative surface re-wraps in its own single scroll view.
///
/// Recognises the only byte-faithful form — a static `(context,
/// scrollController)` closure whose single returned widget is
/// `SingleChildScrollView(controller: scrollController, child: content)` with
/// the scroll view carrying nothing beyond `key` / `controller` / `child`.
/// Returns [DraggableSheetRecognised] with that `content`, a
/// [DraggableSheetDeferred] with a specific reason for any non-faithful body,
/// or [DraggableSheetNotRecognised] when the builder is not a static
/// two-parameter widget-returning closure.
DraggableSheetBuilderOutcome recogniseDraggableSheetBuilder(
  Expression builder,
) {
  if (builder is! FunctionExpression) {
    return const DraggableSheetNotRecognised();
  }
  if (builder.body.isAsynchronous) {
    return const DraggableSheetNotRecognised();
  }
  final params = builder.parameters?.parameters ?? const <FormalParameter>[];
  if (params.length != 2) {
    return const DraggableSheetNotRecognised();
  }
  final body = _singleReturnedExpression(builder.body);
  if (body == null || body is ConditionalExpression) {
    return const DraggableSheetNotRecognised();
  }
  return _proveControllerThread(body, params[1]);
}

/// Proves the builder body [w] is the canonical single
/// `SingleChildScrollView(controller: sc, child: ...)` form whose controller is
/// exactly the [scParam] formal, and returns the inner child as recognised.
DraggableSheetBuilderOutcome _proveControllerThread(
  Expression w,
  FormalParameter scParam,
) {
  final scElement = scParam.declaredFragment?.element;
  final scName = scParam.name?.lexeme;

  // The scroll controller must be referenced exactly once: zero means the body
  // ignores it (no drag-scroll); more than once means it is bound elsewhere.
  final census = _ScrollControllerReferenceCensus(scElement, scName);
  w.accept(census);
  if (census.count != 1) {
    return const DraggableSheetDeferred(
      kDraggableSheetScrollableChildUnsupportedReason,
    );
  }

  // The outermost widget must be the real-Flutter unnamed scroll view.
  final construction = _constructionView(w);
  if (construction == null ||
      construction.typeName != 'SingleChildScrollView' ||
      construction.memberName != null ||
      !_flutterOrUnresolved(construction.cls)) {
    return const DraggableSheetDeferred(
      kDraggableSheetScrollableChildUnsupportedReason,
    );
  }

  // Strict argument subset {key, controller, child}; anything else cannot be
  // reproduced by the wrapper's own bare scroll view.
  Expression? controllerArg;
  Expression? childArg;
  for (final arg in construction.arguments.arguments) {
    if (arg is! NamedExpression) {
      return const DraggableSheetDeferred(
        kDraggableSheetScrollViewArgUnsupportedReason,
      );
    }
    switch (arg.name.label.name) {
      case 'key':
        break;
      case 'controller':
        controllerArg = arg.expression;
      case 'child':
        childArg = arg.expression;
      default:
        return const DraggableSheetDeferred(
          kDraggableSheetScrollViewArgUnsupportedReason,
        );
    }
  }

  // The single reference must be the scroll view's own controller, and a child
  // must be present. (The reference census already guarantees the child is
  // controller-free.)
  if (controllerArg == null ||
      !_isScrollControllerReference(controllerArg, scElement, scName)) {
    return const DraggableSheetDeferred(
      kDraggableSheetScrollableChildUnsupportedReason,
    );
  }
  if (childArg == null) {
    return const DraggableSheetDeferred(
      kDraggableSheetScrollableChildUnsupportedReason,
    );
  }
  return DraggableSheetRecognised(childArg);
}

/// Returns the single widget a closure body reduces to: `=> W` or
/// `{ return W; }`, with semantically-inert parentheses stripped; `null` for
/// any richer shape.
Expression? _singleReturnedExpression(FunctionBody body) {
  if (body is ExpressionFunctionBody) {
    return _stripParens(body.expression);
  }
  if (body is BlockFunctionBody) {
    final statements = body.block.statements;
    if (statements.length != 1) return null;
    final statement = statements.single;
    if (statement is ReturnStatement) {
      final expression = statement.expression;
      return expression == null ? null : _stripParens(expression);
    }
  }
  return null;
}

Expression _stripParens(Expression expression) =>
    expression is ParenthesizedExpression
        ? _stripParens(expression.expression)
        : expression;

/// Resolved-element preferred, name fallback: whether [expression] references
/// the scroll-controller formal.
bool _isScrollControllerReference(
  Expression expression,
  Element? element,
  String? name,
) {
  final identifier = _stripParens(expression);
  if (identifier is! SimpleIdentifier) return false;
  if (element != null && identifier.element != null) {
    return identifier.element == element;
  }
  return name != null && identifier.name == name;
}

/// A uniform view over a widget construction, whether the analyzer resolved it
/// to an [InstanceCreationExpression] (the production, fully-resolved case) or
/// left it as a receiver-less `Foo(args)` [MethodInvocation] (a synthetic /
/// not-yet-resolved input — the form the translator handles throughout).
typedef _Construction = ({
  String typeName,
  String? memberName,
  ClassElement? cls,
  ArgumentList arguments,
});

_Construction? _constructionView(Expression expr) {
  if (expr is InstanceCreationExpression) {
    final element = expr.constructorName.type.element;
    return (
      typeName: _instanceTypeName(expr),
      memberName: _instanceMemberName(expr),
      cls: element is ClassElement ? element : null,
      arguments: expr.argumentList,
    );
  }
  // A bare, receiver-less `Foo(args)` the resolver did not rewrite into a
  // construction. A call with a receiver (e.g. `ListView.builder(...)`) is not
  // the canonical unnamed scroll view, so it is intentionally excluded. Only an
  // UNRESOLVED call (a synthetic test input — null element, the name fallback)
  // or a genuine constructor element is a construction; a call that RESOLVED to
  // a non-constructor (a customer/helper function named like the scroll view)
  // is NOT, and must fall through so the builder fatal-defers rather than be
  // mis-recognised as the canonical scroll view and silently mis-lowered.
  if (expr is MethodInvocation && expr.realTarget == null) {
    final element = expr.methodName.element;
    if (element != null && element is! ConstructorElement) return null;
    final cls = element is ConstructorElement ? element.enclosingElement : null;
    return (
      typeName: expr.methodName.name,
      memberName: null,
      cls: cls is ClassElement ? cls : null,
      arguments: expr.argumentList,
    );
  }
  return null;
}

String _instanceTypeName(InstanceCreationExpression expr) {
  final prefix = expr.constructorName.type.importPrefix?.name.lexeme;
  if (prefix != null && expr.constructorName.name == null) return prefix;
  return expr.constructorName.type.name.lexeme;
}

String? _instanceMemberName(InstanceCreationExpression expr) {
  final prefix = expr.constructorName.type.importPrefix?.name.lexeme;
  if (prefix != null && expr.constructorName.name == null) {
    return expr.constructorName.type.name.lexeme;
  }
  return expr.constructorName.name?.name;
}

/// Resolved-element preferred, name fallback (a customer look-alike resolves to
/// a non-Flutter library; a synthetic unresolved input falls back to the name).
bool _flutterOrUnresolved(Element? element) =>
    element == null || libraryIsFlutter(element);

/// Counts references to the scroll-controller formal in a subtree, preferring
/// the resolved element and falling back to the formal's name.
class _ScrollControllerReferenceCensus extends RecursiveAstVisitor<void> {
  _ScrollControllerReferenceCensus(this.element, this.name);

  final Element? element;
  final String? name;
  int count = 0;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_matches(node)) count++;
    super.visitSimpleIdentifier(node);
  }

  bool _matches(SimpleIdentifier identifier) {
    if (element != null && identifier.element != null) {
      return identifier.element == element;
    }
    return name != null && identifier.name == name;
  }
}
