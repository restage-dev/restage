// The authored events app code fires, read from its resolved source.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart' show log;

import 'package:restage_codegen/src/const_value_literal.dart'
    show identifierElement;
import 'package:restage_codegen/src/islands/islands.dart' show Island;
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_classifier.dart'
    show isAppWidgetClass, isContextSurfaceEvent;

/// Reads the `context.surfaceEvent(...)` calls below a node, through the app
/// widgets, and the States of app widgets, it builds. A surface it builds
/// hosts its own events and isn't read.
final class AppWidgetEvents {
  /// Reads app code of [package] through [astNodeFor].
  AppWidgetEvents({
    required this.package,
    required this.astNodeFor,
    Set<String>? noticeKeys,
  }) : _noticeKeys = noticeKeys ?? <String>{};

  /// The app's package; widgets of other packages aren't read.
  final String? package;

  /// The resolved declaration of a fragment.
  final Future<AstNode?> Function(Fragment fragment) astNodeFor;

  final Map<ClassElement, List<MethodInvocation>> _byClass = {};

  // The warnings already logged this build.
  final Set<String> _noticeKeys;

  /// The event calls below [node] and in the app code it builds.
  Future<List<MethodInvocation>> callsBelow(AstNode node) =>
      _calls(node, Set.identity());

  /// The `SurfaceEvent` constants the app widgets [islands] show, and the
  /// app widgets in [placed] that render from their registered factories,
  /// fire from their own builds.
  Future<Set<PropertyInducingElement>> firedBy(
    Iterable<Island> islands,
    Iterable<ClassElement> placed,
  ) async {
    final fired = <PropertyInducingElement>{};
    final calls = [
      for (final island in islands) ...await callsBelow(island.node),
      for (final type in placed)
        if (!hostsEvents(type))
          ...switch (await astNodeFor(type.firstFragment)) {
            final declaration? => await callsBelow(declaration),
            null => const <MethodInvocation>[],
          },
    ];
    for (final call in calls) {
      if (_firedConstant(call) case final field?) fired.add(field);
      if (inlineEventIssue(call) case final issue?) {
        logBuildNoticeOnce(log, _noticeKeys, issue);
      }
    }
    return fired;
  }

  Future<List<MethodInvocation>> _calls(
    AstNode node,
    Set<ClassElement> visiting,
  ) async {
    final found = _EventCalls();
    node.accept(found);
    final calls = [...found.calls];
    for (final type in found.created) {
      // A StatefulWidget builds in its State, which its createState makes.
      final isState =
          type.allSupertypes.any((t) => t.element.name == 'State') &&
          type.library.uri.scheme == 'package' &&
          type.library.uri.pathSegments.first == package;
      if (!isState && !isAppWidgetClass(type, package: package)) continue;
      if (_byClass[type] case final known?) {
        calls.addAll(known);
        continue;
      }
      if (!visiting.add(type)) continue;
      final declaration = await astNodeFor(type.firstFragment);
      final own = declaration == null
          ? const <MethodInvocation>[]
          : await _calls(declaration, visiting);
      _byClass[type] = own;
      calls.addAll(own);
    }
    return calls;
  }
}

/// A warning for [call] when it fires an event constructed in place, which
/// no contract can name; null otherwise.
Issue? inlineEventIssue(MethodInvocation call) {
  final event = call.argumentList.arguments.firstOrNull;
  if (event is! InstanceCreationExpression ||
      event.constructorName.type.element?.name != 'SurfaceEvent') {
    return null;
  }
  final unit = event.root;
  final source = unit is CompilationUnit
      ? unit.declaredFragment?.source.uri.toString()
      : null;
  final at = unit is CompilationUnit
      ? unit.lineInfo.getLocation(event.offset)
      : null;
  final location = [
    ?source,
    if (at != null) '${at.lineNumber}:${at.columnNumber}',
  ].join(':');
  final declared = event.toSource().replaceFirst('const ', '');
  // A warning: the build still succeeds.
  return Issue(
    code: IssueCode.idiomAutoSubstituted,
    message:
        '`${call.toSource()}` at $location builds its event where it fires, '
        "so the surface's contract can't name it and the event refuses. Try "
        'declaring it as a constant, for example '
        '`static const myEvent = $declared;` or a top-level '
        '`const myEvent = $declared;`, and firing that.',
    location: location,
    buildNoticeIdentity: '$kInlineEventNoticePrefix$location',
  );
}

// The const `SurfaceEvent` [call] fires, when it names one.
PropertyInducingElement? _firedConstant(MethodInvocation call) {
  final event = call.argumentList.arguments.firstOrNull;
  return event == null || event is NamedArgument
      ? null
      : surfaceEventConstant(event.argumentExpression);
}

/// The const `SurfaceEvent` variable [expression] names: a static field or a
/// top-level constant. Null for anything else.
PropertyInducingElement? surfaceEventConstant(Expression expression) {
  var element = switch (expression) {
    final SimpleIdentifier identifier => identifierElement(identifier),
    PrefixedIdentifier(:final identifier) => identifierElement(identifier),
    PropertyAccess(:final propertyName) => identifierElement(propertyName),
    _ => null,
  };
  if (element is PropertyAccessorElement) element = element.variable;
  final constant = switch (element) {
    final FieldElement field when field.isStatic && field.isConst => field,
    final TopLevelVariableElement variable when variable.isConst => variable,
    _ => null,
  };
  final type = constant?.type;
  return type is InterfaceType &&
          type.element.name == 'SurfaceEvent' &&
          type.element.library.uri.toString().startsWith('package:restage/')
      ? constant
      : null;
}

/// Whether [type] is one of Restage's surface hosts or a mount generated
/// for an app surface, which host the events built inside them.
bool hostsEvents(ClassElement type) {
  final library = type.library.uri;
  if (library.scheme == 'package' &&
      library.pathSegments.first == 'restage' &&
      const {
        'RestageScreen',
        'RestagePaywall',
        'RestageFlowGraph',
        'RestageOnboarding',
        'RestagePlacement',
        'RestageEventDispatcher',
        'RestagePaywallEventDispatcher',
      }.contains(type.name)) {
    return true;
  }
  return type.firstFragment.libraryFragment.source.uri.path.contains(
    'restage.generated/',
  );
}

final class _EventCalls extends RecursiveAstVisitor<void> {
  final List<MethodInvocation> calls = [];
  final Set<ClassElement> created = {};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (isContextSurfaceEvent(node)) calls.add(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.element case final ClassElement type) {
      // A surface hosts the events built inside it.
      if (hostsEvents(type)) return;
      created.add(type);
    }
    super.visitInstanceCreationExpression(node);
  }
}
