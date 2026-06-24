import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/helper_registry.dart';

/// Returns the first annotation on [el] whose runtime class is named [name],
/// or `null` if none matches.
///
/// Tries const-evaluation first; falls back to source-text matching when
/// const-eval fails (e.g. a non-const argument or a type error in the
/// annotation arguments). Returning the annotation in the fallback case lets
/// the caller emit a "could not be evaluated" diagnostic instead of silently
/// skipping the annotated element.
ElementAnnotation? firstAnnotation(Element el, String name) {
  for (final a in el.metadata.annotations) {
    final c = a.computeConstantValue();
    if (c?.type?.element?.name == name) return a;
    if (a.toSource().startsWith('@$name')) return a;
  }
  return null;
}

/// Returns the first annotation whose runtime class name is in [names] and
/// whose declaring library is [libraryOrigin].
///
/// Lets a recognizer accept a canonical annotation plus its deprecated
/// alias(es) in one pass. Uses the resolved annotation element before const
/// value inspection so malformed real SDK annotations still produce caller
/// diagnostics, while local or fake-package lookalikes that happen to share a
/// name are ignored at the contract boundary.
ElementAnnotation? firstAnnotationFromOriginAny(
  Element el,
  Set<String> names,
  String libraryOrigin,
) {
  for (final annotation in el.metadata.annotations) {
    final annotationClass = _annotationClass(annotation);
    if (annotationClass == null) continue;
    if (names.contains(annotationClass.name) &&
        libraryUriMatchesOrigin(
          annotationClass.library.identifier,
          libraryOrigin,
        )) {
      return annotation;
    }
  }
  return null;
}

InterfaceElement? _annotationClass(ElementAnnotation annotation) {
  final element = annotation.element;
  if (element is ConstructorElement) return element.enclosingElement;
  if (element is PropertyAccessorElement) {
    final variable = element.variable;
    final type = variable.type;
    if (type is InterfaceType) return type.element;
  }
  if (element is FieldElement) {
    final type = element.type;
    if (type is InterfaceType) return type.element;
  }
  final constElement = annotation.computeConstantValue()?.type?.element;
  if (constElement is InterfaceElement) return constElement;
  return null;
}
