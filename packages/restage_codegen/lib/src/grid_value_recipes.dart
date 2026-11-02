import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/translator_recipe.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Whether a constructor belongs to an admitted native structured value.
bool isGridValueConstructor(ConstructorElement? constructor) {
  if (constructor == null) return false;
  final type = constructor.enclosingElement;
  final origin = _nativeOrigins[type.name];
  if (origin == null || type.library.identifier != origin) return false;
  return type.name == 'ScrollCacheExtent'
      ? constructor.name == 'pixels' || constructor.name == 'viewport'
      : constructor.name == 'new';
}

const _nativeOrigins = {
  'SliverGridDelegateWithFixedCrossAxisCount':
      'package:flutter/src/rendering/sliver_grid.dart',
  'SliverGridDelegateWithMaxCrossAxisExtent':
      'package:flutter/src/rendering/sliver_grid.dart',
  'ScrollPhysics': 'package:flutter/src/widgets/scroll_physics.dart',
  'RangeMaintainingScrollPhysics':
      'package:flutter/src/widgets/scroll_physics.dart',
  'BouncingScrollPhysics': 'package:flutter/src/widgets/scroll_physics.dart',
  'ClampingScrollPhysics': 'package:flutter/src/widgets/scroll_physics.dart',
  'AlwaysScrollableScrollPhysics':
      'package:flutter/src/widgets/scroll_physics.dart',
  'NeverScrollableScrollPhysics':
      'package:flutter/src/widgets/scroll_physics.dart',
  'PageScrollPhysics': 'package:flutter/src/widgets/page_view.dart',
  'FixedExtentScrollPhysics':
      'package:flutter/src/widgets/list_wheel_scroll_view.dart',
  'ScrollCacheExtent': 'package:flutter/src/rendering/viewport.dart',
};

