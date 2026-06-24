import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/theme_recognition.dart';

/// Flutter route constructors recognised as declarative screen navigation.
enum NavigationRouteType {
  /// `MaterialPageRoute(...)` from Flutter Material.
  materialPageRoute,

  /// `CupertinoPageRoute(...)` from Flutter Cupertino.
  cupertinoPageRoute,
}

/// A clean supported navigation trigger captured by the classifier.
final class RecognisedNavigation {
  /// Creates a recognised navigation trigger.
  const RecognisedNavigation({
    required this.routeType,
    required this.pushCall,
    required this.route,
    required this.pushedScreen,
    required this.paywallSourceId,
  });

  /// Which Flutter route constructor was used.
  final NavigationRouteType routeType;

  /// The exact `Navigator.push(...)` invocation in the source AST.
  final MethodInvocation pushCall;

  /// The exact `MaterialPageRoute(...)` / `CupertinoPageRoute(...)`.
  final InstanceCreationExpression route;

  /// The static screen construction returned by the route builder.
  final InstanceCreationExpression pushedScreen;

  /// The `@PaywallSource(id:)` resolved from [pushedScreen].
  final String paywallSourceId;
}

/// Result of recognising a possible navigation trigger slot value.
sealed class NavigationTriggerOutcome {
  const NavigationTriggerOutcome();
}

/// The slot value is a clean synchronous navigation trigger.
final class NavigationRecognised extends NavigationTriggerOutcome {
  /// Creates a recognised outcome.
  const NavigationRecognised(this.navigation);

  /// The recognised navigation trigger.
  final RecognisedNavigation navigation;
}

/// The slot value references navigation but observes the route result.
final class NavigationResultDropped extends NavigationTriggerOutcome {
  /// Creates a result-drop outcome.
  const NavigationResultDropped(this.reason);

  /// Author-facing reason for the fatal defer.
  final String reason;
}

/// The slot value is navigation-shaped but outside the supported lowering.
final class NavigationFormUnsupported extends NavigationTriggerOutcome {
  /// Creates an unsupported-form outcome.
  const NavigationFormUnsupported(this.reason);

  /// Author-facing reason for the fatal defer.
  final String reason;
}

/// The slot value is not a navigation trigger.
final class NavigationNotRecognised extends NavigationTriggerOutcome {
  /// Creates a not-recognised outcome.
  const NavigationNotRecognised();
}

/// Result of extracting a static route builder body.
sealed class NavigationBuilderOutcome {
  const NavigationBuilderOutcome();
}

/// The builder closure reduces to one static screen construction.
final class NavigationBuilderRecognised extends NavigationBuilderOutcome {
  /// Creates a recognised builder outcome.
  const NavigationBuilderRecognised(this.screen);

  /// The screen construction returned by the builder.
  final InstanceCreationExpression screen;
}

/// The builder closure cannot be lowered to a declarative screen reference.
final class NavigationBuilderUnsupported extends NavigationBuilderOutcome {
  /// Creates an unsupported builder outcome.
  const NavigationBuilderUnsupported(this.reason);

  /// Author-facing reason for the fatal defer.
  final String reason;
}

/// Result of recognising a flow-screen back callback.
sealed class NavigatorPopBackOutcome {
  const NavigatorPopBackOutcome();
}

/// The callback is exactly `() => Navigator.pop(context)`.
final class NavigatorPopBackRecognised extends NavigatorPopBackOutcome {
  /// Creates a recognised pop-back outcome.
  const NavigatorPopBackRecognised(this.contextIdentifier);

  /// The context identifier passed to `Navigator.pop`.
  final SimpleIdentifier contextIdentifier;
}

/// The callback uses `Navigator.pop(context, result)`.
final class NavigatorPopResultUnsupported extends NavigatorPopBackOutcome {
  /// Creates a result-bearing pop outcome.
  const NavigatorPopResultUnsupported(this.reason);

  /// Author-facing reason for the fatal defer.
  final String reason;
}

/// The callback is not a flow-screen pop-back form.
final class NavigatorPopNotRecognised extends NavigatorPopBackOutcome {
  /// Creates a not-recognised pop outcome.
  const NavigatorPopNotRecognised();
}

