import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart' show AssetId;
import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/ir/diagnostic.dart';
import 'package:rfw_catalog_compiler/src/walker/walker_issue_codes.dart'
    as issue_codes;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The declared identity of a customer widget library.
@immutable
final class RestageLibraryDeclaration {
  /// Creates a declaration.
  const RestageLibraryDeclaration({
    required this.library,
    this.package,
    this.capabilityVersion,
  });

  /// The namespace this package contributes catalog entries to.
  final WidgetLibrary library;

  /// The source package URI named by `@RestageLibrary`; `null` walks the
  /// barrel's own package.
  final String? package;

  /// The library's declared monotonic capability version, or `null` when the
  /// `@RestageLibrary` annotation omits it. Distinct from a pub semver — it is
  /// the render-support line the delivery-time capability floor is derived
  /// against (recorded as `LibraryInfo.capabilityVersion` in the catalog).
  final int? capabilityVersion;
}

/// Result of walking a barrel library for an `@RestageLibrary` declaration.
@immutable
final class LibraryWalkResult {
  /// Creates a walk result.
  const LibraryWalkResult({
    this.declaration,
    this.widgetClasses = const [],
    this.diagnostics = const [],
  });

  /// The parsed declaration, or `null` when the barrel carries no
  /// `@RestageLibrary` annotation.
  final RestageLibraryDeclaration? declaration;

  /// The `@RestageWidget`-annotated classes exposed by the barrel's export
  /// namespace, filtered to the effective package, in deterministic
  /// fully-qualified-name (`'<library identifier>#<name>'`) order.
  ///
  /// The barrel's export namespace is the catalog gate: only classes that
  /// the namespace itself exposes are listed here. A `@RestageWidget` class
  /// excluded by a `show`/`hide` clause on an `export` directive is not
  /// reachable through the namespace and therefore does not appear, even
  /// when its declaring library is otherwise export-reachable.
  ///
  /// Empty when [declaration] is `null` (the barrel carries no
  /// `@RestageLibrary`) or when no `@RestageWidget`-annotated classes are
  /// exposed.
  final List<ClassElement> widgetClasses;

  /// Diagnostics raised during the walk.
  final List<DiagnosticIR> diagnostics;
}

