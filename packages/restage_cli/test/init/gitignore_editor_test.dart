import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/init/gitignore_editor.dart';
import 'package:test/test.dart';

void main() {
  group('planPortableOutputIgnores', () {
    test('creates all portable-output rules for an absent file', () {
      final plan = planPortableOutputIgnores('');

      expect(plan.isNoOp, isFalse);
      expect(plan.addedPatterns, restagePortableOutputIgnorePatterns);
      expect(
        plan.source,
        contains(
          '# Restage build output (bundled surfaces under '
          'assets/restage/bundles/ stay tracked)',
        ),
      );
      for (final pattern in restagePortableOutputIgnorePatterns) {
        expect(plan.source, contains(pattern));
      }
      expect(plan.source, isNot(contains('*.generated/')));
      expect(plan.source, isNot(contains('generated/')));
      expect(plan.source, contains('.restage/build/'));
      expect(plan.source, isNot(contains('measurement-state.json')));
      expect(plan.source, isNot(contains('wire-ids.events.jsonl')));
    });

    test('upgrades earlier ignore rules without restoring deleted rules', () {
      const source =
          '# Restage portable generated output. Remove or negate '
          'individual rules to track it.\n*.rsbundle\n';
      final plan = planPortableOutputIgnores(source);
      expect(plan.source.startsWith(source), isTrue);
      expect(plan.addedPatterns, [
        '.restage/build/',
        '!assets/restage/bundles/**',
      ]);
      expect(planPortableOutputIgnores(plan.source).isNoOp, isTrue);
    });

    test('keeps a complete existing file byte-for-byte', () {
      const source = '''
# Project rules
build/
.restage/build/
*.rsbundle
*.restage.md
restage.outputs.json
restage.publication.json
restage_a2ui_catalog.a2ui.json
!assets/restage/bundles/**
''';

      final plan = planPortableOutputIgnores(source);

      expect(plan.isNoOp, isTrue);
      expect(plan.source, source);
    });

    test('appends only missing rules after existing user content', () {
      const source = '# Project rules\n*.rsbundle\n';

      final plan = planPortableOutputIgnores(source);

      expect(plan.source.startsWith(source), isTrue);
      expect(
        plan.addedPatterns,
        containsAllInOrder([
          '*.restage.md',
          'restage.outputs.json',
          'restage.publication.json',
          'restage_a2ui_catalog.a2ui.json',
        ]),
      );
      expect(plan.source.split('*.rsbundle').length - 1, 1);
      expect(plan.source, contains('# Project rules\n'));
    });

    test('honors negated rules without re-adding their positive form', () {
      const source = '''
# Project rules
!*.rsbundle
*.restage.md
!restage.publication.json
''';

      final plan = planPortableOutputIgnores(source);

      expect(plan.source, contains('!*.rsbundle'));
      expect(plan.source, contains('!restage.publication.json'));
      expect(plan.source, isNot(contains('\n*.rsbundle')));
      expect(plan.source, isNot(contains('\nrestage.publication.json')));
      expect(plan.addedPatterns, contains('restage.outputs.json'));
    });

    test('preserves CRLF style and an existing trailing blank line', () {
      const source = '# Project rules\r\n\r\n';

      final plan = planPortableOutputIgnores(source);

      expect(plan.source.startsWith(source), isTrue);
      expect(plan.source, isNot(contains('*.generated/')));
      expect(plan.source.replaceAll('\r\n', ''), isNot(contains('\n')));
      expect(plan.source, contains('\r\n# Restage build output'));
    });

    test(
      'does not restore a deliberately deleted rule in its managed section',
      () {
        const source = '''
# Restage portable generated output. Build cache and portable artifacts; remove or negate individual rules to track them.
*.rsbundle
*.restage.md
restage.outputs.json
restage.publication.json
''';

        final plan = planPortableOutputIgnores(source);

        expect(plan.addedPatterns, ['!assets/restage/bundles/**']);
        expect(plan.source, isNot(contains('restage_a2ui_catalog.a2ui.json')));
        expect(planPortableOutputIgnores(plan.source).isNoOp, isTrue);
      },
    );

    test('keeps a user rule that ignores bundled assets', () {
      const source = 'assets/restage/bundles/**\n';

      final plan = planPortableOutputIgnores(source);

      expect(plan.addedPatterns, isNot(contains('!assets/restage/bundles/**')));
    });

    test('git tracks bundled assets and ignores build output', () async {
      final dir = await Directory.systemTemp.createTemp('restage_ignore_');
      addTearDown(() => dir.delete(recursive: true));
      await Process.run('git', ['init', '-q'], workingDirectory: dir.path);
      await File(
        p.join(dir.path, '.gitignore'),
      ).writeAsString(planPortableOutputIgnores('').source);

      Future<bool> ignored(String path) async {
        final file = File(p.join(dir.path, path));
        await file.parent.create(recursive: true);
        await file.writeAsString('x');
        final result = await Process.run('git', [
          'check-ignore',
          '-q',
          path,
        ], workingDirectory: dir.path);
        return result.exitCode == 0;
      }

      expect(
        await ignored('assets/restage/bundles/lib/messages/a.rsbundle'),
        isFalse,
      );
      expect(
        await ignored('.restage/build/bundles/lib/messages/a.rsbundle'),
        isTrue,
      );
      expect(await ignored('lib/messages/a.rsbundle'), isTrue);
      expect(await ignored('restage.publication.json'), isTrue);
    });
  });
}
