import 'package:restage_codegen/src/translator_recipe.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Gradient recipes preserve alignment geometry for Flutter to resolve.
const List<TranslatorRecipe> kGradientRecipes = [
  TranslatorRecipe(
    typeName: 'AlignmentDirectional',
    failureDsl: '{start: 0.0, y: 0.0}',
    validations: [
      RecipeValidation(
        check: ArityExact(2),
        issueCode: 'unrecognizedMethodCall',
        message: 'AlignmentDirectional requires two arguments.',
      ),
    ],
    emit: EmitFragmentMap([
      EmitMapEntry(
        'start',
        EmitFragmentArg(ArgRef.positional(0), asLength: true),
      ),
      EmitMapEntry('y', EmitFragmentArg(ArgRef.positional(1), asLength: true)),
    ]),
  ),
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
    deferredNamedArgs: {'transform'},
    emit: EmitFragmentMap([
      EmitMapEntry('type', EmitFragmentLiteral('"radial"')),
      _kTileModeEntry,
      EmitMapEntry(
        'colors',
        EmitFragmentArg(
          ArgRef.named('colors'),
          itemPropertyType: PropertyType.color,
        ),
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
        EmitFragmentArg(
          ArgRef.named('radius'),
          propertyType: PropertyType.real,
        ),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'focal',
        _kFocalAlignmentArg,
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'focalRadius',
        EmitFragmentArg(
          ArgRef.named('focalRadius'),
          propertyType: PropertyType.real,
        ),
        omitWhenArgUnset: true,
      ),
    ]),
  ),
  // SweepGradient(...) -> {type: "sweep", ...}
  TranslatorRecipe(
    typeName: 'SweepGradient',
    failureDsl: '{type: "sweep"}',
    deferredNamedArgs: {'transform'},
    emit: EmitFragmentMap([
      EmitMapEntry('type', EmitFragmentLiteral('"sweep"')),
      _kTileModeEntry,
      EmitMapEntry(
        'colors',
        EmitFragmentArg(
          ArgRef.named('colors'),
          itemPropertyType: PropertyType.color,
        ),
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
        EmitFragmentArg(
          ArgRef.named('startAngle'),
          propertyType: PropertyType.real,
        ),
        omitWhenArgUnset: true,
      ),
      EmitMapEntry(
        'endAngle',
        EmitFragmentArg(
          ArgRef.named('endAngle'),
          propertyType: PropertyType.real,
        ),
        omitWhenArgUnset: true,
      ),
    ]),
  ),
];

/// Geometry shared by the radial and sweep centers.
const EmitFragment _kCenterAlignmentArg = EmitFragmentArg(
  ArgRef.named('center'),
  propertyType: PropertyType.alignment,
);

/// Radial focal alignment retains its authored geometry.
const EmitFragment _kFocalAlignmentArg = EmitFragmentArg(
  ArgRef.named('focal'),
  propertyType: PropertyType.alignment,
);

const _kTileModeEntry = EmitMapEntry(
  'tileMode',
  EmitFragmentArg(
    ArgRef.named('tileMode'),
    propertyType: PropertyType.enumValue,
  ),
  omitWhenArgUnset: true,
);
