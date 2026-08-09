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
    if (_sourceSpells(a.toSource(), name)) return a;
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
/// An annotation that does not resolve at all is returned by spelling rather
/// than skipped, so the caller can fail on it instead of treating it as
/// absent.
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
  // Nothing resolved to ours. Before concluding the annotation is absent,
  // look for one that did not resolve at all: it has no defining library, so
  // origin can neither clear it nor condemn it, and reporting it as absent is
  // the one answer that is unsafe in both directions — an unresolved exclusion
  // would silently stop excluding, and an unresolved widget marker would
  // silently drop the class. Return it by spelling so the caller fails on its
  // unresolved value. A resolved annotation from another library is skipped
  // here as well as above, so a genuine lookalike is still correctly ignored.
  for (final annotation in el.metadata.annotations) {
    if (_annotationClass(annotation) != null) continue;
    final source = annotation.toSource();
    for (final name in names) {
      if (_sourceSpells(source, name)) return annotation;
    }
  }
  return null;
}

/// Whether [source] is an annotation written with [name]'s own spelling.
///
/// Accepts both forms Dart uses for a no-argument annotation — the class
/// (`@Ignore()`) and its canonical const instance (`@ignore`) — and requires
/// the identifier to end there, so `@ignoreOther` does not read as `@ignore`.
bool _sourceSpells(String source, String name) {
  if (name.isEmpty) return false;
  final instanceName = name[0].toLowerCase() + name.substring(1);
  for (final spelling in <String>{name, instanceName}) {
    if (!source.startsWith('@$spelling')) continue;
    final end = spelling.length + 1;
    if (source.length == end) return true;
    if (!_isIdentifierPart(source.codeUnitAt(end))) return true;
  }
  return false;
}

bool _isIdentifierPart(int unit) =>
    (unit >= 0x30 && unit <= 0x39) || // 0-9
    (unit >= 0x41 && unit <= 0x5A) || // A-Z
    (unit >= 0x61 && unit <= 0x7A) || // a-z
    unit == 0x5F || // _
    unit == 0x24; // $

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