/// Walks [barrel] for an `@RestageLibrary` declaration and enumerates the
/// `@RestageWidget`-annotated classes exposed by its export namespace.
///
/// Returns a [LibraryWalkResult] whose [LibraryWalkResult.declaration] is
/// `null` when the barrel carries no `@RestageLibrary` annotation.
/// [LibraryWalkResult.widgetClasses] is populated with every
/// `@RestageWidget`-annotated class the barrel's export namespace exposes,
/// filtered to the effective package, and sorted by fully-qualified name
/// (`'<library identifier>#<name>'`) for byte-deterministic downstream order.
///
/// The barrel's export namespace is the catalog gate: a `@RestageWidget`
/// class excluded by a `show`/`hide` clause on an `export` directive is not
/// exposed and therefore not enumerated, even when its declaring library is
/// export-reachable.
///
/// The *effective package* is the `package` field of `@RestageLibrary` when
/// set; otherwise the barrel's own package (`barrelAssetId.package`). Only
/// `@RestageWidget` classes whose declaring library originates in the
/// effective package are catalogued; foreign classes produce a
/// [issue_codes.restageLibraryForeignWidget] warning and are dropped.
///
/// Emits a [DiagnosticIR] with [issue_codes.restageLibraryMalformed] and a
/// `null` declaration when the annotation is present but cannot be
/// const-evaluated or is missing the required `library` field.
///
/// Emits a [DiagnosticIR] with [issue_codes.restageLibraryReservedNamespace]
/// and a `null` declaration when the declared `library` names a built-in
/// Restage namespace. The walk does not proceed in that case.
LibraryWalkResult walkRestageLibrary({
  required LibraryElement barrel,
  required AssetId barrelAssetId,
}) {
  final annotated = _findRestageLibraryAnnotated(barrel);
  if (annotated == null) {
    // No @RestageLibrary present — not a customer barrel; no-op.
    return const LibraryWalkResult();
  }

  final location = barrelAssetId.path;
  final annotation = _firstAnnotationNamed(annotated, 'RestageLibrary')!;
  final annotationConst = annotation.computeConstantValue();
  if (annotationConst == null) {
    return LibraryWalkResult(
      diagnostics: [
        DiagnosticIR(
          code: issue_codes.restageLibraryMalformed,
          message: '@RestageLibrary on ${annotated.name} could not be '
              'const-evaluated.',
          location: location,
          severity: DiagnosticSeverity.error,
        ),
      ],
    );
  }

  final namespace = annotationConst
      .getField('library')
      ?.getField('namespace')
      ?.toStringValue();
  if (namespace == null) {
    return LibraryWalkResult(
      diagnostics: [
        DiagnosticIR(
          code: issue_codes.restageLibraryMalformed,
          message: '@RestageLibrary on ${annotated.name} has a missing or '
              'unresolvable `library` field.',
          location: location,
          severity: DiagnosticSeverity.error,
        ),
      ],
    );
  }

  // Guard A: a customer library must not claim a built-in namespace.
  if (WidgetLibrary.builtInByNamespace(namespace) != null) {
    return LibraryWalkResult(
      diagnostics: [
        DiagnosticIR(
          code: issue_codes.restageLibraryReservedNamespace,
          message: '@RestageLibrary on ${annotated.name} declares the '
              'built-in namespace "$namespace", which is reserved.',
          location: location,
          severity: DiagnosticSeverity.error,
        ),
      ],
    );
  }

  final declaredPackage = annotationConst.getField('package')?.toStringValue();
  // `capabilityVersion` is optional on the annotation: a `null` here means it
  // was omitted (the build only fails later if a surface references this
  // library — fail-when-referenced). `toIntValue()` returns `null` for both an
  // absent field and a non-int, which is the correct "undeclared" reading. A
  // *non-positive* declared version cannot reach here: the `@RestageLibrary`
  // const constructor asserts `capabilityVersion == null || >= 1`, so a
  // `capabilityVersion: 0`/`-1` annotation fails const-evaluation and is
  // rejected by the `annotationConst == null` guard above. The catalog encode
  // validator (`_validateCanonicalCatalog`) is the symmetric backstop for a
  // hand-built/mis-threaded catalog.
  final declaredCapabilityVersion =
      annotationConst.getField('capabilityVersion')?.toIntValue();
  // Filter B/C: effective package is the declared package, falling back to
  // the barrel's own package when @RestageLibrary.package is null.
  final effectivePackage = declaredPackage ?? barrelAssetId.package;
  final library = WidgetLibrary.fromNamespace(namespace);

  final (widgetClasses, filterDiagnostics) = _enumerateWidgetClasses(
    barrel,
    effectivePackage: effectivePackage,
    location: location,
  );

  return LibraryWalkResult(
    declaration: RestageLibraryDeclaration(
      library: library,
      package: declaredPackage,
      capabilityVersion: declaredCapabilityVersion,
    ),
    widgetClasses: widgetClasses,
    diagnostics: filterDiagnostics,
  );
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Returns the `@RestageWidget`-annotated classes exposed by [barrel]'s
/// export namespace, together with any diagnostics raised for dropped
/// foreign classes.
///
/// Iterates every name exposed by [barrel]'s export namespace, keeps the
/// values that are [ClassElement]s carrying `@RestageWidget`, and filters by
/// [effectivePackage]: a class whose declaring library does not originate in
/// [effectivePackage] is dropped with a
/// [issue_codes.restageLibraryForeignWidget] warning. The kept classes are
/// sorted by fully-qualified name (`'<library identifier>#<name>'`) for
/// byte-deterministic order.
///
/// Iterating the export namespace — rather than the export closure's
/// libraries — makes the namespace the catalog gate: a `@RestageWidget`
/// class excluded by a `show`/`hide` clause on an `export` directive is not
/// among `definedNames2` and is therefore not enumerated.
///
/// A `@RestageWidget` class whose declaring library has no `package:` URI
/// (e.g. a `dart:` library or an unresolvable identifier) is treated as
/// foreign and dropped with a diagnostic rather than crashing.
(List<ClassElement>, List<DiagnosticIR>) _enumerateWidgetClasses(
  LibraryElement barrel, {
  required String effectivePackage,
  required String location,
}) {
  final classes = <ClassElement>[];
  final diagnostics = <DiagnosticIR>[];

  for (final element in barrel.exportNamespace.definedNames2.values) {
    if (element is! ClassElement) continue;
    if (_firstAnnotationNamed(element, 'RestageWidget') == null) continue;

    final declaringLibrary = element.library;
    final originPackage = _packageFromIdentifier(declaringLibrary.identifier);

    if (originPackage != effectivePackage) {
      // Foreign class — drop it and emit a warning.
      final widgetName = element.name ?? '<unnamed>';
      final message = originPackage != null
          ? '$widgetName originates in package "$originPackage", '
              'not in the declared package "$effectivePackage". '
              'It will not be catalogued.'
          : '$widgetName has no resolvable package origin, so it is not '
              'part of the declared package "$effectivePackage". '
              'It will not be catalogued.';
      diagnostics.add(
        DiagnosticIR(
          code: issue_codes.restageLibraryForeignWidget,
          message: message,
          location: location,
          severity: DiagnosticSeverity.warning,
        ),
      );
      continue;
    }

    classes.add(element);
  }

  classes.sort(
    (a, b) => _qualifiedNameOf(a).compareTo(_qualifiedNameOf(b)),
  );
  return (classes, diagnostics);
}

/// Returns the fully-qualified name of [element] as
/// `'<library identifier>#<name>'`.
///
/// This is the byte-stable sort key for the walk result and the join key
/// against `WidgetEntry.flutterType`, which the `@RestageWidget` visitor
/// synthesizes with the identical formula.
String _qualifiedNameOf(ClassElement element) =>
    '${element.library.identifier}#${element.name ?? ''}';

/// Extracts the package name from a `package:<name>/...` library identifier.
///
/// Returns the segment between `package:` and the first `/`. Returns `null`
/// for any identifier that does not follow the `package:` scheme (e.g.
/// `dart:core`, `file://...`, or an empty/malformed string) so callers can
/// treat such libraries as foreign rather than matching by accident.
String? _packageFromIdentifier(String identifier) {
  if (!identifier.startsWith('package:')) return null;
  final rest = identifier.substring('package:'.length);
  final slash = rest.indexOf('/');
  if (slash <= 0) return null;
  return rest.substring(0, slash);
}

/// Returns the first top-level element in [barrel] that carries an
/// `@RestageLibrary` annotation, or `null` when none is found.
///
/// Searches top-level variables (the canonical location for a barrel sentinel)
/// then top-level functions and class declarations so any valid placement is
/// recognized.
Element? _findRestageLibraryAnnotated(LibraryElement barrel) {
  for (final variable in barrel.topLevelVariables) {
    if (_firstAnnotationNamed(variable, 'RestageLibrary') != null) {
      return variable;
    }
  }
  for (final function in barrel.topLevelFunctions) {
    if (_firstAnnotationNamed(function, 'RestageLibrary') != null) {
      return function;
    }
  }
  for (final cls in barrel.classes) {
    if (_firstAnnotationNamed(cls, 'RestageLibrary') != null) return cls;
  }
  return null;
}

/// Returns the first annotation on [element] whose const-evaluated type is
/// named [name], or `null` when none matches.
///
/// Falls back to source-text matching when const-evaluation fails so the
/// caller can emit a diagnostic rather than silently skip.
ElementAnnotation? _firstAnnotationNamed(Element element, String name) {
  for (final annotation in element.metadata.annotations) {
    final value = annotation.computeConstantValue();
    if (value?.type?.element?.name == name) return annotation;
    if (annotation.toSource().startsWith('@$name')) return annotation;
  }
  return null;
}