/// How a route named argument is handled by navigation lowering.
enum RouteArgumentDisposition {
  /// The argument supplies the pushed screen builder.
  builder,

  /// The argument has no faithful declarative-flow equivalent.
  defer,
}

/// Per-route argument disposition tables. Keeping the tables public within
/// the package lets tests pin completeness without duplicating the list.
const Map<NavigationRouteType, Map<String, RouteArgumentDisposition>>
    kRouteArgumentDispositions = {
  NavigationRouteType.materialPageRoute: {
    'builder': RouteArgumentDisposition.builder,
    'settings': RouteArgumentDisposition.defer,
    'requestFocus': RouteArgumentDisposition.defer,
    'maintainState': RouteArgumentDisposition.defer,
    'fullscreenDialog': RouteArgumentDisposition.defer,
    'allowSnapshotting': RouteArgumentDisposition.defer,
    'barrierDismissible': RouteArgumentDisposition.defer,
    'traversalEdgeBehavior': RouteArgumentDisposition.defer,
    'directionalTraversalEdgeBehavior': RouteArgumentDisposition.defer,
  },
  NavigationRouteType.cupertinoPageRoute: {
    'builder': RouteArgumentDisposition.builder,
    'title': RouteArgumentDisposition.defer,
    'settings': RouteArgumentDisposition.defer,
    'requestFocus': RouteArgumentDisposition.defer,
    'maintainState': RouteArgumentDisposition.defer,
    'fullscreenDialog': RouteArgumentDisposition.defer,
    'allowSnapshotting': RouteArgumentDisposition.defer,
    'barrierDismissible': RouteArgumentDisposition.defer,
  },
};

/// Fatal-defer reason for navigation forms that observe the pushed result.
const String kNavigationResultDroppedReason =
    "the pushed route's result value cannot be observed declaratively; drive a "
    'state field from the pushed screen instead';

/// Fatal-defer reason for unsupported Navigator APIs.
const String kNavigationNavigatorFormUnsupportedReason =
    'only a single Navigator.push(context, route) or '
    'Navigator.of(context).push(route) call can be lowered to a declarative '
    'two-screen flow';

/// Fatal-defer reason for unsupported route expressions.
const String kNavigationRouteUnsupportedReason =
    'only a direct MaterialPageRoute(...) or CupertinoPageRoute(...) can be '
    'lowered to a declarative two-screen flow';

/// Fatal-defer reason for customized route arguments.
const String kNavigationRouteArgumentUnsupportedReason =
    'customized route arguments have no faithful declarative-flow equivalent';

/// Fatal-defer reason for dynamic or context-dependent route builders.
const String kNavigationBuilderUnsupportedReason =
    'the route builder must synchronously return one static screen '
    'construction without reading its BuildContext';

/// Fatal-defer reason for pushed screens that are not paywall sources.
const String kNavigationPushedScreenUnsupportedReason =
    'the pushed screen must be a resolved @PaywallSource class';

/// Fatal-defer reason for `Navigator.pop(context, result)` in flow content.
const String kNavigationNavigatorPopResultReason =
    'Navigator.pop(context, result) returns a route result that cannot be '
    'observed declaratively; navigate back without a result';

/// Fatal-defer reason for a pushed-screen construction that carries arguments
/// or uses a named constructor. The flow can only carry `paywallScreen(id)`, so
/// constructor state / named-constructor semantics have no declarative channel.
const String kNavigationPushedScreenFormReason =
    'the pushed screen must be constructed with no arguments via its default '
    'constructor; constructor arguments cannot be carried into the flow';

/// Fatal-defer reason for a navigation context that is not the build method's
/// BuildContext, referenced directly. A key.currentContext / member access /
/// method call may target a different navigator than the current flow.
const String kNavigationContextUnsupportedReason =
    'the navigation context must be the build method BuildContext referenced '
    'directly (e.g. Navigator.push(context, route))';

