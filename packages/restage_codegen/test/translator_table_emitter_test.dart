import 'package:restage_codegen/src/translator_recipe.dart';
import 'package:restage_codegen/src/translator_recipes.dart';
import 'package:restage_codegen/src/translator_table_emitter.dart';
import 'package:test/test.dart';

void main() {
  group('emitTranslatorTableSource', () {
    final source = emitTranslatorTableSource(kHandAuthoredRecipes);

    test('emits the generated-file header and lint exemption', () {
      expect(source, contains('GENERATED'));
      expect(source, contains('ignore_for_file: type=lint'));
      expect(
        source,
        contains(
          "import 'package:restage_codegen/src/translator_recipe.dart';",
        ),
      );
    });

    test('emits a const recipe map keyed by the triple', () {
      expect(
        source,
        contains('const Map<String, TranslatorRecipe> kTranslatorRecipes = {'),
      );
      expect(source, contains("'#Offset':"));
      expect(source, contains("'#Color':"));
      expect(source, contains("'#Color.fromARGB':"));
      expect(source, contains("'#Color.fromRGBO':"));
    });

    test('renders typed validation checks', () {
      expect(source, contains('ArityExact(2)'));
      expect(source, contains('PositionalIntsInRange(0, 4, 0, 255)'));
      expect(source, contains('PositionalNumLiteralInRange(3, 0.0, 1.0)'));
    });

    test('renders kernels and emit nodes', () {
      expect(source, contains('TranslatorKernel.formatColorHex'));
      expect(source, contains('TranslatorKernel.packArgb'));
      expect(source, contains('TranslatorKernel.quantizeUnitToByte'));
      expect(source, contains('EmitFragmentMap('));
      expect(source, contains('EmitValueArg(ArgRef.positional(0))'));
    });

    test('renders the asDoubleList flag for numeric-list slots', () {
      // The gradient `stops` slots decode as `list<double>`; the emitter must
      // carry the `asDoubleList` coercion flag into the generated table or the
      // dispatcher silently nulls int elements to 0.0 at decode time.
      expect(
        source,
        contains("EmitFragmentArg(ArgRef.named('stops'), asDoubleList: true)"),
      );
    });

    test('carries diagnostic messages verbatim', () {
      expect(
        source,
        contains('Offset() requires two positional arguments (x, y).'),
      );
      expect(
        source,
        contains(
          'Color.fromARGB() channel value {value} is out of the 0..255 '
          'range.',
        ),
      );
    });

    test('escapes a dollar sign in emitted string literals', () {
      // A bare $ in an emitted string literal would be Dart interpolation
      // in the generated file — it must be escaped.
      final emitted = emitTranslatorTableSource(const [
        TranslatorRecipe(
          typeName: 'X',
          emit: EmitFragmentLiteral(r'a$b'),
          failureDsl: '',
        ),
      ]);
      expect(emitted, contains(r'\$'));
      expect(emitted, isNot(contains(r"'a$b'")));
    });
  });
}
