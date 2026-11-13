import 'dart:io';

import 'package:restage_codegen/src/islands/generated_names.dart';
import 'package:test/test.dart';

void main() {
  test('every `_restage` name the generators spell is a generated name', () {
    // A string literal that starts a `_restage` name, up to its closing quote.
    final literal = RegExp(r"""(['"])(_restage(?:[^'"\\\n]|\\.)*?)\1""");
    final uncovered = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final match in literal.allMatches(file.readAsStringSync())) {
        // Interpolations become a word; an escaped `$` stays a `$`.
        final name = match[2]!
            .replaceAll(RegExp(r'(?<!\\)\$\{[^}]*\}'), 'Name')
            .replaceAll(RegExp(r'(?<!\\)\$[A-Za-z_]\w*'), 'Name')
            .replaceAll(r'\$', r'$')
            .split(RegExp(r'[^A-Za-z0-9_$]'))
            .first;
        if (!isGeneratedRestageName(name)) {
          uncovered.add('${file.path}: $name');
        }
      }
    }
    expect(uncovered, isEmpty);
  });

  test("an author's other `_restage` names are not generated ones", () {
    expect(isGeneratedRestageName('_restageLabel'), isFalse);
    expect(isGeneratedRestageName('_restageCount'), isFalse);
    expect(isGeneratedRestageName('_restageDesign'), isTrue);
    expect(isGeneratedRestageName('_restageArgument3'), isTrue);
  });
}