/// Fatal-defer reason for `Navigator.of(...)` forms that cannot be lowered —
/// `rootNavigator: true` and any non-default-context `of(...)` call.
const String kNavigationRootNavigatorUnsupportedReason =
    'Navigator.of(context, rootNavigator: true) and other non-default '
    'Navigator.of(...) forms cannot be lowered; use '
    'Navigator.of(context).push(route)';

/// Fatal-defer reason for navigation calls outside supported trigger slots.
const String kNavigationTriggerSlotUnsupportedReason =
    'screen navigation can only be lowered from an onPressed or onTap callback';

/// Whether a catalog event slot can host a declarative navigation trigger.
bool isNavigationTriggerSlotName(String name) =>
    name == 'onPressed' || name == 'onTap';

/// The Restage SDK library origin used to look-alike-guard the pushed screen's
/// `@PaywallSource` annotation (a customer annotation of the same name from a
/// different package must not be accepted).
const String _kSdkLibraryOrigin = 'package:restage';

/// Recognises the only navigation trigger form that can be lowered without
/// dropping a route result: `() => Navigator.push(...)` or the block
/// equivalent.
NavigationTriggerOutcome recogniseNavigationTrigger(Expression slotValue) {
  if (slotValue is! FunctionExpression) {
    return const NavigationNotRecognised();
  }

  final navigationCallCount = _countNavigatorCalls(slotValue.body);
  if (navigationCallCount == 0) return const NavigationNotRecognised();

  if (slotValue.body.isAsynchronous || !_hasNoParameters(slotValue)) {
    return const NavigationResultDropped(kNavigationResultDroppedReason);
  }

  // More than one navigation call means route completion / sequencing could be
  // observed. Never silently lower it to a single declarative transition.
  if (navigationCallCount != 1) {
    return const NavigationResultDropped(kNavigationResultDroppedReason);
  }

  final call = _extractSingleCall(slotValue.body);
  if (call == null) {
    return const NavigationResultDropped(kNavigationResultDroppedReason);
  }

  switch (_recogniseNavigatorPush(call)) {
    case _NavigatorPushRecognised(:final route):
      switch (_recogniseRoute(route)) {
        case _RouteRecognised(
            :final routeType,
            :final route,
            :final pushedScreen,
            :final paywallSourceId,
          ):
          return NavigationRecognised(
            RecognisedNavigation(
              routeType: routeType,
              pushCall: call,
              route: route,
              pushedScreen: pushedScreen,
              paywallSourceId: paywallSourceId,
            ),
          );
        case _RouteUnsupported(:final reason):
          return NavigationFormUnsupported(reason);
      }
    case _NavigatorPushUnsupported(:final reason):
      return NavigationFormUnsupported(reason);
    case _NavigatorPushNotRecognised():
      return const NavigationResultDropped(kNavigationResultDroppedReason);
  }
}

/// Extracts the screen construction from a static route builder closure:
/// `(_) => Screen(...)` or `(_) { return Screen(...); }`.
NavigationBuilderOutcome recogniseStaticNavigationBuilder(Expression builder) {
  if (builder is! FunctionExpression) {
    return const NavigationBuilderUnsupported(
      kNavigationBuilderUnsupportedReason,
    );
  }
  if (builder.body.isAsynchronous) {
    return const NavigationBuilderUnsupported(
      'the route builder must be synchronous',
    );
  }

  final parameterNames = _parameterNames(builder);
  if (parameterNames.length != 1) {
    return const NavigationBuilderUnsupported(
      'the route builder must take exactly one context parameter',
    );
  }

  final body = _singleReturnedExpression(builder.body);
  if (body == null) {
    return const NavigationBuilderUnsupported(
      'the route builder must return exactly one screen construction',
    );
  }
  if (body is ConditionalExpression) {
    return const NavigationBuilderUnsupported(
      'conditional route builders cannot be lowered to one declarative screen',
    );
  }
  if (body is! InstanceCreationExpression) {
    return const NavigationBuilderUnsupported(
      'the route builder must return a direct screen construction',
    );
  }
  // The flow transition carries only `paywallScreen(id)`; a construction with
  // arguments or a named constructor has no declarative channel for that state
  // and must fatal-defer rather than silently drop it.
  if (body.constructorName.name != null ||
      body.argumentList.arguments.isNotEmpty) {
    return const NavigationBuilderUnsupported(
      kNavigationPushedScreenFormReason,
    );
  }

  final contextName = parameterNames.single;
  if (contextName != '_' && _identifierIsReferenced(body, contextName)) {
    return const NavigationBuilderUnsupported(
      'route builders that read their BuildContext cannot be lowered '
      'statically',
    );
  }

  return NavigationBuilderRecognised(body);
}