/// Closed native grid, scroll-physics and cache-extent constructor recipes.
const List<TranslatorRecipe> kGridValueRecipes = [
  TranslatorRecipe(
    typeName: 'SliverGridDelegateWithFixedCrossAxisCount',
    failureDsl: '{}',
    emit: EmitFragmentMap([
      EmitMapEntry(
        '_s',
        EmitFragmentLiteral('"SliverGridDelegateWithFixedCrossAxisCount"'),
      ),
      EmitMapEntry(
        'crossAxisCount',
        EmitFragmentArg(
          ArgRef.named('crossAxisCount'),
          propertyType: PropertyType.integer,
        ),
      ),
      ..._gridDimensions,
    ]),
  ),
  TranslatorRecipe(
    typeName: 'SliverGridDelegateWithMaxCrossAxisExtent',
    failureDsl: '{}',
    emit: EmitFragmentMap([
      EmitMapEntry(
        '_s',
        EmitFragmentLiteral('"SliverGridDelegateWithMaxCrossAxisExtent"'),
      ),
      EmitMapEntry(
        'maxCrossAxisExtent',
        EmitFragmentArg(ArgRef.named('maxCrossAxisExtent'), asLength: true),
      ),
      ..._gridDimensions,
    ]),
  ),
  TranslatorRecipe(
    typeName: 'ScrollPhysics',
    failureDsl: '{}',
    emit: EmitFragmentMap([
      EmitMapEntry('_s', EmitFragmentLiteral('"ScrollPhysics"')),
      _parent,
    ]),
  ),
  TranslatorRecipe(
    typeName: 'RangeMaintainingScrollPhysics',
    failureDsl: '{}',
    emit: EmitFragmentMap([
      EmitMapEntry(
        '_s',
        EmitFragmentLiteral('"RangeMaintainingScrollPhysics"'),
      ),
      _parent,
    ]),
  ),
  TranslatorRecipe(
    typeName: 'BouncingScrollPhysics',
    failureDsl: '{}',
    emit: EmitFragmentMap([
      EmitMapEntry('_s', EmitFragmentLiteral('"BouncingScrollPhysics"')),
      _parent,
      EmitMapEntry(
        'decelerationRate',
        EmitFragmentArg(
          ArgRef.named('decelerationRate'),
          propertyType: PropertyType.enumValue,
        ),
        omitWhenArgUnset: true,
      ),
    ]),
  ),
  TranslatorRecipe(
    typeName: 'ClampingScrollPhysics',
    failureDsl: '{}',
    emit: EmitFragmentMap([
      EmitMapEntry('_s', EmitFragmentLiteral('"ClampingScrollPhysics"')),
      _parent,
    ]),
  ),
  TranslatorRecipe(
    typeName: 'AlwaysScrollableScrollPhysics',
    failureDsl: '{}',
    emit: EmitFragmentMap([
      EmitMapEntry(
        '_s',
        EmitFragmentLiteral('"AlwaysScrollableScrollPhysics"'),
      ),
      _parent,
    ]),
  ),
  TranslatorRecipe(
    typeName: 'NeverScrollableScrollPhysics',
    failureDsl: '{}',
    emit: EmitFragmentMap([
      EmitMapEntry('_s', EmitFragmentLiteral('"NeverScrollableScrollPhysics"')),
      _parent,
    ]),
  ),
  TranslatorRecipe(
    typeName: 'PageScrollPhysics',
    failureDsl: '{}',
    emit: EmitFragmentMap([
      EmitMapEntry('_s', EmitFragmentLiteral('"PageScrollPhysics"')),
      _parent,
    ]),
  ),
  TranslatorRecipe(
    typeName: 'FixedExtentScrollPhysics',
    failureDsl: '{}',
    emit: EmitFragmentMap([
      EmitMapEntry('_s', EmitFragmentLiteral('"FixedExtentScrollPhysics"')),
      _parent,
    ]),
  ),
  TranslatorRecipe(
    typeName: 'ScrollCacheExtent',
    variant: 'pixels',
    failureDsl: '{}',
    validations: [_cacheArity],
    emit: EmitFragmentMap([
      EmitMapEntry('_s', EmitFragmentLiteral('"pixels"')),
      EmitMapEntry(
        'value',
        EmitFragmentArg(ArgRef.positional(0), asLength: true),
      ),
    ]),
  ),
  TranslatorRecipe(
    typeName: 'ScrollCacheExtent',
    variant: 'viewport',
    failureDsl: '{}',
    validations: [_cacheArity],
    emit: EmitFragmentMap([
      EmitMapEntry('_s', EmitFragmentLiteral('"viewport"')),
      EmitMapEntry(
        'value',
        EmitFragmentArg(ArgRef.positional(0), asLength: true),
      ),
    ]),
  ),
];

const _parent = EmitMapEntry(
  'parent',
  EmitFragmentArg(ArgRef.named('parent')),
  omitWhenArgUnset: true,
);

const _gridDimensions = [
  EmitMapEntry(
    'mainAxisSpacing',
    EmitFragmentArg(ArgRef.named('mainAxisSpacing'), asLength: true),
    omitWhenArgUnset: true,
  ),
  EmitMapEntry(
    'crossAxisSpacing',
    EmitFragmentArg(ArgRef.named('crossAxisSpacing'), asLength: true),
    omitWhenArgUnset: true,
  ),
  EmitMapEntry(
    'childAspectRatio',
    EmitFragmentArg(ArgRef.named('childAspectRatio'), asLength: true),
    omitWhenArgUnset: true,
  ),
  EmitMapEntry(
    'mainAxisExtent',
    EmitFragmentArg(ArgRef.named('mainAxisExtent'), asLength: true),
    omitWhenArgUnset: true,
  ),
];

const _cacheArity = RecipeValidation(
  check: ArityExact(1),
  issueCode: 'unrecognizedMethodCall',
  message: 'ScrollCacheExtent requires one positional numeric argument.',
);
