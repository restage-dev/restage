import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/a2ui/a2ui_example_loader.dart';
import 'package:restage_codegen/src/helper_registry.dart';

const _schemaOrigin = 'package:rfw_catalog_schema';
const _annotationName = 'RestageA2uiExample';

/// Discovers every canonical repeatable `@RestageA2uiExample` occurrence in a
/// resolved library, rejects every non-widget-class site, and loads legal
/// sidecars through the build graph.
Future<List<LoadedA2uiExample>> discoverA2uiExamples({
  required BuildStep buildStep,
  required ResolvedLibraryResult resolvedLibrary,
  required Map<ClassElement, String> widgetNamesByClass,
}) async {
  final anchors = discoverA2uiExampleAnchors(
    resolvedLibrary: resolvedLibrary,
    widgetNamesByClass: widgetNamesByClass,
  );
  final examples = <LoadedA2uiExample>[];
  for (final anchor in anchors) {
    examples.add(await loadA2uiExample(buildStep, anchor));
  }
  return examples;
}

/// Discovers and validates canonical example annotation anchors without
/// loading their assets.
///
/// The production builder follows this with [loadA2uiExample] so every sidecar
/// is tracked by the build graph. The production example drift guard reuses
/// this same discovery seam before loading its checked-in assets from disk.
List<A2uiExampleSourceAnchor> discoverA2uiExampleAnchors({
  required ResolvedLibraryResult resolvedLibrary,
  required Map<ClassElement, String> widgetNamesByClass,
}) {
  final annotations = <Annotation>[];
  final visitor = _CanonicalExampleAnnotationVisitor(annotations);
  for (final unit in resolvedLibrary.units) {
    unit.unit.accept(visitor);
  }

  final anchors = <A2uiExampleSourceAnchor>[];
  final namesByWidget = <String, Set<String>>{};
  for (final annotation in annotations) {
    final value = annotation.elementAnnotation?.computeConstantValue();
    final evaluatedName = value?.getField('name')?.toStringValue();
    final evaluatedAsset = value?.getField('asset')?.toStringValue();
    final name = evaluatedName ?? '<unevaluated-name>';
    final asset = evaluatedAsset ?? '<unevaluated-asset>';
    final parent = annotation.parent;
    final classElement =
        parent is ClassDeclaration ? parent.declaredFragment?.element : null;
    final widgetName = classElement == null
        ? '<invalid-site:${parent.runtimeType}>'
        : widgetNamesByClass[classElement] ?? '<non-RestageWidget>';
    final sourceClass = classElement?.name ?? parent.runtimeType.toString();
    final anchor = A2uiExampleSourceAnchor(
      sourceClass: sourceClass,
      widgetName: widgetName,
      exampleName: name,
      asset: asset,
    );

    if (value == null || evaluatedName == null || evaluatedAsset == null) {
      throw A2uiExampleException(
        'annotation arguments must be compile-time string constants',
        anchor,
      );
    }
    if (classElement == null) {
      throw A2uiExampleException(
        '`@RestageA2uiExample` is legal only on a class that is also '
        'annotated `@RestageWidget`',
        anchor,
      );
    }
    if (!widgetNamesByClass.containsKey(classElement)) {
      throw A2uiExampleException(
        '`@RestageA2uiExample` class is not a discovered `@RestageWidget`',
        anchor,
      );
    }
    if (name.trim().isEmpty) {
      throw A2uiExampleException('example name must be non-blank', anchor);
    }
    final widgetNames = namesByWidget.putIfAbsent(widgetName, () => <String>{});
    if (!widgetNames.add(name)) {
      throw A2uiExampleException(
        'duplicate example name "$name" for this catalog item',
        anchor,
      );
    }
    anchors.add(anchor);
  }

  anchors.sort((a, b) {
    final byWidget = a.widgetName.compareTo(b.widgetName);
    if (byWidget != 0) return byWidget;
    final byName = a.exampleName.compareTo(b.exampleName);
    return byName != 0 ? byName : a.asset.compareTo(b.asset);
  });
  return anchors;
}

final class _CanonicalExampleAnnotationVisitor
    extends RecursiveAstVisitor<void> {
  _CanonicalExampleAnnotationVisitor(this.annotations);

  final List<Annotation> annotations;

  @override
  void visitAnnotation(Annotation node) {
    final annotationClass = _annotationClass(node);
    if (annotationClass?.name == _annotationName &&
        libraryUriMatchesOrigin(
          annotationClass!.library.identifier,
          _schemaOrigin,
        )) {
      annotations.add(node);
    }
    super.visitAnnotation(node);
  }
}

InterfaceElement? _annotationClass(Annotation annotation) {
  final element = annotation.element;
  if (element is ConstructorElement) return element.enclosingElement;

  final constElement =
      annotation.elementAnnotation?.computeConstantValue()?.type?.element;
  if (constElement is InterfaceElement) return constElement;

  if (element is PropertyAccessorElement) {
    final type = element.variable.type;
    if (type is InterfaceType) return type.element;
  }
  if (element is FieldElement) {
    final type = element.type;
    if (type is InterfaceType) return type.element;
  }
  return null;
}
