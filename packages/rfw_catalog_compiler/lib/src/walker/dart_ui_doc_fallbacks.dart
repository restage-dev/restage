import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const _offset = 'dart:ui#Offset';
const _radius = 'dart:ui#Radius';

const _classDescriptions = <String, String>{
  _offset: 'An immutable 2D floating-point offset.',
  _radius: 'A radius for either circular or elliptical shapes.',
};

const _fieldDescriptions = <(String, String), String>{
  (_radius, 'x'): 'The radius value on the horizontal axis.',
  (_radius, 'y'): 'The radius value on the vertical axis.',
};

const _constructorDescriptions = <(String, String?), String>{
  (_offset, null): 'Creates an offset. The first argument sets [dx], '
      'the horizontal component, and the second sets [dy], the vertical '
      'component.',
  (_offset, 'fromDirection'):
      'Creates an offset from its [direction] and [distance].',
  (_radius, 'elliptical'):
      'Constructs an elliptical radius with the given radii.',
};

const _staticMethodDescriptions = <(String, String), String>{
  (_offset, 'lerp'): 'Linearly interpolate between two offsets.',
  (_radius, 'lerp'): 'Linearly interpolate between two radii.',
};

const _constValueDescriptions = <(String, String), String>{
  (_offset, 'infinite'): 'An offset with infinite x and y components.',
  (_offset, 'zero'): 'An offset with zero magnitude.',
  (_radius, 'zero'): 'A radius with [x] and [y] values set to zero.',
};

/// Returns a stable class description for dart:ui types whose docs disappear
/// under build_runner analysis.
String? dartUiClassDescription(String sourceType) =>
    _classDescriptions[sourceType];

/// Returns a stable field description for dart:ui types whose docs disappear
/// under build_runner analysis.
String? dartUiFieldDescription(String ownerSourceType, String fieldName) =>
    _fieldDescriptions[(ownerSourceType, fieldName)];

/// Returns a stable factory-variant description for dart:ui types whose docs
/// disappear under build_runner analysis.
String? dartUiVariantDescription({
  required String ownerSourceType,
  required VariantSourceKind sourceKind,
  String? namedConstructor,
  String? staticAccessor,
}) {
  return switch (sourceKind) {
    VariantSourceKind.constructor =>
      _constructorDescriptions[(ownerSourceType, namedConstructor)],
    VariantSourceKind.staticMethod => staticAccessor == null
        ? null
        : _staticMethodDescriptions[(ownerSourceType, staticAccessor)],
    VariantSourceKind.staticGetter => null,
    VariantSourceKind.constValue => staticAccessor == null
        ? null
        : _constValueDescriptions[(ownerSourceType, staticAccessor)],
  };
}
