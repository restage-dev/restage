import 'package:restage_codegen/src/translator_recipe.dart';

/// Translator recipes for the gradient value types and the `Alignment`
/// type they lean on.
///
/// The RFW gradient decoder reads a `{type, ...}` map and reapplies
/// Flutter's own constructor defaults for any omitted key, so each recipe
/// emits only the keys the author set — the `omitWhenArgUnset` entries drop
/// out when the corresponding named argument is absent.
///
/// `begin` / `end` / `center` / `focal` are alignment-typed. The RFW
/// decoder reads them as `{x, y}` maps, so a member reference such as
/// `Alignment.topLeft` resolves through the member table to its coordinate
/// pair, and an `Alignment(x, y)` constructor call falls through to the
/// `Alignment` recipe via the member table's fallback.
const List<TranslatorRecipe> kGradientRecipes = [
  // Alignment(x, y) -> {x: <x>, y: <y>}
  TranslatorRecipe(
    typeName: 'Alignment',
    failureDsl: '{x: 0.0, y: 0.0}',
    validations: [
      RecipeValidation(
        check: ArityExact(2),
        issueCode: 'unrecognizedMethodCall',
        message: 'Alignment() requires two positional arguments (x, y).',
      ),
    ],
    emit: EmitFragmentMap([
      EmitMapEntry('x', EmitFragmentArg(ArgRef.positional(0), asLength: true)),
      EmitMapEntry('y', EmitFragmentArg(ArgRef.positional(1), asLength: true)),
    ]),
  ),
  // RadialGradient(...) -> {type: "radial", ...}
  TranslatorRecipe(
    typeName: 'RadialGradient',
    failureDsl: '{type: "radial"}',
    emit: EmitFragmentMap([
      EmitMapEntry('type', EmitFragmentLiteral('"radial"')),
      EmitMapEntry(
        'colors',
        EmitFragmentArg(ArgRef.named('colors')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'stops',
        EmitFragmentArg(ArgRef.named('stops'), asDoubleList: true),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'center',
        _kCenterAlignmentArg,
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'radius',
        EmitFragmentArg(ArgRef.named('radius')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'focal',
        _kFocalAlignmentArg,
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'focalRadius',
        EmitFragmentArg(ArgRef.named('focalRadius')),
        omitWhenArgUnset: true,
      ),
    ]),
  ),
  // SweepGradient(...) -> {type: "sweep", ...}
  TranslatorRecipe(
    typeName: 'SweepGradient',
    failureDsl: '{type: "sweep"}',
    emit: EmitFragmentMap([
      EmitMapEntry('type', EmitFragmentLiteral('"sweep"')),
      EmitMapEntry(
        'colors',
        EmitFragmentArg(ArgRef.named('colors')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'stops',
        EmitFragmentArg(ArgRef.named('stops'), asDoubleList: true),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'center',
        _kCenterAlignmentArg,
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'startAngle',
        EmitFragmentArg(ArgRef.named('startAngle')),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'endAngle',
        EmitFragmentArg(ArgRef.named('endAngle')),
        omitWhenArgUnset: true,
      ),
    ]),
  ),
];

/// The `center` alignment argument fragment shared by the radial and sweep
/// recipes. A member reference (`Alignment.X`) resolves through the member
/// table to its `{x, y}` coordinate pair; an `Alignment(x, y)` constructor
/// call misses the table and falls through to the `Alignment` recipe via
/// the recursive-translation fallback.
const EmitFragment _kCenterAlignmentArg = EmitFragmentMemberTable(
  ArgRef.named('center'),
  _kAlignmentMemberFragments,
  fallback: EmitFragmentArg(ArgRef.named('center')),
);

/// The `focal` alignment argument fragment for the radial recipe; same
/// member-table-with-constructor-fallback shape as [_kCenterAlignmentArg].
const EmitFragment _kFocalAlignmentArg = EmitFragmentMemberTable(
  ArgRef.named('focal'),
  _kAlignmentMemberFragments,
  fallback: EmitFragmentArg(ArgRef.named('focal')),
);

/// Coordinate-pair fragments for Flutter's nine `Alignment` constants, in
/// the `{x, y}` shape the RFW alignment decoder reads.
///
/// `AlignmentDirectional` constants are intentionally absent: the RFW gradient
/// decoder requires resolved `{x, y}` coordinates, and directional members
/// (e.g. `AlignmentDirectional.centerStart`) carry no concrete x value until
/// layout-time text direction is known. They fall through to the recipe's
/// `fallback` path and surface a translation diagnostic.
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
