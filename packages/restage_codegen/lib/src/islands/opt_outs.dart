import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/issue.dart';

/// The annotation that keeps widgets as the app builds them.
const kOptOutAnnotation = 'RenderInApp';

/// Why the widget expression [node] at [location] stays as the app builds
/// it, or null when nothing asks for that.
///
/// The annotation may be on the local variable [node] initializes, on the
/// class it constructs, on that class's library, or on a library the
/// surface's library imports that exports the class.
Issue? optOutOf(Expression node, String location) {
  String? where;
  if (node.parent case VariableDeclaration(
    parent: VariableDeclarationList(:final metadata),
  ) when metadata.any((a) => a.name.name == kOptOutAnnotation)) {
    where = 'the variable that holds it';
  } else if (_constructed(node) case final type?) {
    final unit = node.root;
    where = optOutOfClass(
      type,
      unit is CompilationUnit
          ? unit.declaredFragment?.element.firstFragment
          : null,
    );
  }
  if (where == null) return null;
  return Issue(
    code: IssueCode.keptByOptOut,
    message:
        "Designs can't change `${_widget(node)}` ($location) because "
        '`@$kOptOutAnnotation` is on $where.',
    location: location,
  );
}

InterfaceElement? _constructed(Expression node) => switch (node) {
  InstanceCreationExpression(:final constructorName) =>
    switch (constructorName.type.element) {
      final InterfaceElement element => element,
      _ => null,
    },
  _ => null,
};

String _widget(Expression node) => switch (node) {
  InstanceCreationExpression(:final constructorName) =>
    constructorName.type.name.lexeme,
  MethodInvocation(:final methodName) => methodName.name,
  _ => node.toSource(),
};

/// Where the annotation that keeps [type] as the app builds it is, as a
/// message names it, seen from [importer]; null when nothing asks for that.
String? optOutOfClass(InterfaceElement type, LibraryFragment? importer) {
  final library = type.library;
  if (firstAnnotation(type, kOptOutAnnotation) != null) return '`${type.name}`';
  if (firstAnnotation(library, kOptOutAnnotation) != null) {
    return library.uri.toString();
  }
  for (final import in importer?.libraryImports ?? const <Never>[]) {
    final imported = import.importedLibrary;
    if (imported != null &&
        imported != library &&
        firstAnnotation(imported, kOptOutAnnotation) != null &&
        imported.exportNamespace.get2(type.name!) == type) {
      return imported.uri.toString();
    }
  }
  return null;
}

/// The refusal of the widget expression [node] at [location], which the
/// developer keeps as the app builds it and the generated widget can't run;
/// [uses] is what it can't reach, when known.
Issue optOutUnkept(Expression node, String location, String? uses) => Issue(
  code: IssueCode.optOutUnkept,
  message:
      "The generated widget can't build `${_widget(node)}` "
      '($location) in app code as `@$kOptOutAnnotation` asks because '
      '${uses == null ? "the generated widget can't run the code that creates `${_widget(node)}`" : "`${_widget(node)}` uses `$uses`, which the generated widget can't reach"}. '
      'Try removing `@$kOptOutAnnotation`, or passing what '
      "`${_widget(node)}` uses in through the screen's constructor.",
  location: location,
);
