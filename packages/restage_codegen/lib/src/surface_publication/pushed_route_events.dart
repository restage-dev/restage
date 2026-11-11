// Finds routes whose content fires surface events from outside the surface.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

import 'package:restage_codegen/src/annotation_lookup.dart'
    show firstAnnotation;
import 'package:restage_codegen/src/expression_translator.dart'
    show routeContents;
import 'package:restage_codegen/src/surface_publication/app_widget_events.dart';

/// A warning for each route or dialog in [library] whose content fires
/// `context.surfaceEvent(...)` without carrying the event scopes of the
/// surface that pushes it. A class in [recorded] has a generated copy that
/// carries them.
Future<List<String>> pushedRouteEventWarnings(
  LibraryElement library, {
  required String path,
  required Future<AstNode?> Function(Fragment fragment) astNodeFor,
  required Set<ClassElement> recorded,
}) async {
  final package = library.uri.scheme == 'package'
      ? library.uri.pathSegments.first
      : null;
  final events = AppWidgetEvents(package: package, astNodeFor: astNodeFor);
  Future<bool> firesEvent(AstNode node) async =>
      (await events.callsBelow(node)).isNotEmpty;

  final warnings = <String>[];
  for (final cls in library.classes) {
    if (recorded.contains(cls)) continue;
    final declaration = await astNodeFor(cls.firstFragment);
    if (declaration == null) continue;
    for (final content in routeContents(declaration, pushesOnly: true)) {
      if (_carriesScopes(content)) continue;
      if (!await firesEvent(content)) continue;
      final unit = content.root;
      final at = unit is CompilationUnit
          ? unit.lineInfo.getLocation(content.offset)
          : null;
      final location = at == null
          ? path
          : '$path:${at.lineNumber}:${at.columnNumber}';
      final type = content is InstanceCreationExpression
          ? content.constructorName.type
          : null;
      final shown = type?.element;
      final name = type == null ? 'content' : '`${type.toSource()}`';
      // A paywall's next screen becomes part of its delivered design;
      // wrapping it would stop that.
      if (firstAnnotation(_widgetOf(cls), 'Paywall') != null &&
          shown is ClassElement &&
          firstAnnotation(shown, 'Paywall') != null) {
        warnings.add(
          'The route at $location shows the paywall screen $name, which '
          'fires `context.surfaceEvent(...)`. The delivered paywall carries '
          'its events, but when the app shows its own copy of the paywall, '
          'events on that screen refuse until a coming Restage compiler change '
          'carries them too. Keep the push as it is: wrapping it would stop '
          'the delivered paywall from showing the screen.',
        );
        continue;
      }
      warnings.add(
        'The route at $location shows $name, which fires '
        '`context.surfaceEvent(...)`, but a pushed route is built outside '
        'the surface that pushes it, so its events refuse. Try wrapping the '
        "route's content in `InheritedTheme.capture(from: context, to: "
        'Navigator.of(context).context).wrap(...)`, with the context that '
        'pushes it.',
      );
    }
  }
  return warnings;
}

// [cls], or the widget it is the State of.
Element _widgetOf(ClassElement cls) {
  for (final type in cls.allSupertypes) {
    if (type.element.name == 'State' && type.typeArguments.length == 1) {
      return type.typeArguments.single.element ?? cls;
    }
  }
  return cls;
}

// Whether [content] is already `InheritedTheme.capture(...).wrap(...)`.
bool _carriesScopes(Expression content) =>
    content is MethodInvocation &&
    content.methodName.name == 'wrap' &&
    content.realTarget is MethodInvocation &&
    (content.realTarget! as MethodInvocation).methodName.name == 'capture';