/// Recognises the flow-screen back form: `() => Navigator.pop(context)`.
NavigatorPopBackOutcome recogniseNavigatorPopBack(Expression slotValue) {
  if (slotValue is! FunctionExpression) {
    return const NavigatorPopNotRecognised();
  }

  final popCount = _countNavigatorPopCalls(slotValue.body);
  if (popCount == 0) return const NavigatorPopNotRecognised();
  if (slotValue.body.isAsynchronous || !_hasNoParameters(slotValue)) {
    return const NavigatorPopNotRecognised();
  }
  if (popCount != 1) return const NavigatorPopNotRecognised();

  final call = _extractSingleCall(slotValue.body);
  if (call == null || !_isNavigatorPop(call)) {
    return const NavigatorPopNotRecognised();
  }
  if (call.argumentList.arguments.length == 1) {
    final arg = call.argumentList.arguments.single;
    if (arg is NamedExpression) return const NavigatorPopNotRecognised();
    final context = _unwrapParens(arg);
    if (context is! SimpleIdentifier) {
      return const NavigatorPopNotRecognised();
    }
    return NavigatorPopBackRecognised(context);
  }
  if (call.argumentList.arguments.length > 1) {
    return const NavigatorPopResultUnsupported(
      kNavigationNavigatorPopResultReason,
    );
  }
  return const NavigatorPopNotRecognised();
}

