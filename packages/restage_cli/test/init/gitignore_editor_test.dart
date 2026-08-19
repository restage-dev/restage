import 'package:restage_cli/src/init/gitignore_editor.dart';
import 'package:test/test.dart';

void main() {
  group('planPortableOutputIgnores', () {
    test('creates all portable-output rules for an absent file', () {
      final plan = planPortableOutputIgnores('');

      expect(plan.isNoOp, isFalse);
      expect(plan.addedPatterns, restagePortableOutputIgnorePatterns);
      expect(plan.source, contains('# Restage portable generated output.'));
      for (final pattern in restagePortableOutputIgnorePatterns) {
        expect(plan.source, contains(pattern));
      }
      expect(plan.source, isNot(contains('*.generated/')));
      expect(plan.source, isNot(contains('generated/')));
    });

    test('keeps a complete existing file byte-for-byte', () {
      const source = '''
# Project rules
build/
*.rsbundle
*.restage.md
restage.outputs.json
restage.publication.json
restage_a2ui_catalog.a2ui.json
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
      expect(plan.source, contains('\r\n# Restage portable generated output.'));
    });

    test(
      'does not restore a deliberately deleted rule in its managed section',
      () {
        const source = '''
# Restage portable generated output. Remove or negate individual rules to track it.
*.rsbundle
*.restage.md
restage.outputs.json
restage.publication.json
''';

        final plan = planPortableOutputIgnores(source);

        expect(plan.isNoOp, isTrue);
        expect(plan.source, source);
        expect(plan.source, isNot(contains('restage_a2ui_catalog.a2ui.json')));
      },
    );
  });
}
