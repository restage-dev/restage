// packages/rfw_catalog_compiler/lib/src/policy/default_content/default_union_seeds.dart
import 'package:rfw_catalog_compiler/src/policy/union_registry.dart';

/// Discriminator field name carried on every built-in union seed.
///
/// The encoded union value names its concrete member through this field;
/// all built-in seeds share the same name for a uniform wire shape.
const kDefaultUnionDiscriminatorField = '_s';

/// Abstract-type to concrete-subtype seed mappings for Flutter's
/// painting and material layers. Covers gradient, decoration, shape
/// border, box border, and input border hierarchies.
///
/// All member strings use the fully-qualified `<library-identifier>#<Class>`
/// form so downstream analysis passes can resolve each member to a
/// `ClassElement` without an additional lookup step.
const Map<String, UnionRegistryEntry> kBuiltInUnionSeeds = {
  'package:flutter/src/painting/gradient.dart#Gradient': UnionRegistryEntry(
    abstractType: 'package:flutter/src/painting/gradient.dart#Gradient',
    members: [
      'package:flutter/src/painting/gradient.dart#LinearGradient',
      'package:flutter/src/painting/gradient.dart#RadialGradient',
      'package:flutter/src/painting/gradient.dart#SweepGradient',
    ],
    discriminatorField: kDefaultUnionDiscriminatorField,
    description: 'A color gradient: linear, radial, or sweep.',
  ),
  'package:flutter/src/painting/decoration.dart#Decoration': UnionRegistryEntry(
    abstractType: 'package:flutter/src/painting/decoration.dart#Decoration',
    members: [
      'package:flutter/src/painting/box_decoration.dart#BoxDecoration',
      'package:flutter/src/painting/shape_decoration.dart#ShapeDecoration',
    ],
    discriminatorField: kDefaultUnionDiscriminatorField,
    description: 'A box decoration: BoxDecoration or ShapeDecoration.',
  ),
  'package:flutter/src/painting/borders.dart#ShapeBorder': UnionRegistryEntry(
    abstractType: 'package:flutter/src/painting/borders.dart#ShapeBorder',
    members: [
      'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedRectangleBorder',
      'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedSuperellipseBorder',
      'package:flutter/src/painting/circle_border.dart#CircleBorder',
      'package:flutter/src/painting/stadium_border.dart#StadiumBorder',
      'package:flutter/src/painting/continuous_rectangle_border.dart#ContinuousRectangleBorder',
      'package:flutter/src/painting/beveled_rectangle_border.dart#BeveledRectangleBorder',
      'package:flutter/src/painting/linear_border.dart#LinearBorder',
      'package:flutter/src/painting/star_border.dart#StarBorder',
    ],
    discriminatorField: kDefaultUnionDiscriminatorField,
    description: 'A shape border: rounded, superellipse, circle, stadium, '
        'continuous, beveled, linear, or star.',
  ),
  'package:flutter/src/painting/borders.dart#OutlinedBorder':
      UnionRegistryEntry(
    abstractType: 'package:flutter/src/painting/borders.dart#OutlinedBorder',
    members: [
      'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedRectangleBorder',
      'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedSuperellipseBorder',
      'package:flutter/src/painting/circle_border.dart#CircleBorder',
      'package:flutter/src/painting/stadium_border.dart#StadiumBorder',
      'package:flutter/src/painting/continuous_rectangle_border.dart#ContinuousRectangleBorder',
      'package:flutter/src/painting/beveled_rectangle_border.dart#BeveledRectangleBorder',
      'package:flutter/src/painting/linear_border.dart#LinearBorder',
      'package:flutter/src/painting/star_border.dart#StarBorder',
    ],
    discriminatorField: kDefaultUnionDiscriminatorField,
    description: 'An outlined shape border: rounded, superellipse, circle, '
        'stadium, continuous, beveled, linear, or star.',
  ),
  'package:flutter/src/painting/box_border.dart#BoxBorder': UnionRegistryEntry(
    abstractType: 'package:flutter/src/painting/box_border.dart#BoxBorder',
    members: [
      'package:flutter/src/painting/box_border.dart#Border',
      'package:flutter/src/painting/box_border.dart#BorderDirectional',
    ],
    discriminatorField: kDefaultUnionDiscriminatorField,
    description: 'A box border: uniform or per-side Border, or '
        'text-direction-aware BorderDirectional.',
  ),
  'package:flutter/src/material/input_border.dart#InputBorder':
      UnionRegistryEntry(
    abstractType: 'package:flutter/src/material/input_border.dart#InputBorder',
    members: [
      'package:flutter/src/material/input_border.dart#UnderlineInputBorder',
      'package:flutter/src/material/input_border.dart#OutlineInputBorder',
    ],
    discriminatorField: kDefaultUnionDiscriminatorField,
    description: 'A text field border: underline or full outline.',
  ),
};
