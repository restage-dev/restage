import 'package:restage_cli/src/init/pubspec_editor.dart';
import 'package:test/test.dart';

void main() {
  group('addDependencies', () {
    test('adds a missing entry to an existing dependencies block', () {
      const src = '''
name: my_app
description: A sample app.

dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
''';

      final result = addDependencies(src, deps: const {'restage': '^0.1.0'});

      expect(result.added, ['restage']);
      expect(result.kept, isEmpty);
      expect(result.source, contains('restage: ^0.1.0'));
      expect(result.source, contains('http: ^1.2.0'));
    });

    test('keeps an existing dependency unchanged', () {
      const src = '''
name: my_app

dependencies:
  http: ^1.2.0
  restage: ^0.0.5
''';

      final result = addDependencies(src, deps: const {'restage': '^0.1.0'});

      expect(result.added, isEmpty);
      expect(result.kept, ['restage']);
      expect(result.source, contains('restage: ^0.0.5'));
    });

    test('creates the dev_dependencies block when missing', () {
      const src = '''
name: my_app

dependencies:
  http: ^1.2.0
''';

      final result = addDependencies(
        src,
        devDeps: const {
          'build_runner': '>=2.4.0 <3.0.0',
          'restage_codegen': '^0.1.0',
        },
      );

      expect(result.added, containsAll(['build_runner', 'restage_codegen']));
      expect(result.source, contains('dev_dependencies:'));
      expect(result.source, contains('build_runner: '));
      expect(result.source, contains('restage_codegen: ^0.1.0'));
    });

    test('mixed additions report added vs kept correctly', () {
      const src = '''
name: my_app

dependencies:
  http: ^1.2.0
  restage: ^0.0.5

dev_dependencies:
  test: ^1.25.0
''';

      final result = addDependencies(
        src,
        deps: const {'restage': '^0.1.0'},
        devDeps: const {'build_runner': '>=2.4.0 <3.0.0', 'test': '^1.25.0'},
      );

      expect(result.added, containsAll(['build_runner']));
      expect(result.kept, containsAll(['restage', 'test']));
    });

    test('plan() summarises planned changes without writing', () {
      const src = '''
name: my_app

dependencies:
  http: ^1.2.0
''';

      final plan = planAddDependencies(
        src,
        deps: const {'restage': '^0.1.0'},
        devDeps: const {'build_runner': '>=2.4.0 <3.0.0'},
      );

      expect(plan.dependenciesToAdd['restage'], '^0.1.0');
      expect(plan.devDependenciesToAdd['build_runner'], '>=2.4.0 <3.0.0');
      expect(plan.dependenciesToKeep, isEmpty);
      expect(plan.devDependenciesToKeep, isEmpty);
    });

    test('plan() marks existing entries as `kept`', () {
      const src = '''
name: my_app

dependencies:
  restage: ^0.0.5
''';

      final plan = planAddDependencies(src, deps: const {'restage': '^0.1.0'});

      expect(plan.dependenciesToAdd, isEmpty);
      expect(plan.dependenciesToKeep.keys, ['restage']);
    });
  });
}