/// The `@PaywallSource(id:)` resolved from [pushedScreen], or `null`.
///
/// Origin-guarded against the Restage SDK library so a customer annotation that
/// happens to be named `PaywallSource` (from a different package) is not
/// accepted as a valid pushed paywall screen (the look-alike-safe discipline).
String? pushedPaywallSourceId(InstanceCreationExpression pushedScreen) {
  final classElement = pushedScreen.constructorName.type.element;
  if (classElement is! ClassElement) return null;
  final annotation = firstAnnotationFromOriginAny(
    classElement,
    const {'PaywallSource'},
    _kSdkLibraryOrigin,
  );
  final value = annotation?.computeConstantValue();
  return value?.getField('id')?.toStringValue();
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

Expression _unwrapParens(Expression expr) =>
    expr is ParenthesizedExpression ? _unwrapParens(expr.expression) : expr;

sealed class _NavigatorPushOutcome {
  const _NavigatorPushOutcome();
}

final class _NavigatorPushRecognised extends _NavigatorPushOutcome {
  const _NavigatorPushRecognised(this.route);

  final Expression route;
}

final class _NavigatorPushUnsupported extends _NavigatorPushOutcome {
  const _NavigatorPushUnsupported(this.reason);

  final String reason;
}

final class _NavigatorPushNotRecognised extends _NavigatorPushOutcome {
  const _NavigatorPushNotRecognised();
}

_NavigatorPushOutcome _recogniseNavigatorPush(MethodInvocation invocation) {
  final receiver = _navigatorReceiverOf(invocation);
  if (receiver == null) return const _NavigatorPushNotRecognised();

  if (invocation.methodName.name != 'push') {
    return const _NavigatorPushUnsupported(
      kNavigationNavigatorFormUnsupportedReason,
    );
  }

  final methodElement = invocation.methodName.element;
  if (methodElement != null && !libraryIsFlutter(methodElement)) {
    return const _NavigatorPushNotRecognised();
  }

  final args = invocation.argumentList.arguments;
  if (args.any((arg) => arg is NamedExpression)) {
    return const _NavigatorPushUnsupported(
      kNavigationNavigatorFormUnsupportedReason,
    );
  }

  switch (receiver) {
    case _StaticNavigatorReceiver():
      if (args.length != 2) {
        return const _NavigatorPushUnsupported(
          kNavigationNavigatorFormUnsupportedReason,
        );
      }
      // The first argument selects the target navigator. Only the build method
      // BuildContext (a bare identifier) lowers to a depth-1 in-flow
      // transition; a key.currentContext / member access / call may target a
      // different navigator. (Batch B additionally verifies the identifier
      // resolves to the build method's BuildContext parameter.)
      if (args.first is! SimpleIdentifier) {
        return const _NavigatorPushUnsupported(
          kNavigationContextUnsupportedReason,
        );
      }
      return _NavigatorPushRecognised(args[1]);
    case _NavigatorOfReceiver(:final context):
      if (context == null) {
        return const _NavigatorPushUnsupported(
          kNavigationRootNavigatorUnsupportedReason,
        );
      }
      if (context is! SimpleIdentifier) {
        return const _NavigatorPushUnsupported(
          kNavigationContextUnsupportedReason,
        );
      }
      if (args.length != 1) {
        return const _NavigatorPushUnsupported(
          kNavigationNavigatorFormUnsupportedReason,
        );
      }
      return _NavigatorPushRecognised(args.single);
  }
}

sealed class _NavigatorReceiver {
  const _NavigatorReceiver();
}

final class _StaticNavigatorReceiver extends _NavigatorReceiver {
  const _StaticNavigatorReceiver();
}

final class _NavigatorOfReceiver extends _NavigatorReceiver {
  const _NavigatorOfReceiver(this.context);

  /// The single positional `Navigator.of(<context>)` argument, or `null` when
  /// the call is not `Navigator.of(<single positional>)` (e.g. an extra arg
  /// such as `rootNavigator: true`).
  final Expression? context;
}

_NavigatorReceiver? _navigatorReceiverOf(MethodInvocation invocation) {
  final target = invocation.realTarget;
  if (_isFlutterNavigatorTarget(target)) {
    return const _StaticNavigatorReceiver();
  }
  if (target is MethodInvocation && _isNavigatorOfInvocation(target)) {
    return _NavigatorOfReceiver(_navigatorOfContext(target));
  }
  return null;
}

bool _isNavigatorOfInvocation(MethodInvocation invocation) {
  if (invocation.methodName.name != 'of') return false;
  if (!_isFlutterNavigatorTarget(invocation.realTarget)) return false;
  final methodElement = invocation.methodName.element;
  if (methodElement != null && !libraryIsFlutter(methodElement)) return false;
  return true;
}

/// The single positional `Navigator.of(<context>)` argument, or `null` when the
/// call has a different argument shape (extra or named args, e.g.
/// `rootNavigator: true`).
Expression? _navigatorOfContext(MethodInvocation invocation) {
  final args = invocation.argumentList.arguments;
  if (args.length != 1) return null;
  final arg = args.single;
  if (arg is NamedExpression) return null;
  return arg;
}

/// Whether [target] references the Flutter `Navigator` class, either bare
/// (`Navigator`) or import-prefixed (`material.Navigator`). Element-gated so a
/// resolved customer look-alike is rejected. A null element on the BARE form
/// falls back to the name for synthetic unresolved parser-test input; a
/// prefixed form requires resolution (it only appears in real resolved code, so
/// a name-only fallback would risk admitting a customer `obj.Navigator`).
bool _isFlutterNavigatorTarget(Expression? target) {
  if (target is SimpleIdentifier) {
    if (target.name != 'Navigator') return false;
    final element = target.element;
    if (element != null) return libraryIsFlutter(element);
    return true;
  }
  if (target is PrefixedIdentifier) {
    if (target.identifier.name != 'Navigator') return false;
    final element = target.identifier.element;
    return element != null && libraryIsFlutter(element);
  }
  return false;
}

sealed class _RouteOutcome {
  const _RouteOutcome();
}

final class _RouteRecognised extends _RouteOutcome {
  const _RouteRecognised({
    required this.routeType,
    required this.route,
    required this.pushedScreen,
    required this.paywallSourceId,
  });

  final NavigationRouteType routeType;
  final InstanceCreationExpression route;
  final InstanceCreationExpression pushedScreen;
  final String paywallSourceId;
}

final class _RouteUnsupported extends _RouteOutcome {
  const _RouteUnsupported(this.reason);

  final String reason;
}

_RouteOutcome _recogniseRoute(Expression routeExpression) {
  final route = _unwrapParens(routeExpression);
  if (route is! InstanceCreationExpression) {
    return const _RouteUnsupported(kNavigationRouteUnsupportedReason);
  }

  final routeType = _routeTypeOf(route);
  if (routeType == null) {
    return const _RouteUnsupported(kNavigationRouteUnsupportedReason);
  }

  final dispositions = kRouteArgumentDispositions[routeType]!;
  Expression? builder;
  for (final arg in route.argumentList.arguments) {
    if (arg is! NamedExpression) {
      return const _RouteUnsupported(
        kNavigationRouteArgumentUnsupportedReason,
      );
    }
    final name = arg.name.label.name;
    final disposition = dispositions[name];
    if (disposition == null) {
      return _RouteUnsupported(_routeArgumentReason(name));
    }
    switch (disposition) {
      case RouteArgumentDisposition.builder:
        builder = arg.expression;
      case RouteArgumentDisposition.defer:
        return _RouteUnsupported(_routeArgumentReason(name));
    }
  }

  if (builder == null) {
    return const _RouteUnsupported(kNavigationBuilderUnsupportedReason);
  }

  switch (recogniseStaticNavigationBuilder(builder)) {
    case NavigationBuilderRecognised(:final screen):
      final paywallSourceId = pushedPaywallSourceId(screen);
      if (paywallSourceId == null) {
        return const _RouteUnsupported(
          kNavigationPushedScreenUnsupportedReason,
        );
      }
      return _RouteRecognised(
        routeType: routeType,
        route: route,
        pushedScreen: screen,
        paywallSourceId: paywallSourceId,
      );
    case NavigationBuilderUnsupported(:final reason):
      return _RouteUnsupported(reason);
  }
}

NavigationRouteType? _routeTypeOf(InstanceCreationExpression expr) {
  if (expr.constructorName.name != null) return null;

  final typeName = _routeClassName(expr);
  final byName = switch (typeName) {
    'MaterialPageRoute' => NavigationRouteType.materialPageRoute,
    'CupertinoPageRoute' => NavigationRouteType.cupertinoPageRoute,
    _ => null,
  };
  if (byName == null) return null;

  final constructorElement = expr.constructorName.element;
  if (constructorElement != null) {
    if (!libraryIsFlutter(constructorElement)) return null;
    return byName;
  }

  final classElement = expr.constructorName.type.element;
  if (classElement != null) {
    if (!libraryIsFlutter(classElement)) return null;
    return byName;
  }

  return byName;
}

String _routeClassName(InstanceCreationExpression expr) {
  final constructorElement = expr.constructorName.element;
  if (constructorElement is ConstructorElement) {
    return constructorElement.enclosingElement.name ??
        expr.constructorName.type.name.lexeme;
  }
  return expr.constructorName.type.element?.name ??
      expr.constructorName.type.name.lexeme;
}

/// The customized-route-argument fatal-defer reason, stamped with the offending
/// argument [name]. Centralised so the base reason constant has no hidden
/// suffix convention at its call sites.
String _routeArgumentReason(String name) =>
    '$kNavigationRouteArgumentUnsupportedReason: $name';

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

int _countNavigatorCalls(AstNode node) =>
    _countMatchingInvocations(node, _isNavigatorActionCall);

bool _isNavigatorActionCall(MethodInvocation invocation) =>
    invocation.methodName.name != 'of' &&
    _navigatorReceiverOf(invocation) != null;

int _countNavigatorPopCalls(AstNode node) =>
    _countMatchingInvocations(node, _isNavigatorPop);

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

bool _isNavigatorPop(MethodInvocation invocation) {
  if (invocation.methodName.name != 'pop') return false;
  if (!_isFlutterNavigatorTarget(invocation.realTarget)) return false;
  final methodElement = invocation.methodName.element;
  if (methodElement != null && !libraryIsFlutter(methodElement)) return false;
  return true;
}
