import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:test/test.dart';

void main() {
  group('resolveStructuredDescriptions', () {
    test('implements the full precedence and absence matrix', () async {
      final model = await _resolveModel('''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Example {
  const Example({
    @RestageDataField(description: 'Explicit parameter.') required this.parameter,
    required this.explicitMember,
    /// Parameter fallback.
    required this.memberDoc,
    /// Resolved parameter Dartdoc.
    required this.parameterDoc,
    required this.absent,
  });

  final String parameter;

  @RestageDataField(description: 'Explicit member.')
  final String explicitMember;

  /// Member Dartdoc.
  final String memberDoc;

  final String parameterDoc;
  final String absent;
}
''');

      _expectDescription(model, 'parameter', 'Explicit parameter.');
      _expectDescription(model, 'explicitMember', 'Explicit member.');
      _expectDescription(model, 'memberDoc', 'Member Dartdoc.');
      _expectDescription(
        model,
        'parameterDoc',
        'Resolved parameter Dartdoc.',
      );
      expect(model.descriptionForParameterName('absent'), isNull);
    });

    test('same-text and different-text duplicate explicit sources conflict',
        () async {
      for (final memberText in const ['Same.', 'Different.']) {
        final model = await _resolveModel('''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Example {
  const Example({
    @RestageDataField(description: 'Same.') required this.value,
  });

  @RestageDataField(description: '$memberText')
  final String value;
}
''');
        expect(model.conflicts, hasLength(1));
        expect(model.conflicts.single.anchors, hasLength(2));
        expect(model.conflicts.single.message, contains('exactly one'));
      }
    });

    test('same-site parameter annotations never first-win', () async {
      for (final secondText in const ['Same.', 'Different.']) {
        final model = await _resolveModel('''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Example {
  const Example({
    @RestageDataField(description: 'Same.')
    @RestageDataField(description: '$secondText')
    required this.value,
  });
  final String value;
}
''');

        expect(model.conflicts, hasLength(1));
        expect(model.conflicts.single.anchors, hasLength(2));
        expect(model.conflicts.single.anchors.toSet(), hasLength(2));
      }
    });

    test('same-site field annotations never first-win', () async {
      for (final secondText in const ['Same.', 'Different.']) {
        final model = await _resolveModel('''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Example {
  const Example({required this.value});

  @RestageDataField(description: 'Same.')
  @RestageDataField(description: '$secondText')
  final String value;
}
''');

        expect(model.conflicts, hasLength(1));
        expect(model.conflicts.single.anchors, hasLength(2));
        expect(model.conflicts.single.anchors.toSet(), hasLength(2));
      }
    });

    test('same-site getter annotations are all reported while held unresolved',
        () async {
      for (final secondText in const ['Same.', 'Different.']) {
        final model = await _resolveModel('''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Example {
  const Example(this._value);
  final String _value;

  @RestageDataField(description: 'Same.')
  @RestageDataField(description: '$secondText')
  String get value => _value;
}
''');

        expect(model.conflicts, hasLength(1));
        expect(model.conflicts.single.anchors, hasLength(2));
        expect(model.conflicts.single.anchors.toSet(), hasLength(2));
      }
    });

    test('a blank annotation conflict retains every participating anchor',
        () async {
      final model = await _resolveModel('''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Example {
  const Example({
    @RestageDataField(description: '   ') required this.value,
  });

  @RestageDataField(description: 'Second source.')
  final String value;
}
''');

      expect(model.conflicts, hasLength(1));
      expect(model.conflicts.single.anchors, hasLength(2));
      expect(model.conflicts.single.anchors.toSet(), hasLength(2));
    });

    test('explicit metadata wins over member and parameter Dartdoc', () async {
      final model = await _resolveModel('''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Example {
  const Example({
    /// Parameter fallback that must not win.
    @RestageDataField(description: 'Explicit description.')
    required this.value,
  });

  /// Member fallback that must not win.
  final String value;
}
''');

      _expectDescription(model, 'value', 'Explicit description.');
    });

    test('blank explicit text conflicts with an actionable anchor', () async {
      final model = await _resolveModel('''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Example {
  const Example({
    @RestageDataField(description: '   ') required this.value,
  });
  final String value;
}
''');

      expect(model.conflicts, hasLength(1));
      expect(model.conflicts.single.anchors, hasLength(1));
      expect(model.conflicts.single.message, contains('non-empty'));
    });

    test('ordinary unresolved association never guesses by equal name',
        () async {
      final model = await _resolveModel('''
class Example {
  const Example({
    /// Unlinked parameter documentation.
    required String value,
  }) : value = value;

  /// Unlinked member documentation.
  final String value;
}
''');

      expect(model.descriptionForParameterName('value'), isNull);
      expect(model.conflicts, isEmpty);
    });

    test('an unassociated member annotation is fatal instead of name-matched',
        () async {
      final model = await _resolveModel('''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Example {
  const Example({required String value}) : value = value;

  @RestageDataField(description: 'Do not attach by name.')
  final String value;
}
''');

      expect(model.conflicts, hasLength(1));
      expect(model.conflicts.single.anchors, hasLength(1));
      expect(model.conflicts.single.anchors.single, contains('field'));
      expect(
        model.conflicts.single.message,
        contains('no analyzer identity link'),
      );
      expect(model.conflicts.single.message, contains('canonical wire DTO'));
    });

    test('explicit metadata on an unresolved parameter fails with guidance',
        () async {
      final model = await _resolveModel('''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Example {
  const Example(
    @RestageDataField(description: 'Do not use by name.') String value,
  ) : value = value;
  final String value;
}
''');

      expect(model.conflicts, hasLength(1));
      expect(model.conflicts.single.anchors, hasLength(1));
      expect(
        model.conflicts.single.anchors.single,
        contains('constructor parameter'),
      );
      expect(
        model.conflicts.single.message,
        contains('no analyzer identity link'),
      );
      expect(model.conflicts.single.message, contains('`this.field`'));
      expect(model.conflicts.single.message, contains('super-formal chain'));
      expect(model.conflicts.single.message, contains('canonical wire DTO'));
      expect(
        model.conflicts.single.message,
        isNot(contains('public field or getter')),
      );
    });

    test('explicit metadata on an unresolved getter fails with guidance',
        () async {
      final model = await _resolveModel('''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Example {
  const Example(this._value);
  final String _value;

  @RestageDataField(description: 'Do not use a computed getter.')
  String get value => _value;
}
''');

      expect(model.conflicts, hasLength(1));
      expect(model.conflicts.single.anchors, hasLength(1));
      expect(model.conflicts.single.anchors.single, contains('getter'));
      expect(
        model.conflicts.single.message,
        contains('no analyzer identity link'),
      );
      expect(model.conflicts.single.message, contains('`this.field`'));
      expect(model.conflicts.single.message, contains('super-formal chain'));
      expect(model.conflicts.single.message, contains('canonical wire DTO'));
    });

    test('multiple named constructors preserve ambiguity and absence',
        () async {
      final model = await _resolveModel('''
class Example {
  const Example.first(this.value);
  const Example.second(this.value);
  final String value;
}
''');

      expect(model.constructor, isNull);
      expect(model.conflicts, isEmpty);
    });

    test('explicit metadata with ambiguous constructors reports its anchor',
        () async {
      final model = await _resolveModel('''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Example {
  const Example.first(this.value);
  const Example.second(this.value);

  @RestageDataField(description: 'Cannot choose a constructor.')
  final String value;
}
''');

      expect(model.constructor, isNull);
      expect(model.conflicts, hasLength(1));
      expect(model.conflicts.single.anchors, hasLength(1));
      expect(
        model.conflicts.single.message,
        contains('canonical generative constructor'),
      );
    });

    test('a transitive super-formal chain terminates at a field-formal',
        () async {
      final model = await _resolveModel('''
class Base {
  const Base.named({required this.value});
  /// Base value.
  final String value;
}

class Middle extends Base {
  const Middle.named({required super.value}) : super.named();
}

class Example extends Middle {
  const Example.named({required super.value}) : super.named();
}
''');

      expect(model.constructor, isNotNull);
      _expectDescription(model, 'value', 'Base value.');
    });

    test('a super-formal chain ending at an ordinary parameter is unresolved',
        () async {
      final absent = await _resolveModel('''
class Base {
  const Base.named({required String value}) : value = value;
  final String value;
}

class Example extends Base {
  const Example.named({required super.value}) : super.named();
}
''');

      expect(absent.descriptionForParameterName('value'), isNull);
      expect(absent.conflicts, isEmpty);

      final explicit = await _resolveModel('''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Base {
  const Base.named({required String value}) : value = value;
  final String value;
}

class Example extends Base {
  const Example.named({
    @RestageDataField(description: 'Still unresolved.') required super.value,
  }) : super.named();
}
''');

      expect(explicit.descriptionForParameterName('value'), isNull);
      expect(explicit.conflicts, hasLength(1));
      expect(
        explicit.conflicts.single.message,
        contains('no analyzer identity link'),
      );
      expect(explicit.conflicts.single.message, contains('canonical wire DTO'));
    });

    test('generic queries match a second substituted formal by declaration',
        () async {
      final model = await _resolveModel(
        '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Box<T> {
  const Box({required this.value});

  @RestageDataField(description: 'Generic value.')
  final T value;
}
''',
        className: 'Box',
      );

      final secondView = model.constructor!.formalParameters.single;
      expect(
        model.descriptionForParameter(secondView),
        'Generic value.',
      );
    });

    test('generic super-formals match their substituted base declaration',
        () async {
      final model = await _resolveModel('''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Base<T> {
  const Base({required this.value});

  @RestageDataField(description: 'Inherited generic value.')
  final T value;
}

class Example<T> extends Base<T> {
  const Example({required super.value});
}
''');

      final secondView = model.constructor!.formalParameters.single;
      expect(
        model.descriptionForParameter(secondView),
        'Inherited generic value.',
      );
    });
  });
}

void _expectDescription(
  StructuredDescriptionResolution resolution,
  String parameterName,
  String text,
) {
  expect(resolution.descriptionForParameterName(parameterName), text);
}

Future<StructuredDescriptionResolution> _resolveModel(
  String source, {
  String className = 'Example',
}) async {
  final root = Directory.current.parent.parent.path;
  final dir = Directory('$root/.dart_tool/structured_description_resolver_test')
    ..createSync(recursive: true);
  final file = File('${dir.path}/fixture.dart')..writeAsStringSync(source);
  try {
    final collection = AnalysisContextCollection(includedPaths: [file.path]);
    final context = collection.contextFor(file.path);
    final resolved = await context.currentSession.getResolvedLibrary(file.path);
    if (resolved is! ResolvedLibraryResult) {
      throw StateError('failed to resolve fixture: $resolved');
    }
    final element = resolved.element.classes.firstWhere(
      (candidate) => candidate.name == className,
    );
    return resolveStructuredDescriptions(element.thisType);
  } finally {
    file.deleteSync();
  }
}

extension on StructuredDescriptionResolution {
  String? descriptionForParameterName(String name) {
    final parameter = constructor!.formalParameters.firstWhere(
      (candidate) => candidate.name == name,
      orElse: () => throw StateError('no constructor parameter $name'),
    );
    return descriptionForParameter(parameter);
  }
}
