import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/theme_recognition.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Unit tests for the shared `libraryIsFlutter(Element?)` recognition atom —
/// the single `package:flutter/`-library check the translator, the classifier,
/// and the theme-read recogniser all key their framework-vs-customer
/// disambiguation on. A null element (genuinely-unresolvable input) is NOT
/// recognised: the recognised set is the resolved-real-Flutter case only.
void main() {
  group('libraryIsFlutter', () {
    test('a null element is not recognised (defer-on-null)', () {
      expect(libraryIsFlutter(null), isFalse);
    });

    test('a real package:flutter/ element is recognised', () async {
      // `EdgeInsets.zero` parses as a PrefixedIdentifier; its `prefix.element`
      // is the resolved `EdgeInsets` class in `package:flutter/`.
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/widgets.dart';
        Object x() => EdgeInsets.zero;
        ''',
        rootPackage: 'apps_examples',
      );
      final prefix = (expr as PrefixedIdentifier).prefix;
      expect(libraryIsFlutter(prefix.element), isTrue);
    });

    test('a customer look-alike class (not package:flutter/) is not recognised',
        () async {
      final expr = await parseExpressionFromSourceForTest('''
        class EdgeInsets {
          EdgeInsets._();
          static const int zero = 0;
        }
        Object x() => EdgeInsets.zero;
      ''');
      final prefix = (expr as PrefixedIdentifier).prefix;
      expect(libraryIsFlutter(prefix.element), isFalse);
    });
  });
}
