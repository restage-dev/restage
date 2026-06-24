import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Resolves [source] in-memory and returns the resolved [DartType] of the
/// named public field [fieldName] on class [className].
///
/// This drives the shape reflector against REAL resolved analyzer types (the
/// same idiom the structured-walker tests use), not hand-built fakes. The
/// source is plain Dart — the reflector reads types, so the fixtures need no
/// Flutter or annotation dependency.
Future<DartType> resolveFieldType(
  String source, {
  required String className,
  required String fieldName,
}) async {
  final element = await resolveClass(source, className);
  final field = element.fields.firstWhere(
    (f) => f.name == fieldName,
    orElse: () => throw StateError(
      "no field '$fieldName' on class '$className'",
    ),
  );
  return field.type;
}

/// Resolves [source] in-memory, returning the [ClassElement] for [className].
Future<ClassElement> resolveClass(String source, String className) async {
  final dir = Directory.systemTemp.createTempSync('a2ui_shape_reflector_test');
  try {
    final file = File('${dir.path}/fixture.dart')..writeAsStringSync(source);
    final collection = AnalysisContextCollection(includedPaths: [file.path]);
    final context = collection.contextFor(file.path);
    final resolved = await context.currentSession.getResolvedLibrary(file.path);
    if (resolved is! ResolvedLibraryResult) {
      throw StateError('failed to resolve the fixture library: $resolved');
    }
    return resolved.element.classes.firstWhere(
      (c) => c.name == className,
      orElse: () => throw StateError("no class '$className' in the fixture"),
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}
