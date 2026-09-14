import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:test/test.dart';

import 'helpers.dart';

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

  test('resolved SDK origin survives prefixes, const aliases, and typedefs',
      () async {
    const source = '''
import 'package:restage/restage.dart' as rs;

const runtimeMount = rs.RestagePaywall(id: 'const_alias');
typedef RuntimePaywall = rs.RestagePaywall;

@rs.RestagePaywall(id: 'prefixed')
class Prefixed {}

@runtimeMount
class ConstAlias {}

@RuntimePaywall(id: 'typedef_alias')
class TypedefAlias {}
''';

    await resolveWorkspaceSources(
      const {'apps_examples|lib/fixture.dart': source},
      (resolver) async {
        final library = await resolver.libraryFor(
          AssetId('apps_examples', 'lib/fixture.dart'),
          allowSyntaxErrors: true,
        );
        for (final name in ['Prefixed', 'ConstAlias', 'TypedefAlias']) {
          final annotation = library.classes
              .singleWhere((element) => element.name == name)
              .metadata
              .annotations
              .single;
          expect(resolvedAnnotationClass(annotation)?.name, 'RestagePaywall');
          expect(annotationHasOrigin(annotation, 'package:restage'), isTrue);
        }
      },
      resolverFor: 'apps_examples|lib/fixture.dart',
      rootPackage: 'apps_examples',
    );
  });

  test('resolved local lookalike does not have SDK origin', () async {
    final target = await _resolveClass(
      '''
class RestagePaywall {
  const RestagePaywall({required this.id});
  final String id;
}

@RestagePaywall(id: 'local')
class Target {}
''',
      'Target',
    );
    final annotation = target.metadata.annotations.single;

    expect(resolvedAnnotationClass(annotation)?.name, 'RestagePaywall');
    expect(annotationHasOrigin(annotation, 'package:restage'), isFalse);
  });
}
