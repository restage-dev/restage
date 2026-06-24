import 'package:restage_codegen/src/decoration_image_recipes.dart';
import 'package:restage_codegen/src/gradient_recipes.dart';
import 'package:restage_codegen/src/translator_recipe.dart';

/// Hand-authored translator recipes for the property-type-backed value
/// types. These carry RFW-decoder-contract knowledge — a color is a packed
/// integer, an offset is an `{x, y}` map — that no signature walker can
/// derive. The emit stage serializes them into `translator_tables.g.dart`.
const List<TranslatorRecipe> kHandAuthoredRecipes = [
  ..._kValueTypeRecipes,
  ...kGradientRecipes,
  ...kDecorationImageRecipes,
];

/// The property-type-backed value-type recipes (`Color`, `Offset`).
const List<TranslatorRecipe> _kValueTypeRecipes = [
  // Offset(x, y) -> {x: <x>, y: <y>}. `asLength` on both slots coerces
  // bare int literals (`Offset(0, 8)` — valid Dart via implicit
  // int→double parameter conversion) to double on the wire so rfw's
  // `offset` decoder, which reads `x` / `y` with `source.v<double>`,
  // doesn't silently null them.
  TranslatorRecipe(
    typeName: 'Offset',
    failureDsl: '{x: 0.0, y: 0.0}',
    validations: [
      RecipeValidation(
        check: ArityExact(2),
        issueCode: 'unrecognizedMethodCall',
        message: 'Offset() requires two positional arguments (x, y).',
      ),
    ],
    emit: EmitFragmentMap([
      EmitMapEntry('x', EmitFragmentArg(ArgRef.positional(0), asLength: true)),
      EmitMapEntry('y', EmitFragmentArg(ArgRef.positional(1), asLength: true)),
    ]),
  ),
  // Size(width, height) -> {width: <width>, height: <height>}. `asLength`
  // on both slots coerces bare int literals (`Size(200, 48)` — valid Dart
  // via implicit int→double parameter conversion) to double on the wire so
  // the registered `size` decoder, which reads `width` / `height` with
  // `source.v<double>`, doesn't silently null them.
  TranslatorRecipe(
    typeName: 'Size',
    failureDsl: '{width: 0.0, height: 0.0}',
    validations: [
      RecipeValidation(
        check: ArityExact(2),
        issueCode: 'unrecognizedMethodCall',
        message: 'Size() requires two positional arguments (width, height).',
      ),
    ],
    emit: EmitFragmentMap([
      EmitMapEntry(
        'width',
        EmitFragmentArg(ArgRef.positional(0), asLength: true),
      ),
      EmitMapEntry(
        'height',
        EmitFragmentArg(ArgRef.positional(1), asLength: true),
      ),
    ]),
  ),
  // TextStyle(...) -> {color, fontSize, fontWeight, ...} flat map. Used for
  // a TextStyle value surfaced as a registered STRUCTURED slot (e.g. a
  // button's `textStyle`) — distinct from (and coexisting with) the FLAT
  // TextStyle decompose on Text / DefaultTextStyle, which keeps using the
  // owning-widget recipe path. Each named arg recursively translates to its
  // wire shape (Color -> packed int, FontWeight.bold -> "w700", a double
  // stays double via `asLength`, a Shadow / FontFeature list -> the same
  // identity-projected list the flat decompose emits); the registered
  // `textStyle` decoder (`RestageDecoders.textStyle`) reads the SAME keys
  // this map emits — for the list/paint/locale fields this is the identical
  // `_translate` path the flat decompose's `projectList(identity)` /
  // identity mappings use, so they round-trip byte-for-byte.
  //
  // The full `TextStyle` named-arg surface is mapped (every authorable field
  // gets an entry) so a set-but-unmapped arg never silently drops — matching
  // the flat decompose's complete coverage. Each entry is `omitWhenArgUnset`
  // so an unset field stays off the wire and the decoder's per-field default
  // (the Flutter ctor default) applies. The ctor arg `package` carries the
  // `fontPackage` wire key the decoder reads (same rename the flat decompose
  // applies).
  TranslatorRecipe(
    typeName: 'TextStyle',
    failureDsl: '{}',
    emit: EmitFragmentMap([
      EmitMapEntry(
        'inherit',
        EmitFragmentArg(ArgRef.named('inherit')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'color',
        EmitFragmentArg(ArgRef.named('color')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'backgroundColor',
        EmitFragmentArg(ArgRef.named('backgroundColor')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'fontSize',
        EmitFragmentArg(ArgRef.named('fontSize'), asLength: true),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'fontWeight',
        EmitFragmentArg(ArgRef.named('fontWeight')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'fontStyle',
        EmitFragmentArg(ArgRef.named('fontStyle')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'letterSpacing',
        EmitFragmentArg(ArgRef.named('letterSpacing'), asLength: true),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'wordSpacing',
        EmitFragmentArg(ArgRef.named('wordSpacing'), asLength: true),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'textBaseline',
        EmitFragmentArg(ArgRef.named('textBaseline')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'height',
        EmitFragmentArg(ArgRef.named('height'), asLength: true),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'leadingDistribution',
        EmitFragmentArg(ArgRef.named('leadingDistribution')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'locale',
        EmitFragmentArg(ArgRef.named('locale')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'foreground',
        EmitFragmentArg(ArgRef.named('foreground')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'background',
        EmitFragmentArg(ArgRef.named('background')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'shadows',
        EmitFragmentArg(ArgRef.named('shadows')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'fontFeatures',
        EmitFragmentArg(ArgRef.named('fontFeatures')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'fontVariations',
        EmitFragmentArg(ArgRef.named('fontVariations')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'decoration',
        EmitFragmentArg(ArgRef.named('decoration')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'decorationColor',
        EmitFragmentArg(ArgRef.named('decorationColor')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'decorationStyle',
        EmitFragmentArg(ArgRef.named('decorationStyle')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'decorationThickness',
        EmitFragmentArg(ArgRef.named('decorationThickness'), asLength: true),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'debugLabel',
        EmitFragmentArg(ArgRef.named('debugLabel')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'fontFamily',
        EmitFragmentArg(ArgRef.named('fontFamily')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'fontFamilyFallback',
        EmitFragmentArg(ArgRef.named('fontFamilyFallback')),
        omitWhenArgUnset: true,
      ),
      // The ctor arg is `package`; the decoder reads the `fontPackage` wire
      // key (the same rename the flat TextStyle decompose applies).
      EmitMapEntry(
        'fontPackage',
        EmitFragmentArg(ArgRef.named('package')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'overflow',
        EmitFragmentArg(ArgRef.named('overflow')),
        omitWhenArgUnset: true,
      ),
    ]),
  ),
  // Color(0xAARRGGBB) -> 0xAARRGGBB
  TranslatorRecipe(
    typeName: 'Color',
    failureDsl: '',
    validations: [
      RecipeValidation(
        check: ArityExact(1),
        issueCode: 'unrecognizedMethodCall',
        message: 'Color() requires a single integer literal argument. '
            'For non-literal channel values use Color.fromARGB.',
      ),
      RecipeValidation(
        check: PositionalsAreIntLiterals(0, 1),
        issueCode: 'unrecognizedMethodCall',
        message: 'Color() requires a single integer literal argument. '
            'For non-literal channel values use Color.fromARGB.',
      ),
      RecipeValidation(
        check: PositionalIntsHaveValue(0, 1),
        issueCode: 'integerLiteralOverflow',
        message: 'Color() integer literal overflows int64.',
      ),
    ],
    emit: EmitFragmentKernel(
      TranslatorKernel.formatColorHex,
      [EmitValueArg(ArgRef.positional(0))],
    ),
  ),
  // Color.fromARGB(a, r, g, b) -> 0xAARRGGBB
  TranslatorRecipe(
    typeName: 'Color',
    variant: 'fromARGB',
    failureDsl: '',
    validations: [
      RecipeValidation(
        check: ArityExact(4),
        issueCode: 'unrecognizedMethodCall',
        message: 'Color.fromARGB() requires four positional integer '
            'arguments (alpha, red, green, blue).',
      ),
      RecipeValidation(
        check: PositionalsAreIntLiterals(0, 4),
        issueCode: 'unrecognizedMethodCall',
        message: 'Color.fromARGB() arguments must be integer literals. Use '
            'Color(0xAARRGGBB) for compile-time-known colors derived '
            'from runtime values.',
      ),
      RecipeValidation(
        check: PositionalIntsHaveValue(0, 4),
        issueCode: 'unrecognizedMethodCall',
        message: 'Color.fromARGB() arguments must be integer literals. Use '
            'Color(0xAARRGGBB) for compile-time-known colors derived '
            'from runtime values.',
      ),
      RecipeValidation(
        check: PositionalIntsInRange(0, 4, 0, 255),
        issueCode: 'unrecognizedMethodCall',
        message: 'Color.fromARGB() channel value {value} is out of the '
            '0..255 range.',
      ),
    ],
    emit: EmitFragmentKernel(TranslatorKernel.formatColorHex, [
      EmitValueKernel(TranslatorKernel.packArgb, [
        EmitValueArg(ArgRef.positional(0)),
        EmitValueArg(ArgRef.positional(1)),
        EmitValueArg(ArgRef.positional(2)),
        EmitValueArg(ArgRef.positional(3)),
      ]),
    ]),
  ),
  // Color.fromRGBO(r, g, b, opacity) -> 0xAARRGGBB
  TranslatorRecipe(
    typeName: 'Color',
    variant: 'fromRGBO',
    failureDsl: '',
    validations: [
      RecipeValidation(
        check: ArityExact(4),
        issueCode: 'unrecognizedMethodCall',
        message: 'Color.fromRGBO() requires four positional arguments '
            '(red, green, blue, opacity).',
      ),
      RecipeValidation(
        check: PositionalsAreIntLiterals(0, 3),
        issueCode: 'unrecognizedMethodCall',
        message: 'Color.fromRGBO() red/green/blue must be integer literals.',
      ),
      RecipeValidation(
        check: PositionalIntsHaveValue(0, 3),
        issueCode: 'unrecognizedMethodCall',
        message: 'Color.fromRGBO() red/green/blue must be integer literals.',
      ),
      RecipeValidation(
        check: PositionalIntsInRange(0, 3, 0, 255),
        issueCode: 'unrecognizedMethodCall',
        message: 'Color.fromRGBO() channel value {value} is out of the '
            '0..255 range.',
      ),
      RecipeValidation(
        check: PositionalNumLiteralInRange(3, 0, 1),
        issueCode: 'unrecognizedMethodCall',
        message: 'Color.fromRGBO() opacity must be a numeric literal in '
            '0.0..1.0.',
      ),
    ],
    emit: EmitFragmentKernel(TranslatorKernel.formatColorHex, [
      EmitValueKernel(TranslatorKernel.packArgb, [
        EmitValueKernel(TranslatorKernel.quantizeUnitToByte, [
          EmitValueArg(ArgRef.positional(3)),
        ]),
        EmitValueArg(ArgRef.positional(0)),
        EmitValueArg(ArgRef.positional(1)),
        EmitValueArg(ArgRef.positional(2)),
      ]),
    ]),
  ),
];
