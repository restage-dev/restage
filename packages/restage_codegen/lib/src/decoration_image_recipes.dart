import 'package:restage_codegen/src/translator_recipe.dart';

/// Translator recipes for the `DecorationImage` value (a `BoxDecoration.image`
/// background) and the two `ImageProvider` types it lowers.
///
/// The runtime `RestageDecoders.decorationImage` decoder reads a
/// self-describing map: a nested `image` provider map (`{kind, src}`) plus
/// optional `fit`, `alignment` (`{x, y}`), `repeat`, `opacity`, and `scale`
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
      EmitMapEntry('src', EmitFragmentArg(ArgRef.positional(0))),
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
        message: 'AssetImage() requires a single positional asset-name '
            'argument.',
      ),
    ],
    deferredNamedArgs: {'bundle'},
    emit: EmitFragmentMap([
      EmitMapEntry('kind', EmitFragmentLiteral('"asset"')),
      EmitMapEntry('src', EmitFragmentArg(ArgRef.positional(0))),
      EmitMapEntry(
        'package',
        EmitFragmentArg(ArgRef.named('package')),
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
        EmitFragmentArg(ArgRef.named('fit')),
        omitWhenArgUnset: true,
      ),
      // A concrete `Alignment.<member>` resolves through the member table to
      // its `{x, y}` coordinate pair (the shape the runtime `alignmentXY`
      // decoder reads); an `Alignment(x, y)` constructor call misses the table
      // and recurses via the fallback to the same `{x, y}` shape. A resolved
      // framework member NOT in the table (`AlignmentDirectional.*`, which has
      // no concrete x until layout-time text direction) defers LOUD at the
      // member-table dispatch rather than emitting its bare name (which the
      // decoder would silently null to `Alignment.center`).
      EmitMapEntry(
        'alignment',
        _kAlignmentArg,
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'repeat',
        EmitFragmentArg(ArgRef.named('repeat')),
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

/// The `alignment` argument fragment for the `DecorationImage` recipe. A member
/// reference (`Alignment.X`) resolves through the member table to its `{x, y}`
/// coordinate pair; an `Alignment(x, y)` constructor call (not a member access)
/// recurses via the `fallback` to the same `{x, y}` shape. A resolved framework
/// member NOT in the table defers LOUD at the member-table dispatch (see the
/// member-table handling in `recipe_dispatcher.dart`) rather than reaching the
/// recursing fallback. Both supported shapes decode at runtime via
/// `RestageDecoders.alignmentXY`.
const EmitFragment _kAlignmentArg = EmitFragmentMemberTable(
  ArgRef.named('alignment'),
  _kAlignmentMemberFragments,
  fallback: EmitFragmentArg(ArgRef.named('alignment')),
);

/// Coordinate-pair fragments for Flutter's nine `Alignment` constants, in the
/// `{x, y}` shape the runtime `alignmentXY` decoder reads.
///
/// `AlignmentDirectional` constants are intentionally absent: a resolved
/// `{x, y}` pair is required, and directional members carry no concrete x
/// value until layout-time text direction is known. A resolved
/// `AlignmentDirectional.*` member-access misses this table and defers LOUD at
/// the member-table dispatch (never its bare name, which the decoder would
/// silently null to `Alignment.center`).
const Map<String, EmitFragment> _kAlignmentMemberFragments = {
  'topLeft': EmitFragmentLiteral('{x: -1.0, y: -1.0}'),
  'topCenter': EmitFragmentLiteral('{x: 0.0, y: -1.0}'),
  'topRight': EmitFragmentLiteral('{x: 1.0, y: -1.0}'),
  'centerLeft': EmitFragmentLiteral('{x: -1.0, y: 0.0}'),
  'center': EmitFragmentLiteral('{x: 0.0, y: 0.0}'),
  'centerRight': EmitFragmentLiteral('{x: 1.0, y: 0.0}'),
  'bottomLeft': EmitFragmentLiteral('{x: -1.0, y: 1.0}'),
  'bottomCenter': EmitFragmentLiteral('{x: 0.0, y: 1.0}'),
  'bottomRight': EmitFragmentLiteral('{x: 1.0, y: 1.0}'),
};
