import 'package:restage_codegen/src/translator_recipe.dart';
import 'package:test/test.dart';

void main() {
  group('TranslatorRecipe', () {
    test('holds library, type, variant, validations, emit, failureDsl', () {
      const recipe = TranslatorRecipe(
        typeName: 'Offset',
        emit: EmitFragmentMap([
          EmitMapEntry('x', EmitFragmentArg(ArgRef.positional(0))),
          EmitMapEntry('y', EmitFragmentArg(ArgRef.positional(1))),
        ]),
        failureDsl: '{x: 0.0, y: 0.0}',
        validations: [
          RecipeValidation(
            check: ArityExact(2),
            issueCode: 'unrecognizedMethodCall',
            message: 'Offset() requires two positional arguments (x, y).',
          ),
        ],
      );
      expect(recipe.typeName, 'Offset');
      expect(recipe.library, isNull);
      expect(recipe.variant, isNull);
      expect(recipe.validations.single.check, isA<ArityExact>());
      expect(recipe.failureDsl, '{x: 0.0, y: 0.0}');
    });

    test('framework-type key omits the library segment', () {
      const recipe = TranslatorRecipe(
        typeName: 'Color',
        variant: 'fromARGB',
        emit: EmitFragmentLiteral('0x00000000'),
        failureDsl: '',
      );
      expect(recipe.key, '#Color.fromARGB');
    });

    test('unnamed-constructor key omits the variant segment', () {
      const recipe = TranslatorRecipe(
        typeName: 'Offset',
        emit: EmitFragmentLiteral('{}'),
        failureDsl: '',
      );
      expect(recipe.key, '#Offset');
    });

    test('library-scoped key carries the library segment', () {
      const recipe = TranslatorRecipe(
        library: 'restage.material',
        typeName: 'TextStyle',
        emit: EmitFragmentLiteral('{}'),
        failureDsl: '',
      );
      expect(recipe.key, 'restage.material#TextStyle');
    });
  });

  group('recipeKey', () {
    test('encodes the (library, type, variant) triple', () {
      expect(
        recipeKey(library: null, typeName: 'Color', variant: null),
        '#Color',
      );
      expect(
        recipeKey(library: null, typeName: 'Color', variant: 'fromARGB'),
        '#Color.fromARGB',
      );
      expect(
        recipeKey(library: 'restage.core', typeName: 'Pad', variant: 'all'),
        'restage.core#Pad.all',
      );
    });

    test('a framework type does not collide with a same-named library type',
        () {
      final frameworkColor =
          recipeKey(library: null, typeName: 'Color', variant: null);
      final libraryColor = recipeKey(
        library: 'restage.material',
        typeName: 'Color',
        variant: null,
      );
      expect(frameworkColor, isNot(libraryColor));
    });
  });

  group('ValidationCheck', () {
    test('typed checks carry their parameters', () {
      const arity = ArityExact(4);
      const range = PositionalIntsInRange(0, 4, 0, 255);
      const opacity = PositionalNumLiteralInRange(3, 0, 1);
      expect(arity.count, 4);
      expect(range.start, 0);
      expect(range.endExclusive, 4);
      expect(range.min, 0);
      expect(range.max, 255);
      expect(opacity.index, 3);
      expect(opacity.min, 0.0);
      expect(opacity.max, 1.0);
    });

    test('ValidationCheck is a sealed family', () {
      const checks = <ValidationCheck>[
        ArityExact(1),
        PositionalsAreIntLiterals(0, 1),
        PositionalIntsHaveValue(0, 1),
        PositionalIntsInRange(0, 1, 0, 255),
        PositionalNumLiteralInRange(0, 0, 1),
      ];
      expect(checks, hasLength(5));
    });
  });

  group('ArgRef', () {
    test('distinguishes positional and named', () {
      const p = ArgRef.positional(3);
      const n = ArgRef.named('color');
      expect(p.index, 3);
      expect(p.label, isNull);
      expect(n.label, 'color');
      expect(n.index, isNull);
    });

    test('equality is value-based', () {
      expect(const ArgRef.positional(0), const ArgRef.positional(0));
      expect(const ArgRef.named('x'), const ArgRef.named('x'));
      expect(const ArgRef.positional(0), isNot(const ArgRef.positional(1)));
      expect(const ArgRef.positional(0), isNot(const ArgRef.named('x')));
    });
  });

  group('emit tree', () {
    test('EmitValueKernel composes kernels for fromRGBO-shaped emit', () {
      const emit = EmitFragmentKernel(
        TranslatorKernel.formatColorHex,
        [
          EmitValueKernel(TranslatorKernel.packArgb, [
            EmitValueKernel(
              TranslatorKernel.quantizeUnitToByte,
              [EmitValueArg(ArgRef.positional(3))],
            ),
            EmitValueArg(ArgRef.positional(0)),
            EmitValueArg(ArgRef.positional(1)),
            EmitValueArg(ArgRef.positional(2)),
          ]),
        ],
      );
      expect(emit.kernel, TranslatorKernel.formatColorHex);
      expect(emit.inputs.single, isA<EmitValueKernel>());
    });

    test('EmitMapEntry carries an omit-when-unset flag', () {
      const set = EmitMapEntry('a', EmitFragmentLiteral('1'));
      const omittable = EmitMapEntry(
        'b',
        EmitFragmentArg(ArgRef.named('b')),
        omitWhenArgUnset: true,
      );
      expect(set.omitWhenArgUnset, isFalse);
      expect(omittable.omitWhenArgUnset, isTrue);
    });
  });
}
