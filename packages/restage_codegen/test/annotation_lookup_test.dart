import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/restage_codegen.dart';
import 'package:test/test.dart';

Future<ClassElement> _resolveClass(String source, String className) async {
  final directory = Directory(
    '${Directory.current.path}/.dart_tool/annotation_lookup_test_'
    '${DateTime.now().microsecondsSinceEpoch}',
  )..createSync(recursive: true);
  try {
    final file = File('${directory.path}/fixture.dart')
      ..writeAsStringSync(source);
    final collection = AnalysisContextCollection(includedPaths: [file.path]);
    final context = collection.contextFor(file.path);
    final result = await context.currentSession.getResolvedLibrary(file.path);
    if (result is! ResolvedLibraryResult) {
      throw StateError('failed to resolve annotation fixture: $result');
    }
    return result.element.classes.singleWhere(
      (element) => element.name == className,
    );
  } finally {
    directory.deleteSync(recursive: true);
  }
}

void main() {
  test('source fallback requires an exact annotation-name boundary', () async {
    final target = await _resolveClass(
      '''
class FooBar {
  const FooBar(Object? value);
}

@FooBar(notDeclared)
class Target {}
''',
      'Target',
    );

    expect(firstAnnotation(target, 'FooBar'), isNotNull);
    expect(firstAnnotation(target, 'Foo'), isNull);
  });
}
