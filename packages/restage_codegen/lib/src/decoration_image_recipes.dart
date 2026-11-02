import 'package:restage_codegen/src/translator_recipe.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Translator recipes for the `DecorationImage` value (a `BoxDecoration.image`
/// background) and the two `ImageProvider` types it lowers.
///
/// The runtime `RestageDecoders.decorationImage` decoder reads a
/// self-describing map: a nested `image` provider map (`{kind, src}`) plus
/// optional `fit`, alignment geometry, `repeat`, `opacity`, and `scale`
/// fields. Each recipe emits only the keys the author set — the
/// `omitWhenArgUnset` entries drop out when their named argument is absent, so
/// the decoder reapplies the Flutter `DecorationImage` constructor default for
/// the omitted field.
///
/// Only the two serializable providers are authorable: `NetworkImage` (a URL
/// string) and `AssetImage` (a bundle key string). `MemoryImage` / `FileImage`
/// carry runtime bytes / a device path that cannot ride a delivered blob, so
/// they have no recipe and defer LOUD through the host translator's
/// unknown-construction path rather than lowering as a fabricated image.
const List<TranslatorRecipe> kDecorationImageRecipes = [
  // NetworkImage(url, {scale}) -> {kind: "network", src: <url>, scale?}.
  // `scale` is mapped (it changes the resolved image density). The remaining
  // named args (`headers`, `webHtmlElementStrategy`) carry non-serializable /
  // host-only values and defer LOUD when set — never a silent drop.
  TranslatorRecipe(
    typeName: 'NetworkImage',
    failureDsl: '{}',
    validations: [
      RecipeValidation(
        check: ArityExact(1),
        issueCode: 'unrecognizedMethodCall',
        message: 'NetworkImage() requires a single positional URL argument.',
      ),
    ],
    deferredNamedArgs: {'headers', 'webHtmlElementStrategy'},
    emit: EmitFragmentMap([
      EmitMapEntry('kind', EmitFragmentLiteral('"network"')),
      EmitMapEntry(
        'src',
        EmitFragmentArg(
          ArgRef.positional(0),
          propertyType: PropertyType.string,
        ),
      ),
      EmitMapEntry(
        'scale',
        EmitFragmentArg(ArgRef.named('scale'), asLength: true),
        omitWhenArgUnset: true,
      ),
    ]),
  ),
  // AssetImage(name, {package}) -> {kind: "asset", src: <name>, package?}.
  // `package` is mapped (it changes asset resolution — `packages/<package>/…`).
  // `bundle` (a non-serializable AssetBundle) defers LOUD when set.
  TranslatorRecipe(
    typeName: 'AssetImage',
    failureDsl: '{}',
    validations: [
      RecipeValidation(
        check: ArityExact(1),
        issueCode: 'unrecognizedMethodCall',
        message:
            'AssetImage() requires a single positional asset-name '
            'argument.',
      ),
    ],
    deferredNamedArgs: {'bundle'},
    emit: EmitFragmentMap([
      EmitMapEntry('kind', EmitFragmentLiteral('"asset"')),
      EmitMapEntry(
        'src',
        EmitFragmentArg(
          ArgRef.positional(0),
          propertyType: PropertyType.string,
        ),
      ),
      EmitMapEntry(
        'package',
        EmitFragmentArg(
          ArgRef.named('package'),
          propertyType: PropertyType.string,
        ),
        omitWhenArgUnset: true,
      ),
    ]),
  ),
  // DecorationImage(image: <provider>, fit:, alignment:, repeat:, opacity:,
  // scale:) -> {image: <recursed provider map>, fit, alignment: {x, y},
  // repeat, opacity, scale}. The `image` arg recurses into the provider recipe
  // above; an unsupported provider defers loud through that recursion. Each
  // optional field is `omitWhenArgUnset`, so an unset field stays off the wire
  // and the decoder's per-field DecorationImage default applies.
  TranslatorRecipe(
    typeName: 'DecorationImage',
    failureDsl: '{}',
    // Supported-but-not-yet-lowered fields defer LOUD when present rather than
    // silently dropping (which omitting an emit entry would do): the
    // color-filter surface, the 9-slice center rect, the direction/quality/
    // anti-alias knobs, and `invertColors` (Flutter PAINTS with it — inverting
    // the image colors — so dropping it is a wrong render, NOT a debug no-op).
    // `onError` (a callback) is the only field intentionally absent from both
    // this set AND the emit map — it carries no serializable, render-affecting
    // value, so ignoring it is faithful, not a silent loss.
    deferredNamedArgs: {
      'colorFilter',
      'centerSlice',
      'matchTextDirection',
      'filterQuality',
      'invertColors',
      'isAntiAlias',
    },
    emit: EmitFragmentMap([
      // The provider map recurses into the NetworkImage / AssetImage recipe;
      // an unsupported provider has no recipe and defers loud through the host
      // translator's unknown-construction path.
      EmitMapEntry(
        'image',
        EmitFragmentArg(ArgRef.named('image')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'fit',
        EmitFragmentArg(
          ArgRef.named('fit'),
          propertyType: PropertyType.enumValue,
        ),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'alignment',
        _kAlignmentArg,
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'repeat',
        EmitFragmentArg(
          ArgRef.named('repeat'),
          propertyType: PropertyType.enumValue,
        ),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'opacity',
        EmitFragmentArg(ArgRef.named('opacity'), asLength: true),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'scale',
        EmitFragmentArg(ArgRef.named('scale'), asLength: true),
        omitWhenArgUnset: true,
      ),
    ]),
  ),
];

/// Alignment geometry is resolved by Flutter at render time.
const EmitFragment _kAlignmentArg = EmitFragmentArg(
  ArgRef.named('alignment'),
  propertyType: PropertyType.alignment,
);
